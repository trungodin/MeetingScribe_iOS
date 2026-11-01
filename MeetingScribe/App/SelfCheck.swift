//
//  SelfCheck.swift
//  MeetingScribe
//
//  Bộ tự kiểm tra chạy ngay trên máy (không cần mạng, không cần Xcode).
//
//  Vì sao cần: dự án build bằng xtool trên Windows/WSL nên không chạy được
//  XCTest của Apple. Các kiểm tra dưới đây khoá lại những hành vi dễ vỡ nhất
//  (phân loại lỗi → có thử lại hay không, chạy tiếp sau khi lỗi, đọc database
//  cũ, mốc thời gian, xuất PDF/Word) và hiển thị kết quả ngay trong app.
//

import Foundation

public struct SelfCheckResult: Identifiable {
    public let id = UUID()
    public let name: String
    public let passed: Bool
    /// Thông tin thành công, hoặc lý do hỏng khi `passed == false`
    public let detail: String
}

public enum SelfCheck {

    /// Lỗi của chính bộ kiểm tra (không phải lỗi app)
    private struct CheckFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Chạy tất cả

    public static func runAll() -> [SelfCheckResult] {
        AppLog.info("Bắt đầu tự kiểm tra (\(checks.count) mục)", .app)

        let results: [SelfCheckResult] = checks.map { item in
            let result = check(item.name, item.body)
            if result.passed {
                AppLog.debug("✔ \(result.name): \(result.detail)")
            } else {
                AppLog.error("✘ \(result.name): \(result.detail)")
            }
            return result
        }

        let failed = results.filter { !$0.passed }.count
        AppLog.info("Tự kiểm tra xong: \(results.count - failed)/\(results.count) đạt")
        return results
    }

    private typealias Check = (name: String, body: () throws -> String)

    private static var checks: [Check] {
        [
            ("Lỗi mạng → phân loại là mất kết nối", {
                let failure = AiFailureClassifier.classify(URLError(.notConnectedToInternet))
                try expect(failure == .offline, "nhận được \(failure)")
                try expect(failure.isRetryable, "mất mạng phải thử lại được")
                return "offline · \(failure.shortLabel)"
            }),
            ("Quá thời gian chờ → thử lại được", {
                let failure = AiFailureClassifier.classify(URLError(.timedOut))
                try expect(failure == .timedOut, "nhận được \(failure)")
                try expect(failure.isRetryable, "timeout phải thử lại được")
                return "timedOut · \(failure.shortLabel)"
            }),
            ("HTTP 503 → thử lại được", {
                let failure = AiFailureClassifier.classify(NSError(domain: "GroqAsrService", code: 503))
                try expect(failure == .serverError(503), "nhận được \(failure)")
                try expect(failure.isRetryable, "5xx phải thử lại được")
                return "serverError(503)"
            }),
            ("HTTP 401 → dừng và nhắc kiểm tra API Key", {
                let error = NSError(
                    domain: "GroqAsrService",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid API Key"]
                )
                let failure = AiFailureClassifier.classify(error)
                try expect(failure == .unauthorized("Invalid API Key"), "nhận được \(failure)")
                try expect(!failure.isRetryable, "401 không được thử lại (chỉ tốn thời gian)")
                try expect(failure.userMessage.contains("API Key"), "câu báo lỗi thiếu hướng dẫn API Key")
                return failure.userMessage
            }),
            ("HTTP 429 → thử lại được", {
                let failure = AiFailureClassifier.classify(NSError(domain: "DeepSeek", code: 429))
                try expect(failure == .rateLimited(""), "nhận được \(failure)")
                try expect(failure.isRetryable, "429 phải thử lại được")
                return "rateLimited"
            }),
            ("Người dùng bấm Huỷ → không phải lỗi", {
                let failure = AiFailureClassifier.classify(CancellationError())
                try expect(failure == .cancelled, "nhận được \(failure)")
                try expect(!failure.isRetryable, "huỷ thì không thử lại")
                return "cancelled"
            }),
            ("Chính sách thử lại: 3 lần, chờ 2s/5s/12s", {
                let policy = ChunkedTranscriber.RetryPolicy.default
                try expect(policy.maxAttempts == 3, "số lần thử = \(policy.maxAttempts)")
                try expect(policy.delays == [2, 5, 12], "khoảng chờ = \(policy.delays)")
                return "\(policy.maxAttempts) lần · \(policy.delays)"
            }),
            ("Chạy tiếp sau khi lỗi giữa chừng", {
                // Đang dở 1/3 đoạn → phải tạo được tiến trình chạy tiếp
                let partial = Meeting(
                    id: 1,
                    title: "Họp dở",
                    transcript: "Nội dung đoạn 1",
                    transcribedChunkCount: 1,
                    transcribedChunkTotal: 3
                )
                let resume = partial.resumableTranscription
                try expect(resume?.completedChunks == 1, "không tạo được tiến trình chạy tiếp")
                try expect(resume?.totalChunks == 3, "tổng số đoạn sai")

                // Đã xong 3/3 → không được mời chạy tiếp
                let finished = Meeting(
                    id: 2,
                    title: "Đã xong",
                    transcript: "Đủ nội dung",
                    transcribedChunkCount: 3,
                    transcribedChunkTotal: 3
                )
                try expect(finished.resumableTranscription == nil, "đã xong mà vẫn báo chạy tiếp")

                // Có mốc tiến trình nhưng không có văn bản → không dùng lại được
                let empty = Meeting(
                    id: 3,
                    title: "Rỗng",
                    transcript: "",
                    transcribedChunkCount: 2,
                    transcribedChunkTotal: 3
                )
                try expect(empty.resumableTranscription == nil, "không có văn bản mà vẫn báo chạy tiếp")
                return "1/3 chạy tiếp · 3/3 và 0 ký tự thì không"
            }),
            ("Lưu/đọc mốc thời gian qua JSON", {
                let segments = [
                    TranscriptSegment(startMs: 0, endMs: 2_000, text: "Xin chào"),
                    TranscriptSegment(startMs: 2_000, endMs: 4_500, text: "Bắt đầu họp")
                ]
                let meeting = Meeting(id: 7, title: "Họp", transcript: "Xin chào\nBắt đầu họp", segments: segments)
                let data = try JSONEncoder().encode([meeting])
                let decoded = try JSONDecoder().decode([Meeting].self, from: data)
                try expect(decoded.first?.segments == segments, "mốc thời gian bị mất khi lưu")
                return "\(segments.count) mốc giữ nguyên"
            }),
            ("Đọc database bản cũ (chưa có trường mới)", {
                let base = Meeting(id: 1, title: "Cuộc họp cũ", transcript: "nội dung")
                let encoded = try JSONEncoder().encode(base)
                guard var dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
                    throw CheckFailure(message: "không tạo được JSON thử nghiệm")
                }
                // Bản cũ thực sự không có 3 khoá này
                dict.removeValue(forKey: "segments")
                dict.removeValue(forKey: "transcribedChunkCount")
                dict.removeValue(forKey: "transcribedChunkTotal")

                let legacyData = try JSONSerialization.data(withJSONObject: dict)
                let decoded = try JSONDecoder().decode(Meeting.self, from: legacyData)
                try expect(decoded.segments == nil, "segments phải là nil")
                try expect(decoded.transcribedChunkCount == nil, "transcribedChunkCount phải là nil")
                try expect(decoded.transcript == "nội dung", "mất văn bản cũ")
                return "decode OK, không mất dữ liệu"
            }),
            ("Mốc thời gian: định dạng và tìm câu đang phát", {
                let short = TranscriptSegment.format(milliseconds: 65_000)
                try expect(short == "01:05", "65s → \(short)")
                let long = TranscriptSegment.format(milliseconds: 3_725_000)
                try expect(long == "1:02:05", "hơn 1 giờ → \(long)")

                let segments = [
                    TranscriptSegment(startMs: 0, endMs: 1_000, text: "a"),
                    TranscriptSegment(startMs: 1_000, endMs: 3_000, text: "b")
                ]
                try expect(TranscriptSegment.index(at: 1.5, in: segments) == 1, "1,5s phải thuộc câu thứ 2")
                try expect(TranscriptSegment.index(at: 9, in: segments) == nil, "ngoài phạm vi phải là nil")
                return "01:05 · 1:02:05 · tô sáng đúng câu"
            }),
            ("Tên file xuất: bỏ ký tự cấm", {
                let name = DetailView.safeFileName("Bien ban/2026:hop*1?<x>.docx")
                try expect(!name.contains("/") && !name.contains(":") && !name.contains("*"), "còn ký tự cấm: \(name)")
                try expect(!DetailView.safeFileName("   ").isEmpty, "tên rỗng phải có giá trị mặc định")
                return name
            }),
            ("Bản text dùng cho nút Copy", {
                let text = sampleSummary().plainText
                try expect(text.contains("BIÊN BẢN CUỘC HỌP"), "thiếu tiêu đề")
                try expect(text.contains("Họp giao ban tháng 11"), "thiếu tên cuộc họp")
                try expect(text.contains("II. KẾT LUẬN CUỘC HỌP"), "thiếu phần kết luận")
                return "\(text.count) ký tự"
            }),
            ("Xuất PDF (A4, tự ngắt trang)", {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("selfcheck-\(UUID().uuidString).pdf")
                defer { try? FileManager.default.removeItem(at: url) }

                _ = try PdfExporter.shared.exportToPdf(
                    summary: sampleSummary(),
                    organizationName: "Phòng Giáo dục và Đào tạo",
                    outputPath: url
                )
                let data = try Data(contentsOf: url)
                try expect(data.count > 2_000, "file PDF quá nhỏ (\(data.count) byte)")
                let head = String(data: data.prefix(4), encoding: .ascii) ?? ""
                try expect(head == "%PDF", "thiếu header %PDF (nhận được \"\(head)\")")
                let body = String(decoding: data, as: UTF8.self)
                let pageCount = max(1, body.components(separatedBy: "/MediaBox").count - 1)
                return "\(data.count) byte · \(pageCount) trang"
            }),
            ("Xuất Word NĐ 30 (.docx)", {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("selfcheck-\(UUID().uuidString).docx")
                defer { try? FileManager.default.removeItem(at: url) }

                _ = try DocxExporter.shared.exportToWord(
                    summary: sampleSummary(),
                    organizationName: "Phòng Giáo dục và Đào tạo",
                    outputPath: url
                )
                let data = try Data(contentsOf: url)
                try expect(data.count > 1_000, "file Word quá nhỏ (\(data.count) byte)")
                try expect(data.prefix(2).elementsEqual([0x50, 0x4B]), "không phải file OpenXML (ZIP)")
                return "\(data.count) byte"
            }),
            ("Định dạng dung lượng bộ nhớ", {
                let text = StorageUsage.format(1_500_000)
                try expect(!text.isEmpty, "chuỗi rỗng")
                try expect(text.contains("MB") || text.contains("KB"), "thiếu đơn vị: \(text)")
                return "1.500.000 byte → \(text)"
            })
        ]
    }

    // MARK: - Tiện ích

    private static func check(_ name: String, _ body: () throws -> String) -> SelfCheckResult {
        do {
            return SelfCheckResult(name: name, passed: true, detail: try body())
        } catch {
            return SelfCheckResult(name: name, passed: false, detail: error.localizedDescription)
        }
    }

    private static func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition {
            throw CheckFailure(message: message())
        }
    }

    /// Dữ liệu mẫu đủ các mục để kiểm tra cả DOCX và PDF
    private static func sampleSummary() -> MeetingSummary {
        MeetingSummary(
            tenCuocHop: "Họp giao ban tháng 11",
            thoiGian: "08:00 ngày 01/11/2026",
            diaDiem: "Phòng họp số 1",
            chuTri: "Nguyễn Văn A",
            thuKy: "Trần Thị B",
            thanhPhan: ["Nguyễn Văn A", "Trần Thị B", "Lê Văn C"],
            noiDungChinh: [
                ContentItem(tieuDe: "Tiến độ công việc", noiDung: "Đã hoàn thành 80% kế hoạch tháng."),
                ContentItem(tieuDe: "Khó khăn", noiDung: "Thiếu nhân sự ở bộ phận tiếp nhận hồ sơ.")
            ],
            ketLuan: ["Tiếp tục thực hiện theo kế hoạch đã duyệt."],
            deXuat: ["Bổ sung 02 nhân sự trong tháng tới."]
        )
    }
}
