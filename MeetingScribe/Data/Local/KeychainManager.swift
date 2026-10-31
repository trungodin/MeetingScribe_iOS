//
//  KeychainManager.swift
//  MeetingScribe
//
//  Lưu trữ an toàn API key trong iOS Keychain (thay thế EncryptedSharedPreferences)
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
        case asrEngine = "KEY_ASR_ENGINE"
        case aiProvider = "KEY_AI_PROVIDER"
    }

    private init() {}

    public func sanitize(_ key: String) -> String {
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    public func save(key: Key, value: String) {
        let cleanValue = sanitize(value)
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

    public func get(key: Key) -> String {
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
            return sanitize(str)
        }
        return ""
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
