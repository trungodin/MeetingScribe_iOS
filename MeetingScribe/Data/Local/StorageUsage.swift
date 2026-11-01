//
//  StorageUsage.swift
//  MeetingScribe
//
//  Thống kê dung lượng app đang chiếm trên máy: file ghi âm + biên bản Word đã xuất.
//  Dùng cho màn hình Cài đặt ➔ Dung lượng để người dùng biết vì sao máy đầy.
//

import Foundation

public struct StorageUsage: Equatable {
    /// Tổng dung lượng các file ghi âm còn trên máy
    public let audioBytes: Int64
    /// Tổng dung lượng các file biên bản Word đã xuất
    public let exportBytes: Int64
    /// Số file ghi âm còn trên máy
    public let audioFileCount: Int

    public init(audioBytes: Int64 = 0, exportBytes: Int64 = 0, audioFileCount: Int = 0) {
        self.audioBytes = audioBytes
        self.exportBytes = exportBytes
        self.audioFileCount = audioFileCount
    }

    public var totalBytes: Int64 { audioBytes + exportBytes }

    /// "12,4 MB" — định dạng theo kiểu file của iOS
    public static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: max(0, bytes))
    }
}
