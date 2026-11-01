//
//  TranscriptSegment.swift
//  MeetingScribe
//
//  Mốc thời gian của từng đoạn trong bản chuyển văn bản.
//  Có mốc thời gian thì người dùng bấm vào một câu là nghe lại đúng chỗ đó
//  (thay vì phải tua mò cả file họp 1–2 giờ).
//

import Foundation

public struct TranscriptSegment: Codable, Equatable, Hashable {
    /// Thời điểm bắt đầu (mili giây, tính từ đầu file ghi âm gốc)
    public var startMs: Int64
    /// Thời điểm kết thúc (mili giây)
    public var endMs: Int64
    public var text: String

    public init(startMs: Int64, endMs: Int64, text: String) {
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
    }

    public var durationMs: Int64 { max(0, endMs - startMs) }

    /// "12:34" hoặc "1:02:03" nếu bản ghi dài hơn 1 giờ
    public var startLabel: String { TranscriptSegment.format(milliseconds: startMs) }

    public static func format(milliseconds: Int64) -> String {
        let totalSeconds = max(0, milliseconds) / 1000
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Đoạn đang phát tại thời điểm `positionSeconds` (để tô sáng khi nghe lại)
    public static func index(at positionSeconds: Double, in segments: [TranscriptSegment]) -> Int? {
        guard positionSeconds.isFinite else { return nil }
        let ms = Int64(positionSeconds * 1000)
        return segments.firstIndex { ms >= $0.startMs && ms < $0.endMs }
    }
}

/// Kết quả nhận dạng của một đoạn audio: văn bản + mốc thời gian (nếu engine hỗ trợ).
/// Groq Whisper trả về mốc thời gian từng câu; Gemini ASR chỉ trả văn bản nên `segments` rỗng.
public struct TranscribedChunk {
    public let text: String
    public let segments: [TranscriptSegment]

    public init(text: String, segments: [TranscriptSegment] = []) {
        self.text = text
        self.segments = segments
    }
}
