//
//  DocxExporter.swift
//  MeetingScribe
//
//  Xuất file Word .docx đúng chuẩn thể thức văn bản hành chính Nghị định 30/2020/NĐ-CP
//  Tạo file OpenXML ZIP chuẩn 100% bằng Swift thuần (hỗ trợ mở hoàn hảo trên mọi ứng dụng Word, WPS, Drive, Files)
//

import Foundation
import zlib

public class DocxExporter {
    public static let shared = DocxExporter()

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

        // 1. Chuẩn bị nội dung thay thế
        let org = organizationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "ỦY BAN NHÂN DÂN"
            : organizationName.uppercased()

        let title = summary.tenCuocHop.isEmpty ? "BIÊN BẢN CUỘC HỌP" : summary.tenCuocHop.uppercased()
        let time = summary.thoiGian.isEmpty ? "Không xác định" : summary.thoiGian
        let location = summary.diaDiem.isEmpty ? "Phòng họp cơ quan" : summary.diaDiem
        let chair = summary.chuTri.isEmpty ? "Không xác định" : summary.chuTri
        let secretary = summary.thuKy.isEmpty ? "Không xác định" : summary.thuKy
        let participants = summary.thanhPhan.isEmpty ? "Các thành viên tham dự" : summary.thanhPhan.joined(separator: ", ")

        // Ngày tháng năm địa danh
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "vi_VN")
        dateFormatter.dateFormat = "..., ngày dd tháng MM năm yyyy"
        let dateString = dateFormatter.string(from: Date())

        // 2. Tạo nội dung XML cho diễn biến và kết luận
        let conclusionsToUse = customConclusions ?? summary.ketLuan
        var contentXml = ""

        // Phần I: Diễn biến
        if !summary.noiDungChinh.isEmpty {
            contentXml += """
            <w:p><w:pPr><w:spacing w:before="240" w:after="120"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:b/><w:sz w:val="28"/><w:u w:val="single"/></w:rPr><w:t>I. DIỄN BIẾN VÀ NỘI DUNG CUỘC HỌP</w:t></w:r></w:p>
            """
            for (idx, item) in summary.noiDungChinh.enumerated() {
                contentXml += """
                <w:p><w:pPr><w:spacing w:before="120" w:after="60"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:b/><w:sz w:val="26"/></w:rPr><w:t>\(idx + 1). \(escapeXml(item.tieuDe))</w:t></w:r></w:p>
                <w:p><w:pPr><w:ind w:firstLine="720"/><w:jc w:val="both"/><w:spacing w:line="276" w:lineRule="auto"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="26"/></w:rPr><w:t>\(escapeXml(item.noiDung))</w:t></w:r></w:p>
                """
            }
        }

        // Phần II: Kết luận
        if !conclusionsToUse.isEmpty {
            contentXml += """
            <w:p><w:pPr><w:spacing w:before="240" w:after="120"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:b/><w:sz w:val="28"/><w:u w:val="single"/></w:rPr><w:t>II. KẾT LUẬN VÀ CHỈ ĐẠO CỦA CHỦ TRÌ</w:t></w:r></w:p>
            """
            for (idx, item) in conclusionsToUse.enumerated() {
                contentXml += """
                <w:p><w:pPr><w:ind w:left="360"/><w:spacing w:after="60"/><w:jc w:val="both"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="26"/></w:rPr><w:t>- \(idx + 1). \(escapeXml(item))</w:t></w:r></w:p>
                """
            }
        }

        // Đề xuất nếu có
        if !summary.deXuat.isEmpty {
            contentXml += """
            <w:p><w:pPr><w:spacing w:before="240" w:after="120"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:b/><w:sz w:val="28"/><w:u w:val="single"/></w:rPr><w:t>III. ĐỀ XUẤT, KIẾN NGHỊ</w:t></w:r></w:p>
            """
            for (idx, item) in summary.deXuat.enumerated() {
                contentXml += """
                <w:p><w:pPr><w:ind w:left="360"/><w:spacing w:after="60"/><w:jc w:val="both"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="26"/></w:rPr><w:t>• \(escapeXml(item))</w:t></w:r></w:p>
                """
            }
        }

        // 3. Thay thế các placeholder vào document.xml gốc
        var docXml = DocxTemplateData.documentXmlTemplate
        docXml = docXml.replacingOccurrences(of: "${dia_danh_ngay_thang}", with: escapeXml(dateString))
        docXml = docXml.replacingOccurrences(of: "${ten_cuoc_hop}", with: escapeXml(title))
        docXml = docXml.replacingOccurrences(of: "${thoi_gian}", with: escapeXml(time))
        docXml = docXml.replacingOccurrences(of: "${dia_diem}", with: escapeXml(location))
        docXml = docXml.replacingOccurrences(of: "${danh_sach_thanh_phan}", with: escapeXml(participants))
        docXml = docXml.replacingOccurrences(of: "${chu_tri}", with: escapeXml(chair))
        docXml = docXml.replacingOccurrences(of: "${ten_chu_tri}", with: escapeXml(chair))
        docXml = docXml.replacingOccurrences(of: "${ten_thu_ky}", with: escapeXml(secretary))
        docXml = docXml.replacingOccurrences(of: "${thoi_gian_ket_thuc}", with: "Cuộc họp kết thúc cùng ngày.")

        // Thay thế paragraph bookmark ${noi_dung_cuoc_hop} bằng chuỗi paragraph nội dung
        let targetP = "<w:p><w:pPr><w:spacing w:after=\"200\"/><w:jc w:val=\"both\"/></w:pPr><w:bookmarkStart w:id=\"1\" w:name=\"NOI_DUNG\"/><w:r><w:rPr><w:rFonts w:ascii=\"Times New Roman\" w:hAnsi=\"Times New Roman\"/><w:i/><w:color w:val=\"787878\"/><w:sz w:val=\"26\"/></w:rPr><w:t>${noi_dung_cuoc_hop}</w:t></w:r><w:bookmarkEnd w:id=\"1\"/></w:p>"
        if docXml.contains(targetP) {
            docXml = docXml.replacingOccurrences(of: targetP, with: contentXml)
        } else {
            docXml = docXml.replacingOccurrences(of: "${noi_dung_cuoc_hop}", with: "")
        }

        // 4. Giải nén các file phụ thuộc của template mẫu NĐ 30
        var allFiles: [String: Data] = [:]
        allFiles["word/document.xml"] = docXml.data(using: .utf8) ?? Data()

        for (filename, info) in DocxTemplateData.auxiliaryFiles {
            if let compressedData = Data(base64Encoded: info.base64Compressed) {
                let decompressed = decompressZlib(data: compressedData, uncompressedSize: info.uncompressedSize)
                allFiles[filename] = decompressed
            }
        }

        // 5. Đóng gói thành file ZIP .docx chuẩn
        let zipData = createZipArchive(files: allFiles)
        try zipData.write(to: destinationURL, options: .atomic)

        return destinationURL
    }

    private func escapeXml(_ str: String) -> String {
        return str.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    // MARK: - Zlib Decompressor

    private func decompressZlib(data: Data, uncompressedSize: Int) -> Data {
        var dest = Data(count: uncompressedSize)
        var destLen = uLongf(uncompressedSize)

        data.withUnsafeBytes { srcBytes in
            dest.withUnsafeMutableBytes { destBytes in
                _ = uncompress(
                    destBytes.bindMemory(to: Bytef.self).baseAddress,
                    &destLen,
                    srcBytes.bindMemory(to: Bytef.self).baseAddress,
                    uLong(data.count)
                )
            }
        }
        dest.count = Int(destLen)
        return dest
    }

    // MARK: - Pure Swift ZIP Builder (PKZip Specification)

    private func createZipArchive(files: [String: Data]) -> Data {
        var records: [Data] = []
        var cdRecords: [Data] = []
        var offset: UInt32 = 0

        for (filename, fileData) in files {
            guard let nameBytes = filename.data(using: .utf8) else { continue }
            let size = UInt32(fileData.count)

            // Tính CRC32
            var crcValue: UInt32 = 0
            fileData.withUnsafeBytes { raw in
                let ptr = raw.bindMemory(to: Bytef.self).baseAddress
                crcValue = UInt32(crc32(0, ptr, uInt(fileData.count)))
            }

            // Local File Header (30 bytes + filename + data)
            var localHeader = Data()
            localHeader.appendUInt32(0x04034b50)  // Signature
            localHeader.appendUInt16(20)          // Version needed
            localHeader.appendUInt16(0)           // Flags
            localHeader.appendUInt16(0)           // Compression: Stored (0)
            localHeader.appendUInt16(0)           // Mod time
            localHeader.appendUInt16(0)           // Mod date
            localHeader.appendUInt32(crcValue)    // CRC32
            localHeader.appendUInt32(size)        // Compressed size
            localHeader.appendUInt32(size)        // Uncompressed size
            localHeader.appendUInt16(UInt16(nameBytes.count)) // File name length
            localHeader.appendUInt16(0)           // Extra field length
            localHeader.append(nameBytes)
            localHeader.append(fileData)

            records.append(localHeader)

            // Central Directory Header (46 bytes + filename)
            var cdHeader = Data()
            cdHeader.appendUInt32(0x02014b50)     // Signature
            cdHeader.appendUInt16(20)             // Version made by
            cdHeader.appendUInt16(20)             // Version needed
            cdHeader.appendUInt16(0)              // Flags
            cdHeader.appendUInt16(0)              // Compression: Stored (0)
            cdHeader.appendUInt16(0)              // Mod time
            cdHeader.appendUInt16(0)              // Mod date
            cdHeader.appendUInt32(crcValue)       // CRC32
            cdHeader.appendUInt32(size)           // Compressed size
            cdHeader.appendUInt32(size)           // Uncompressed size
            cdHeader.appendUInt16(UInt16(nameBytes.count)) // File name length
            cdHeader.appendUInt16(0)              // Extra field length
            cdHeader.appendUInt16(0)              // File comment length
            cdHeader.appendUInt16(0)              // Disk number start
            cdHeader.appendUInt16(0)              // Internal file attributes
            cdHeader.appendUInt32(0)              // External file attributes
            cdHeader.appendUInt32(offset)         // Relative offset of local header
            cdHeader.append(nameBytes)

            cdRecords.append(cdHeader)

            offset += UInt32(localHeader.count)
        }

        var centralDirectoryData = Data()
        for cd in cdRecords {
            centralDirectoryData.append(cd)
        }

        let cdSize = UInt32(centralDirectoryData.count)
        let cdOffset = offset
        let totalEntries = UInt16(files.count)

        // End of Central Directory Record (22 bytes)
        var eocd = Data()
        eocd.appendUInt32(0x06054b50)             // Signature
        eocd.appendUInt16(0)                      // Disk number
        eocd.appendUInt16(0)                      // Disk with CD
        eocd.appendUInt16(totalEntries)           // Entries on disk
        eocd.appendUInt16(totalEntries)           // Total entries
        eocd.appendUInt32(cdSize)                 // Size of CD
        eocd.appendUInt32(cdOffset)               // Offset of CD
        eocd.appendUInt16(0)                      // Comment length

        var result = Data()
        for rec in records {
            result.append(rec)
        }
        result.append(centralDirectoryData)
        result.append(eocd)

        return result
    }
}

// MARK: - Binary Extensions

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { ptr in
            append(contentsOf: ptr)
        }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { ptr in
            append(contentsOf: ptr)
        }
    }
}
