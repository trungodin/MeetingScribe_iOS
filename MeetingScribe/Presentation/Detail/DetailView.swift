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
    @State private var progressPercent: Double = 0
    @State private var statusMessage = ""
    @State private var errorMessage: String?
    // Giữ handle để huỷ job đang chạy + mốc thời gian bắt đầu (hiển thị "đã chạy bao lâu")
    @State private var processingTask: Task<Void, Never>?
    @State private var processingStartedAt: Date?
    // Lần cuối nhận được mốc tiến trình mới (để biết app còn "sống" hay đã treo)
    @State private var lastProgressAt: Date?

    // Xuất file & Edit trước khi xuất
    @State private var showingEditExportSheet = false

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
                    Button(action: shareExportedFile) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
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
        setupAudioPlayer()
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
                    if audioPlayer == nil {
                        setupAudioPlayer()
                    }
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
            ProgressView(value: progressPercent, total: 100)
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
                        // Whisper chỉ báo % sau mỗi 30 GIÂY audio (1 khối).
                        // Với file ngắn (1 khối) hoặc khối đầu tiên, thanh % buộc phải
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

    /// Đang chờ whisper xử lý nốt 1 khối 30 giây (chưa có mốc % mới) hay không
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

        // Chỉ báo khi thật sự lâu không nhích (whisper đang xử lý 1 khối nặng hoặc bị chặn)
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

    private func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        processingStartedAt = nil
        isProcessing = false
        progressPercent = 0
        statusMessage = "Đã huỷ."
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
            Button(action: shareExportedFile) {
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
                    ShareSheetPresenter.present(items: [docxURL])
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

    private func setupAudioPlayer() {
        guard let audioURL = meeting?.resolvedAudioURL else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.prepareToPlay()
            self.audioPlayer = player
            self.totalDuration = player.duration
        } catch {
            print("setupAudioPlayer error: \(error)")
        }
    }

    private func togglePlayAudio() {
        guard let audioURL = meeting?.resolvedAudioURL else {
            errorMessage = "File âm thanh không tồn tại trên thiết bị"
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("AVAudioSession setCategory error: \(error)")
        }

        if isPlaying {
            audioPlayer?.pause()
            isPlaying = false
            playbackTimer?.invalidate()
        } else {
            if audioPlayer == nil {
                do {
                    let player = try AVAudioPlayer(contentsOf: audioURL)
                    player.prepareToPlay()
                    audioPlayer = player
                    totalDuration = player.duration
                } catch {
                    errorMessage = "Không thể phát audio: \(error.localizedDescription)"
                    return
                }
            }

            guard let player = audioPlayer else { return }

            // Nếu đã phát gần hết hoặc hết file, bấm play sẽ tua lại từ đầu
            if player.currentTime >= player.duration - 0.2 {
                player.currentTime = 0
                playbackPosition = 0
            }

            if player.play() {
                isPlaying = true
                startPlaybackTimer()
            } else {
                errorMessage = "Không thể bắt đầu phát âm thanh. Vui lòng thử lại."
            }
        }
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let player = audioPlayer else { return }
            if player.isPlaying {
                playbackPosition = player.currentTime
            } else {
                // Đã dừng hoặc phát xong hết file
                isPlaying = false
                if player.currentTime >= player.duration - 0.2 {
                    playbackPosition = 0
                    player.currentTime = 0
                }
                playbackTimer?.invalidate()
            }
        }
    }

    private func seekBy(_ seconds: Double) {
        if audioPlayer == nil {
            setupAudioPlayer()
        }
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

    /// Chia sẻ file ghi âm gốc.
    ///
    /// Trước đây hàm này bật một `.sheet` chứa UIActivityViewController nên trên iOS mới
    /// bảng chia sẻ hiện ra một ô ĐEN. Ngoài ra file ghi âm gốc nằm trong container của app
    /// (UUID thay đổi sau mỗi lần build) nên tên file rất xấu. Vì vậy:
    ///  1. Copy sang thư mục tạm với tên thân thiện = tên cuộc họp.
    ///  2. Present bảng chia sẻ trực tiếp từ UIKit (ShareSheetPresenter).
    private func shareAudioFile() {
        guard let m = meeting else { return }
        guard let audioURL = m.resolvedAudioURL else {
            errorMessage = "File âm thanh không tồn tại trên thiết bị."
            return
        }

        let ext = audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension
        let prettyName = Self.safeFileName(m.title.isEmpty ? "Ghi am cuoc hop" : m.title) + "." + ext
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(prettyName)

        var urlToShare = audioURL
        do {
            try? FileManager.default.removeItem(at: tempURL)
            try FileManager.default.copyItem(at: audioURL, to: tempURL)
            urlToShare = tempURL
        } catch {
            // Copy lỗi thì vẫn chia sẻ file gốc
            urlToShare = audioURL
        }

        guard ShareSheetPresenter.presentFile(at: urlToShare) else {
            errorMessage = "Không mở được file âm thanh để chia sẻ. Vui lòng thử lại."
            return
        }
    }

    /// Chia sẻ file Word (.docx) đã xuất
    private func shareExportedFile() {
        guard let m = meeting, !m.exportFilePath.isEmpty else {
            errorMessage = "Chưa có file Word. Vui lòng bấm \"Xuất Word NĐ30\" trước."
            return
        }
        let url = URL(fileURLWithPath: m.exportFilePath)
        guard ShareSheetPresenter.presentFile(at: url) else {
            errorMessage = "File Word không còn trên thiết bị. Vui lòng xuất lại."
            return
        }
    }

    /// Bỏ các ký tự không hợp lệ trong tên file (Windows/iOS/Share sheet)
    static func safeFileName(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = raw
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Ghi am cuoc hop" : String(cleaned.prefix(80))
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
        guard let audioURL = m.resolvedAudioURL else {
            errorMessage = "File âm thanh không tồn tại trên thiết bị."
            return
        }
        let engine = KeychainManager.shared.get(key: .asrEngine, defaultValue: "GROQ")

        isProcessing = true
        progressPercent = 10
        processingStartedAt = Date()
        lastProgressAt = Date()
        processingTask?.cancel()

        processingTask = Task {
            do {
                var text = ""
                if engine == "WHISPER" {
                    statusMessage = "Đang nhận dạng bằng Whisper Offline (trên máy)..."
                    text = try await WhisperEngine.shared.transcribe(
                        audioFileURL: audioURL,
                        onProgress: { p in
                            DispatchQueue.main.async {
                                // Không cho thanh tiến trình chạy lùi (engine báo 8% đầu tiên)
                                progressPercent = max(progressPercent, p)
                                lastProgressAt = Date()
                            }
                        },
                        onStatus: { stage in
                            DispatchQueue.main.async { statusMessage = stage }
                        }
                    )
                } else if engine == "GEMINI" {
                    let key = KeychainManager.shared.get(key: .geminiApiKey)
                    let proxy = KeychainManager.shared.get(key: .geminiProxyUrl)
                    // Thiếu API Key là nguyên nhân phổ biến nhất của lỗi 403 PERMISSION_DENIED
                    // ("Method doesn't allow unregistered callers"). Báo ngay, rõ ràng.
                    if AiEndpoints.isDirectCall(proxyBaseUrl: proxy),
                       KeychainManager.shared.sanitize(key).isEmpty {
                        throw NSError(
                            domain: "Settings",
                            code: 401,
                            userInfo: [NSLocalizedDescriptionKey: "Chưa nhập Gemini API Key.\nVào Cài đặt ➔ Google Gemini để dán API Key (lấy tại aistudio.google.com/apikey) rồi bấm Lưu."]
                        )
                    }
                    statusMessage = "Đang chuyển văn bản qua Google Gemini Flash..."
                    text = try await GeminiService.shared.transcribe(
                        audioFileURL: audioURL,
                        apiKey: key,
                        proxyUrl: proxy
                    ) { p in
                        DispatchQueue.main.async {
                            progressPercent = Double(p)
                            lastProgressAt = Date()
                        }
                    }
                } else {
                    // Groq Whisper
                    let key = KeychainManager.shared.get(key: .groqApiKey)
                    guard !key.isEmpty else {
                        throw NSError(domain: "Settings", code: 401, userInfo: [NSLocalizedDescriptionKey: "Chưa nhập Groq API Key trong Cài đặt."])
                    }
                    statusMessage = "Đang nhận dạng qua Groq Whisper large-v3-turbo..."
                    text = try await GroqAsrService.shared.transcribe(
                        audioFileURL: audioURL,
                        apiKey: key
                    ) { p in
                        DispatchQueue.main.async {
                            progressPercent = Double(p)
                            lastProgressAt = Date()
                        }
                    }
                }

                await MainActor.run {
                    let finalTranscript = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "(Không nhận diện được giọng nói trong đoạn ghi âm này)"
                        : text
                    store.updateTranscript(id: m.id, transcript: finalTranscript)
                    loadMeetingData()
                    isProcessing = false
                    processingStartedAt = nil
                    processingTask = nil
                    progressPercent = 100
                    statusMessage = "Đã chuyển văn bản thành công!"
                }
            } catch is CancellationError {
                await MainActor.run {
                    isProcessing = false
                    processingStartedAt = nil
                    processingTask = nil
                    progressPercent = 0
                    statusMessage = "Đã huỷ."
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    processingStartedAt = nil
                    processingTask = nil
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
        processingStartedAt = Date()
        lastProgressAt = Date()
        processingTask?.cancel()

        processingTask = Task {
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
                    ) { p in
                        DispatchQueue.main.async {
                            progressPercent = Double(p)
                            lastProgressAt = Date()
                        }
                    }
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
                    ) { p in
                        DispatchQueue.main.async {
                            progressPercent = Double(p)
                            lastProgressAt = Date()
                        }
                    }
                }

                await MainActor.run {
                    store.updateSummary(id: m.id, summaryJson: json)
                    loadMeetingData()
                    isProcessing = false
                    processingStartedAt = nil
                    processingTask = nil
                    selectedTab = 1
                    statusMessage = "Đã tóm tắt thành công!"
                }
            } catch is CancellationError {
                await MainActor.run {
                    isProcessing = false
                    processingStartedAt = nil
                    processingTask = nil
                    progressPercent = 0
                    statusMessage = "Đã huỷ."
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    processingStartedAt = nil
                    processingTask = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
