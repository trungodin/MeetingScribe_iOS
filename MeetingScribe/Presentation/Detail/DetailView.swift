//
//  DetailView.swift
//  MeetingScribe
//
//  Màn hình Chi tiết cuộc họp: Phát lại audio, chuyển văn bản, tóm tắt AI, xuất Word
//

import SwiftUI
import AVFoundation

public struct DetailView: View {
    let meetingId: Int64

    @StateObject private var store = MeetingStore.shared
    @State private var meeting: Meeting?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0
    @State private var playbackTimer: Timer?

    // Trạng thái AI
    @State private var isProcessing = false
    @State private var progressPercent = 0
    @State private var statusMessage = ""
    @State private var errorMessage: String?
    @State private var showingShareSheet = false
    @State private var exportedFileURL: URL?

    public init(meetingId: Int64) {
        self.meetingId = meetingId
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let meeting = meeting {
                    // 1. Thẻ thông tin cuộc họp & Audio Player
                    audioPlayerCard(meeting: meeting)

                    // 2. Cụm nút hành động AI
                    aiActionButtons(meeting: meeting)

                    // 3. Tiến trình xử lý (nếu có)
                    if isProcessing {
                        processingCard
                    }

                    // 4. Kết quả Tóm tắt (Biên bản)
                    if let summary = meeting.parsedSummary {
                        summaryCard(summary: summary)
                    }

                    // 5. Nội dung transcript gốc
                    if !meeting.transcript.isEmpty {
                        transcriptCard(transcript: meeting.transcript)
                    }
                } else {
                    ProgressView()
                }
            }
            .padding()
        }
        .navigationTitle(meeting?.title ?? "Chi tiết")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let exportPath = meeting?.exportFilePath, !exportPath.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        exportedFileURL = URL(fileURLWithPath: exportPath)
                        showingShareSheet = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Thông báo", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            loadMeetingData()
        }
        .onDisappear {
            stopAudio()
        }
    }

    private func loadMeetingData() {
        meeting = store.getMeeting(id: meetingId)
    }

    // MARK: - View Components

    private func audioPlayerCard(meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(meeting.title)
                    .font(.headline)
                Spacer()
                Text(meeting.formattedDuration)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Slider(value: $playbackProgress, in: 0...1) { editing in
                if !editing, let player = audioPlayer {
                    player.currentTime = playbackProgress * player.duration
                }
            }

            HStack {
                Button(action: togglePlayAudio) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.blue)
                }

                Spacer()

                Text(meeting.formattedCreatedAt)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func aiActionButtons(meeting: Meeting) -> some View {
        VStack(spacing: 12) {
            // Nút Chuyển văn bản
            Button(action: startTranscribe) {
                HStack {
                    Image(systemName: "waveform")
                    Text(meeting.transcript.isEmpty ? "Chuyển thành văn bản (Groq ASR)" : "Chuyển văn bản lại")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(isProcessing)

            // Nút Tóm tắt AI
            Button(action: startSummarize) {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text("Tóm tắt biên bản (DeepSeek AI)")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(isProcessing || meeting.transcript.isEmpty)
        }
    }

    private var processingCard: some View {
        VStack(spacing: 12) {
            ProgressView(value: Double(progressPercent), total: 100)
            HStack {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(progressPercent)%")
                    .font(.caption)
                    .fontWeight(.bold)
            }
        }
        .padding()
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }

    private func summaryCard(summary: MeetingSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BIÊN BẢN CUỘC HỌP")
                .font(.headline)
                .foregroundColor(.purple)

            Divider()

            Group {
                summaryRow(title: "Chủ trì:", value: summary.chuTri)
                summaryRow(title: "Thư ký:", value: summary.thuKy)
                summaryRow(title: "Thời gian:", value: summary.thoiGian)
                summaryRow(title: "Địa điểm:", value: summary.diaDiem)
            }

            if !summary.ketLuan.isEmpty {
                Text("Kết luận & Chỉ đạo:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                ForEach(summary.ketLuan, id: \.self) { item in
                    Text("• \(item)")
                        .font(.body)
                }
            }

            if !summary.deXuat.isEmpty {
                Text("Đề xuất & Kiến nghị:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                ForEach(summary.deXuat, id: \.self) { item in
                    Text("• \(item)")
                        .font(.body)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .fontWeight(.medium)
                .frame(width: 90, alignment: .leading)
            Text(value.isEmpty ? "Không xác định" : value)
                .foregroundColor(.primary)
            Spacer()
        }
        .font(.subheadline)
    }

    private func transcriptCard(transcript: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Văn bản cuộc họp (Transcript)")
                .font(.headline)
            Text(transcript)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Audio Actions

    private func togglePlayAudio() {
        guard let path = meeting?.audioFilePath, FileManager.default.fileExists(atPath: path) else {
            errorMessage = "File âm thanh không tồn tại"
            return
        }

        if isPlaying {
            audioPlayer?.pause()
            isPlaying = false
            playbackTimer?.invalidate()
        } else {
            if audioPlayer == nil {
                do {
                    audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
                } catch {
                    errorMessage = "Không thể phát audio: \(error.localizedDescription)"
                    return
                }
            }

            audioPlayer?.play()
            isPlaying = true

            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
                guard let player = audioPlayer else { return }
                if player.isPlaying {
                    playbackProgress = player.currentTime / player.duration
                } else {
                    isPlaying = false
                    playbackProgress = 0
                    playbackTimer?.invalidate()
                }
            }
        }
    }

    private func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playbackTimer?.invalidate()
    }

    // MARK: - AI Actions

    private func startTranscribe() {
        guard let m = meeting else { return }
        let groqKey = KeychainManager.shared.get(key: .groqApiKey)
        guard !groqKey.isEmpty else {
            errorMessage = "Vui lòng vào Cài đặt để nhập Groq API Key (gsk_...)"
            return
        }

        isProcessing = true
        progressPercent = 5
        statusMessage = "Đang gửi file âm thanh lên Groq Whisper..."

        Task {
            do {
                let text = try await GroqAsrService.shared.transcribe(
                    audioFileURL: URL(fileURLWithPath: m.audioFilePath),
                    apiKey: groqKey
                ) { p in
                    DispatchQueue.main.async {
                        progressPercent = p
                    }
                }

                await MainActor.run {
                    store.updateTranscript(id: m.id, transcript: text)
                    loadMeetingData()
                    isProcessing = false
                    statusMessage = "Chuyển văn bản thành công!"
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func startSummarize() {
        guard let m = meeting else { return }
        let deepSeekKey = KeychainManager.shared.get(key: .deepSeekApiKey)
        guard !deepSeekKey.isEmpty else {
            errorMessage = "Vui lòng vào Cài đặt để nhập DeepSeek API Key"
            return
        }

        isProcessing = true
        progressPercent = 10
        statusMessage = "DeepSeek đang phân tích biên bản..."

        Task {
            do {
                let json = try await DeepSeekSummarizerService.shared.summarize(
                    transcript: m.transcript,
                    apiKey: deepSeekKey
                ) { p in
                    DispatchQueue.main.async {
                        progressPercent = p
                    }
                }

                await MainActor.run {
                    store.updateSummary(id: m.id, summaryJson: json)
                    loadMeetingData()
                    isProcessing = false
                    statusMessage = "Tóm tắt thành công!"
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
