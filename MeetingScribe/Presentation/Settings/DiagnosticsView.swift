//
//  DiagnosticsView.swift
//  MeetingScribe
//
//  Màn hình Chẩn đoán: chạy bộ tự kiểm tra + xem log gần đây ngay trên máy.
//  Người dùng gặp lỗi chỉ cần mở màn hình này, bấm "Chia sẻ log" là đủ dữ liệu
//  để tìm nguyên nhân (không cần cắm máy tính, không cần Xcode).
//

import SwiftUI

public struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var results: [SelfCheckResult] = []
    @State private var logs: [LogEntry] = []
    @State private var showLogs = false
    @State private var isRunning = false

    public init() {}

    private var passedCount: Int { results.filter(\.passed).count }
    private var failedCount: Int { results.count - passedCount }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: summaryIcon)
                            .font(.title2)
                            .foregroundColor(summaryColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summaryTitle)
                                .font(.headline)
                            Text("\(passedCount)/\(results.count) mục đạt · không cần mạng")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        runChecks()
                    } label: {
                        Label(isRunning ? "Đang kiểm tra..." : "Chạy lại kiểm tra", systemImage: "arrow.clockwise")
                    }
                    .disabled(isRunning)
                }

                if failedCount > 0 {
                    Section("Mục chưa đạt") {
                        ForEach(results.filter { !$0.passed }) { result in
                            resultRow(result)
                        }
                    }
                }

                Section("Tất cả kết quả") {
                    ForEach(results.filter(\.passed)) { result in
                        resultRow(result)
                    }
                }

                Section {
                    Toggle(isOn: $showLogs) {
                        Label("Hiện log gần đây", systemImage: "text.alignleft")
                    }
                    Button {
                        shareLogs()
                    } label: {
                        Label("Chia sẻ log (\(logs.count) dòng)", systemImage: "square.and.arrow.up")
                    }
                    if !logs.isEmpty {
                        Button(role: .destructive) {
                            AppLog.clear()
                            refreshLogs()
                        } label: {
                            Label("Xoá log", systemImage: "trash")
                        }
                    }
                } footer: {
                    Text("Log chỉ lưu trong bộ nhớ (tối đa 600 dòng) và tự mất khi tắt app. Không chứa API Key.")
                }

                if showLogs {
                    Section("Log") {
                        if logs.isEmpty {
                            Text("Chưa có log.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(logs) { entry in
                                Text(entry.line)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(color(for: entry.level))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chẩn đoán")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Xong") { dismiss() }
                }
            }
            .onAppear {
                if results.isEmpty {
                    runChecks()
                } else {
                    refreshLogs()
                }
            }
        }
    }

    // MARK: - Dòng kết quả

    private func resultRow(_ result: SelfCheckResult) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundColor(result.passed ? .green : .red)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.subheadline)
                Text(result.detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Hành động

    private func runChecks() {
        isRunning = true
        results = SelfCheck.runAll()
        refreshLogs()
        isRunning = false
    }

    private func refreshLogs() {
        logs = AppLog.recent(limit: 250)
    }

    /// Ghi log ra file tạm rồi mở bảng chia sẻ hệ thống
    private func shareLogs() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingScribe-log-\(Int(Date().timeIntervalSince1970)).txt")
        do {
            try AppLog.exportText().write(to: url, atomically: true, encoding: .utf8)
            ShareSheetPresenter.present(items: [url])
        } catch {
            AppLog.error("Không tạo được file log", .app, error: error)
        }
    }

    private var summaryTitle: String {
        if results.isEmpty { return "Chưa kiểm tra" }
        return failedCount == 0 ? "Mọi thứ hoạt động bình thường" : "\(failedCount) mục cần chú ý"
    }

    private var summaryIcon: String {
        if results.isEmpty { return "hourglass" }
        return failedCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private var summaryColor: Color {
        if results.isEmpty { return .secondary }
        return failedCount == 0 ? .green : .orange
    }

    private func color(for level: LogEntry.Level) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }
}
