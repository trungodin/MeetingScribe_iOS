//
//  AiEndpoints.swift
//  MeetingScribe
//
//  Cấu hình Endpoint cho Groq, DeepSeek và Gemini (khớp 100% với Android)
//

import Foundation

public struct AiEndpoints {
    public static let geminiDirectBase = "https://generativelanguage.googleapis.com/"
    public static let deepSeekBase = "https://api.deepseek.com/"

    // Groq - Whisper large-v3-turbo (nhanh ~8x, chuẩn OpenAI)
    public static let groqBase = "https://api.groq.com/openai/"
    public static let groqAsrPath = "v1/audio/transcriptions"
    public static let groqAsrModel = "whisper-large-v3-turbo"
    public static let groqAsrModelFallback = "whisper-large-v3"

    // DeepSeek
    public static let deepSeekModel = "deepseek-flash"

    // Proxy header
    public static let headerClient = "X-MeetingScribe-Client"
    public static let clientValue = "ios"

    public static func geminiGenerateContentUrl(proxyBaseUrl: String, model: String) -> URL? {
        let path = "v1beta/models/\(model):generateContent"
        let trimmedProxy = proxyBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedProxy.isEmpty {
            return URL(string: geminiDirectBase + path)
        } else {
            let base = trimmedProxy.hasSuffix("/") ? String(trimmedProxy.dropLast()) : trimmedProxy
            return URL(string: "\(base)/\(path)")
        }
    }

    public static func isDirectCall(proxyBaseUrl: String) -> Bool {
        return proxyBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

