//
//  DetailView.swift
//  MeetingScribe
//
//  Màn hình Chi tiết cuộc họp: Phát lại audio (Seekbar + Tua 5s), Tab Transcript / Summary,
//  Hộp thoại xem trước & chỉnh sửa trước khi xuất Word NĐ 30, Chia sẻ file.
//

import SwiftUI
import AVFoundation

public struct DetailView: View {
    let meetingId: Int64

    @StateObject private var store = MeetingStore.shared
    @State private var meeting: Meeting?
    @State private var selectedTab = 0 // 0: Transcript, 1: Tóm tắt biên bản

    // Audio Player
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playbackPosition: Double = 0
    @State private var totalDuration: Double = 0
    @State private var playbackTimer: Timer?

    // Tiến trình AI
    @State private var isProcessing = false
    @State private var progressPercent = 0
    @State private var statusMessage = ""
    @State private var errorMessage: String?

    // Xuất file & Edit trước khi xuất
    @State private var showingEditExportSheet = false
    @State private var showingShareSheet = false
    @State private var exportedFileURL: URL?
    @State private var shareAudioURL: URL?
    @State private var showingAudioShareSheet = false

    // Dữ liệu chỉnh sửa trước khi xuất
    @State private var editTitle = ""
    @State private var editOrg = ""
    @State private var editChair = ""
    @State private var editSecretary = ""
    @State private var editTime = ""
    @State private var editLocation = ""
    @State private var editConclusions = ""

    public init(meetingId: Int64) {
        self.meetingId = meetingId
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let m = meeting {
                // 1. Trình phát Audio (Audio Player Card đầy đủ Seekbar + Tua 5s)
                audioPlayerCard(meeting: m)

                // 2. Thanh chuyển Tab (Văn bản / Tóm tắt)
                Picker("", selection: $selectedTab) {
                    Text("Văn bản gốc").tag(0)
                    Text("Tóm tắt AI").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // 3. Nội dung Tab
                TabView(selection: $selectedTab) {
                    transcriptTabView(meeting: m)
                        .tag(0)

                    summaryTabView(meeting: m)
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // 4. Thanh nút hành động phía dưới (Xuất Word, Chia sẻ)
                bottomActionBar(meeting: m)
            } else {
                ProgressView()
                    .frame(maxHeight: .infinity)
            }
        }
        .navigationTitle(meeting?.title ?? "Chi tiết cuộc họp")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let m = meeting, !m.exportFilePath.isEmpty {
                    Button(action: {
                        exportedFileURL = URL(fileURLWithPath: m.exportFilePath)
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
        .sheet(isPresented: $showingAudioShareSheet) {
            if let url = shareAudioURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showingEditExportSheet) {
            editExportModalView
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
        if let path = meeting?.audioFilePath, FileManager.default.fileExists(atPath: path) {
            if let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) {
                totalDuration = player.duration
            }
        }
    }

    // MARK: - 1. Audio Player Card (Seekbar + Tua lùi / tới 5s)

    private func audioPlayerCard(meeting: Meeting) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(formatDuration(playbackPosition))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()

                // Nút chia sẻ file ghi âm gốc
                Button(action: shareAudioFile) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Xuất audio")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }

                Spacer()
                Text(formatDuration(totalDuration > 0 ? totalDuration : Double(meeting.durationMs) / 1000))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Thanh tua thời gian Seekbar
            Slider(value: Binding(
                get: { playbackPosition },
                set: { newVal in
                    playbackPosition = newVal
                    audioPlayer?.currentTime = newVal
                }
            ), in: 0...max(1, totalDuration > 0 ? totalDuration : 1))

            HStack(spacing: 32) {
                // Tua lùi 5s
                Button(action: { seekBy(-5) }) {
                    Image(systemName: "gobackward.5")
                        .font(.title2)
                        .foregroundColor(.primary)
                }

                // Phát / Dừng
                Button(action: togglePlayAudio) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                }

                // Tua tới 5s
                Button(action: { seekBy(5) }) {
                    Image(systemName: "goforward.5")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - 2. Tab Transcript

    private func transcriptTabView(meeting: Meeting) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isProcessing {
                    processingCard
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
                        Button("Chuyển lại", action: startTranscribe)
                            .font(.caption)
                    }

                    Text(meeting.transcript)
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
            }
            .padding(16)
        }
    }

    // MARK: - 3. Tab Summary

    private func summaryTabView(meeting: Meeting) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isProcessing {
                    processingCard
                }

                if let summary = meeting.parsedSummary {
                    summaryContentView(summary: summary)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Chưa có tóm tắt biên bản")
                            .font(.headline)
                        Text("Tự động bóc tách thành phần, nội dung chính, kết luận theo thể thức Nghị định 30/2020/NĐ-CP.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: startSummarize) {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("Tóm tắt bằng AI")
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(meeting.transcript.isEmpty ? Color.gray : Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(meeting.transcript.isEmpty || isProcessing)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding(16)
        }
    }

    private func summaryContentView(summary: MeetingSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                summaryRow(title: "Cuộc họp:", value: summary.tenCuocHop)
                summaryRow(title: "Thời gian:", value: summary.thoiGian)
                summaryRow(title: "Địa điểm:", value: summary.diaDiem)
                summaryRow(title: "Chủ trì:", value: summary.chuTri)
                summaryRow(title: "Thư ký:", value: summary.thuKy)
                if !summary.thanhPhan.isEmpty {
                    summaryRow(title: "Thành phần:", value: summary.thanhPhan.joined(separator: ", "))
                }
            }

            Divider()

            if !summary.noiDungChinh.isEmpty {
                Text("I. NỘI DUNG CHÍNH")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                ForEach(Array(summary.noiDungChinh.enumerated()), id: \.offset) { idx, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(idx + 1). \(item.tieuDe)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        Text(item.noiDung)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(8)
                }
            }

            if !summary.ketLuan.isEmpty {
                Text("II. KẾT LUẬN & CHỈ ĐẠO")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                ForEach(Array(summary.ketLuan.enumerated()), id: \.offset) { idx, item in
                    Text("- \(item)")
                        .font(.body)
                }
            }

            if !summary.deXuat.isEmpty {
                Text("III. ĐỀ XUẤT, KIẾN NGHỊ")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                ForEach(Array(summary.deXuat.enumerated()), id: \.offset) { idx, item in
                    Text("• \(item)")
                        .font(.body)
                }
            }
        }
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .fontWeight(.bold)
                .frame(width: 95, alignment: .leading)
            Text(value.isEmpty ? "Không xác định" : value)
                .foregroundColor(.primary)
            Spacer()
        }
        .font(.subheadline)
    }

    private var processingCard: some View {
        VStack(spacing: 8) {
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
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }

    // MARK: - 4. Bottom Action Bar

    private func bottomActionBar(meeting: Meeting) -> some View {
        HStack(spacing: 12) {
            // Nút Xuất Word NĐ30
            Button(action: openEditExportModal) {
                HStack {
                    Image(systemName: "doc.fill")
                    Text("Xuất Word NĐ30")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(meeting.summaryJson.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(meeting.summaryJson.isEmpty || isProcessing)

            // Nút Chia sẻ
            Button(action: {
                if !meeting.exportFilePath.isEmpty {
                    exportedFileURL = URL(fileURLWithPath: meeting.exportFilePath)
                    showingShareSheet = true
                }
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Chia sẻ")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(meeting.exportFilePath.isEmpty ? Color.gray.opacity(0.4) : Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(meeting.exportFilePath.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: -2)
    }

    // MARK: - 5. Modal Xem trước & Chỉnh sửa trước khi Xuất Word NĐ 30

    private func openEditExportModal() {
        guard let summary = meeting?.parsedSummary else {
            errorMessage = "Vui lòng bấm Tóm tắt bằng AI trước khi xuất Word."
            return
        }

        editTitle = summary.tenCuocHop.isEmpty ? (meeting?.title ?? "") : summary.tenCuocHop
        editOrg = KeychainManager.shared.get(key: .defaultOrg, defaultValue: "ỦY BAN NHÂN DÂN")
        editChair = summary.chuTri.isEmpty ? KeychainManager.shared.get(key: .defaultChair) : summary.chuTri
        editSecretary = summary.thuKy.isEmpty ? KeychainManager.shared.get(key: .defaultSecretary) : summary.thuKy
        editTime = summary.thoiGian
        editLocation = summary.diaDiem
        editConclusions = summary.ketLuan.joined(separator: "\n")

        showingEditExportSheet = true
    }

    private var editExportModalView: some View {
        NavigationStack {
            Form {
                Section(header: Text("Thông tin cơ quan & Thể thức")) {
                    TextField("Cơ quan ban hành (in hoa)", text: $editOrg)
                    TextField("Tên cuộc họp", text: $editTitle)
                }

                Section(header: Text("Thời gian & Địa điểm")) {
                    TextField("Thời gian họp", text: $editTime)
                    TextField("Địa điểm họp", text: $editLocation)
                }

                Section(header: Text("Người ký biên bản")) {
                    TextField("Chủ trì cuộc họp", text: $editChair)
                    TextField("Thư ký ghi biên bản", text: $editSecretary)
                }

                Section(header: Text("Kết luận & Chỉ đạo (mỗi dòng 1 ý)")) {
                    TextEditor(text: $editConclusions)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Thông tin biên bản NĐ 30")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hủy") { showingEditExportSheet = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Tạo file Word") {
                        saveAndExportWord()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }

    private func saveAndExportWord() {
        showingEditExportSheet = false
        guard let m = meeting, let summary = m.parsedSummary else { return }

        isProcessing = true
        statusMessage = "Đang tạo file Word (.docx) chuẩn Nghị định 30..."
        progressPercent = 40

        let conclusionsList = editConclusions.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^[-•*]\\s*", with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }

        let updatedSummary = MeetingSummary(
            tenCuocHop: editTitle,
            thoiGian: editTime,
            diaDiem: editLocation,
            chuTri: editChair,
            thuKy: editSecretary,
            thanhPhan: summary.thanhPhan,
            noiDungChinh: summary.noiDungChinh,
            ketLuan: conclusionsList.isEmpty ? summary.ketLuan : conclusionsList,
            deXuat: summary.deXuat
        )

        Task {
            do {
                let docxURL = try DocxExporter.shared.exportToWord(
                    summary: updatedSummary,
                    organizationName: editOrg,
                    customConclusions: conclusionsList
                )

                await MainActor.run {
                    var updatedMeeting = m
                    updatedMeeting.exportFilePath = docxURL.path
                    updatedMeeting.status = .exported
                    _ = store.insert(meeting: updatedMeeting)
                    loadMeetingData()

                    isProcessing = false
                    exportedFileURL = docxURL
                    showingShareSheet = true
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = "Lỗi xuất file Word: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Audio Logic

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
                    totalDuration = audioPlayer?.duration ?? 0
                } catch {
                    errorMessage = "Không thể phát audio: \(error.localizedDescription)"
                    return
                }
            }

            audioPlayer?.play()
            isPlaying = true

            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                guard let player = audioPlayer else { return }
                if player.isPlaying {
                    playbackPosition = player.currentTime
                } else {
                    isPlaying = false
                    playbackPosition = 0
                    playbackTimer?.invalidate()
                }
            }
        }
    }

    private func seekBy(_ seconds: Double) {
        guard let player = audioPlayer else { return }
        let target = max(0, min(player.duration, player.currentTime + seconds))
        player.currentTime = target
        playbackPosition = target
    }

    private func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playbackTimer?.invalidate()
    }

    private func shareAudioFile() {
        guard let path = meeting?.audioFilePath, !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            errorMessage = "File âm thanh không tồn tại trên thiết bị."
            return
        }
        shareAudioURL = URL(fileURLWithPath: path)
        showingAudioShareSheet = true
    }

    private func formatDuration(_ sec: Double) -> String {
        let total = Int(sec)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - AI Execution

    private func startTranscribe() {
        guard let m = meeting else { return }
        let engine = KeychainManager.shared.get(key: .asrEngine, defaultValue: "GROQ")

        isProcessing = true
        progressPercent = 10

        Task {
            do {
                var text = ""
                if engine == "WHISPER" {
                    statusMessage = "Đang nhận dạng bằng Whisper Offline (trên máy)..."
                    text = try await WhisperEngine.shared.transcribe(
                        audioFileURL: URL(fileURLWithPath: m.audioFilePath)
                    ) { p in DispatchQueue.main.async { progressPercent = p } }
                } else if engine == "GEMINI" {
                    let key = KeychainManager.shared.get(key: .geminiApiKey)
                    let proxy = KeychainManager.shared.get(key: .geminiProxyUrl)
                    statusMessage = "Đang chuyển văn bản qua Google Gemini Flash..."
                    text = try await GeminiService.shared.transcribe(
                        audioFileURL: URL(fileURLWithPath: m.audioFilePath),
                        apiKey: key,
                        proxyUrl: proxy
                    ) { p in DispatchQueue.main.async { progressPercent = p } }
                } else {
                    // Groq Whisper
                    let key = KeychainManager.shared.get(key: .groqApiKey)
                    guard !key.isEmpty else {
                        throw NSError(domain: "Settings", code: 401, userInfo: [NSLocalizedDescriptionKey: "Chưa nhập Groq API Key trong Cài đặt."])
                    }
                    statusMessage = "Đang nhận dạng qua Groq Whisper large-v3-turbo..."
                    text = try await GroqAsrService.shared.transcribe(
                        audioFileURL: URL(fileURLWithPath: m.audioFilePath),
                        apiKey: key
                    ) { p in DispatchQueue.main.async { progressPercent = p } }
                }

                await MainActor.run {
                    store.updateTranscript(id: m.id, transcript: text)
                    loadMeetingData()
                    isProcessing = false
                    statusMessage = "Đã chuyển văn bản thành công!"
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
        guard let m = meeting, !m.transcript.isEmpty else { return }
        let provider = KeychainManager.shared.get(key: .aiProvider, defaultValue: "DEEPSEEK")

        isProcessing = true
        progressPercent = 15

        Task {
            do {
                var json = ""
                if provider == "GEMINI" {
                    let key = KeychainManager.shared.get(key: .geminiApiKey)
                    let proxy = KeychainManager.shared.get(key: .geminiProxyUrl)
                    statusMessage = "Google Gemini đang tóm tắt biên bản..."
                    json = try await GeminiService.shared.summarize(
                        transcript: m.transcript,
                        apiKey: key,
                        proxyUrl: proxy
                    ) { p in DispatchQueue.main.async { progressPercent = p } }
                } else {
                    // DeepSeek
                    let key = KeychainManager.shared.get(key: .deepSeekApiKey)
                    guard !key.isEmpty else {
                        throw NSError(domain: "Settings", code: 401, userInfo: [NSLocalizedDescriptionKey: "Chưa nhập DeepSeek API Key trong Cài đặt."])
                    }
                    statusMessage = "DeepSeek đang tóm tắt biên bản NĐ 30..."
                    json = try await DeepSeekSummarizerService.shared.summarize(
                        transcript: m.transcript,
                        apiKey: key
                    ) { p in DispatchQueue.main.async { progressPercent = p } }
                }

                await MainActor.run {
                    store.updateSummary(id: m.id, summaryJson: json)
                    loadMeetingData()
                    isProcessing = false
                    selectedTab = 1
                    statusMessage = "Đã tóm tắt thành công!"
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
