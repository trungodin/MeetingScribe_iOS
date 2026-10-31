//
//  MeetingStatus.swift
//  MeetingScribe
//
//  Tương đương MeetingStatus.kt trên Android
//

import Foundation

public enum MeetingStatus: String, Codable, CaseIterable {
    case recorded = "RECORDED"
    case transcribing = "TRANSCRIBING"
    case transcribed = "TRANSCRIBED"
    case summarizing = "SUMMARIZING"
    case summarized = "SUMMARIZED"
    case exported = "EXPORTED"

    public var displayName: String {
        switch self {
        case .recorded: return "Chưa chuyển văn bản"
        case .transcribing: return "Đang chuyển văn bản..."
        case .transcribed: return "Đã chuyển văn bản"
        case .summarizing: return "Đang tóm tắt..."
        case .summarized: return "Đã tóm tắt"
        case .exported: return "Đã xuất file"
        }
    }
}

