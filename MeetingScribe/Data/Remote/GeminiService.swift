//
//  GeminiService.swift
//  MeetingScribe
//
//  Dịch vụ ASR và Tóm tắt bằng Google Gemini (hỗ trợ direct key và relay/proxy)
//  Tương đương GeminiAsrEngine.kt và GeminiSummarizer.kt trên Android
//

import Foundation

public class GeminiService {
    public static let shared = GeminiService()

    private init() {}

    // MARK: - ASR (Chuyển giọng nói sang văn bản)

    public func transcribe(audioFileURL: URL, apiKey: String, proxyUrl: String = "", onProgress: ((Int) -> Void)? = nil) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw NSError(domain: "GeminiService", code: 404, userInfo: [NSLocalizedDescriptionKey: "File âm thanh không tồn tại"])
        }

        // Kiểm tra API Key TRƯỚC khi đọc file: thiếu key sẽ khiến Google trả về
        // 403 PERMISSION_DENIED "callers without established identity" (khó hiểu).
        if AiEndpoints.isDirectCall(proxyBaseUrl: proxyUrl),
           KeychainManager.shared.sanitize(apiKey).isEmpty {
            throw Self.missingKeyError()
        }

        let audioData = try Data(contentsOf: audioFileURL)

        // Gemini nhận audio dạng inline base64 => toàn bộ request phải < ~20MB.
        if audioData.count > 18 * 1024 * 1024 {
            throw NSError(domain: "GeminiService", code: 413, userInfo: [NSLocalizedDescriptionKey: "File ghi âm quá lớn để gửi trực tiếp cho Gemini (tối đa ~18MB). Vui lòng chọn Groq Whisper large-v3-turbo trong Cài đặt để chuyển văn bản cho file dài."])
        }

        let base64Audio = audioData.base64EncodedString()
        onProgress?(20)

        // Gemini kiểm tra MIME: file nhập từ ngoài có thể là wav/mp3/aac, không phải luôn m4a
        let mimeType: String
        switch audioFileURL.pathExtension.lowercased() {
        case "wav": mimeType = "audio/wav"
        case "mp3": mimeType = "audio/mp3"
        case "aac", "m4a": mimeType = "audio/m4a"
        case "mp4": mimeType = "audio/mp4"
        case "ogg", "opus": mimeType = "audio/ogg"
        case "flac": mimeType = "audio/flac"
        case "aif", "aiff": mimeType = "audio/aiff"
        default: mimeType = "audio/m4a"
        }

        let prompt = "Bạn là trợ lý AI chuyên nhận dạng tiếng Việt. Hãy chuyển toàn bộ file âm thanh này thành văn bản tiếng Việt chính xác, đầy đủ từng câu từ, đúng ngữ pháp, không tóm tắt hay lược bỏ bất kỳ ý nào. Chỉ trả về nội dung văn bản thuần túy, không thêm lời chào hay giải thích gì khác."

        let requestPayload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": prompt],
                        [
                            "inlineData": [
                                "mimeType": mimeType,
                                "data": base64Audio
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.0,
                "maxOutputTokens": 8192
            ]
        ]

        // Thứ tự model: đặt alias ổn định "gemini-flash-lite-latest" lên đầu để nếu tài khoản
        // không có model mới thì vẫn nhận dạng được ngay, không phải chờ 2 lần thất bại.
        let models = ["gemini-flash-lite-latest", "gemini-3.5-flash-lite", "gemini-3.5-flash"]
        var lastError: Error?

        for model in models {
            do {
                onProgress?(50)
                let text = try await executeGeminiRequest(payload: requestPayload, model: model, apiKey: apiKey, proxyUrl: proxyUrl)
                onProgress?(100)
                return text
            } catch {
                lastError = error
                // Lỗi xác thực/quyền thì thử model khác cũng vô ích => dừng ngay
                if Self.isAuthError(error) { throw error }
            }
        }

        throw lastError ?? NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Tất cả các model Gemini đều thất bại"])
    }

    // MARK: - Summarizer (Tóm tắt biên bản)

    public func summarize(transcript: String, apiKey: String, proxyUrl: String = "", onProgress: ((Int) -> Void)? = nil) async throws -> String {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "GeminiService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Transcript rỗng"])
        }

        if AiEndpoints.isDirectCall(proxyBaseUrl: proxyUrl),
           KeychainManager.shared.sanitize(apiKey).isEmpty {
            throw Self.missingKeyError()
        }

        onProgress?(20)
        let prompt = """
        \(PromptBuilder.buildSystemPrompt())

        \(PromptBuilder.buildUserPrompt(transcript: transcript))
        """

        let requestPayload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]

        let models = ["gemini-3.5-flash", "gemini-flash-lite-latest", "gemini-flash-latest"]
        var lastError: Error?

        for model in models {
            do {
                onProgress?(60)
                let text = try await executeGeminiRequest(payload: requestPayload, model: model, apiKey: apiKey, proxyUrl: proxyUrl)
                onProgress?(100)
                return cleanJsonResponse(text)
            } catch {
                lastError = error
                if Self.isAuthError(error) { throw error }
            }
        }

        throw lastError ?? NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Tóm tắt Gemini thất bại"])
    }

    // MARK: - Helper

    private func executeGeminiRequest(payload: [String: Any], model: String, apiKey: String, proxyUrl: String) async throws -> String {
        guard let url = AiEndpoints.geminiGenerateContentUrl(proxyBaseUrl: proxyUrl, model: model) else {
            throw NSError(domain: "GeminiService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Sai cấu hình URL Gemini"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AiEndpoints.clientValue, forHTTPHeaderField: AiEndpoints.headerClient)

        if AiEndpoints.isDirectCall(proxyBaseUrl: proxyUrl) {
            let cleanKey = KeychainManager.shared.sanitize(apiKey)
            guard !cleanKey.isEmpty else { throw Self.missingKeyError() }
            request.setValue(cleanKey, forHTTPHeaderField: "x-goog-api-key")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Phản hồi không hợp lệ"])
        }

        if httpResponse.statusCode == 200 {
            if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = root["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first,
               let content = firstCandidate["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let firstPart = parts.first,
               let text = firstPart["text"] as? String {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            throw NSError(domain: "GeminiService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Không parse được kết quả Gemini"])
        } else {
            throw Self.friendlyError(
                statusCode: httpResponse.statusCode,
                data: data,
                usingProxy: !AiEndpoints.isDirectCall(proxyBaseUrl: proxyUrl)
            )
        }
    }

    // MARK: - Thông báo lỗi thân thiện

    /// Lỗi do thiếu API Key — đúng nguyên nhân của 403 PERMISSION_DENIED
    /// "Method doesn't allow unregistered callers (callers without established identity)".
    static func missingKeyError() -> NSError {
        return NSError(
            domain: "GeminiService",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Chưa nhập Gemini API Key.\nVào Cài đặt ➔ Google Gemini để dán API Key (lấy tại aistudio.google.com/apikey) rồi bấm Lưu."]
        )
    }

    /// Lỗi xác thực/quyền: thử model khác cũng thất bại nên không cần retry.
    static func isAuthError(_ error: Error) -> Bool {
        let code = (error as NSError).code
        return code == 401 || code == 403
    }

    /// Chuyển JSON lỗi của Google thành câu tiếng Việt dễ hiểu.
    /// - Parameter usingProxy: `true` nếu app đang gọi qua Cloudflare Relay/Proxy → khi đó
    ///   lỗi "unregistered callers" là do PROXY chưa gắn API Key, không phải do app.
    static func friendlyError(statusCode: Int, data: Data, usingProxy: Bool = false) -> NSError {
        let raw = String(data: data, encoding: .utf8) ?? ""
        var message = raw
        var status = ""

        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = root["error"] as? [String: Any] {
            message = (error["message"] as? String) ?? raw
            status = (error["status"] as? String) ?? ""
        }

        let lower = message.lowercased()
        let keyProblem = statusCode == 401
            || statusCode == 403
            || lower.contains("unregistered callers")
            || lower.contains("api key not valid")
            || lower.contains("api_key_invalid")

        if keyProblem {
            let statusText = status.isEmpty ? "HTTP \(statusCode)" : status
            let hint: String
            if usingProxy {
                hint = "App đang gọi qua Relay/Proxy nhưng proxy chưa gắn Gemini API Key.\nCách sửa: (1) cấu hình biến GEMINI_API_KEY cho proxy, hoặc (2) xoá trống ô \"Cloudflare Relay / Proxy Base URL\" trong Cài đặt và dán API Key trực tiếp lấy từ aistudio.google.com/apikey."
            } else {
                hint = "Kiểm tra lại: Cài đặt ➔ Google Gemini ➔ dán API Key mới lấy từ aistudio.google.com/apikey rồi bấm Lưu."
            }
            return NSError(
                domain: "GeminiService",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Gemini từ chối API Key (\(statusText)).\n\(hint)"]
            )
        }

        switch statusCode {
        case 404:
            return NSError(domain: "GeminiService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy model Gemini (404). API Key có thể chưa được bật Gemini API hoặc model không còn hỗ trợ."])
        case 429:
            return NSError(domain: "GeminiService", code: 429, userInfo: [NSLocalizedDescriptionKey: "Gemini đã hết hạn mức (quota). Vui lòng thử lại sau hoặc chuyển sang Groq/DeepSeek."])
        default:
            break
        }

        let shortMessage = message.count > 300 ? String(message.prefix(300)) + "…" : message
        return NSError(domain: "GeminiService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Gemini lỗi \(statusCode): \(shortMessage)"])
    }

    private func cleanJsonResponse(_ raw: String) -> String {
        var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("```json") {
            str = String(str.dropFirst(7))
        } else if str.hasPrefix("```") {
            str = String(str.dropFirst(3))
        }
        if str.hasSuffix("```") {
            str = String(str.dropLast(3))
        }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

