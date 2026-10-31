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
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "DeepSeek", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "DeepSeek thất bại: \(errorMsg)"])
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

