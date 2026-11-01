//
//  DeepSeekSummarizerService.swift
//  MeetingScribe
//
//  Tóm tắt biên bản cuộc họp bằng DeepSeek (deepseek-flash, tắt thinking)
//

import Foundation

public class DeepSeekSummarizerService {
    public static let shared = DeepSeekSummarizerService()

    private init() {}

    public func summarize(transcript: String, apiKey: String, onProgress: ((Int) -> Void)? = nil) async throws -> String {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "DeepSeek", code: 400, userInfo: [NSLocalizedDescriptionKey: "Transcript rỗng"])
        }

        let cleanKey = KeychainManager.shared.sanitize(apiKey)
        guard !cleanKey.isEmpty else {
            throw NSError(domain: "DeepSeek", code: 401, userInfo: [NSLocalizedDescriptionKey: "Chưa cấu hình DeepSeek API Key"])
        }

        onProgress?(15)
        let chunks = PromptBuilder.splitTranscript(transcript)

        if chunks.count == 1 {
            let json = try await callDeepSeek(
                systemPrompt: PromptBuilder.buildSystemPrompt(),
                userPrompt: PromptBuilder.buildUserPrompt(transcript: transcript),
                apiKey: cleanKey
            )
            onProgress?(100)
            return json
        } else {
            var chunkSummaries: [String] = []
            for (idx, chunk) in chunks.enumerated() {
                let chunkJson = try await callDeepSeek(
                    systemPrompt: PromptBuilder.buildSystemPrompt(),
                    userPrompt: PromptBuilder.buildChunkPrompt(chunkIndex: idx, totalChunks: chunks.count, chunk: chunk),
                    apiKey: cleanKey
                )
                chunkSummaries.append(chunkJson)
                let p = 20 + Int(Double(idx + 1) / Double(chunks.count) * 60)
                onProgress?(p)
            }

            let merged = try await callDeepSeek(
                systemPrompt: PromptBuilder.buildSystemPrompt(),
                userPrompt: PromptBuilder.buildMergePrompt(chunkSummaries: chunkSummaries),
                apiKey: cleanKey
            )
            onProgress?(100)
            return merged
        }
    }

    private func callDeepSeek(systemPrompt: String, userPrompt: String, apiKey: String) async throws -> String {
        guard let url = URL(string: AiEndpoints.deepSeekBase + "chat/completions") else {
            throw NSError(domain: "DeepSeek", code: 400, userInfo: [NSLocalizedDescriptionKey: "Sai URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "model": AiEndpoints.deepSeekModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "thinking": ["type": "disabled"],
            "response_format": ["type": "json_object"],
            "temperature": 0.2,
            "max_tokens": 4096
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "DeepSeek", code: -1, userInfo: [NSLocalizedDescriptionKey: "Phản hồi không hợp lệ"])
        }

        if httpResponse.statusCode == 200 {
            if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = root["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                return cleanJsonResponse(content)
            }
            throw NSError(domain: "DeepSeek", code: -2, userInfo: [NSLocalizedDescriptionKey: "Phản hồi DeepSeek không đúng định dạng"])
        } else {
            throw Self.friendlyError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    // MARK: - Thông báo lỗi thân thiện

    /// DeepSeek trả lỗi tiếng Anh trong JSON → đổi sang câu tiếng Việt có hành động cụ thể.
    static func friendlyError(statusCode: Int, data: Data) -> NSError {
        let raw = String(data: data, encoding: .utf8) ?? ""
        var detail = raw
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = root["error"] as? [String: Any],
           let message = error["message"] as? String {
            detail = message
        }
        let short = detail.count > 200 ? String(detail.prefix(200)) + "…" : detail

        switch statusCode {
        case 401, 403:
            return NSError(
                domain: "DeepSeek",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "DeepSeek từ chối API Key (HTTP \(statusCode)).\nVào Cài đặt ➔ DeepSeek API Key để dán key mới (lấy tại platform.deepseek.com/api_keys) rồi bấm Lưu."]
            )
        case 402:
            return NSError(
                domain: "DeepSeek",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Tài khoản DeepSeek đã hết số dư (HTTP 402). Nạp thêm hoặc chuyển sang Google Gemini trong Cài đặt."]
            )
        case 429:
            return NSError(
                domain: "DeepSeek",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "DeepSeek đang giới hạn tần suất (HTTP 429). Chờ khoảng 30–60 giây rồi bấm tóm tắt lại."]
            )
        case 500...599:
            return NSError(
                domain: "DeepSeek",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Máy chủ DeepSeek đang gặp sự cố (HTTP \(statusCode)). Vui lòng thử lại sau ít phút."]
            )
        default:
            return NSError(
                domain: "DeepSeek",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "DeepSeek lỗi \(statusCode): \(short)"]
            )
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

