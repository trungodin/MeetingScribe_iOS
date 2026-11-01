//
//  SettingsView.swift
//  MeetingScribe
//
//  Màn hình Cài đặt đầy đủ:
//  - Chọn Nhà cung cấp AI (Google Gemini / DeepSeek AI)
//  - Chọn Mô hình ASR (Groq Whisper large-v3-turbo / Google Gemini)
//  - Hướng dẫn lấy API Key trực quan
//  - Cấu hình thông tin cơ quan mặc định (Cơ quan, Chủ trì, Thư ký) cho biên bản NĐ 30
//

import SwiftUI

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // AI Provider & ASR Engine
    @State private var selectedAiProvider: String = "DEEPSEEK" // "DEEPSEEK" hoặc "GEMINI"
    @State private var selectedAsrEngine: String = "GROQ"       // "GROQ" hoặc "GEMINI"


    // API Keys
    @State private var groqKey: String = ""
    @State private var deepSeekKey: String = ""
    @State private var geminiKey: String = ""
    @State private var geminiProxy: String = ""

    // Ẩn/hiện mật khẩu
    @State private var showGroqKey = false
    @State private var showDeepSeekKey = false
    @State private var showGeminiKey = false

    // Thông tin mặc định văn bản NĐ 30
    @State private var defaultOrg: String = ""
    @State private var defaultChair: String = ""
    @State private var defaultSecretary: String = ""

    @State private var savedAlert = false

    // Dung lượng & dọn dẹp
    @State private var usage = StorageUsage()
    @State private var exportedCleanup = CleanupTarget()
    @State private var oldCleanup = CleanupTarget()
    @State private var cleanupMessage: String?
    @State private var showCleanupExportedConfirm = false
    @State private var showCleanupOldConfirm = false

    /// Màn hình Chẩn đoán (tự kiểm tra + log) — mở dạng sheet để không lồng NavigationStack
    @State private var showDiagnostics = false

    /// Tập cuộc họp sẽ dọn audio (id + tổng dung lượng) để hiện trên nút và hộp xác nhận
    struct CleanupTarget: Equatable {
        var ids: [Int64] = []
        var bytes: Int64 = 0
        var count: Int { ids.count }
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // MARK: 1. Nhà cung cấp AI (Tóm tắt biên bản)
                Section(header: Label("Nhà cung cấp AI (Tóm tắt)", systemImage: "sparkles")) {
                    Picker("Nhà cung cấp AI", selection: $selectedAiProvider) {
                        Text("DeepSeek AI (Khuyên dùng)").tag("DEEPSEEK")
                        Text("Google Gemini").tag("GEMINI")
                    }
                    .pickerStyle(.segmented)

                    if selectedAiProvider == "DEEPSEEK" {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Model: deepseek-flash (DeepSeek-V4.1-Flash)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Bóc tách cấu trúc biên bản NĐ 30/2020/NĐ-CP cực nhanh và rẻ.")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Link("Lấy API key tại: platform.deepseek.com ➔", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                                .font(.caption)
                                .padding(.top, 2)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Google Gemini Flash (Miễn phí)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Có thể dùng trực tiếp API Key hoặc thông qua Relay/Proxy Cloudflare.")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Link("Lấy API key tại: aistudio.google.com ➔", destination: URL(string: "https://aistudio.google.com/apikey")!)
                                .font(.caption)
                                .padding(.top, 2)
                        }
                    }
                }

                // MARK: 2. Mô hình nhận dạng giọng nói ASR
                Section(header: Label("Nhận dạng giọng nói (ASR)", systemImage: "waveform")) {
                    Picker("Mô hình ASR", selection: $selectedAsrEngine) {
                        Text("Groq Turbo").tag("GROQ")
                        Text("Gemini").tag("GEMINI")
                    }
                    .pickerStyle(.segmented)

                    if selectedAsrEngine == "GROQ" {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Groq Whisper large-v3-turbo (Online)")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Nhanh gấp ~8 lần realtime, chính xác tiếng Việt, không bị giới hạn vùng.")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Link("Lấy Groq API key tại: console.groq.com ➔", destination: URL(string: "https://console.groq.com/keys")!)
                                .font(.caption)
                                .padding(.top, 2)
                        }
                    } else {
                        Text("Google Gemini ASR Flash (Hỗ trợ audio trực tiếp).")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: 3. Nhập API Key
                Section(header: Label("Khóa bảo mật API Key (Lưu Keychain)", systemImage: "key.fill")) {
                    // Groq Key
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Groq API Key (gsk_...)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        HStack {
                            if showGroqKey {
                                TextField("gsk_...", text: $groqKey)
                                    .autocapitalization(.none)
                            } else {
                                SecureField("gsk_...", text: $groqKey)
                            }
                            Button(action: { showGroqKey.toggle() }) {
                                Image(systemName: showGroqKey ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // DeepSeek Key
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DeepSeek API Key (sk-...)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        HStack {
                            if showDeepSeekKey {
                                TextField("sk-...", text: $deepSeekKey)
                                    .autocapitalization(.none)
                            } else {
                                SecureField("sk-...", text: $deepSeekKey)
                            }
                            Button(action: { showDeepSeekKey.toggle() }) {
                                Image(systemName: showDeepSeekKey ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Gemini Key
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gemini API Key (AIzaSy...)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        HStack {
                            if showGeminiKey {
                                TextField("AIzaSy...", text: $geminiKey)
                                    .autocapitalization(.none)
                            } else {
                                SecureField("AIzaSy...", text: $geminiKey)
                            }
                            Button(action: { showGeminiKey.toggle() }) {
                                Image(systemName: showGeminiKey ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Gemini Proxy
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cloudflare Relay / Proxy Base URL (Tùy chọn)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("https://meetingscribe-relay.workers.dev", text: $geminiProxy)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                    }
                }

                // MARK: 4. Thông tin mặc định văn bản hành chính NĐ 30
                Section(header: Label("Thông tin mặc định (Biên bản NĐ 30)", systemImage: "building.2.fill")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tên cơ quan / tổ chức")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("VD: CÔNG TY CỔ PHẦN CẤP NƯỚC BẾN THÀNH", text: $defaultOrg)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chủ trì mặc định")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("VD: Nguyễn Văn A - Giám đốc", text: $defaultChair)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Thư ký mặc định")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("VD: Trần Thị B - Thư ký", text: $defaultSecretary)
                    }
                }

                // MARK: 5. Dung lượng & dọn dẹp
                Section(header: Label("Dung lượng bộ nhớ", systemImage: "internaldrive")) {
                    LabeledContent("File ghi âm") {
                        Text("\(StorageUsage.format(usage.audioBytes)) · \(usage.audioFileCount) file")
                            .foregroundColor(.secondary)
                    }
                    LabeledContent("Biên bản Word") {
                        Text(StorageUsage.format(usage.exportBytes))
                            .foregroundColor(.secondary)
                    }
                    LabeledContent("Tổng cộng") {
                        Text(StorageUsage.format(usage.totalBytes))
                            .fontWeight(.semibold)
                    }

                    Button {
                        showCleanupExportedConfirm = true
                    } label: {
                        Label("Xoá audio của cuộc họp đã có biên bản (\(exportedCleanup.count))", systemImage: "trash")
                    }
                    .disabled(exportedCleanup.count == 0)

                    Button {
                        showCleanupOldConfirm = true
                    } label: {
                        Label("Xoá audio cũ hơn 30 ngày (\(oldCleanup.count))", systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(oldCleanup.count == 0)

                    if let cleanupMessage {
                        Text(cleanupMessage)
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    Text("Xoá audio chỉ giải phóng dung lượng: văn bản và biên bản Word vẫn giữ nguyên. File chưa có văn bản sẽ không bị xoá.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // MARK: 5. Hỗ trợ & chẩn đoán
                Section(
                    header: Label("Hỗ trợ", systemImage: "stethoscope"),
                    footer: Text("Tự kiểm tra không gọi mạng: chỉ chạy các phép kiểm tra nội bộ để phát hiện sớm lỗi phân loại, mốc thời gian, xuất PDF/Word và đọc dữ liệu cũ.")
                ) {
                    Button {
                        showDiagnostics = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Chẩn đoán ứng dụng")
                                    .foregroundColor(.primary)
                                Text("Tự kiểm tra · xem log lỗi gần đây")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Cài đặt hệ thống")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Lưu") { saveSettings() }
                        .fontWeight(.bold)
                }
            }
            .alert("Đã lưu thành công", isPresented: $savedAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Tất cả cấu hình và API Key đã được bảo vệ trong iOS Keychain.")
            }
            .confirmationDialog(
                "Xoá file ghi âm của \(exportedCleanup.count) cuộc họp?",
                isPresented: $showCleanupExportedConfirm,
                titleVisibility: .visible
            ) {
                Button("Xoá audio, giữ biên bản", role: .destructive) {
                    deleteAudio(for: exportedCleanup.ids)
                }
                Button("Huỷ", role: .cancel) {}
            } message: {
                Text("Giải phóng khoảng \(StorageUsage.format(exportedCleanup.bytes)). Văn bản và biên bản Word vẫn xem lại được.")
            }
            .confirmationDialog(
                "Xoá audio cũ hơn 30 ngày của \(oldCleanup.count) cuộc họp?",
                isPresented: $showCleanupOldConfirm,
                titleVisibility: .visible
            ) {
                Button("Xoá audio cũ", role: .destructive) {
                    deleteAudio(for: oldCleanup.ids)
                }
                Button("Huỷ", role: .cancel) {}
            } message: {
                Text("Giải phóng khoảng \(StorageUsage.format(oldCleanup.bytes)). Văn bản và biên bản Word vẫn xem lại được.")
            }
            .onAppear {
                loadSettings()
                refreshStorage()
            }
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView()
            }
        }
    }

    private func loadSettings() {
        selectedAiProvider = KeychainManager.shared.get(key: .aiProvider, defaultValue: "DEEPSEEK")

        // Chế độ nhận dạng offline (Whisper) đã được gỡ bỏ: bản cũ có thể lưu "WHISPER"
        // trong Keychain, khi đó tự chuyển về Groq (online) và ghi đè lại cấu hình.
        let storedAsrEngine = KeychainManager.shared.get(key: .asrEngine, defaultValue: "GROQ")
        selectedAsrEngine = (storedAsrEngine == "GEMINI") ? "GEMINI" : "GROQ"
        if storedAsrEngine != selectedAsrEngine {
            KeychainManager.shared.save(key: .asrEngine, value: selectedAsrEngine)
        }

        groqKey = KeychainManager.shared.get(key: .groqApiKey)
        deepSeekKey = KeychainManager.shared.get(key: .deepSeekApiKey)
        geminiKey = KeychainManager.shared.get(key: .geminiApiKey)
        geminiProxy = KeychainManager.shared.get(key: .geminiProxyUrl)

        defaultOrg = KeychainManager.shared.get(key: .defaultOrg, defaultValue: "")
        defaultChair = KeychainManager.shared.get(key: .defaultChair, defaultValue: "")
        defaultSecretary = KeychainManager.shared.get(key: .defaultSecretary, defaultValue: "")
    }

    private func saveSettings() {
        KeychainManager.shared.save(key: .aiProvider, value: selectedAiProvider)
        KeychainManager.shared.save(key: .asrEngine, value: selectedAsrEngine)

        KeychainManager.shared.save(key: .groqApiKey, value: groqKey)
        KeychainManager.shared.save(key: .deepSeekApiKey, value: deepSeekKey)
        KeychainManager.shared.save(key: .geminiApiKey, value: geminiKey)
        KeychainManager.shared.save(key: .geminiProxyUrl, value: geminiProxy)

        KeychainManager.shared.save(key: .defaultOrg, value: defaultOrg)
        KeychainManager.shared.save(key: .defaultChair, value: defaultChair)
        KeychainManager.shared.save(key: .defaultSecretary, value: defaultSecretary)

        savedAlert = true
    }

    // MARK: - Dung lượng

    /// Đo lại dung lượng và danh sách có thể dọn (gọi khi mở Cài đặt và sau mỗi lần xoá)
    private func refreshStorage() {
        let store = MeetingStore.shared
        usage = store.storageUsage()

        func target(olderThanDays days: Int?) -> CleanupTarget {
            let items = store.cleanableAudio(olderThanDays: days)
            return CleanupTarget(
                ids: items.map { $0.meeting.id },
                bytes: items.reduce(Int64(0)) { $0 + $1.bytes }
            )
        }

        exportedCleanup = target(olderThanDays: nil)
        oldCleanup = target(olderThanDays: 30)
    }

    private func deleteAudio(for ids: [Int64]) {
        guard !ids.isEmpty else { return }
        let freed = MeetingStore.shared.deleteAudioFiles(meetingIds: Set(ids))
        cleanupMessage = "Đã xoá audio của \(ids.count) cuộc họp, giải phóng \(StorageUsage.format(freed))."
        AppLog.info(
            "Dọn audio \(ids.count) cuộc họp, giải phóng \(StorageUsage.format(freed))",
            .store
        )
        refreshStorage()
    }
}
