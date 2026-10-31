//
//  WhisperModelManager.swift
//  MeetingScribe
//
//  Quản lý tải, kiểm tra tính toàn vẹn và xoá model GGML Whisper Offline trên iOS
//  Tương đương WhisperModelManager.kt trên Android
//

import Foundation

public class WhisperModelManager: ObservableObject {
    public static let shared = WhisperModelManager()

    public enum Variant: String, CaseIterable, Identifiable {
        case baseQ5_1 = "ggml-base-q5_1.bin"
        case smallQ5_1 = "ggml-small-q5_1.bin"

        public var id: String { rawValue }

        public var fileName: String { rawValue }

        public var displayName: String {
            switch self {
            case .baseQ5_1: return "Whisper Base (q5_1)"
            case .smallQ5_1: return "Whisper Small (q5_1)"
            }
        }

        public var approxSizeText: String {
            switch self {
            case .baseQ5_1: return "57MB"
            case .smallQ5_1: return "181MB"
            }
        }

        public var expectedSizeBytes: Int64 {
            switch self {
            case .baseQ5_1: return 59_707_625
            case .smallQ5_1: return 190_085_487
            }
        }

        public var downloadUrl: URL {
            return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
        }

        public var note: String {
            switch self {
            case .baseQ5_1: return "~57MB · Rất nhẹ, nhanh; phù hợp ghi chú ngắn, ít ồn"
            case .smallQ5_1: return "~181MB · Chính xác cao hơn; khuyến nghị cho cuộc họp"
            }
        }
    }

    @Published public var isDownloading = false
    @Published public var downloadProgress: Double = 0
    @Published public var downloadedModelName: String = ""
    @Published public var downloadedModelSizeText: String = ""
    @Published public var downloadError: String?

    private var activeDownloadTask: URLSessionDownloadTask?

    private init() {
        refreshModelStatus()
    }

    public var modelsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("models", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public func getModelPath(for variant: Variant) -> URL {
        return modelsDirectory.appendingPathComponent(variant.fileName)
    }

    public func isModelReady(for variant: Variant) -> Bool {
        let file = getModelPath(for: variant)
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           let size = attrs[.size] as? Int64 {
            return size >= 20 * 1024 * 1024 // Tối thiểu > 20MB
        }
        return false
    }

    public func getActiveModelURL() -> URL? {
        // Ưu tiên Small nếu đã tải, sau đó mới đến Base
        for variant in [Variant.smallQ5_1, Variant.baseQ5_1] {
            if isModelReady(for: variant) {
                return getModelPath(for: variant)
            }
        }
        return nil
    }

    public func refreshModelStatus() {
        // Kiểm tra Small trước, nếu có thì hiển thị Small
        for variant in [Variant.smallQ5_1, Variant.baseQ5_1] {
            let path = getModelPath(for: variant)
            if FileManager.default.fileExists(atPath: path.path),
               let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
               let size = attrs[.size] as? Int64, size >= 20 * 1024 * 1024 {
                downloadedModelName = variant.displayName
                downloadedModelSizeText = "\(size / (1024 * 1024))MB"
                return
            }
        }
        downloadedModelName = ""
        downloadedModelSizeText = ""
    }

    public func downloadModel(variant: Variant = .baseQ5_1) {
        guard !isDownloading else { return }

        isDownloading = true
        downloadProgress = 0
        downloadError = nil

        let destination = getModelPath(for: variant)
        let partFile = destination.deletingPathExtension().appendingPathExtension("part")

        let delegate = DownloadProgressDelegate { [weak self] progress in
            DispatchQueue.main.async {
                self?.downloadProgress = progress
            }
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: variant.downloadUrl) { [weak self] tempURL, response, error in
            defer {
                DispatchQueue.main.async {
                    self?.isDownloading = false
                    self?.refreshModelStatus()
                }
            }

            if let error = error {
                DispatchQueue.main.async {
                    self?.downloadError = "Lỗi tải model: \(error.localizedDescription)"
                }
                return
            }

            guard let tempURL = tempURL else {
                DispatchQueue.main.async {
                    self?.downloadError = "Không nhận được file tải về"
                }
                return
            }

            do {
                let fm = FileManager.default
                if fm.fileExists(atPath: partFile.path) {
                    try fm.removeItem(at: partFile)
                }
                try fm.moveItem(at: tempURL, to: partFile)

                // Kiểm tra kích thước
                let attrs = try fm.attributesOfItem(atPath: partFile.path)
                let size = attrs[.size] as? Int64 ?? 0
                if size < 20 * 1024 * 1024 {
                    try? fm.removeItem(at: partFile)
                    throw NSError(domain: "WhisperModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "File tải về quá nhỏ hoặc không hợp lệ"])
                }

                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.moveItem(at: partFile, to: destination)

            } catch {
                DispatchQueue.main.async {
                    self?.downloadError = "Lỗi lưu model: \(error.localizedDescription)"
                }
            }
        }

        self.activeDownloadTask = task
        task.resume()
    }

    public func deleteModel() {
        let fm = FileManager.default
        for variant in Variant.allCases {
            let path = getModelPath(for: variant)
            try? fm.removeItem(at: path)
        }
        refreshModelStatus()
    }
}

private class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            onProgress(p)
        }
    }
}

