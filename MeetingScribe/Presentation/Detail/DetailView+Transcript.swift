//
//  DetailView+Transcript.swift
//  MeetingScribe
//
//  Tab Văn bản gốc: danh sách câu kèm mốc thời gian (bấm để tua) + chế độ sửa tay trước khi tóm tắt.
//

import SwiftUI
import AVFoundation
import UIKit

extension DetailView {

    // MARK: - 2. Tab Transcript

    func transcriptTabView(meeting: Meeting) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isProcessing {
                    processingCard
                }

                if let state = meeting.resumableTranscription, !isProcessing {
                    resumeBanner(completed: state.completedChunks, total: state.totalChunks)
                }

                if meeting.transcript.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Chưa chuyển văn bản")
                            .font(.headline)
                        Text("Bấm nút bên dưới để chuyển giọng nói thành văn bản tiếng Việt.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: startTranscribe) {
                            HStack {
                                Image(systemName: "record.circle")
                                Text("Chuyển văn bản")
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        // Audio đã bị xoá thì không thể nhận dạng lại
                        .disabled(meeting.resolvedAudioURL == nil)
                        .opacity(meeting.resolvedAudioURL == nil ? 0.4 : 1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    HStack {
                        Text("NỘI DUNG VĂN BẢN")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        Spacer()

                        if !isEditingTranscript {
                            // Copy nhanh văn bản gốc
                            Button {
                                UIPasteboard.general.string = meeting.transcript
                                errorMessage = "Đã copy văn bản vào bộ nhớ tạm."
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .font(.caption)
                            .accessibilityLabel("Sao chép toàn bộ văn bản")
                            .disabled(isProcessing)

                            Button("Sửa") { startEditingTranscript(meeting) }
                                .font(.caption)
                                .disabled(isProcessing)
                        }

                        Button(action: startTranscribe) {
                            Text(Self.transcribeButtonTitle(for: meeting))
                        }
                            .font(.caption)
                            // Audio đã bị xoá (dọn dung lượng) thì không nhận dạng lại được
                            .disabled(isProcessing || meeting.resolvedAudioURL == nil)
                    }

                    if isEditingTranscript {
                        // ASR luôn sai tên riêng/số liệu → cho sửa tay trước khi tóm tắt để biên bản Word đúng
                        TextEditor(text: $transcriptDraft)
                            .font(.body)
                            .lineSpacing(2)
                            .frame(minHeight: 260)
                            .padding(6)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                            .accessibilityLabel("Nội dung văn bản, sửa được")

                        HStack {
                            Button("Huỷ", action: cancelEditingTranscript)
                                .font(.caption)

                            Spacer()

                            Button(action: { saveTranscript(meeting) }) {
                                Text("Lưu văn bản")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                    } else if let segments = meeting.segments, !segments.isEmpty {
                        // Có mốc thời gian từng câu: bấm vào mốc là nghe lại đúng chỗ đó
                        transcriptSegmentsView(segments: segments, canSeek: meeting.resolvedAudioURL != nil)
                    } else {
                        Text(meeting.transcript)
                            .font(.body)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(16)
        }
    }

    /// Danh sách câu kèm mốc thời gian. Bấm vào mốc để tua audio tới đúng câu đó —
    /// cần thiết với cuộc họp dài, thay vì tua mò để tìm lại một ý.
    func transcriptSegmentsView(segments: [TranscriptSegment], canSeek: Bool) -> some View {
        let activeIndex = TranscriptSegment.index(at: playbackPosition, in: segments)

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        seek(to: Double(segment.startMs) / 1000.0, autoplay: true)
                    } label: {
                        Text(segment.startLabel)
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSeek)
                    .accessibilityLabel("Tua tới \(segment.startLabel)")
                    .accessibilityHint("Phát lại bản ghi âm từ câu này")

                    Text(segment.text)
                        .font(.body)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(6)
                .background(index == activeIndex ? Color.blue.opacity(0.10) : Color.clear)
                .cornerRadius(6)
            }

            if !canSeek {
                Text("Không tua được vì file ghi âm đã được xoá để tiết kiệm dung lượng.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }


    // MARK: - Sửa tay văn bản

    func startEditingTranscript(_ meeting: Meeting) {
        transcriptDraft = meeting.transcript
        isEditingTranscript = true
    }

    func cancelEditingTranscript() {
        isEditingTranscript = false
        transcriptDraft = ""
    }

    func saveTranscript(_ meeting: Meeting) {
        let text = transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = "Văn bản không được để trống."
            return
        }
        guard text != meeting.transcript else {
            cancelEditingTranscript()
            return
        }

        // Giữ nguyên trạng thái hiện tại: đây chỉ là sửa lỗi nhận dạng, không phải job mới
        store.updateTranscript(id: meeting.id, transcript: text, status: meeting.status)
        isEditingTranscript = false
        transcriptDraft = ""
        loadMeetingData()
        statusMessage = meeting.summaryJson.isEmpty
            ? "Đã lưu văn bản đã sửa."
            : "Đã lưu văn bản đã sửa. Nên tóm tắt lại để biên bản khớp nội dung mới."
    }
}
