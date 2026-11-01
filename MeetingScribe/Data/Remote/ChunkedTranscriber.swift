//
//  ChunkedTranscriber.swift
//  MeetingScribe
//
//  Điều phối chuyển văn bản cho file ghi âm dài: cắt thành nhiều đoạn ≤ 10 phút,
//  gửi lần lượt cho engine ASR (Groq/Gemini), ghép lại thành một transcript duy nhất.
//

import Foundation

/// Lỗi cuối cùng của một phiên chuyển văn bản: đã phân loại + biết đã lưu được bao nhiêu đoạn
public struct TranscriptionError: LocalizedError {
    public let failure: AiFailure
    /// Số lần đã thử cho đoạn bị lỗi
    public let attempts: Int
    public let completedChunks: Int
    public let totalChunks: Int

    public var errorDescription: String? {
        var text = failure.userMessage
        if completedChunks > 0 && completedChunks < totalChunks {
            text += "\n\nĐã nhận dạng và lưu \(completedChunks)/\(totalChunks) đoạn. Bấm \"Chuyển văn bản\" lại để chạy tiếp từ đoạn \(completedChunks + 1) — không phải làm lại từ đầu."
        }
        return text
    }
}

public final class ChunkedTranscriber {
    public static let shared = ChunkedTranscriber()

    public struct Outcome {
        /// Toàn bộ văn bản đã ghép từ các đoạn
        public let text: String
        /// Số đoạn đã gửi (1 = file ngắn, không phải cắt)
        public let chunkCount: Int
        /// Mốc thời gian từng câu đã cộng bù theo vị trí đoạn trong file gốc (rỗng nếu engine không trả về)
        public let segments: [TranscriptSegment]

        public init(text: String, chunkCount: Int, segments: [TranscriptSegment] = []) {
            self.text = text
            self.chunkCount = chunkCount
            self.segments = segments
        }
    }

    /// Tiến trình của lần chạy trước còn dùng để chạy tiếp được
    public struct ResumeState {
        /// Số đoạn đã nhận dạng xong
        public let completedChunks: Int
        /// Tổng số đoạn của lần chạy trước (phải khớp số đoạn hiện tại mới dùng lại được)
        public let totalChunks: Int
        /// Văn bản đã có của các đoạn trước đó
        public let text: String
        /// Mốc thời gian đã có của các đoạn trước đó
        public let segments: [TranscriptSegment]

        public init(completedChunks: Int, totalChunks: Int, text: String, segments: [TranscriptSegment] = []) {
            self.completedChunks = completedChunks
            self.totalChunks = totalChunks
            self.text = text
            self.segments = segments
        }
    }

    /// Chính sách thử lại khi lỗi tạm thời (mạng/5xx/429)
    public struct RetryPolicy {
        public let maxAttempts: Int
        /// Thời gian chờ (giây) trước lần thử thứ 2, 3, 4...
        public let delays: [Double]

        public static let `default` = RetryPolicy(maxAttempts: 3, delays: [2, 5, 12])

        public init(maxAttempts: Int, delays: [Double]) {
            self.maxAttempts = maxAttempts
            self.delays = delays
        }
    }

    private init() {}

    /// - Parameters:
    ///   - resume: tiến trình của lần chạy trước (nil = làm mới từ đầu)
    ///   - retryPolicy: số lần thử và khoảng chờ khi gặp lỗi tạm thời
    ///   - onStatus: thông điệp trạng thái cho UI ("Đoạn 2/5 · đang gửi...")
    ///   - onProgress: % toàn file (0…100) đã tính theo số đoạn hoàn thành
    ///   - onChunkCompleted: gọi ngay sau mỗi đoạn xong để UI lưu xuống DB (lỗi về sau không mất công)
    ///   - transcribeChunk: gửi 1 file audio lên engine; tham số thứ 2 là callback % của riêng đoạn đó (0…100)
    public func transcribe(
        audioFileURL: URL,
        chunkSeconds: Double = AudioChunker.defaultChunkSeconds,
        resume: ResumeState? = nil,
        retryPolicy: RetryPolicy = .default,
        onStatus: @escaping (String) -> Void,
        onProgress: @escaping (Double) -> Void,
        onChunkCompleted: ((_ completedChunks: Int, _ totalChunks: Int, _ textSoFar: String, _ segments: [TranscriptSegment]) -> Void)? = nil,
        transcribeChunk: @escaping (URL, @escaping (Int) -> Void) async throws -> TranscribedChunk
    ) async throws -> Outcome {

        let chunks = try await AudioChunker.shared.split(audioFileURL: audioFileURL, chunkSeconds: chunkSeconds)
        // Luôn dọn file tạm, kể cả khi lỗi hoặc bị huỷ
        defer { AudioChunker.shared.cleanup(chunks) }

        let total = chunks.count

        if total == 1 {
            onStatus("Đang gửi file ghi âm lên máy chủ...")
            let result = try await attempt(
                policy: retryPolicy,
                makeError: { failure, attempts in
                    TranscriptionError(failure: failure, attempts: attempts, completedChunks: 0, totalChunks: 1)
                },
                onRetry: { _, delay, failure in
                    onStatus("\(failure.shortLabel) — thử lại sau \(Self.describe(delay))...")
                },
                operation: {
                    try await transcribeChunk(chunks[0].url) { percent in
                        onProgress(Double(min(100, max(0, percent))))
                    }
                }
            )
            onProgress(100)
            return Outcome(text: result.text, chunkCount: 1, segments: result.segments)
        }

        var parts: [String] = []
        var segments: [TranscriptSegment] = []
        var startIndex = 0

        // Chạy tiếp từ đoạn dang dở của lần trước (chỉ khi bố cục đoạn không đổi)
        if let resume,
           resume.totalChunks == total,
           resume.completedChunks > 0,
           resume.completedChunks < total {
            let saved = resume.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !saved.isEmpty {
                parts = [saved]
                segments = resume.segments
                startIndex = resume.completedChunks
                onStatus("Tiếp tục từ đoạn \(startIndex + 1)/\(total) — \(startIndex) đoạn trước đã nhận dạng xong.")
                onProgress(Double(startIndex) / Double(total) * 100.0)
            }
        }

        var completedChunks = startIndex

        for index in startIndex..<total {
            try Task.checkCancellation()
            let chunk = chunks[index]

            onStatus("File dài chia \(total) đoạn · đoạn \(index + 1)/\(total) đang gửi...")
            let part = try await attempt(
                policy: retryPolicy,
                makeError: { failure, attempts in
                    TranscriptionError(
                        failure: failure,
                        attempts: attempts,
                        completedChunks: completedChunks,
                        totalChunks: total
                    )
                },
                onRetry: { attempt, delay, failure in
                    let next = min(attempt + 1, retryPolicy.maxAttempts)
                    onStatus("Đoạn \(index + 1)/\(total) · \(failure.shortLabel) — thử lại sau \(Self.describe(delay)) (lần \(next)/\(retryPolicy.maxAttempts))...")
                },
                operation: {
                    try await transcribeChunk(chunk.url) { percent in
                        let inner = Double(min(100, max(0, percent))) / 100.0
                        onProgress((Double(index) + inner) / Double(total) * 100.0)
                    }
                }
            )

            let trimmed = part.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
            // Mốc thời gian của đoạn này được cộng bù vị trí bắt đầu của nó trong file gốc
            let offsetMs = Int64((chunk.startSeconds * 1000).rounded())
            segments.append(contentsOf: part.segments.map { Self.shifted($0, by: offsetMs) })

            completedChunks = index + 1
            onProgress(Double(completedChunks) / Double(total) * 100.0)
            // Lưu ngay sau mỗi đoạn: lỗi ở đoạn sau không làm mất công đã nhận dạng
            onChunkCompleted?(completedChunks, total, parts.joined(separator: "\n\n"), segments)
        }

        return Outcome(text: parts.joined(separator: "\n\n"), chunkCount: total, segments: segments)
    }
    // MARK: - Thử lại khi lỗi tạm thời

    /// Chạy `operation`, tự thử lại khi gặp lỗi tạm thời (mất mạng/timeout/429/5xx).
    /// Lỗi cấu hình (sai API Key, file quá lớn...) thì ném ngay, thử lại chỉ tốn thời gian.
    private func attempt<T>(
        policy: RetryPolicy,
        makeError: (AiFailure, Int) -> Error,
        onRetry: (Int, Double, AiFailure) -> Void,
        operation: () async throws -> T
    ) async throws -> T {
        let maxAttempts = max(1, policy.maxAttempts)
        var currentAttempt = 1

        while true {
            do {
                return try await operation()
            } catch {
                if error is CancellationError { throw error }
                // Lỗi đã được bọc sẵn ở tầng ngoài → không bọc lại
                if error is TranscriptionError { throw error }

                let failure = AiFailureClassifier.classify(error)
                if failure == .cancelled { throw CancellationError() }

                guard failure.isRetryable, currentAttempt < maxAttempts else {
                    throw makeError(failure, currentAttempt)
                }

                let delay = policy.delays.isEmpty
                    ? 2.0
                    : policy.delays[min(currentAttempt - 1, policy.delays.count - 1)]
                onRetry(currentAttempt, delay, failure)
                // Ngủ giữa 2 lần thử; bị huỷ thì Task.sleep ném CancellationError
                try await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
                currentAttempt += 1
            }
        }
    }

    /// "2s" thay vì "2.0s" cho dễ đọc
    private static func describe(_ delay: Double) -> String {
        let rounded = delay.rounded()
        if abs(delay - rounded) < 0.05 {
            return "\(Int(rounded))s"
        }
        return String(format: "%.1fs", delay)
    }

    /// Dời mốc thời gian của một câu theo vị trí đoạn audio trong file gốc
    private static func shifted(_ segment: TranscriptSegment, by offsetMs: Int64) -> TranscriptSegment {
        TranscriptSegment(
            startMs: segment.startMs + offsetMs,
            endMs: segment.endMs + offsetMs,
            text: segment.text
        )
    }

}
