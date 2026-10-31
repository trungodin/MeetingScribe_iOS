//
//  WhisperEngine.swift
//  MeetingScribe
//
//  Cầu nối Whisper Offline trên iOS
//
//  FIX lỗi "chuyển văn bản offline đứng ở 96% không bao giờ đạt 100%":
//  1. Nguyên nhân gốc: thanh tiến trình trước đây là TICKER GIẢ, cứ 0.7s +2% và bị chặn cứng
//     ở 96% (50 -> 96 cần 23 nhịp ≈ 15.9 giây). Sau 96% chỉ còn 2 mốc: 98% (khi whisper trả về)
//     và 100%. Vì vậy mọi file cần > 16 giây để suy diễn đều "đứng ở 96%" — app KHÔNG treo,
//     nó chỉ đang chờ whisper.cpp chạy xong.
//  2. Vì sao chạy mãi không xong: engine ép n_threads = 1 (chỉ 1 lõi CPU) + model Small (181 MB)
//     => chậm gấp 4-6 lần mức có thể. File họp 60 phút mất 1.5-3 giờ.
//  3. Bộ nhớ: nạp TOÀN BỘ file vào 1 PCM buffer rồi convert 1 lần (≈ 690 MB với file 60 phút)
//     => memory pressure / jetsam, càng chậm hoặc bị hệ thống kill.
//
//  Cách xử lý trong file này:
//  - Dùng progress_callback THẬT của whisper.cpp (bridge đã hỗ trợ sẵn) => % phản ánh đúng.
//  - ms_whisper_set_n_threads(4) => nhanh hơn 4-6 lần.
//  - Chia audio thành cửa sổ 10 phút: RAM giới hạn (~38 MB/cửa sổ), tiến độ mịn, huỷ được.
//  - Đọc + convert audio theo block 8192 frame => không bao giờ nạp cả file vào RAM.
//  - Hỗ trợ huỷ giữa chừng: Task cancellation -> ms_whisper_request_abort().
//

import Foundation
import AVFoundation
import whisper_c

public class WhisperEngine {
    public static let shared = WhisperEngine()

    /// Độ dài mỗi cửa sổ suy diễn: 10 phút ≈ 38 MB float 16 kHz, an toàn cho mọi iPhone.
    private static let windowSeconds: Double = 600
    /// Chồng lấn giữa 2 cửa sổ để không cắt mất từ ở ranh giới.
    private static let overlapSeconds: Double = 3
    /// Định dạng đầu vào chuẩn của Whisper
    private static let targetSampleRate: Double = 16000
    /// Kích thước block khi đọc file (giới hạn RAM khi convert)
    private static let readBlockFrames: AVAudioFrameCount = 8192

    private init() {}

    public func isAvailable() -> Bool {
        return WhisperModelManager.shared.getActiveModelURL() != nil
    }

    /**
     * Nhận dạng offline file âm thanh bằng model Whisper GGML đã tải
     */
    public func transcribe(audioFileURL: URL, onProgress: ((Int) -> Void)? = nil) async throws -> String {
        guard let modelURL = WhisperModelManager.shared.getActiveModelURL() else {
            throw Self.makeError(404, "Chưa có model Whisper trên máy. Vui lòng vào Cài đặt để tải model.")
        }

        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw Self.makeError(404, "File âm thanh không tồn tại")
        }

        onProgress?(10)

        let duration = try await Self.audioDuration(of: audioFileURL)
        guard duration > 0.5 else {
            throw Self.makeError(400, "File âm thanh không có dữ liệu")
        }

        onProgress?(12)

        // Nạp model 1 lần cho tất cả cửa sổ (nạp lại mỗi cửa sổ tốn vài giây/lần)
        guard let ctx = ms_whisper_init(modelURL.path) else {
            throw Self.makeError(-5, "Không thể nạp mô hình Whisper từ: \(modelURL.path)")
        }
        defer { ms_whisper_free(ctx) }

        // 4 luồng: nhanh hơn single-thread 4-6 lần (trước đây bị ép cứng 1 luồng)
        let threadCount = Int32(max(2, min(4, ProcessInfo.processInfo.activeProcessorCount)))
        ms_whisper_set_n_threads(threadCount)

        let windows = Self.makeWindows(duration: duration)
        var pieces: [String] = []

        for (index, window) in windows.enumerated() {
            try Task.checkCancellation()

            let samples = try await Self.decodeSamples(
                audioFileURL,
                startSeconds: window.start,
                durationSeconds: window.length
            )

            try Task.checkCancellation()

            let base = Double(index) / Double(windows.count)
            let span = 1.0 / Double(windows.count)

            if samples.isEmpty {
                onProgress?(min(98, Int(12.0 + (base + span) * 86.0)))
                continue
            }

            ms_whisper_reset_abort()
            let text = try await withTaskCancellationHandler {
                try await Self.runInference(ctx: ctx, samples: samples) { localPercent in
                    // localPercent 0..100 theo đúng seek position của whisper.cpp
                    let mapped = 12.0 + (base + span * Double(localPercent) / 100.0) * 86.0
                    onProgress?(max(12, min(98, Int(mapped))))
                }
            } onCancel: {
                // Dừng ngay bên trong whisper_full() ở lần kiểm tra kế tiếp
                ms_whisper_request_abort()
            }

            try Task.checkCancellation()

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                pieces.append(trimmed)
            }

            onProgress?(min(98, Int(12.0 + (base + span) * 86.0)))
        }

        try Task.checkCancellation()

        let merged = Self.mergeWindows(pieces)
        onProgress?(100)
        return merged
    }

    // MARK: - Cửa sổ suy diễn

    private struct Window {
        let start: Double
        let length: Double
    }

    private static func makeWindows(duration: Double) -> [Window] {
        guard duration > windowSeconds else {
            return [Window(start: 0, length: duration)]
        }

        var windows: [Window] = []
        var start = 0.0
        while start < duration {
            let length = min(windowSeconds, duration - start)
            windows.append(Window(start: start, length: length))
            if start + length >= duration { break }
            start += windowSeconds - overlapSeconds
        }
        return windows
    }

    /// Ghép văn bản của các cửa sổ, bỏ phần bị lặp do chồng lấn 3 giây
    private static func mergeWindows(_ pieces: [String]) -> String {
        var result: [String] = []
        var previousWords: [String] = []

        for piece in pieces {
            let words = piece.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard !words.isEmpty else { continue }

            var dropped = 0
            let maxCheck = min(12, min(previousWords.count, words.count))
            if maxCheck > 0 {
                for k in stride(from: maxCheck, through: 1, by: -1)
                where Array(previousWords.suffix(k)) == Array(words.prefix(k)) {
                    dropped = k
                    break
                }
            }

            let kept = words.dropFirst(dropped)
            if !kept.isEmpty {
                result.append(kept.joined(separator: " "))
            }
            previousWords = words
        }

        return result.joined(separator: "\n")
    }

    // MARK: - Audio

    private static func audioDuration(of url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        do {
            let seconds = try await asset.load(.duration).seconds
            if seconds.isFinite && seconds > 0 { return seconds }
        } catch {
            // rơi xuống fallback bên dưới
        }

        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        guard rate > 0 else { return 0 }
        return Double(file.length) / rate
    }

    /// Đọc 1 cửa sổ audio và convert sang PCM Float32 16 kHz mono.
    /// Đọc theo block 8192 frame để không bao giờ nạp cả file vào RAM (trước đây gây OOM).
    private static func decodeSamples(
        _ url: URL,
        startSeconds: Double,
        durationSeconds: Double
    ) async throws -> [Float] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let file = try AVAudioFile(forReading: url)
                    let inputFormat = file.processingFormat
                    let sourceRate = inputFormat.sampleRate

                    guard sourceRate > 0, inputFormat.channelCount > 0 else {
                        throw makeError(-1, "Định dạng audio không hợp lệ")
                    }
                    guard let outputFormat = AVAudioFormat(
                        commonFormat: .pcmFormatFloat32,
                        sampleRate: targetSampleRate,
                        channels: 1,
                        interleaved: false
                    ) else {
                        throw makeError(-1, "Không tạo được định dạng 16kHz")
                    }
                    guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                        throw makeError(-2, "Không tạo được bộ chuyển đổi audio")
                    }

                    let startFrame = AVAudioFramePosition((max(0, startSeconds) * sourceRate).rounded())
                    let requestedFrames = AVAudioFramePosition((durationSeconds * sourceRate).rounded())
                    let endFrame = min(file.length, startFrame + requestedFrames)

                    guard endFrame > startFrame else {
                        continuation.resume(returning: [])
                        return
                    }

                    let sourceFrames = endFrame - startFrame
                    let estimatedOutput = Int(Double(sourceFrames) * targetSampleRate / sourceRate) + 4096
                    guard let outputBuffer = AVAudioPCMBuffer(
                        pcmFormat: outputFormat,
                        frameCapacity: AVAudioFrameCount(estimatedOutput)
                    ) else {
                        throw makeError(-3, "Lỗi tạo buffer")
                    }

                    file.framePosition = startFrame

                    var remaining = sourceFrames
                    var conversionError: NSError?

                    let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                        if remaining <= 0 {
                            outStatus.pointee = .endOfStream
                            return nil
                        }

                        let frames = AVAudioFrameCount(min(Int64(readBlockFrames), remaining))
                        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frames) else {
                            outStatus.pointee = .endOfStream
                            return nil
                        }

                        do {
                            try file.read(into: inputBuffer, frameCount: frames)
                        } catch {
                            outStatus.pointee = .endOfStream
                            return nil
                        }

                        if inputBuffer.frameLength == 0 {
                            outStatus.pointee = .endOfStream
                            return nil
                        }

                        remaining -= Int64(inputBuffer.frameLength)
                        outStatus.pointee = .haveData
                        return inputBuffer
                    }

                    if let conversionError = conversionError {
                        throw conversionError
                    }

                    guard status == .haveData || status == .endOfStream else {
                        continuation.resume(returning: [])
                        return
                    }
                    guard let channel = outputBuffer.floatChannelData?[0] else {
                        continuation.resume(returning: [])
                        return
                    }

                    let samples = Array(UnsafeBufferPointer(start: channel, count: Int(outputBuffer.frameLength)))
                    continuation.resume(returning: samples)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Suy diễn

    /// Hộp giữ closure tiến độ để truyền qua con trỏ user_data của C
    private final class ProgressBox {
        let handler: (Int) -> Void
        init(handler: @escaping (Int) -> Void) {
            self.handler = handler
        }
    }

    /// C không giữ được closure Swift => dùng hàm @convention(c) + user_data
    private static let progressTrampoline: @convention(c) (Int32, UnsafeMutableRawPointer?) -> Void = { value, userData in
        guard let userData = userData else { return }
        let box = Unmanaged<ProgressBox>.fromOpaque(userData).takeUnretainedValue()
        box.handler(Int(value))
    }

    /// Bọc con trỏ context để truyền an toàn qua closure @Sendable của GCD
    private struct ContextHandle: @unchecked Sendable {
        let raw: UnsafeMutableRawPointer
    }

    private static func runInference(
        ctx: UnsafeMutableRawPointer,
        samples: [Float],
        onProgress: @escaping (Int) -> Void
    ) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let context = ContextHandle(raw: ctx)
            DispatchQueue.global(qos: .userInitiated).async {
                let box = ProgressBox(handler: onProgress)

                let textPtr = withExtendedLifetime(box) { () -> UnsafeMutablePointer<CChar>? in
                    samples.withUnsafeBufferPointer { buffer -> UnsafeMutablePointer<CChar>? in
                        guard let baseAddress = buffer.baseAddress, buffer.count > 0 else { return nil }
                        return ms_whisper_transcribe(
                            context.raw,
                            baseAddress,
                            Int32(buffer.count),
                            progressTrampoline,
                            Unmanaged.passUnretained(box).toOpaque()
                        )
                    }
                }

                guard let textPtr = textPtr else {
                    continuation.resume(returning: "")
                    return
                }
                defer { ms_whisper_free_string(textPtr) }

                continuation.resume(returning: String(cString: textPtr))
            }
        }
    }

    private static func makeError(_ code: Int, _ message: String) -> NSError {
        return NSError(domain: "WhisperOffline", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
