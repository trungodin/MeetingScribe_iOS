//
//  MeetingStore.swift
//  MeetingScribe
//
//  Quản lý danh sách cuộc họp và lưu trữ bền vững (Local JSON Storage)
//

import Foundation
import Combine

@MainActor
public class MeetingStore: ObservableObject {
    public static let shared = MeetingStore()

    @Published public var meetings: [Meeting] = []

    private var storageURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("meetings_database.json")
    }

    public init() {
        loadMeetings()
    }

    public func loadMeetings() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            self.meetings = []
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            self.meetings = try JSONDecoder().decode([Meeting].self, from: data)
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            print("Lỗi load meetings: \(error.localizedDescription)")
            self.meetings = []
        }
    }

    public func saveMeetings() {
        do {
            let data = try JSONEncoder().encode(meetings)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Lỗi lưu meetings: \(error.localizedDescription)")
        }
    }

    public func insert(meeting: Meeting) -> Int64 {
        var m = meeting
        if m.id == 0 {
            m.id = Int64(Date().timeIntervalSince1970 * 1000)
        }
        meetings.removeAll { $0.id == m.id }
        meetings.insert(m, at: 0)
        saveMeetings()
        return m.id
    }

    public func updateTranscript(id: Int64, transcript: String) {
        if let idx = meetings.firstIndex(where: { $0.id == id }) {
            meetings[idx].transcript = transcript
            meetings[idx].status = .transcribed
            saveMeetings()
        }
    }

    public func updateSummary(id: Int64, summaryJson: String) {
        if let idx = meetings.firstIndex(where: { $0.id == id }) {
            meetings[idx].summaryJson = summaryJson
            meetings[idx].status = .summarized
            saveMeetings()
        }
    }

    public func updateStatus(id: Int64, status: MeetingStatus) {
        if let idx = meetings.firstIndex(where: { $0.id == id }) {
            meetings[idx].status = status
            saveMeetings()
        }
    }

    public func delete(id: Int64) {
        if let meeting = meetings.first(where: { $0.id == id }) {
            if !meeting.audioFilePath.isEmpty {
                try? FileManager.default.removeItem(atPath: meeting.audioFilePath)
            }
            if !meeting.exportFilePath.isEmpty {
                try? FileManager.default.removeItem(atPath: meeting.exportFilePath)
            }
            meetings.removeAll { $0.id == id }
            saveMeetings()
        }
    }

    public func getMeeting(id: Int64) -> Meeting? {
        return meetings.first { $0.id == id }
    }
}
