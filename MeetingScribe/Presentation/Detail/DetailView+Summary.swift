//
//  DetailView+Summary.swift
//  MeetingScribe
//
//  Tab Tóm tắt AI: hiển thị biên bản bóc tách theo thể thức Nghị định 30/2020/NĐ-CP.
//

import SwiftUI
import AVFoundation
import UIKit

extension DetailView {

    // MARK: - 3. Tab Summary

    func summaryTabView(meeting: Meeting) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isProcessing {
                    processingCard
                }

                if let summary = meeting.parsedSummary {
                    summaryContentView(summary: summary)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Chưa có tóm tắt biên bản")
                            .font(.headline)
                        Text("Tự động bóc tách thành phần, nội dung chính, kết luận theo thể thức Nghị định 30/2020/NĐ-CP.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: startSummarize) {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("Tóm tắt bằng AI")
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(meeting.transcript.isEmpty ? Color.gray : Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(meeting.transcript.isEmpty || isProcessing)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding(16)
        }
    }

    func summaryContentView(summary: MeetingSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                // Copy nhanh biên bản dạng chữ (dán vào Zalo/Email mà không cần xuất file)
                Button {
                    UIPasteboard.general.string = summary.plainText
                    errorMessage = "Đã copy biên bản vào bộ nhớ tạm."
                } label: {
                    Label("Copy biên bản", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                Spacer()
            }

            Group {
                summaryRow(title: "Cuộc họp:", value: summary.tenCuocHop)
                summaryRow(title: "Thời gian:", value: summary.thoiGian)
                summaryRow(title: "Địa điểm:", value: summary.diaDiem)
                summaryRow(title: "Chủ trì:", value: summary.chuTri)
                summaryRow(title: "Thư ký:", value: summary.thuKy)
                if !summary.thanhPhan.isEmpty {
                    summaryRow(title: "Thành phần:", value: summary.thanhPhan.joined(separator: ", "))
                }
            }

            Divider()

            if !summary.noiDungChinh.isEmpty {
                Text("I. NỘI DUNG CHÍNH")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                ForEach(Array(summary.noiDungChinh.enumerated()), id: \.offset) { idx, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(idx + 1). \(item.tieuDe)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        Text(item.noiDung)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(8)
                }
            }

            if !summary.ketLuan.isEmpty {
                Text("II. KẾT LUẬN & CHỈ ĐẠO")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                ForEach(Array(summary.ketLuan.enumerated()), id: \.offset) { idx, item in
                    Text("- \(item)")
                        .font(.body)
                }
            }

            if !summary.deXuat.isEmpty {
                Text("III. ĐỀ XUẤT, KIẾN NGHỊ")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                ForEach(Array(summary.deXuat.enumerated()), id: \.offset) { idx, item in
                    Text("• \(item)")
                        .font(.body)
                }
            }
        }
    }

    /// Một hàng "nhãn: giá trị" của biên bản.
    /// Cỡ chữ thường: nhãn và giá trị cùng dòng. Cỡ chữ trợ năng (Accessibility): xếp dọc để chữ không bị cắt.
    @ViewBuilder
    func summaryRow(title: String, value: String) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.bold)
                Text(value.isEmpty ? "Không xác định" : value)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.subheadline)
        } else {
            HStack(alignment: .top) {
                Text(title)
                    .fontWeight(.bold)
                    .frame(width: 95, alignment: .leading)
                Text(value.isEmpty ? "Không xác định" : value)
                    .foregroundColor(.primary)
                Spacer()
            }
            .font(.subheadline)
        }
    }
}
