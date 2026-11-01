//
//  MeetingScribeApp.swift
//  MeetingScribe
//
//  Entry point chính của ứng dụng iOS (SwiftUI App)
//

import SwiftUI

@main
struct MeetingScribeApp: App {
    init() {
        Self.cleanupRemovedOfflineData()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }

    /// Chế độ nhận dạng offline (Whisper trên máy) đã được gỡ bỏ khỏi ứng dụng.
    /// Bản cũ có thể còn model GGML (57–181MB) trong `Documents/models` và cấu hình
    /// ASR = "WHISPER" trong Keychain → dọn sạch để app chỉ chạy online.
    private static func cleanupRemovedOfflineData() {
        let fm = FileManager.default
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let modelsDir = docs.appendingPathComponent("models", isDirectory: true)
            if fm.fileExists(atPath: modelsDir.path) {
                try? fm.removeItem(at: modelsDir)
            }
        }

        if KeychainManager.shared.get(key: .asrEngine, defaultValue: "GROQ") == "WHISPER" {
            KeychainManager.shared.save(key: .asrEngine, value: "GROQ")
        }
    }
}

