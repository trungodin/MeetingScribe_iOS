//
//  GroqAsrService.swift
//  MeetingScribe
//
//  Chuyển giọng nói sang văn bản qua Groq Whisper large-v3-turbo (chuẩn Multipart)
//

import Foundation

public class GroqAsrService {
    public static let shared = GroqAsrService()

    private init() {}

    public func transcribe(audioFileURL: URL, apiKey: String, onProgress: ((Int) -> Void)? = nil) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw NSError(domain: "GroqAsrService", code: 404, userInfo: [NSLocalizedDescriptionKey: "File âm thanh không tồn tại"])
        }

        let audioData = try Data(contentsOf: audioFileURL)
        guard audioData.count > 0 else {
            throw NSError(domain: "GroqAsrService", code: 400, userInfo: [NSLocalizedDescriptionKey: "File âm thanh rỗng"])
        }

        onProgress?(10)

        guard let url = URL(string: AiEndpoints.groqBase + AiEndpoints.groqAsrPath) else {
            throw NSError(domain: "GroqAsrService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Sai định dạng URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120

        let cleanKey = KeychainManager.shared.sanitize(apiKey)
        request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // 1. model
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.appendString("\(AiEndpoints.groqAsrModel)\r\n")

        // 2. language
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        body.appendString("vi\r\n")

        // 3. response_format
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        body.appendString("json\r\n")

        // 4. temperature
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n")
        body.appendString("0\r\n")

        // 5. file
        let filename = audioFileURL.lastPathComponent
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.appendString("Content-Type: audio/m4a\r\n\r\n")
        body.append(audioData)
        body.appendString("\r\n")

        // End boundary
        body.appendString("--\(boundary)--\r\n")

        request.httpBody = body

        onProgress?(30)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GroqAsrService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Phản hồi không hợp lệ từ máy chủ"])
        }

        onProgress?(90)

        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                onProgress?(100)
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            throw NSError(domain: "GroqAsrService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Không phân tích được phản hồi JSON từ Groq"])
        } else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Lỗi \(httpResponse.statusCode)"
            throw NSError(domain: "GroqAsrService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Groq ASR thất bại: \(errorMsg)"])
        }
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

