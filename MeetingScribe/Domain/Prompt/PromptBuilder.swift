//
//  PromptBuilder.swift
//  MeetingScribe
//
//  Xây dựng prompt tiếng Việt gửi cho AI (chuẩn y hệt Android)
//

import Foundation

public struct PromptBuilder {

    public static func buildSystemPrompt() -> String {
        return """
Bạn là trợ lý AI chuyên tóm tắt biên bản cuộc họp bằng tiếng Việt.

NHIỆM VỤ: Phân tích transcript cuộc họp và trích xuất thông tin theo cấu trúc biên bản hành chính Việt Nam.

QUY TẮC BẮT BUỘC:
1. Chỉ trả về JSON thuần túy, KHÔNG có markdown code fence, KHÔNG có text giải thích.
2. Nếu không xác định được thông tin nào, điền "Không xác định" hoặc để mảng rỗng.
3. Nội dung phải bằng tiếng Việt, rõ ràng, súc tích.
4. Mỗi mục trong "noi_dung_chinh" phải có tiêu đề ngắn gọn và nội dung chi tiết.
5. "ket_luan" và "de_xuat" phải là các câu hoàn chỉnh.

SCHEMA JSON BẮT BUỘC:
{
  "ten_cuoc_hop": "string - tên/chủ đề cuộc họp",
  "thoi_gian": "string - thời gian họp, định dạng dd/MM/yyyy HH:mm nếu xác định được",
  "dia_diem": "string - địa điểm họp",
  "chu_tri": "string - người chủ trì",
  "thu_ky": "string - người ghi biên bản",
  "thanh_phan": ["string - danh sách người tham dự"],
  "noi_dung_chinh": [
    {"tieu_de": "string", "noi_dung": "string"}
  ],
  "ket_luan": ["string - các kết luận của cuộc họp"],
  "de_xuat": ["string - các đề xuất, kiến nghị"]
}
"""
    }

    public static func buildUserPrompt(transcript: String) -> String {
        return """
Hãy phân tích transcript cuộc họp sau đây và trả về JSON theo đúng schema đã quy định.
Chỉ trả về JSON, không có gì khác.

TRANSCRIPT:
\(transcript)
"""
    }

    public static func buildChunkPrompt(chunkIndex: Int, totalChunks: Int, chunk: String) -> String {
        return """
Đây là phần \(chunkIndex + 1)/\(totalChunks) của transcript cuộc họp.
Hãy tóm tắt các nội dung chính, kết luận, và đề xuất trong phần này.
Trả về JSON theo schema đã quy định. Nếu phần này không có đủ thông tin cho tất cả các trường, điền "Không xác định" cho các trường thiếu.

TRANSCRIPT (Phần \(chunkIndex + 1)/\(totalChunks)):
\(chunk)
"""
    }

    public static func buildMergePrompt(chunkSummaries: [String]) -> String {
        let joined = chunkSummaries.enumerated().map { (i, s) in
            "--- Phần \(i + 1) ---\n\(s)"
        }.joined(separator: "\n\n")

        return """
Dưới đây là các phần tóm tắt từ một cuộc họp dài. Hãy tổng hợp tất cả thành MỘT biên bản cuộc họp hoàn chỉnh.
Loại bỏ thông tin trùng lặp, gộp nội dung liên quan, và trả về JSON theo đúng schema đã quy định.
Chỉ trả về JSON, không có gì khác.

CÁC PHẦN TÓM TẮT:
\(joined)
"""
    }

    public static func splitTranscript(_ transcript: String, maxWordsPerChunk: Int = 3000) -> [String] {
        let words = transcript.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if words.count <= maxWordsPerChunk {
            return [transcript]
        }

        var chunks: [String] = []
        var currentIndex = 0

        while currentIndex < words.count {
            let endIndex = min(currentIndex + maxWordsPerChunk, words.count)
            var cutPoint = endIndex

            if endIndex < words.count {
                let lowerBound = max(currentIndex + maxWordsPerChunk / 2, currentIndex)
                for i in stride(from: endIndex - 1, through: lowerBound, by: -1) {
                    let word = words[i]
                    if word.hasSuffix(".") || word.hasSuffix("?") || word.hasSuffix("!") {
                        cutPoint = i + 1
                        break
                    }
                }
            }

            let slice = words[currentIndex..<cutPoint]
            chunks.append(slice.joined(separator: " "))
            currentIndex = cutPoint
        }

        return chunks
    }
}
