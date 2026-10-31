//
//  SettingsView.swift
//  MeetingScribe
//
//  Màn hình Cài đặt: Quản lý API Key Groq, DeepSeek, Gemini (lưu an toàn vào Keychain)
//

import SwiftUI

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var groqKey: String = ""
    @State private var deepSeekKey: String = ""
    @State private var geminiKey: String = ""
    @State private var geminiProxy: String = ""
    @State private var selectedAsr: String = "GROQ"
    @State private var savedAlert = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: Groq Whisper (ASR Online khuyên dùng)
                Section(header: Text("Chuyển giọng nói sang văn bản (ASR)")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Groq API Key (Khuyên dùng)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        SecureField("gsk_...", text: $groqKey)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        Text("Sử dụng model Whisper large-v3-turbo, miễn phí tốc độ cao từ console.groq.com")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Section 2: DeepSeek AI (Tóm tắt biên bản)
                Section(header: Text("Tóm tắt biên bản cuộc họp (AI)")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DeepSeek API Key (Chính)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        SecureField("sk-...", text: $deepSeekKey)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        Text("Model deepseek-flash chuẩn bóc tách Nghị định 30/2020/NĐ-CP từ platform.deepseek.com")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Section 3: Gemini (Dự phòng)
                Section(header: Text("Dự phòng (Google Gemini)")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Gemini API Key")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        SecureField("AIza...", text: $geminiKey)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cloudflare Relay / Proxy URL (Tùy chọn)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("https://relay.workers.dev", text: $geminiProxy)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    .padding(.vertical, 4)
                }

                // Section 4: Hướng dẫn
                Section(header: Text("Thông tin ứng dụng")) {
                    HStack {
                        Text("Phiên bản")
                        Spacer()
                        Text("1.0 (iOS)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Thể thức biên bản")
                        Spacer()
                        Text("Nghị định 30/2020/NĐ-CP")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Cài đặt")
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
            .alert("Đã lưu cài đặt", isPresented: $savedAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Thông tin API Key đã được bảo vệ trong iOS Keychain.")
            }
            .onAppear {
                loadSettings()
            }
        }
    }

    private func loadSettings() {
        groqKey = KeychainManager.shared.get(key: .groqApiKey)
        deepSeekKey = KeychainManager.shared.get(key: .deepSeekApiKey)
        geminiKey = KeychainManager.shared.get(key: .geminiApiKey)
        geminiProxy = KeychainManager.shared.get(key: .geminiProxyUrl)
    }

    private func saveSettings() {
        KeychainManager.shared.save(key: .groqApiKey, value: groqKey)
        KeychainManager.shared.save(key: .deepSeekApiKey, value: deepSeekKey)
        KeychainManager.shared.save(key: .geminiApiKey, value: geminiKey)
        KeychainManager.shared.save(key: .geminiProxyUrl, value: geminiProxy)
        savedAlert = true
    }
}
