//
//  KeychainManager.swift
//  MeetingScribe
//
//  Lưu trữ an toàn cấu hình và API key trong iOS Keychain
//

import Foundation
import Security

public class KeychainManager {
    public static let shared = KeychainManager()

    private let service = "com.example.meetingscribe.keys"

    public enum Key: String {
        case geminiApiKey = "KEY_GEMINI_API_KEY"
        case deepSeekApiKey = "KEY_DEEPSEEK_API_KEY"
        case groqApiKey = "KEY_GROQ_API_KEY"
        case geminiProxyUrl = "KEY_GEMINI_PROXY_URL"
        case asrEngine = "KEY_ASR_ENGINE"          // "GROQ" hoặc "GEMINI" (offline Whisper đã gỡ)
        case aiProvider = "KEY_AI_PROVIDER"        // "DEEPSEEK", "GEMINI"
        case defaultOrg = "KEY_DEFAULT_ORG"
        case defaultChair = "KEY_DEFAULT_CHAIR"
        case defaultSecretary = "KEY_DEFAULT_SECRETARY"
    }

    private init() {}

    public func sanitize(_ key: String) -> String {
        var clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Người dùng hay copy kèm dấu nháy từ tài liệu/website: "AIza..." hoặc 'AIza...'
        if clean.count >= 2,
           (clean.hasPrefix("\"") && clean.hasSuffix("\"")) || (clean.hasPrefix("'") && clean.hasSuffix("'")) {
            clean = String(clean.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return clean
    }

    public func save(key: Key, value: String) {
        let cleanValue = (key == .asrEngine || key == .aiProvider || key == .defaultOrg || key == .defaultChair || key == .defaultSecretary)
            ? value.trimmingCharacters(in: .whitespacesAndNewlines)
            : sanitize(value)

        guard let data = cleanValue.data(using: .utf8) else { return }

        // Xóa item cũ nếu có
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    public func get(key: Key, defaultValue: String = "") -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess, let data = dataTypeRef as? Data, let str = String(data: data, encoding: .utf8) {
            let res = str.trimmingCharacters(in: .whitespacesAndNewlines)
            return res.isEmpty ? defaultValue : res
        }
        return defaultValue
    }

    public func delete(key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }
}
