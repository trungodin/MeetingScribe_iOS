//
//  AppLog.swift
//  MeetingScribe
//
//  Ghi log 2 đích:
//  1. `os.Logger` → xem bằng Console.app / `idevicesyslog` khi cắm máy tính.
//  2. Vòng đệm trong bộ nhớ (tối đa 600 dòng) → xem ngay trên iPhone ở
//     Cài đặt ➔ Chẩn đoán, không cần máy tính. Người dùng gặp lỗi chỉ cần
//     bấm "Chia sẻ log" là có đủ ngữ cảnh để tìm nguyên nhân.
//

import Foundation
import OSLog

/// Một dòng log trong bộ đệm bộ nhớ
public struct LogEntry: Identifiable, Equatable {
    public enum Level: String {
        case debug = "D"
        case info = "I"
        case warning = "W"
        case error = "E"
    }

    public let id = UUID()
    public let timeText: String
    public let level: Level
    public let category: String
    public let message: String

    public var line: String { "\(timeText) [\(level.rawValue)] \(category): \(message)" }
}

public enum AppLog {
    /// Nhóm log — dùng làm `category` của os.Logger để lọc trong Console.app
    public enum Category: String, CaseIterable {
        case app
        case record
        case transcribe
        case summarize
        case export
        case store
    }

    private static let subsystem = "com.example.meetingscribe"
    /// Số dòng giữ trong bộ nhớ (đủ để dựng lại một phiên làm việc, không tốn RAM)
    private static let capacity = 600

    /// Khoá bảo vệ toàn bộ trạng thái tĩnh bên dưới: log được gọi từ cả
    /// luồng mạng (URLSession callback) lẫn main thread.
    private static let lock = NSLock()
    private static var buffer: [LogEntry] = []
    private static var loggers: [String: Logger] = [:]

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    // MARK: - API ghi log

    public static func debug(_ message: @autoclosure () -> String, _ category: Category = .app) {
        write(level: .debug, message: message(), category: category)
    }

    public static func info(_ message: @autoclosure () -> String, _ category: Category = .app) {
        write(level: .info, message: message(), category: category)
    }

    public static func warning(_ message: @autoclosure () -> String, _ category: Category = .app) {
        write(level: .warning, message: message(), category: category)
    }

    /// Lỗi kèm đối tượng `Error` — tự thêm domain/code để đọc log là biết ngay nguyên nhân
    public static func error(_ message: @autoclosure () -> String, _ category: Category = .app, error: Error? = nil) {
        var text = message()
        if let error {
            text += " — \(describe(error))"
        }
        write(level: .error, message: text, category: category)
    }

    // MARK: - Đọc / xoá (màn hình Chẩn đoán)

    /// Các dòng log mới nhất xếp lên đầu
    public static func recent(limit: Int = 300) -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return Array(buffer.suffix(max(1, limit)).reversed())
    }

    public static func clear() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()
    }

    /// Toàn bộ log dạng text để chia sẻ ra ngoài (Zalo/Email/Files)
    public static func exportText() -> String {
        lock.lock()
        defer { lock.unlock() }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM/yyyy HH:mm:ss"

        let header = """
        MeetingScribe — log chẩn đoán
        Xuất lúc: \(formatter.string(from: Date()))
        Số dòng: \(buffer.count)

        """
        return header + (buffer.isEmpty ? "(chưa có log)" : buffer.map(\.line).joined(separator: "\n"))
    }

    // MARK: - Nội bộ

    private static func write(level: LogEntry.Level, message: String, category: Category) {
        let logger = logger(for: category)
        // `.public` để Console.app hiển thị đầy đủ nội dung (log không chứa API Key)
        switch level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }

        lock.lock()
        defer { lock.unlock() }
        buffer.append(LogEntry(
            timeText: timeFormatter.string(from: Date()),
            level: level,
            category: category.rawValue,
            message: message
        ))
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
    }

    /// Mỗi category một `Logger` (tạo 1 lần, sau đó dùng lại)
    private static func logger(for category: Category) -> Logger {
        lock.lock()
        defer { lock.unlock() }
        if let existing = loggers[category.rawValue] {
            return existing
        }
        let created = Logger(subsystem: subsystem, category: category.rawValue)
        loggers[category.rawValue] = created
        return created
    }

    /// "NSURLErrorDomain(-1009): The Internet connection appears to be offline."
    private static func describe(_ error: Error) -> String {
        if let transcriptionError = error as? TranscriptionError {
            return "TranscriptionError(\(transcriptionError.failure.shortLabel), "
                + "\(transcriptionError.completedChunks)/\(transcriptionError.totalChunks) đoạn, "
                + "\(transcriptionError.attempts) lần thử)"
        }
        let nsError = error as NSError
        return "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
    }
}
