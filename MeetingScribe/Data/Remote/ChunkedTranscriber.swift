//
//  ChunkedTranscriber.swift
//  MeetingScribe
//
//  Điều phối chuyển văn bản cho file ghi âm dài: cắt thành nhiều đoạn ≤ 10 phút,
//  gửi lần lượt cho engine ASR (Groq/Gemini), ghép lại thành một transcript duy nhất.
//

import Foundation

public final class ChunkedTranscriber {
    public static let shared = ChunkedTranscriber()

    public struct Outcome {
        /// Toàn bộ văn bản đã ghép từ các đoạn
        public let text: String
        /// Số đoạn đã gửi (1 = file ngắn, không phải cắt)
        public let chunkCount: Int
    }

    private init() {}

    /// - Parameters:
    ///   - onStatus: thông điệp trạng thái cho UI ("Đoạn 2/5 · đang gửi...")
    ///   - onProgress: % toàn file (0…100) đã tính theo số đoạn hoàn thành
    ///   - transcribeChunk: gửi 1 file audio lên engine; tham số thứ 2 là callback % của riêng đoạn đó (0…100)
    public func transcribe(
        audioFileURL: URL,
        chunkSeconds: Double = AudioChunker.defaultChunkSeconds,
        onStatus: @escaping (String) -> Void,
        onProgress: @escaping (Double) -> Void,
        transcribeChunk: @escaping (URL, @escaping (Int) -> Void) async throws -> String
    ) async throws -> Outcome {

        let chunks = try await AudioChunker.shared.split(audioFileURL: audioFileURL, chunkSeconds: chunkSeconds)
        // Luôn dọn file tạm, kể cả khi lỗi hoặc bị huỷ
        defer { AudioChunker.shared.cleanup(chunks) }

        let total = chunks.count

        if total == 1 {
            onStatus("Đang gửi file ghi âm lên máy chủ...")
            let text = try await transcribeChunk(chunks[0].url) { percent in
                onProgress(Double(min(100, max(0, percent))))
            }
            onProgress(100)
            return Outcome(text: text, chunkCount: 1)
        }

        var parts: [String] = []
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()

            onStatus("File dài chia \(total) đoạn · đoạn \(index + 1)/\(total) đang gửi...")
            let part = try await transcribeChunk(chunk.url) { percent in
                let inner = Double(min(100, max(0, percent))) / 100.0
                onProgress((Double(index) + inner) / Double(total) * 100.0)
            }

            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
            onProgress(Double(index + 1) / Double(total) * 100.0)
        }

        return Outcome(text: parts.joined(separator: "\n\n"), chunkCount: total)
    }
}
