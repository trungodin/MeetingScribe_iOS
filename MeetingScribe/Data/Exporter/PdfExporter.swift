//
//  PdfExporter.swift
//  MeetingScribe
//
//  Xuất biên bản cuộc họp ra PDF (khổ A4) để gửi Zalo/Email hoặc in trực tiếp.
//  Dùng CÙNG dữ liệu `MeetingSummary` với bản Word NĐ 30 nên hai bản không bao giờ lệch nhau.
//

import Foundation
import UIKit
import CoreText

public final class PdfExporter {
    public static let shared = PdfExporter()

    /// A4 ở 72 dpi (595 × 842 pt)
    private let pageSize = CGSize(width: 595, height: 842)
    private let margin: CGFloat = 44

    private init() {}

    /// Tạo file PDF trong Documents/exports (hoặc `outputPath`) và trả về đường dẫn.
    public func exportToPdf(
        summary: MeetingSummary,
        organizationName: String,
        outputPath: URL? = nil
    ) throws -> URL {
        let document = attributedDocument(summary: summary, organizationName: organizationName)
        let data = renderPdf(text: document)

        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("exports", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let cleanTitle = summary.tenCuocHop
            .replacingOccurrences(of: "[\\\\/:*?\"<>|]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(40)
        let fileName = "BienBan_\(cleanTitle.isEmpty ? "CuocHop" : cleanTitle)_\(Int(Date().timeIntervalSince1970)).pdf"
        let destinationURL = outputPath ?? directory.appendingPathComponent(fileName)

        try data.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    // MARK: - Dựng nội dung

    private func attributedDocument(summary: MeetingSummary, organizationName: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = UIFont.systemFont(ofSize: 12)

        func append(
            _ text: String,
            font: UIFont? = nil,
            alignment: NSTextAlignment = .justified,
            spacingAfter: CGFloat = 6
        ) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineSpacing = 2
            paragraph.paragraphSpacing = spacingAfter
            result.append(NSAttributedString(
                string: text + "\n",
                attributes: [.font: font ?? bodyFont, .paragraphStyle: paragraph]
            ))
        }

        let org = organizationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "ỦY BAN NHÂN DÂN"
            : organizationName.uppercased()
        append(org, font: .boldSystemFont(ofSize: 11), alignment: .center, spacingAfter: 2)
        append("Số: ......../BB-........", font: .systemFont(ofSize: 10), alignment: .center, spacingAfter: 12)

        append("BIÊN BẢN CUỘC HỌP", font: .boldSystemFont(ofSize: 16), alignment: .center, spacingAfter: 2)
        let title = summary.tenCuocHop.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            append(title.uppercased(), font: .boldSystemFont(ofSize: 13), alignment: .center, spacingAfter: 10)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "vi_VN")
        dateFormatter.dateFormat = "HH:mm 'ngày' dd 'tháng' MM 'năm' yyyy"
        append(
            "Thời gian: \(summary.thoiGian.isEmpty ? dateFormatter.string(from: Date()) : summary.thoiGian)",
            alignment: .left,
            spacingAfter: 2
        )
        append(
            "Địa điểm: \(summary.diaDiem.isEmpty ? "Phòng họp cơ quan" : summary.diaDiem)",
            alignment: .left,
            spacingAfter: 10
        )

        append("Thành phần tham dự:", font: .boldSystemFont(ofSize: 12), alignment: .left, spacingAfter: 2)
        let participants = summary.thanhPhan.isEmpty ? ["Các thành viên tham dự"] : summary.thanhPhan
        for participant in participants {
            append("• \(participant)", alignment: .left, spacingAfter: 1)
        }

        append("Chủ trì: \(summary.chuTri.isEmpty ? "Không xác định" : summary.chuTri)", alignment: .left, spacingAfter: 2)
        append("Thư ký: \(summary.thuKy.isEmpty ? "Không xác định" : summary.thuKy)", alignment: .left, spacingAfter: 14)

        if !summary.noiDungChinh.isEmpty {
            append("I. DIỄN BIẾN VÀ NỘI DUNG CUỘC HỌP", font: .boldSystemFont(ofSize: 12), alignment: .left, spacingAfter: 6)
            for (index, item) in summary.noiDungChinh.enumerated() {
                append("\(index + 1). \(item.tieuDe)", font: .boldSystemFont(ofSize: 12), alignment: .left, spacingAfter: 2)
                if !item.noiDung.isEmpty {
                    append(item.noiDung, alignment: .justified, spacingAfter: 6)
                }
            }
        }

        if !summary.ketLuan.isEmpty {
            append("II. KẾT LUẬN CUỘC HỌP", font: .boldSystemFont(ofSize: 12), alignment: .left, spacingAfter: 6)
            for item in summary.ketLuan {
                append("• \(item)", alignment: .justified, spacingAfter: 4)
            }
        }

        if !summary.deXuat.isEmpty {
            append("III. ĐỀ XUẤT, KIẾN NGHỊ", font: .boldSystemFont(ofSize: 12), alignment: .left, spacingAfter: 6)
            for item in summary.deXuat {
                append("• \(item)", alignment: .justified, spacingAfter: 4)
            }
        }

        append("", spacingAfter: 14)
        append("THƯ KÝ", font: .boldSystemFont(ofSize: 12), alignment: .right, spacingAfter: 2)
        append(
            summary.thuKy.isEmpty ? "(Ký, ghi rõ họ tên)" : summary.thuKy,
            alignment: .right,
            spacingAfter: 2
        )

        return result
    }

    // MARK: - Render PDF nhiều trang

    /// Vẽ nội dung bằng CoreText: tự ngắt trang khi hết chỗ, nên biên bản dài vẫn đủ nội dung.
    private func renderPdf(text: NSAttributedString) -> Data {
        let pageRect = CGRect(origin: .zero, size: pageSize)
        let textRect = pageRect.insetBy(dx: margin, dy: margin)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextCreator as String: "MeetingScribe"]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        return renderer.pdfData { context in
            let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
            var location = 0
            let totalLength = text.length

            repeat {
                context.beginPage()
                let cgContext = context.cgContext

                cgContext.saveGState()
                // CoreText vẽ theo trục y hướng lên → lật lại cho đúng toạ độ UIKit
                cgContext.textMatrix = .identity
                cgContext.translateBy(x: 0, y: pageRect.height)
                cgContext.scaleBy(x: 1, y: -1)

                let path = CGPath(rect: textRect, transform: nil)
                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    CFRange(location: location, length: 0),
                    path,
                    nil
                )
                CTFrameDraw(frame, cgContext)
                cgContext.restoreGState()

                let visible = CTFrameGetVisibleStringRange(frame)
                // Không vẽ được gì thêm (font lỗi/văn bản rỗng) → dừng để không lặp vô tận
                if visible.length <= 0 { break }
                location += visible.length
            } while location < totalLength
        }
    }
}

extension MeetingSummary {
    /// Bản text thuần của biên bản — dùng cho nút Copy (dán vào Zalo, Email, Word đều đọc được).
    public var plainText: String {
        var lines: [String] = []
        lines.append("BIÊN BẢN CUỘC HỌP")
        if !tenCuocHop.isEmpty { lines.append(tenCuocHop) }
        lines.append("")
        lines.append("Thời gian: \(thoiGian.isEmpty ? "Không xác định" : thoiGian)")
        lines.append("Địa điểm: \(diaDiem.isEmpty ? "Không xác định" : diaDiem)")
        lines.append("Chủ trì: \(chuTri.isEmpty ? "Không xác định" : chuTri)")
        lines.append("Thư ký: \(thuKy.isEmpty ? "Không xác định" : thuKy)")
        if !thanhPhan.isEmpty {
            lines.append("Thành phần: \(thanhPhan.joined(separator: ", "))")
        }

        if !noiDungChinh.isEmpty {
            lines.append("")
            lines.append("I. DIỄN BIẾN VÀ NỘI DUNG CUỘC HỌP")
            for (index, item) in noiDungChinh.enumerated() {
                lines.append("\(index + 1). \(item.tieuDe)")
                if !item.noiDung.isEmpty { lines.append(item.noiDung) }
            }
        }

        if !ketLuan.isEmpty {
            lines.append("")
            lines.append("II. KẾT LUẬN CUỘC HỌP")
            lines.append(contentsOf: ketLuan.map { "• \($0)" })
        }

        if !deXuat.isEmpty {
            lines.append("")
            lines.append("III. ĐỀ XUẤT, KIẾN NGHỊ")
            lines.append(contentsOf: deXuat.map { "• \($0)" })
        }

        return lines.joined(separator: "\n")
    }
}
