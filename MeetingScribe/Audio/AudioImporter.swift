//
//  AudioImporter.swift
//  MeetingScribe
//
//  Nhập file ghi âm từ bên ngoài vào thư mục recordings của ứng dụng
//  Tương đương FileUtils.importAudioFile trên Android
//

import Foundation
import AVFoundation

public class AudioImporter {
    public static let shared = AudioImporter()

    private init() {}

    public func importAudioFile(from sourceURL: URL) throws -> (fileURL: URL, durationMs: Int64) {
        let isSecured = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isSecured {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let recordingsDir = paths[0].appendingPathComponent("recordings", isDirectory: true)

        if !fileManager.fileExists(atPath: recordingsDir.path) {
            try fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        }

        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let originalName = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "[\\\\/:*?\"<>|]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(40)

        let targetFileName = "imported_\(Int(Date().timeIntervalSince1970 * 1000))_\(originalName).\(ext)"
        let targetURL = recordingsDir.appendingPathComponent(targetFileName)

        // Sao chép file vào thư mục nội bộ
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        try fileManager.copyItem(at: sourceURL, to: targetURL)

        // Đo thời lượng audio
        let asset = AVURLAsset(url: targetURL)
        let durationSeconds = CMTimeGetSeconds(asset.duration)
        let durationMs = Int64(max(0, durationSeconds.isNaN ? 0 : durationSeconds * 1000))

        return (targetURL, durationMs)
    }
}

