//
//  DetailView+Export.swift
//  MeetingScribe
//
//  Thanh nút hành động dưới cùng, hộp thoại chỉnh sửa trước khi xuất,
//  xuất Word NĐ 30 / PDF và chia sẻ file đã xuất.
//

import SwiftUI
import AVFoundation
import UIKit

extension DetailView {

    // MARK: - 4. Bottom Action Bar

    func bottomActionBar(meeting: Meeting) -> some View {
        HStack(spacing: 10) {
            // Xuất Word NĐ 30
            Button(action: openEditExportModal) {
                actionLabel(icon: "doc.fill", title: "Word NĐ 30")
                    .background(meeting.summaryJson.isEmpty ? Color.gray : Color.blue)
            }
            .disabled(meeting.summaryJson.isEmpty || isProcessing)

            // Xuất PDF (cùng dữ liệu biên bản, tiện gửi Zalo/Email và in luôn)
            Button {
                exportPdf(meeting: meeting)
            } label: {
                actionLabel(icon: "doc.richtext", title: "PDF")
                    .background(meeting.summaryJson.isEmpty ? Color.gray : Color.indigo)
            }
            .disabled(meeting.summaryJson.isEmpty || isProcessing)

            // Chia sẻ file đã xuất
            Button(action: shareExportedFile) {
                actionLabel(icon: "square.and.arrow.up", title: "Chia sẻ")
                    .background(meeting.exportFilePath.isEmpty ? Color.gray.opacity(0.4) : Color.green)
            }
            .disabled(meeting.exportFilePath.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: -2)
    }

    /// Nhãn nút hành động ở thanh dưới (icon + chữ, tự co giãn đều nhau)
    func actionLabel(icon: String, title: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18))
            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .foregroundColor(.white)
        .cornerRadius(12)
    }

    // MARK: - 5. Modal Xem trước & Chỉnh sửa trước khi Xuất Word NĐ 30

    func openEditExportModal() {
        guard let summary = meeting?.parsedSummary else {
            errorMessage = "Vui lòng bấm Tóm tắt bằng AI trước khi xuất Word."
            return
        }

        editTitle = summary.tenCuocHop.isEmpty ? (meeting?.title ?? "") : summary.tenCuocHop
        editOrg = KeychainManager.shared.get(key: .defaultOrg, defaultValue: "ỦY BAN NHÂN DÂN")
        editChair = summary.chuTri.isEmpty ? KeychainManager.shared.get(key: .defaultChair) : summary.chuTri
        editSecretary = summary.thuKy.isEmpty ? KeychainManager.shared.get(key: .defaultSecretary) : summary.thuKy
        editTime = summary.thoiGian
        editLocation = summary.diaDiem
        editConclusions = summary.ketLuan.joined(separator: "\n")

        showingEditExportSheet = true
    }

    var editExportModalView: some View {
        NavigationStack {
            Form {
                Section(header: Text("Thông tin cơ quan & Thể thức")) {
                    TextField("Cơ quan ban hành (in hoa)", text: $editOrg)
                    TextField("Tên cuộc họp", text: $editTitle)
                }

                Section(header: Text("Thời gian & Địa điểm")) {
                    TextField("Thời gian họp", text: $editTime)
                    TextField("Địa điểm họp", text: $editLocation)
                }

                Section(header: Text("Người ký biên bản")) {
                    TextField("Chủ trì cuộc họp", text: $editChair)
                    TextField("Thư ký ghi biên bản", text: $editSecretary)
                }

                Section(header: Text("Kết luận & Chỉ đạo (mỗi dòng 1 ý)")) {
                    TextEditor(text: $editConclusions)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Thông tin biên bản NĐ 30")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hủy") { showingEditExportSheet = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Tạo file Word") {
                        saveAndExportWord()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }

    func saveAndExportWord() {
        showingEditExportSheet = false
        guard let m = meeting, let summary = m.parsedSummary else { return }

        isProcessing = true
        statusMessage = "Đang tạo file Word (.docx) chuẩn Nghị định 30..."
        progressPercent = 40

        let conclusionsList = editConclusions.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^[-•*]\\s*", with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }

        let updatedSummary = MeetingSummary(
            tenCuocHop: editTitle,
            thoiGian: editTime,
            diaDiem: editLocation,
            chuTri: editChair,
            thuKy: editSecretary,
            thanhPhan: summary.thanhPhan,
            noiDungChinh: summary.noiDungChinh,
            ketLuan: conclusionsList.isEmpty ? summary.ketLuan : conclusionsList,
            deXuat: summary.deXuat
        )

        Task {
            do {
                let docxURL = try DocxExporter.shared.exportToWord(
                    summary: updatedSummary,
                    organizationName: editOrg,
                    customConclusions: conclusionsList
                )

                await MainActor.run {
                    var updatedMeeting = m
                    updatedMeeting.exportFilePath = docxURL.path
                    updatedMeeting.status = .exported
                    _ = store.insert(meeting: updatedMeeting)
                    loadMeetingData()

                    isProcessing = false
                    AppLog.info("Đã xuất Word NĐ 30: \(docxURL.lastPathComponent)", .export)
                    ShareSheetPresenter.present(items: [docxURL])
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = "Lỗi xuất file Word: \(error.localizedDescription)"
                    AppLog.error("Xuất Word thất bại", .export, error: error)
                }
            }
        }
    }


    /// Chia sẻ file Word (.docx) đã xuất
    func shareExportedFile() {
        guard let m = meeting, !m.exportFilePath.isEmpty else {
            errorMessage = "Chưa có file Word. Vui lòng bấm \"Xuất Word NĐ30\" trước."
            return
        }
        let url = m.resolvedExportURL ?? URL(fileURLWithPath: m.exportFilePath)
        guard ShareSheetPresenter.presentFile(at: url) else {
            errorMessage = "File Word không còn trên thiết bị. Vui lòng xuất lại."
            return
        }
    }

    // MARK: - Xuất PDF

    /// Xuất biên bản ra PDF rồi mở bảng chia sẻ (gửi Zalo/Email, in trực tiếp, lưu vào Files).
    /// Dùng cùng dữ liệu với bản Word NĐ 30 nên nội dung hai bản luôn khớp nhau.
    func exportPdf(meeting: Meeting) {
        guard let summary = meeting.parsedSummary else {
            errorMessage = "Vui lòng bấm Tóm tắt bằng AI trước khi xuất PDF."
            return
        }

        let organization = KeychainManager.shared.get(key: .defaultOrg, defaultValue: "")
        do {
            let url = try PdfExporter.shared.exportToPdf(summary: summary, organizationName: organization)
            AppLog.info("Đã xuất PDF: \(url.lastPathComponent)", .export)
            guard ShareSheetPresenter.presentFile(at: url) else {
                errorMessage = "Không mở được bảng chia sẻ cho file PDF."
                AppLog.warning("Có file PDF nhưng không mở được bảng chia sẻ", .export)
                return
            }
        } catch {
            errorMessage = "Lỗi xuất PDF: \(error.localizedDescription)"
            AppLog.error("Xuất PDF thất bại", .export, error: error)
        }
    }

    /// Bỏ các ký tự không hợp lệ trong tên file (Windows/iOS/Share sheet)
    static func safeFileName(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = raw
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Ghi am cuoc hop" : String(cleaned.prefix(80))
    }
}
