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

    /// Cảnh báo khi database JSON bị hỏng (file cũ đã được sao lưu) để UI báo cho người dùng
    @Published public var storageWarning: String?

    private var storageURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("meetings_database.json")
    }

    public init() {
        loadMeetings()
        // Job AI có thể bị iOS kill giữa chừng (app xuống nền quá lâu) → trả item về trạng thái ổn định
        recoverInterruptedJobs()
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
            // KHÔNG xoá dữ liệu người dùng: đổi tên file hỏng thành bản backup rồi mới reset.
            // Nếu chỉ gán meetings = [] thì lần saveMeetings() kế tiếp sẽ ghi đè mất toàn bộ danh sách.
            let backupName = "meetings_database.corrupt-\(Int(Date().timeIntervalSince1970)).json"
            let backupURL = storageURL.deletingLastPathComponent().appendingPathComponent(backupName)
            try? FileManager.default.moveItem(at: storageURL, to: backupURL)
            self.meetings = []
            self.storageWarning = "Không đọc được dữ liệu cuộc họp (\(error.localizedDescription)). File cũ đã được sao lưu thành \(backupName)."
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

    /// Cập nhật văn bản. `status` = nil → đánh dấu "đã chuyển văn bản";
    /// truyền status hiện tại khi người dùng chỉ sửa lỗi nhận dạng để không mất mốc "đã tóm tắt".
    public func updateTranscript(id: Int64, transcript: String, status: MeetingStatus? = nil) {
        if let idx = meetings.firstIndex(where: { $0.id == id }) {
            meetings[idx].transcript = transcript
            meetings[idx].status = status ?? .transcribed
            // Đã xong (hoặc người dùng sửa tay) → bỏ mốc tiến trình từng đoạn
            meetings[idx].transcribedChunkCount = nil
            meetings[idx].transcribedChunkTotal = nil
            saveMeetings()
        }
    }

    /// Lưu tiến trình ngay sau mỗi đoạn audio đã nhận dạng xong.
    /// Nhờ vậy lỗi mạng ở đoạn sau không làm mất công các đoạn trước: lần chạy sau chỉ cần
    /// nhận dạng tiếp các đoạn còn lại. Trạng thái giữ nguyên `.transcribing`.
    public func saveTranscriptionProgress(id: Int64, transcript: String, completedChunks: Int, totalChunks: Int) {
        if let idx = meetings.firstIndex(where: { $0.id == id }) {
            meetings[idx].transcript = transcript
            meetings[idx].transcribedChunkCount = completedChunks
            meetings[idx].transcribedChunkTotal = totalChunks
            meetings[idx].status = .transcribing
            saveMeetings()
        }
    }

    /// Kết thúc phiên chuyển văn bản bị huỷ/lỗi: suy ra trạng thái từ dữ liệu đang có
    /// (giữ nguyên số đoạn đã xong để lần sau chạy tiếp, không kẹt ở "Đang chuyển văn bản...").
    public func settleTranscription(id: Int64) {
        if let idx = meetings.firstIndex(where: { $0.id == id }) {
            if !meetings[idx].summaryJson.isEmpty {
                meetings[idx].status = .summarized
            } else if !meetings[idx].transcript.isEmpty {
                meetings[idx].status = .transcribed
            } else {
                meetings[idx].status = .recorded
            }
            saveMeetings()
        }
    }

    /// Đổi tên cuộc họp (tên do máy tự sinh lúc ghi âm nên cần cho người dùng sửa lại)
    public func rename(id: Int64, title: String) {
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty else { return }
        if let idx = meetings.firstIndex(where: { $0.id == id }) {
            meetings[idx].title = newTitle
            saveMeetings()
        }
    }

    /// Trả các job đang dở (app bị kill khi đang chuyển văn bản/tóm tắt) về trạng thái ổn định
    public func recoverInterruptedJobs() {
        var changed = false
        for idx in meetings.indices {
            switch meetings[idx].status {
            case .transcribing:
                meetings[idx].status = meetings[idx].transcript.isEmpty ? .recorded : .transcribed
                changed = true
            case .summarizing:
                meetings[idx].status = meetings[idx].summaryJson.isEmpty ? .transcribed : .summarized
                changed = true
            default:
                break
            }
        }
        if changed {
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
            // Dùng resolved*URL: đường dẫn lưu trong DB chứa UUID container cũ, sau khi cài lại/cập nhật app
            // sẽ không còn đúng → xoá theo path thô thì file nằm lại vĩnh viễn và làm đầy bộ nhớ máy.
            if let audioURL = meeting.resolvedAudioURL {
                try? FileManager.default.removeItem(at: audioURL)
            }
            if let exportURL = meeting.resolvedExportURL {
                try? FileManager.default.removeItem(at: exportURL)
            }
            meetings.removeAll { $0.id == id }
            saveMeetings()
        }
    }
    // MARK: - Dung lượng & dọn dẹp

    /// Dung lượng file ghi âm + biên bản Word đang chiếm trên máy (để người dùng biết vì sao máy đầy).
    public func storageUsage() -> StorageUsage {
        var audioBytes: Int64 = 0
        var exportBytes: Int64 = 0
        var audioFileCount = 0

        for meeting in meetings {
            if let audioURL = meeting.resolvedAudioURL {
                audioBytes += Self.fileSize(at: audioURL)
                audioFileCount += 1
            }
            if let exportURL = meeting.resolvedExportURL {
                exportBytes += Self.fileSize(at: exportURL)
            }
        }

        return StorageUsage(audioBytes: audioBytes, exportBytes: exportBytes, audioFileCount: audioFileCount)
    }

    /// Các file ghi âm có thể xoá mà KHÔNG mất nội dung: cuộc họp đã có văn bản/biên bản
    /// và (đã tóm tắt xong hoặc cũ hơn `olderThanDays` ngày).
    /// Cố tình bỏ qua file chưa có văn bản — xoá sẽ mất luôn bản ghi âm duy nhất.
    public func cleanableAudio(olderThanDays days: Int? = nil) -> [(meeting: Meeting, bytes: Int64)] {
        let threshold = days.map { Date().addingTimeInterval(-Double($0) * 86_400) }

        return meetings.compactMap { meeting -> (Meeting, Int64)? in
            guard let audioURL = meeting.resolvedAudioURL else { return nil }
            let hasText = !meeting.transcript.isEmpty || !meeting.summaryJson.isEmpty
            guard hasText else { return nil }

            let isFinished = !meeting.summaryJson.isEmpty
            let isOld = threshold.map {
                Date(timeIntervalSince1970: Double(meeting.createdAt) / 1000) < $0
            } ?? false
            guard isFinished || isOld else { return nil }

            return (meeting, Self.fileSize(at: audioURL))
        }
    }

    /// Xoá file ghi âm của các cuộc họp, giữ nguyên văn bản + biên bản Word.
    /// Trả về số byte đã giải phóng để UI báo lại cho người dùng.
    @discardableResult
    public func deleteAudioFiles(meetingIds: Set<Int64>) -> Int64 {
        var freed: Int64 = 0
        var changed = false

        for idx in meetings.indices where meetingIds.contains(meetings[idx].id) {
            guard let audioURL = meetings[idx].resolvedAudioURL else { continue }
            freed += Self.fileSize(at: audioURL)
            try? FileManager.default.removeItem(at: audioURL)
            // Xoá đường dẫn để UI biết audio không còn (nội dung văn bản vẫn nguyên)
            meetings[idx].audioFilePath = ""
            changed = true
        }

        if changed {
            saveMeetings()
        }
        return freed
    }

    static func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }



    public func getMeeting(id: Int64) -> Meeting? {
        return meetings.first { $0.id == id }
    }
}

