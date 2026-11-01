//
//  DetailView+Processing.swift
//  MeetingScribe
//
//  Thẻ tiến trình (thanh % + thời gian đã chạy + ước lượng còn lại), huỷ job,
//  xin thời gian chạy nền và các hàm suy ra trạng thái item.
//

import SwiftUI
import AVFoundation
import UIKit

extension DetailView {

    var processingCard: some View {
        VStack(spacing: 8) {
            ProgressView(value: progressPercent, total: 100)
                .accessibilityLabel("Tiến trình xử lý")
                .accessibilityValue("\(Int(progressPercent)) phần trăm")
            HStack {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Spacer()
                Text(String(format: "%.1f%%", progressPercent))
                    .font(.caption)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }

            if let startedAt = processingStartedAt {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    HStack(spacing: 8) {
                        // Máy chủ ASR chỉ trả % theo từng đoạn (chunk) audio.
                        // Với file ngắn (1 đoạn) hoặc đoạn đầu tiên, thanh % buộc phải
                        // đứng yên vài giây. Spinner này cho biết app vẫn đang xử lý.
                        if Self.isWaitingForNextStep(lastProgressAt: lastProgressAt, now: context.date) {
                            ProgressView()
                                .scaleEffect(0.55)
                                .frame(width: 14, height: 14)
                        }

                        Text(Self.progressFootnote(startedAt: startedAt, lastProgressAt: lastProgressAt, progressPercent: progressPercent, now: context.date))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)

                        Spacer()

                        Button(role: .destructive, action: cancelProcessing) {
                            Text("Huỷ")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }

    /// Đã lâu chưa có mốc % mới (đang chờ máy chủ ASR trả kết quả đoạn tiếp theo) hay không
    static func isWaitingForNextStep(lastProgressAt: Date?, now: Date) -> Bool {
        guard let last = lastProgressAt else { return false }
        return now.timeIntervalSince(last) >= 3
    }

    /// Dòng chân: đã chạy bao lâu + ước lượng còn lại + cảnh báo khi lâu không có mốc mới
    static func progressFootnote(startedAt: Date, lastProgressAt: Date?, progressPercent: Double, now: Date) -> String {
        var parts: [String] = [elapsedText(from: startedAt, to: now)]

        // Ước lượng thời gian còn lại theo tốc độ trung bình (mốc 10% = lúc bắt đầu suy diễn)
        let elapsed = now.timeIntervalSince(startedAt)
        let doneRange = progressPercent - 10.0
        if elapsed > 8, doneRange > 3, progressPercent < 100 {
            let secondsPerPercent = elapsed / doneRange
            let remaining = max(0, (98.0 - progressPercent) * secondsPerPercent)
            parts.append("còn ~" + shortDuration(remaining))
        }

        // Chỉ báo khi thật sự lâu không nhích (đoạn audio dài hoặc mạng chậm)
        if let last = lastProgressAt {
            let idle = max(0, Int(now.timeIntervalSince(last)))
            if idle >= 60 {
                parts.append("chờ \(idle)s · vẫn xử lý")
            } else if idle >= 20 {
                parts.append("chờ \(idle)s")
            }
        }
        return parts.joined(separator: " · ")
    }

    /// Rút gọn thời lượng: 40 -> "40s", 720 -> "12 phút", 3900 -> "1g05p"
    static func shortDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60) phút" }
        return String(format: "%dg%02dp", total / 3600, (total % 3600) / 60)
    }

    static func elapsedText(from start: Date, to now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "Đã chạy %d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "Đã chạy %d:%02d", minutes, seconds)
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        processingStartedAt = nil
        isProcessing = false
        progressPercent = 0
        statusMessage = "Đã huỷ."
        // Không để item kẹt ở trạng thái "đang xử lý" khi người dùng bấm Huỷ
        if let m = meeting {
            store.updateStatus(id: m.id, status: Self.idleStatus(for: m))
            loadMeetingData()
        }
        endProcessingBackgroundTask()
    }


    // MARK: - Trạng thái & chạy nền

    /// Trạng thái "nghỉ" suy ra từ dữ liệu hiện có (dùng khi huỷ/thất bại để item không kẹt ở trạng thái đang xử lý)
    static func idleStatus(for meeting: Meeting) -> MeetingStatus {
        if !meeting.summaryJson.isEmpty {
            return meeting.exportFilePath.isEmpty ? .summarized : .exported
        }
        return meeting.transcript.isEmpty ? .recorded : .transcribed
    }

    /// Nhắc người dùng còn bao nhiêu đoạn đã lưu được, nếu lần chạy bị dừng giữa chừng.
    /// Chuỗi rỗng khi không có tiến trình dở dang.
    static func savedChunkInfo(_ meeting: Meeting?) -> String {
        guard let meeting,
              let done = meeting.transcribedChunkCount,
              let total = meeting.transcribedChunkTotal,
              done > 0, total > done else {
            return ""
        }
        return " Đã lưu \(done)/\(total) đoạn — bấm chạy lại để làm tiếp từ đoạn \(done + 1)."
    }

    /// Tiêu đề nút chạy ASR: có tiến trình dở dang thì nói rõ là chạy tiếp đoạn còn lại
    static func transcribeButtonTitle(for meeting: Meeting) -> String {
        guard let state = meeting.resumableTranscription else { return "Chuyển lại" }
        return "Chạy tiếp (\(state.completedChunks)/\(state.totalChunks))"
    }

    /// Nhắc người dùng còn đoạn chưa nhận dạng xong (lần trước lỗi mạng giữa chừng)
    func resumeBanner(completed: Int, total: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundColor(.orange)
            Text("Đã nhận dạng \(completed)/\(total) đoạn. Bấm \"Chạy tiếp\" để làm nốt \(total - completed) đoạn còn lại — phần đã có không bị mất.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
    }

    /// Xin iOS thêm thời gian chạy nền: nếu người dùng chuyển app/khoá máy giữa lúc AI đang xử lý,
    /// job vẫn có cơ hội hoàn tất thay vì bị treo im lặng.
    func beginProcessingBackgroundTask() {
        endProcessingBackgroundTask()
        processingBgTaskId = UIApplication.shared.beginBackgroundTask(withName: "MeetingScribe.AI") {
            // Hết thời gian chạy nền: huỷ job một cách có kiểm soát, trạng thái item được trả lại
            // như trước để người dùng có thể bấm chạy lại.
            processingTask?.cancel()
            endProcessingBackgroundTask()
        }
    }

    func endProcessingBackgroundTask() {
        guard processingBgTaskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(processingBgTaskId)
        processingBgTaskId = .invalid
    }
}
