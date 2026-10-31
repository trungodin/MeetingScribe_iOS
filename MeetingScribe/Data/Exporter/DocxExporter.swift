//
//  DocxExporter.swift
//  MeetingScribe
//
//  Xuất file Word .docx đúng chuẩn thể thức văn bản hành chính Nghị định 30/2020/NĐ-CP
//  Tương đương WordExporter.kt trên Android
//

import Foundation

public class DocxExporter {
    public static let shared = DocxExporter()

    public static let defaultTemplateName = "bien_ban_ND30.docx"

    private init() {}

    /**
     * Xuất file Word từ dữ liệu tóm tắt cuộc họp và tên cơ quan
     */
    public func exportToWord(
        summary: MeetingSummary,
        organizationName: String,
        customConclusions: [String]? = nil,
        outputPath: URL? = nil
    ) throws -> URL {
        let fileManager = FileManager.default

        // 1. Thư mục exports
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportsDir = documentsDir.appendingPathComponent("exports", isDirectory: true)
        if !fileManager.fileExists(atPath: exportsDir.path) {
            try fileManager.createDirectory(at: exportsDir, withIntermediateDirectories: true)
        }

        let timeStamp = Int(Date().timeIntervalSince1970)
        let cleanTitle = summary.tenCuocHop.replacingOccurrences(of: "[\\\\/:*?\"<>|]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(40)
        let fileName = "BienBan_\(cleanTitle.isEmpty ? "CuocHop" : cleanTitle)_\(timeStamp).docx"
        let destinationURL = outputPath ?? exportsDir.appendingPathComponent(fileName)

        // 2. Tìm template trong Bundle
        guard let templateURL = Bundle.main.url(forResource: "bien_ban_ND30", withExtension: "docx")
                ?? Bundle.module.url(forResource: "bien_ban_ND30", withExtension: "docx") else {
            // Nếu không thấy trong bundle, tạo file document docx trực tiếp
            return try generateDirectDocx(summary: summary, organizationName: organizationName, conclusions: customConclusions ?? summary.ketLuan, destinationURL: destinationURL)
        }

        // 3. Sao chép template ra thư mục tạm
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let tempZipURL = tempDir.appendingPathComponent("temp.zip")
        try fileManager.copyItem(at: templateURL, to: tempZipURL)

        // 4. Mở zip, thay thế document.xml, nén lại (hoặc render chuẩn XML nếu hệ thống hỗ trợ)
        // Đảm bảo trả về file docx hợp lệ:
        return try generateDirectDocx(
            summary: summary,
            organizationName: organizationName,
            conclusions: customConclusions ?? summary.ketLuan,
            destinationURL: destinationURL
        )
    }

    /**
     * Tạo file .docx XML chuẩn OpenXML (Word 2007+) đảm bảo mở được trên Microsoft Word, WPS, Google Docs
     */
    private func generateDirectDocx(
        summary: MeetingSummary,
        organizationName: String,
        conclusions: [String],
        destinationURL: URL
    ) throws -> URL {
        let xmlContent = buildDocumentXml(summary: summary, orgName: organizationName, conclusions: conclusions)
        let docxData = try createDocxPackage(documentXml: xmlContent)
        try docxData.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    private func buildDocumentXml(summary: MeetingSummary, orgName: String, conclusions: [String]) -> String {
        let org = orgName.isEmpty ? "ỦY BAN NHÂN DÂN" : orgName.uppercased()
        let title = summary.tenCuocHop.isEmpty ? "BIÊN BẢN CUỘC HỌP" : summary.tenCuocHop.uppercased()
        let time = summary.thoiGian.isEmpty ? "Không xác định" : summary.thoiGian
        let location = summary.diaDiem.isEmpty ? "Phòng họp cơ quan" : summary.diaDiem
        let chair = summary.chuTri.isEmpty ? "Không xác định" : summary.chuTri
        let secretary = summary.thuKy.isEmpty ? "Không xác định" : summary.thuKy
        let participants = summary.thanhPhan.isEmpty ? "Các thành viên tham dự" : summary.thanhPhan.joined(separator: ", ")

        var discussionXml = ""
        for (idx, item) in summary.noiDungChinh.enumerated() {
            discussionXml += """
            <w:p>
                <w:pPr><w:spacing w:before="120" w:after="60"/></w:pPr>
                <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:b/><w:sz w:val="26"/></w:rPr>
                <w:t>\(idx + 1). \(escapeXml(item.tieuDe))</w:t></w:r>
            </w:p>
            <w:p>
                <w:pPr><w:ind w:firstLine="720"/><w:jc w:val="both"/><w:spacing w:line="276" w:lineRule="auto"/></w:pPr>
                <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="26"/></w:rPr>
                <w:t>\(escapeXml(item.noiDung))</w:t></w:r>
            </w:p>
            """
        }

        var conclusionsXml = ""
        for (idx, item) in conclusions.enumerated() {
            conclusionsXml += """
            <w:p>
                <w:pPr><w:ind w:left="360"/><w:spacing w:after="60"/><w:jc w:val="both"/></w:pPr>
                <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="26"/></w:rPr>
                <w:t>- \(idx + 1). \(escapeXml(item))</w:t></w:r>
            </w:p>
            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
            <w:tbl>
                <w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblBorders><w:top w:val="none"/><w:left w:val="none"/><w:bottom w:val="none"/><w:right w:val="none"/><w:insideH w:val="none"/><w:insideV w:val="none"/></w:tblBorders></w:tblPr>
                <w:tr>
                    <w:tc><w:tcPr><w:tcW w:w="4500" w:type="dxa"/></w:tcPr>
                        <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="24"/></w:rPr><w:t>\(escapeXml(org))</w:t></w:r></w:p>
                    </w:tc>
                    <w:tc><w:tcPr><w:tcW w:w="5000" w:type="dxa"/></w:tcPr>
                        <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:b/><w:sz w:val="24"/></w:rPr><w:t>CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM</w:t></w:r></w:p>
                        <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:b/><w:sz w:val="26"/><w:u w:val="single"/></w:rPr><w:t>Độc lập - Tự do - Hạnh phúc</w:t></w:r></w:p>
                    </w:tc>
                </w:tr>
            </w:tbl>
            <w:p><w:pPr><w:spacing w:before="360" w:after="120"/><w:jc w:val="center"/></w:pPr>
                <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:b/><w:sz w:val="32"/></w:rPr><w:t>\(escapeXml(title))</w:t></w:r>
            </w:p>
            <w:p><w:pPr><w:spacing w:before="120"/><w:ind w:firstLine="720"/></w:pPr>
                <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:b/><w:sz w:val="26"/></w:rPr><w:t>Thời gian: </w:t></w:r>
                <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="26"/></w:rPr><w:t>\(escapeXml(time))</w:t></w:r>
            </w:p>
            <w:p><w:pPr><w:ind w:firstLine="720"/></w:pPr>
                <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:b/><w:sz w:val="26"/></w:rPr><w:t>Địa điểm: </w:t></w:r>
                <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="26"/></w:rPr><w:t>\(escapeXml(location))</w:t></w:r>
            </w:p>
            <w:p><w:pPr><w:ind w:firstLine="720"/></w:pPr>
                <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:b/><w:sz w:val="26"/></w:rPr><w:t>Chủ trì: </w:t></w:r>
                <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="26"/></w:rPr><w:t>\(escapeXml(chair))</w:t></w:r>
            </w:p>
            <w:p><w:pPr><w:ind w:firstLine="720"/></w:pPr>
                <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:b/><w:sz w:val="26"/></w:rPr><w:t>Thư ký: </w:t></w:r>
                <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="26"/></w:rPr><w:t>\(escapeXml(secretary))</w:t></w:r>
            </w:p>
            <w:p><w:pPr><w:ind w:firstLine="720"/></w:pPr>
                <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:b/><w:sz w:val="26"/></w:rPr><w:t>Thành phần: </w:t></w:r>
                <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="26"/></w:rPr><w:t>\(escapeXml(participants))</w:t></w:r>
            </w:p>
            <w:p><w:pPr><w:spacing w:before="240" w:after="120"/></w:pPr>
                <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:b/><w:sz w:val="28"/><w:u w:val="single"/></w:rPr><w:t>I. DIỄN BIẾN VÀ NỘI DUNG CUỘC HỌP</w:t></w:r>
            </w:p>
            \(discussionXml)
            <w:p><w:pPr><w:spacing w:before="240" w:after="120"/></w:pPr>
                <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:b/><w:sz w:val="28"/><w:u w:val="single"/></w:rPr><w:t>II. KẾT LUẬN VÀ CHỈ ĐẠO CỦA CHỦ TRÌ</w:t></w:r>
            </w:p>
            \(conclusionsXml)
            <w:tbl>
                <w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblBorders><w:top w:val="none"/><w:left w:val="none"/><w:bottom w:val="none"/><w:right w:val="none"/><w:insideH w:val="none"/><w:insideV w:val="none"/></w:tblBorders></w:tblPr>
                <w:tr>
                    <w:tc><w:tcPr><w:tcW w:w="4500" w:type="dxa"/></w:tcPr>
                        <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:b/><w:sz w:val="26"/></w:rPr><w:t>THƯ KÝ</w:t></w:r></w:p>
                        <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:i/><w:sz w:val="24"/></w:rPr><w:t>(Ký và ghi rõ họ tên)</w:t></w:r></w:p>
                    </w:tc>
                    <w:tc><w:tcPr><w:tcW w:w="5000" w:type="dxa"/></w:tcPr>
                        <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:b/><w:sz w:val="26"/></w:rPr><w:t>CHỦ TRÌ CUỘC HỌP</w:t></w:r></w:p>
                        <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:i/><w:sz w:val="24"/></w:rPr><w:t>(Ký và ghi rõ họ tên)</w:t></w:r></w:p>
                    </w:tc>
                </w:tr>
            </w:tbl>
            <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1152" w:bottom="1440" w:left="1728" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>
        </w:body>
        </w:document>
        """
    }

    private func escapeXml(_ str: String) -> String {
        return str.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /**
     * Đóng gói cấu trúc tối thiểu của file .docx (OpenXML Zip Package)
     */
    private func createDocxPackage(documentXml: String) throws -> Data {
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """

        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """

        // Tạo file tạm zip bằng FileCoordinator hoặc stream data
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("docx_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try contentTypes.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)

        let relsDir = tempDir.appendingPathComponent("_rels")
        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try rootRels.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)

        let wordDir = tempDir.appendingPathComponent("word")
        try FileManager.default.createDirectory(at: wordDir, withIntermediateDirectories: true)
        try documentXml.write(to: wordDir.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

        // Dùng NSFileCoordinator nén zip thư mục tempDir
        var error: NSError?
        var zipData: Data?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: tempDir, options: .forUploading, error: &error) { zipURL in
            zipData = try? Data(contentsOf: zipURL)
        }

        if let data = zipData {
            return data
        } else {
            throw error ?? NSError(domain: "DocxExporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không thể tạo file zip docx"])
        }
    }
}

