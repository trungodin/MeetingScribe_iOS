//
//  HomeView.swift
//  MeetingScribe
//
//  Màn hình chính danh sách cuộc họp: Tìm kiếm, Import file ghi âm, Ghi âm mới
//

import SwiftUI
import UniformTypeIdentifiers

public struct HomeView: View {
    @StateObject private var store = MeetingStore.shared
    @State private var showingRecord = false
    @State private var showingSettings = false
    @State private var showingDocumentPicker = false
    @State private var selectedMeeting: Meeting?
    @State private var searchQuery: String = ""
    @State private var meetingToDelete: Meeting?
    @State private var meetingToRename: Meeting?
    @State private var renameDraft: String = ""
    @State private var errorMessage: String?
    @State private var isImporting = false

    public init() {}

    private var filteredMeetings: [Meeting] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return store.meetings
        }
        return store.meetings.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery) ||
            $0.transcript.localizedCaseInsensitiveContains(searchQuery) ||
            $0.summaryJson.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Cảnh báo khi database JSON bị hỏng (file cũ đã được sao lưu, không mất dữ liệu)
                    if let warning = store.storageWarning {
                        storageWarningBanner(warning)
                    }

                    // Thanh tìm kiếm cuộc họp
                    searchBarView

                    if filteredMeetings.isEmpty {
                        emptyStateView
                    } else {
                        meetingListView
                    }
                }
            }
            .navigationTitle("Cuộc họp của bạn")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: { showingDocumentPicker = true }) {
                            if isImporting {
                                ProgressView()
                            } else {
                                Image(systemName: "square.and.arrow.down")
                            }
                        }

                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                floatingControls
            }
            .sheet(isPresented: $showingRecord) {
                RecordView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker { url in
                    importAudio(url: url)
                }
            }
            .navigationDestination(item: $selectedMeeting) { meeting in
                DetailView(meetingId: meeting.id)
            }
            .alert("Xác nhận xóa?", isPresented: Binding(
                get: { meetingToDelete != nil },
                set: { if !$0 { meetingToDelete = nil } }
            )) {
                Button("Xóa", role: .destructive) {
                    if let m = meetingToDelete {
                        store.delete(id: m.id)
                        meetingToDelete = nil
                    }
                }
                Button("Hủy", role: .cancel) {
                    meetingToDelete = nil
                }
            } message: {
                Text("Bản ghi âm và toàn bộ nội dung tóm tắt của '\(meetingToDelete?.title ?? "")' sẽ bị xóa hoàn toàn khỏi máy.")
            }
            .alert("Thông báo", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Đồng ý", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Đổi tên cuộc họp", isPresented: Binding(
                get: { meetingToRename != nil },
                set: { if !$0 { meetingToRename = nil } }
            )) {
                TextField("Tên cuộc họp", text: $renameDraft)
                Button("Lưu") {
                    if let m = meetingToRename {
                        store.rename(id: m.id, title: renameDraft)
                    }
                    meetingToRename = nil
                }
                Button("Huỷ", role: .cancel) {
                    meetingToRename = nil
                }
            } message: {
                Text("Đặt tên dễ nhớ để tìm lại cuộc họp nhanh hơn.")
            }
            .onAppear {
                store.loadMeetings()
            }
        }
    }

    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Tìm kiếm cuộc họp...", text: $searchQuery)
                .textFieldStyle(.plain)
            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "mic.slash.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("Chưa có cuộc họp nào")
                .font(.headline)
                .foregroundColor(.primary)

            Text("Nhấn nút tròn đỏ để ghi âm trực tiếp hoặc nút 'Thêm file' để nhập bản ghi âm có sẵn từ máy.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var meetingListView: some View {
        List {
            ForEach(filteredMeetings) { meeting in
                MeetingRowView(meeting: meeting)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedMeeting = meeting
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            renameDraft = meeting.title
                            meetingToRename = meeting
                        } label: {
                            Label("Đổi tên", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            meetingToDelete = meeting
                        } label: {
                            Label("Xóa", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Banner cảnh báo dữ liệu: database JSON hỏng đã được backup (thay vì im lặng xoá trắng)
    private func storageWarningBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button(action: { store.storageWarning = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var floatingControls: some View {
        HStack(spacing: 12) {
            // Nút Thêm file ghi âm từ điện thoại
            Button(action: { showingDocumentPicker = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.badge.plus")
                    Text("Thêm file")
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground))
                .foregroundColor(.primary)
                .cornerRadius(24)
                .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 2)
            }

            // Nút Ghi âm mới trực tiếp
            Button(action: { showingRecord = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                    Text("Ghi âm mới")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(30)
                .shadow(color: Color.red.opacity(0.4), radius: 8, x: 0, y: 4)
            }
        }
        .padding(20)
    }

    private func importAudio(url: URL) {
        isImporting = true
        Task {
            do {
                let result = try await AudioImporter.shared.importAudioFile(from: url)
                let formatter = DateFormatter()
                formatter.dateFormat = "dd/MM/yyyy HH:mm"
                let title = "Ghi âm đã nhập \(formatter.string(from: Date()))"

                let meeting = Meeting(
                    title: title,
                    audioFilePath: result.fileURL.path,
                    durationMs: result.durationMs,
                    status: .recorded
                )

                let newId = store.insert(meeting: meeting)
                isImporting = false
                selectedMeeting = store.getMeeting(id: newId)
            } catch {
                isImporting = false
                errorMessage = "Không thể đọc file âm thanh đã chọn: \(error.localizedDescription)"
            }
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.audio, .mp3, .mpeg4Audio, UTType(filenameExtension: "m4a") ?? .audio, .wav]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let first = urls.first {
                parent.onPick(first)
            }
        }
    }
}

public struct MeetingRowView: View {
    let meeting: Meeting

    public init(meeting: Meeting) {
        self.meeting = meeting
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.title)
                .font(.headline)
                .foregroundColor(.primary)

            HStack {
                Label(meeting.formattedCreatedAt, systemImage: "calendar")
                Spacer()
                Label(meeting.formattedDuration, systemImage: "clock")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Text(meeting.status.displayName)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.15))
                .foregroundColor(statusColor)
                .cornerRadius(6)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch meeting.status {
        case .recorded: return .gray
        case .transcribing, .summarizing: return .orange
        case .transcribed: return .blue
        case .summarized: return .purple
        case .exported: return .green
        }
    }
}
