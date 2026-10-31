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

    public init(
        id: Int64 = 0,
        title: String,
        audioFilePath: String = "",
        durationMs: Int64 = 0,
        transcript: String = "",
        summaryJson: String = "",
        exportFilePath: String = "",
        status: MeetingStatus = .recorded,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
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
}

