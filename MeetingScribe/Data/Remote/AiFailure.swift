//
//  AiFailure.swift
//  MeetingScribe
//
//  Phân loại lỗi khi gọi API AI (Groq/Gemini/DeepSeek): lỗi nào là tạm thời để thử lại,
//  lỗi nào người dùng phải sửa cấu hình, và câu tiếng Việt hiển thị cho người dùng.
//

import Foundation

public enum AiFailure: Equatable {
    /// Người dùng bấm Huỷ — không phải lỗi
    case cancelled
    /// Thiếu / sai API Key → phải vào Cài đặt
    case missingApiKey(String)
    /// 401 / 403
    case unauthorized(String)
    /// 404 — sai model hoặc API chưa bật
    case notFound(String)
    /// 413 — file vượt giới hạn của nhà cung cấp
    case payloadTooLarge(String)
    /// 429 — bị giới hạn tần suất / hết hạn mức
    case rateLimited(String)
    /// 5xx
    case serverError(Int)
    /// 400 — request sai (thường do tham số/định dạng file)
    case badRequest(Int, String)
    /// URLSession timeout
    case timedOut
    /// Mất mạng / mất sóng / máy bay
    case offline
    /// Đứt kết nối giữa chừng, DNS, TLS...
    case network(String)
    /// Máy chủ trả về dữ liệu không đọc được
    case badResponse(String)
    /// Không xác định
    case other(String)

    /// Lỗi tạm thời → đáng thử lại. Lỗi cấu hình (key, dung lượng, model) thì thử lại vô ích.
    public var isRetryable: Bool {
        switch self {
        case .timedOut, .offline, .network, .serverError, .rateLimited:
            return true
        case .cancelled, .missingApiKey, .unauthorized, .notFound,
             .payloadTooLarge, .badRequest, .badResponse, .other:
            return false
        }
    }

    /// Nhãn ngắn để hiện trong thông điệp "đang thử lại..."
    public var shortLabel: String {
        switch self {
        case .cancelled: return "đã huỷ"
        case .missingApiKey: return "thiếu API Key"
        case .unauthorized: return "API Key bị từ chối"
        case .notFound: return "không tìm thấy model"
        case .payloadTooLarge: return "file quá lớn"
        case .rateLimited: return "bị giới hạn tần suất"
        case .serverError: return "máy chủ AI lỗi"
        case .badRequest: return "yêu cầu không hợp lệ"
        case .timedOut: return "quá thời gian chờ"
        case .offline: return "mất kết nối mạng"
        case .network: return "kết nối bị ngắt"
        case .badResponse: return "phản hồi không đọc được"
        case .other: return "lỗi không xác định"
        }
    }

    /// Câu tiếng Việt hiển thị cho người dùng.
    /// Lỗi do service tự soạn (key sai, hết quota, 413...) đã có câu tiếng Việt cụ thể nên giữ nguyên.
    public var userMessage: String {
        switch self {
        case .cancelled:
            return "Đã huỷ."
        case .missingApiKey(let message),
             .unauthorized(let message),
             .notFound(let message),
             .payloadTooLarge(let message),
             .rateLimited(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "Nhà cung cấp AI từ chối yêu cầu. Kiểm tra lại API Key trong Cài đặt."
                : trimmed
        case .serverError(let status):
            return "Máy chủ AI đang gặp sự cố (HTTP \(status)). Vui lòng thử lại sau ít phút."
        case .badRequest(let status, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Yêu cầu không hợp lệ (HTTP \(status))." : trimmed
        case .timedOut:
            return "Máy chủ phản hồi quá chậm (quá 2 phút). Kiểm tra mạng rồi bấm chạy lại."
        case .offline:
            return "Không có kết nối mạng. Bật Wi-Fi/4G rồi bấm chạy lại."
        case .network(let detail):
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "Kết nối bị ngắt giữa chừng. Thử lại khi mạng ổn định hơn."
                : "Kết nối bị ngắt giữa chừng (\(trimmed)). Thử lại khi mạng ổn định hơn."
        case .badResponse(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Máy chủ AI trả về dữ liệu không đọc được. Vui lòng thử lại." : trimmed
        case .other(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Đã có lỗi không xác định. Vui lòng thử lại." : trimmed
        }
    }
}

public enum AiFailureClassifier {

    /// Quy đổi bất kỳ `Error` nào (NSError của service, URLError của URLSession, CancellationError)
    /// thành `AiFailure` để biết có nên thử lại hay không.
    public static func classify(_ error: Error) -> AiFailure {
        if error is CancellationError { return .cancelled }

        if let urlError = error as? URLError {
            return classify(urlError)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return classify(URLError(URLError.Code(rawValue: nsError.code)))
        }

        // Service trong app ném NSError với code = HTTP status
        switch nsError.domain {
        case "Settings":
            return .missingApiKey(nsError.localizedDescription)
        case "GroqAsrService", "GeminiService", "DeepSeek":
            return classify(statusCode: nsError.code, message: nsError.localizedDescription)
        default:
            break
        }

        if (400...599).contains(nsError.code) {
            return classify(statusCode: nsError.code, message: nsError.localizedDescription)
        }

        return .other(nsError.localizedDescription)
    }

    private static func classify(_ urlError: URLError) -> AiFailure {
        switch urlError.code {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .callIsActive:
            return .offline
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .secureConnectionFailed, .badServerResponse, .cannotLoadFromNetwork:
            return .network(urlError.localizedDescription)
        default:
            return .other(urlError.localizedDescription)
        }
    }

    private static func classify(statusCode: Int, message: String) -> AiFailure {
        switch statusCode {
        case 400:
            return .badRequest(statusCode, message)
        case 401, 403:
            return .unauthorized(message)
        case 404:
            return .notFound(message)
        case 413:
            return .payloadTooLarge(message)
        case 429:
            return .rateLimited(message)
        case 500...599:
            return .serverError(statusCode)
        case -1, -2:
            // Quy ước riêng của service: phản hồi không đọc được
            return .badResponse(message)
        default:
            return .other(message)
        }
    }

    /// Câu tiếng Việt để hiện cho người dùng với bất kỳ lỗi nào.
    public static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return description
        }
        return classify(error).userMessage
    }
}

