//
//  Meeting.swift
//  MeetingScribe
//
//  Domain model tương đương Meeting.kt trên Android
//

import Foundation

public struct Meeting: Identifiable, Codable, Equatable, Hashable {
    public var id: Int64
    public var title: String
    public var audioFilePath: String
    public var durationMs: Int64
    public var transcript: String
    public var summaryJson: String
    public var exportFilePath: String
    public var status: MeetingStatus
    public var createdAt: Int64

    /// Số đoạn audio đã nhận dạng xong ở lần chạy gần nhất (để chạy tiếp khi lỗi mạng giữa chừng).
    /// Optional vì database cũ chưa có trường này — decode vẫn phải chạy được.
    public var transcribedChunkCount: Int?
    /// Tổng số đoạn của lần chạy gần nhất, dùng để biết tiến trình cũ còn dùng lại được hay không
    public var transcribedChunkTotal: Int?

    public init(
        id: Int64 = 0,
        title: String,
        audioFilePath: String = "",
        durationMs: Int64 = 0,
        transcript: String = "",
        summaryJson: String = "",
        exportFilePath: String = "",
        status: MeetingStatus = .recorded,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        transcribedChunkCount: Int? = nil,
        transcribedChunkTotal: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.audioFilePath = audioFilePath
        self.durationMs = durationMs
        self.transcript = transcript
        self.summaryJson = summaryJson
        self.exportFilePath = exportFilePath
        self.status = status
        self.createdAt = createdAt
        self.transcribedChunkCount = transcribedChunkCount
        self.transcribedChunkTotal = transcribedChunkTotal
    }

    /// Tiến trình nhận dạng dở dang còn dùng để chạy tiếp được (đã xong ≥1 đoạn nhưng chưa hết)
    public var resumableTranscription: ChunkedTranscriber.ResumeState? {
        guard let done = transcribedChunkCount,
              let total = transcribedChunkTotal,
              done > 0, total > done,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return ChunkedTranscriber.ResumeState(completedChunks: done, totalChunks: total, text: transcript)
    }

    public var parsedSummary: MeetingSummary? {
        guard !summaryJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = summaryJson.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(MeetingSummary.self, from: data)
    }

    public var formattedDuration: String {
        let totalSeconds = durationMs / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let hours = minutes / 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes % 60, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public var formattedCreatedAt: String {
        let date = Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000.0)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter.string(from: date)
    }

    /// Trả về đường dẫn hợp lệ trên thiết bị hiện tại (giải quyết việc UUID container của iOS thay đổi sau mỗi lần build/update app)
    public var resolvedAudioURL: URL? {
        guard !audioFilePath.isEmpty else { return nil }
        let currentUrl = URL(fileURLWithPath: audioFilePath)
        if FileManager.default.fileExists(atPath: currentUrl.path) {
            return currentUrl
        }

        // Nếu container UUID thay đổi, tìm file trong thư mục Documents/recordings hiện tại
        let fileName = currentUrl.lastPathComponent
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let inRecordings = docs[0].appendingPathComponent("recordings").appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: inRecordings.path) {
            return inRecordings
        }

        let inDocs = docs[0].appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: inDocs.path) {
            return inDocs
        }

        return nil
    }

    /// Trả về đường dẫn file Word đã xuất trên thiết bị hiện tại (cùng lý do: UUID container thay đổi sau mỗi lần build/update app)
    public var resolvedExportURL: URL? {
        guard !exportFilePath.isEmpty else { return nil }
        let currentUrl = URL(fileURLWithPath: exportFilePath)
        if FileManager.default.fileExists(atPath: currentUrl.path) {
            return currentUrl
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let inExports = docs[0].appendingPathComponent("exports").appendingPathComponent(currentUrl.lastPathComponent)
        if FileManager.default.fileExists(atPath: inExports.path) {
            return inExports
        }

        let inDocs = docs[0].appendingPathComponent(currentUrl.lastPathComponent)
        if FileManager.default.fileExists(atPath: inDocs.path) {
            return inDocs
        }

        return nil
    }
}

