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

        let audioData = try Data(contentsOf: audioFileURL)
        let base64Audio = audioData.base64EncodedString()
        onProgress?(20)

        let prompt = "Bạn là trợ lý AI chuyên nhận dạng tiếng Việt. Hãy chuyển toàn bộ file âm thanh này thành văn bản tiếng Việt chính xác, đầy đủ từng câu từ, đúng ngữ pháp, không tóm tắt hay lược bỏ bất kỳ ý nào. Chỉ trả về nội dung văn bản thuần túy, không thêm lời chào hay giải thích gì khác."

        let requestPayload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": prompt],
                        [
                            "inlineData": [
                                "mimeType": "audio/m4a",
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

        let models = ["gemini-3.5-flash-lite", "gemini-flash-lite-latest", "gemini-3.5-flash"]
        var lastError: Error?

        for model in models {
            do {
                onProgress?(50)
                let text = try await executeGeminiRequest(payload: requestPayload, model: model, apiKey: apiKey, proxyUrl: proxyUrl)
                onProgress?(100)
                return text
            } catch {
                lastError = error
            }
        }

        throw lastError ?? NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Tất cả các model Gemini đều thất bại"])
    }

    // MARK: - Summarizer (Tóm tắt biên bản)

    public func summarize(transcript: String, apiKey: String, proxyUrl: String = "", onProgress: ((Int) -> Void)? = nil) async throws -> String {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "GeminiService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Transcript rỗng"])
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
            let errMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Gemini lỗi: \(errMsg)"])
        }
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
