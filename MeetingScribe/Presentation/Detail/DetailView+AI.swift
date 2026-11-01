//
//  DetailView+AI.swift
//  MeetingScribe
//
//  Chạy chuyển văn bản (ASR theo từng đoạn, có chạy tiếp) và tóm tắt biên bản bằng AI.
//

import SwiftUI
import AVFoundation
import UIKit

extension DetailView {

    // MARK: - AI Execution

    func startTranscribe() {
        guard let m = meeting else { return }
        guard let audioURL = m.resolvedAudioURL else {
            errorMessage = "File âm thanh không tồn tại trên thiết bị."
            return
        }
        // Chế độ nhận dạng offline (Whisper) đã được gỡ bỏ. Bản cũ có thể còn lưu
        // "WHISPER" trong Keychain → coi như Groq để app vẫn chạy bình thường.
        let storedEngine = KeychainManager.shared.get(key: .asrEngine, defaultValue: "GROQ")
        let engine = (storedEngine == "GEMINI") ? "GEMINI" : "GROQ"

        isProcessing = true
        progressPercent = 5
        processingStartedAt = Date()
        lastProgressAt = Date()
        processingTask?.cancel()
        // Ghi trạng thái xuống DB: rời màn hình hay app bị kill vẫn biết job đang dở
        store.updateStatus(id: m.id, status: .transcribing)
        // Xin iOS thêm thời gian chạy nền để job không chết khi người dùng chuyển sang app khác
        beginProcessingBackgroundTask()

        // Lần trước có thể đã nhận dạng xong vài đoạn (lỗi mạng giữa chừng) → chỉ làm tiếp phần còn lại
        let resumeState = m.resumableTranscription

        processingTask = Task {
            do {
                // Engine chọn 1 lần, dùng chung cho mọi đoạn
                let transcribeOneChunk: (URL, @escaping (Int) -> Void) async throws -> TranscribedChunk = { chunkURL, onChunkProgress in
                    if engine == "GEMINI" {
                        let key = KeychainManager.shared.get(key: .geminiApiKey)
                        let proxy = KeychainManager.shared.get(key: .geminiProxyUrl)
                        // Thiếu API Key là nguyên nhân phổ biến nhất của lỗi 403 PERMISSION_DENIED
                        // ("Method doesn't allow unregistered callers"). Báo ngay, rõ ràng.
                        if AiEndpoints.isDirectCall(proxyBaseUrl: proxy),
                           KeychainManager.shared.sanitize(key).isEmpty {
                            throw NSError(
                                domain: "Settings",
                                code: 401,
                                userInfo: [NSLocalizedDescriptionKey: "Chưa nhập Gemini API Key.\nVào Cài đặt ➔ Google Gemini để dán API Key (lấy tại aistudio.google.com/apikey) rồi bấm Lưu."]
                            )
                        }
                        return try await GeminiService.shared.transcribe(
                            audioFileURL: chunkURL,
                            apiKey: key,
                            proxyUrl: proxy,
                            onProgress: onChunkProgress
                        )
                    } else {
                        // Groq Whisper
                        let key = KeychainManager.shared.get(key: .groqApiKey)
                        guard !key.isEmpty else {
                            throw NSError(domain: "Settings", code: 401, userInfo: [NSLocalizedDescriptionKey: "Chưa nhập Groq API Key trong Cài đặt."])
                        }
                        return try await GroqAsrService.shared.transcribe(
                            audioFileURL: chunkURL,
                            apiKey: key,
                            onProgress: onChunkProgress
                        )
                    }
                }

                // File dài được cắt thành nhiều đoạn ≤ 10 phút: tránh giới hạn 25MB của Groq,
                // ~18MB của Gemini và tránh nạp cả file ghi âm vào RAM.
                let outcome = try await ChunkedTranscriber.shared.transcribe(
                    audioFileURL: audioURL,
                    resume: resumeState,
                    onStatus: { message in
                        DispatchQueue.main.async {
                            statusMessage = message
                            lastProgressAt = Date()
                        }
                    },
                    onProgress: { percent in
                        DispatchQueue.main.async {
                            progressPercent = max(5, min(99, percent))
                            lastProgressAt = Date()
                        }
                    },
                    onChunkCompleted: { completed, total, textSoFar, chunkSegments in
                        // Lưu ngay xuống DB: lỗi/huỷ ở đoạn sau vẫn giữ được các đoạn đã nhận dạng
                        DispatchQueue.main.async {
                            store.saveTranscriptionProgress(
                                id: m.id,
                                transcript: textSoFar,
                                segments: chunkSegments,
                                completedChunks: completed,
                                totalChunks: total
                            )
                        }
                    },
                    transcribeChunk: transcribeOneChunk
                )

                await MainActor.run {
                    let finalTranscript = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "(Không nhận diện được giọng nói trong đoạn ghi âm này)"
                        : outcome.text
                    store.updateTranscript(
                        id: m.id,
                        transcript: finalTranscript,
                        segments: outcome.segments.isEmpty ? nil : outcome.segments
                    )
                    loadMeetingData()
                    isProcessing = false
                    processingStartedAt = nil
                    processingTask = nil
                    progressPercent = 100
                    statusMessage = outcome.chunkCount > 1
                        ? "Đã chuyển văn bản xong (\(outcome.chunkCount) đoạn)."
                        : "Đã chuyển văn bản thành công!"
                    AppLog.info(
                        "Chuyển văn bản xong: \(outcome.chunkCount) đoạn, "
                        + "\(finalTranscript.count) ký tự, \(outcome.segments.count) mốc thời gian",
                        .transcribe
                    )
                    endProcessingBackgroundTask()
                }
            } catch is CancellationError {
                await MainActor.run {
                    // Huỷ giữa chừng: các đoạn đã xong vẫn được giữ để chạy tiếp;
                    // trạng thái suy ra từ dữ liệu hiện có (không kẹt "Đang chuyển văn bản...")
                    store.settleTranscription(id: m.id)
                    loadMeetingData()
                    isProcessing = false
                    processingStartedAt = nil
                    processingTask = nil
                    progressPercent = 0
                    statusMessage = "Đã huỷ." + Self.savedChunkInfo(store.meetings.first { $0.id == m.id })
                    endProcessingBackgroundTask()
                }
            } catch {
                await MainActor.run {
                    store.settleTranscription(id: m.id)
                    loadMeetingData()
                    isProcessing = false
                    processingStartedAt = nil
                    processingTask = nil
                    // Câu lỗi tiếng Việt đã phân loại + nhắc các đoạn đã lưu (nếu có)
                    errorMessage = AiFailureClassifier.message(for: error)
                        + Self.savedChunkInfo(store.meetings.first { $0.id == m.id })
                    AppLog.error("Chuyển văn bản thất bại", .transcribe, error: error)
                    endProcessingBackgroundTask()
                }
            }
        }
    }

    func startSummarize() {
        guard let m = meeting, !m.transcript.isEmpty else { return }
        let provider = KeychainManager.shared.get(key: .aiProvider, defaultValue: "DEEPSEEK")

        isProcessing = true
        progressPercent = 15
        processingStartedAt = Date()
        lastProgressAt = Date()
        processingTask?.cancel()
        store.updateStatus(id: m.id, status: .summarizing)
        beginProcessingBackgroundTask()

        let previousStatus = Self.idleStatus(for: m)

        processingTask = Task {
            do {
                var json = ""
                if provider == "GEMINI" {
                    let key = KeychainManager.shared.get(key: .geminiApiKey)
                    let proxy = KeychainManager.shared.get(key: .geminiProxyUrl)
                    statusMessage = "Google Gemini đang tóm tắt biên bản..."
                    json = try await GeminiService.shared.summarize(
                        transcript: m.transcript,
                        apiKey: key,
                        proxyUrl: proxy
                    ) { p in
                        DispatchQueue.main.async {
                            progressPercent = Double(p)
                            lastProgressAt = Date()
                        }
                    }
                } else {
                    // DeepSeek
                    let key = KeychainManager.shared.get(key: .deepSeekApiKey)
                    guard !key.isEmpty else {
                        throw NSError(domain: "Settings", code: 401, userInfo: [NSLocalizedDescriptionKey: "Chưa nhập DeepSeek API Key trong Cài đặt."])
                    }
                    statusMessage = "DeepSeek đang tóm tắt biên bản NĐ 30..."
                    json = try await DeepSeekSummarizerService.shared.summarize(
                        transcript: m.transcript,
                        apiKey: key
                    ) { p in
                        DispatchQueue.main.async {
                            progressPercent = Double(p)
                            lastProgressAt = Date()
                        }
                    }
                }

                await MainActor.run {
                    store.updateSummary(id: m.id, summaryJson: json)
                    loadMeetingData()
                    isProcessing = false
                    processingStartedAt = nil
                    processingTask = nil
                    selectedTab = 1
                    statusMessage = "Đã tóm tắt thành công!"
                    endProcessingBackgroundTask()
                }
            } catch is CancellationError {
                await MainActor.run {
                    // Huỷ giữa chừng: trả item về trạng thái trước đó, không để kẹt "Đang tóm tắt..."
                    store.updateStatus(id: m.id, status: previousStatus)
                    loadMeetingData()
                    isProcessing = false
                    processingStartedAt = nil
                    processingTask = nil
                    progressPercent = 0
                    statusMessage = "Đã huỷ."
                    endProcessingBackgroundTask()
                }
            } catch {
                await MainActor.run {
                    store.updateStatus(id: m.id, status: previousStatus)
                    loadMeetingData()
                    isProcessing = false
                    processingStartedAt = nil
                    processingTask = nil
                    // Câu lỗi tiếng Việt đã phân loại (key sai, hết quota, mất mạng...)
                    errorMessage = AiFailureClassifier.message(for: error)
                    endProcessingBackgroundTask()
                }
            }
        }
    }
}
