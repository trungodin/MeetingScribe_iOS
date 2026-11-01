//
//  AudioChunker.swift
//  MeetingScribe
//
//  Chia file ghi âm dài thành nhiều đoạn ngắn trước khi gửi ASR.
//  Lý do: Groq giới hạn 25MB/request, Gemini chỉ nhận inline audio ~18MB,
//  và nạp cả file họp 2–3 giờ vào RAM sẽ khiến iOS kill app.
//

import Foundation
import AVFoundation

/// Một đoạn audio được cắt ra từ file ghi âm gốc
public struct AudioChunk {
    public let index: Int
    public let url: URL
    /// Đoạn do app cắt ra (file tạm) → phải xoá sau khi dùng xong
    public let isTemporary: Bool

    public init(index: Int, url: URL, isTemporary: Bool) {
        self.index = index
        self.url = url
        self.isTemporary = isTemporary
    }
}

public final class AudioChunker {
    public static let shared = AudioChunker()

    /// 10 phút @ 32kbps ≈ 2.4MB → an toàn cho cả Groq (25MB) và Gemini (~18MB)
    public static let defaultChunkSeconds: Double = 600

    /// Giới hạn dung lượng mỗi đoạn. 12MB thô ⇒ base64 ~16MB ⇒ vẫn dưới hạn inline ~20MB của Gemini
    /// và dưới 25MB của Groq. Cần thiết vì file nhập từ ngoài (wav/mp3 bitrate cao) có thể rất nặng
    /// dù thời lượng ngắn.
    public static let defaultMaxChunkBytes: Int64 = 12 * 1024 * 1024

    private let timescale: CMTimeScale = 600

    private init() {}

    /// Cắt file thành các đoạn ≤ `chunkSeconds` và ≤ `maxChunkBytes`.
    /// File ngắn sẽ trả về chính file gốc (không re-encode để giữ nguyên chất lượng).
    public func split(
        audioFileURL: URL,
        chunkSeconds: Double = AudioChunker.defaultChunkSeconds,
        maxChunkBytes: Int64 = AudioChunker.defaultMaxChunkBytes
    ) async throws -> [AudioChunk] {

        let asset = AVURLAsset(url: audioFileURL)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        let fileSize: Int64 = {
            let attributes = try? FileManager.default.attributesOfItem(atPath: audioFileURL.path)
            return ((attributes?[.size]) as? NSNumber)?.int64Value ?? 0
        }()

        let original = [AudioChunk(index: 0, url: audioFileURL, isTemporary: false)]

        guard totalSeconds.isFinite, totalSeconds > 0, chunkSeconds > 0 else {
            return original
        }

        var effectiveSeconds = chunkSeconds
        if fileSize > maxChunkBytes {
            // Bitrate cao (wav/mp3 nhập từ ngoài): cắt ngắn hơn để mỗi đoạn không vượt giới hạn dung lượng
            let ratio = Double(maxChunkBytes) / Double(fileSize)
            effectiveSeconds = min(chunkSeconds, max(30, totalSeconds * ratio * 0.95))
        }

        if totalSeconds <= effectiveSeconds && fileSize <= maxChunkBytes {
            return original
        }

        let directory = try makeTemporaryDirectory()
        var chunks: [AudioChunk] = []
        var start: Double = 0
        var index = 0

        while start < totalSeconds - 0.5 {
            try Task.checkCancellation()

            let length = min(effectiveSeconds, totalSeconds - start)
            let range = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: timescale),
                duration: CMTime(seconds: length, preferredTimescale: timescale)
            )
            let outputURL = directory.appendingPathComponent(String(format: "chunk_%03d.m4a", index))
            try await export(asset: asset, timeRange: range, to: outputURL)

            chunks.append(AudioChunk(index: index, url: outputURL, isTemporary: true))
            index += 1
            start += length
        }

        guard !chunks.isEmpty else {
            try? FileManager.default.removeItem(at: directory)
            return original
        }
        return chunks
    }

    /// Xoá các đoạn tạm đã cắt (luôn gọi sau khi chuyển văn bản xong/lỗi để không đầy bộ nhớ máy)
    public func cleanup(_ chunks: [AudioChunk]) {
        var directories = Set<URL>()
        for chunk in chunks where chunk.isTemporary {
            try? FileManager.default.removeItem(at: chunk.url)
            directories.insert(chunk.url.deletingLastPathComponent())
        }
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: - Private

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("asr_chunks_\(Int(Date().timeIntervalSince1970 * 1000))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func export(asset: AVAsset, timeRange: CMTimeRange, to outputURL: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(
                domain: "AudioChunker",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Không thể cắt file âm thanh này (định dạng không được hỗ trợ)."]
            )
        }

        try? FileManager.default.removeItem(at: outputURL)
        session.timeRange = timeRange
        session.shouldOptimizeForNetworkUse = true

        if #available(iOS 18.0, *) {
            try await session.export(to: outputURL, as: .m4a)
        } else {
            session.outputURL = outputURL
            session.outputFileType = .m4a
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously {
                    continuation.resume()
                }
            }
            if session.status != .completed {
                throw session.error ?? NSError(
                    domain: "AudioChunker",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Cắt đoạn âm thanh thất bại."]
                )
            }
        }
    }
}
