//
//  WhisperEngine.swift
//  MeetingScribe
//
//  Cầu nối Whisper Offline trên iOS
//

import Foundation
import AVFoundation
import whisper_c

public class WhisperEngine {
    public static let shared = WhisperEngine()

    private init() {}

    public func isAvailable() -> Bool {
        return WhisperModelManager.shared.getActiveModelURL() != nil
    }

    /**
     * Nhận dạng offline file âm thanh bằng model Whisper GGML đã tải
     */
    public func transcribe(audioFileURL: URL, onProgress: ((Int) -> Void)? = nil) async throws -> String {
        guard let modelURL = WhisperModelManager.shared.getActiveModelURL() else {
            throw NSError(domain: "WhisperOffline", code: 404, userInfo: [NSLocalizedDescriptionKey: "Chưa có model Whisper trên máy. Vui lòng vào Cài đặt để tải model."])
        }

        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw NSError(domain: "WhisperOffline", code: 404, userInfo: [NSLocalizedDescriptionKey: "File âm thanh không tồn tại"])
        }

        onProgress?(10)

        // Đọc PCM 16kHz mono từ audio file
        let samples = try await decodeAudioTo16kHzSamples(audioFileURL: audioFileURL)
        onProgress?(30)

        guard samples.count > 0 else {
            throw NSError(domain: "WhisperOffline", code: 400, userInfo: [NSLocalizedDescriptionKey: "File âm thanh không có dữ liệu"])
        }

        onProgress?(50)

        // Thực thi nhận diện giọng nói bằng whisper.cpp native engine
        let resultText = try await runWhisperInference(samples: samples, modelPath: modelURL.path, onProgress: onProgress)
        onProgress?(100)
        return resultText
    }

    private func decodeAudioTo16kHzSamples(audioFileURL: URL) async throws -> [Float] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let file = try AVAudioFile(forReading: audioFileURL)
                    guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
                        continuation.resume(throwing: NSError(domain: "WhisperEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tạo được định dạng 16kHz"]))
                        return
                    }

                    guard let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat) else {
                        continuation.resume(throwing: NSError(domain: "WhisperEngine", code: -2, userInfo: [NSLocalizedDescriptionKey: "Không tạo được bộ chuyển đổi audio"]))
                        return
                    }

                    let frameCount = AVAudioFrameCount(file.length)
                    guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
                        continuation.resume(throwing: NSError(domain: "WhisperEngine", code: -3, userInfo: [NSLocalizedDescriptionKey: "Lỗi tạo buffer"]))
                        return
                    }

                    try file.read(into: inputBuffer)

                    let outputFrameCapacity = AVAudioFrameCount(Double(frameCount) * (16000.0 / file.processingFormat.sampleRate))
                    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
                        continuation.resume(throwing: NSError(domain: "WhisperEngine", code: -4, userInfo: [NSLocalizedDescriptionKey: "Lỗi tạo output buffer"]))
                        return
                    }

                    var error: NSError?
                    var allRead = false
                    converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                        if allRead {
                            outStatus.pointee = .noDataNow
                            return nil
                        }
                        allRead = true
                        outStatus.pointee = .haveData
                        return inputBuffer
                    }

                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let channelData = outputBuffer.floatChannelData else {
                        continuation.resume(returning: [])
                        return
                    }

                    let channel = channelData[0]
                    let samples = Array(UnsafeBufferPointer(start: channel, count: Int(outputBuffer.frameLength)))
                    continuation.resume(returning: samples)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runWhisperInference(samples: [Float], modelPath: String, onProgress: ((Int) -> Void)?) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Ticker tăng tiến độ đều đặn 50% -> 96% để giao diện luôn sống động trong suốt quá trình suy diễn
                var currentUIProg = 50
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
                timer.schedule(deadline: .now() + 0.5, repeating: 0.7)
                timer.setEventHandler {
                    if currentUIProg < 96 {
                        currentUIProg += 2
                        DispatchQueue.main.async {
                            onProgress?(currentUIProg)
                        }
                    }
                }
                timer.resume()

                defer {
                    timer.cancel()
                }

                guard let ctx = ms_whisper_init(modelPath) else {
                    continuation.resume(throwing: NSError(domain: "WhisperEngine", code: -5, userInfo: [NSLocalizedDescriptionKey: "Không thể nạp mô hình Whisper từ: \(modelPath)"]))
                    return
                }
                defer {
                    ms_whisper_free(ctx)
                }

                let textPtr = samples.withUnsafeBufferPointer { ptr -> UnsafeMutablePointer<CChar>? in
                    guard let baseAddr = ptr.baseAddress else { return nil }
                    return ms_whisper_transcribe(ctx, baseAddr, Int32(samples.count), nil, nil)
                }

                guard let textPtr = textPtr else {
                    continuation.resume(returning: "")
                    return
                }
                defer {
                    ms_whisper_free_string(textPtr)
                }

                let transcript = String(cString: textPtr).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: transcript)
            }
        }
    }
}

