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

    public func transcribe(audioFileURL: URL, apiKey: String, onProgress: ((Int) -> Void)? = nil) async throws -> TranscribedChunk {
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

        // 3. response_format: verbose_json để Groq trả kèm "segments" (mốc thời gian từng câu)
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        body.appendString("verbose_json\r\n")

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
                return TranscribedChunk(
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    segments: Self.parseSegments(json["segments"])
                )
            }
            throw NSError(domain: "GroqAsrService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Không phân tích được phản hồi JSON từ Groq"])
        } else {
            throw Self.friendlyError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    /// Đọc `segments` của verbose_json → mốc thời gian từng câu (Groq trả giây, ta lưu mili giây).
    /// Không có segments (model/định dạng không hỗ trợ) thì trả mảng rỗng — transcript vẫn dùng bình thường.
    static func parseSegments(_ raw: Any?) -> [TranscriptSegment] {
        guard let list = raw as? [[String: Any]] else { return [] }

        return list.compactMap { item in
            guard let start = (item["start"] as? NSNumber)?.doubleValue,
                  let end = (item["end"] as? NSNumber)?.doubleValue,
                  let text = item["text"] as? String else {
                return nil
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            return TranscriptSegment(
                startMs: Int64((start * 1000).rounded()),
                endMs: Int64((end * 1000).rounded()),
                text: trimmed
            )
        }
    }

    // MARK: - Thông báo lỗi thân thiện

    /// Chuyển lỗi HTTP của Groq thành câu tiếng Việt có hành động cụ thể.
    /// Groq trả `{"error":{"message":"..."}}` bằng tiếng Anh nên không hiện trực tiếp cho người dùng.
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
                domain: "GroqAsrService",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Groq từ chối API Key (HTTP \(statusCode)).\nVào Cài đặt ➔ Groq API Key để dán key mới (lấy tại console.groq.com/keys) rồi bấm Lưu."]
            )
        case 413:
            return NSError(
                domain: "GroqAsrService",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "File gửi lên vượt giới hạn 25MB của Groq. Hãy dùng file ghi âm của app (app tự cắt thành đoạn nhỏ) thay vì file nhập từ ngoài có dung lượng lớn."]
            )
        case 429:
            return NSError(
                domain: "GroqAsrService",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Groq đang giới hạn tần suất (HTTP 429). Chờ khoảng 30–60 giây rồi bấm chạy lại — các đoạn đã nhận dạng được giữ nguyên, không phải làm lại từ đầu."]
            )
        case 500...599:
            return NSError(
                domain: "GroqAsrService",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Máy chủ Groq đang gặp sự cố (HTTP \(statusCode)). Vui lòng thử lại sau ít phút."]
            )
        default:
            return NSError(
                domain: "GroqAsrService",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Groq ASR lỗi \(statusCode): \(short)"]
            )
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

