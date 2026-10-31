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
    @State private var selectedAsrEngine: String = "GROQ"       // "GROQ", "GEMINI", "WHISPER"

    @ObservedObject private var modelManager = WhisperModelManager.shared

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
                        Text("Whisper Offline").tag("WHISPER")
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
                    } else if selectedAsrEngine == "GEMINI" {
                        Text("Google Gemini ASR Flash (Hỗ trợ audio trực tiếp).")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Whisper Offline (Không cần mạng Internet)")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Nhận dạng trực tiếp trên chip của iPhone. Cần tải model GGML ở mục bên dưới.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: 2.1 Quản lý Model Whisper Offline
                Section(header: Label("Model Whisper Offline (Trên máy)", systemImage: "arrow.down.circle")) {
                    ForEach(WhisperModelManager.Variant.allCases) { variant in
                        let isReady = modelManager.isModelReady(for: variant)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(variant.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(variant.note)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if isReady {
                                HStack(spacing: 8) {
                                    Text("Đã có (\(variant.approxSizeText))")
                                        .font(.caption2)
                                        .foregroundColor(.green)

                                    Button("Xóa", role: .destructive) {
                                        let path = modelManager.getModelPath(for: variant)
                                        try? FileManager.default.removeItem(at: path)
                                        modelManager.refreshModelStatus()
                                    }
                                    .font(.caption)
                                }
                            } else {
                                Button(action: { modelManager.downloadModel(variant: variant) }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.down")
                                        Text("Tải (\(variant.approxSizeText))")
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                .disabled(modelManager.isDownloading)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if modelManager.isDownloading {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: modelManager.downloadProgress, total: 1.0)
                            Text("Đang tải model: \(Int(modelManager.downloadProgress * 100))%")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        .padding(.vertical, 4)
                    }

                    if let err = modelManager.downloadError {
                        Text(err)
                            .font(.caption2)
                            .foregroundColor(.red)
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
            .onAppear {
                loadSettings()
            }
        }
    }

    private func loadSettings() {
        selectedAiProvider = KeychainManager.shared.get(key: .aiProvider, defaultValue: "DEEPSEEK")
        selectedAsrEngine = KeychainManager.shared.get(key: .asrEngine, defaultValue: "GROQ")

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
}
