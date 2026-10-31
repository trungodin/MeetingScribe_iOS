//
//  AudioRecorder.swift
//  MeetingScribe
//
//  Quản lý ghi âm bằng AVAudioRecorder (M4A AAC, 16kHz, Mono, 32kbps)
//  Hỗ trợ chạy nền (UIBackgroundModes audio) và metering vẽ waveform
//

import Foundation
import AVFoundation

public enum RecorderStatus {
    case idle
    case recording
    case paused
}

public protocol AudioRecorderDelegate: AnyObject {
    func audioRecorderDidUpdateMeters(amplitude: Float)
    func audioRecorderStatusDidChange(status: RecorderStatus)
}

public class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    public static let shared = AudioRecorder()

    @Published public private(set) var status: RecorderStatus = .idle
    @Published public private(set) var currentDuration: TimeInterval = 0
    @Published public private(set) var currentFilePath: URL?

    public weak var delegate: AudioRecorderDelegate?

    private var audioRecorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var durationTimer: Timer?

    private override init() {
        super.init()
        setupAudioSessionNotifications()
    }

    private var recordingsDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public func requestPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    public func startRecording() throws -> URL {
        if status == .recording, let file = currentFilePath {
            return file
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let fileName = "meeting_\(Int(Date().timeIntervalSince1970 * 1000)).m4a"
        let fileURL = recordingsDirectory.appendingPathComponent(fileName)

        // Cấu hình âm thanh: 16kHz, mono, AAC 32kbps siêu nhẹ tối ưu cho AI
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw NSError(domain: "AudioRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không thể bắt đầu ghi âm"])
        }

        self.audioRecorder = recorder
        self.currentFilePath = fileURL
        self.currentDuration = 0
        self.status = .recording
        self.delegate?.audioRecorderStatusDidChange(status: .recording)

        startTimers()
        return fileURL
    }

    public func pauseRecording() {
        guard status == .recording else { return }
        audioRecorder?.pause()
        status = .paused
        delegate?.audioRecorderStatusDidChange(status: .paused)
        stopTimers()
    }

    public func resumeRecording() {
        guard status == .paused else { return }
        audioRecorder?.record()
        status = .recording
        delegate?.audioRecorderStatusDidChange(status: .recording)
        startTimers()
    }

    @discardableResult
    public func stopRecording() -> URL? {
        stopTimers()
        audioRecorder?.stop()
        audioRecorder = nil

        let path = currentFilePath
        status = .idle
        delegate?.audioRecorderStatusDidChange(status: .idle)

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return path
    }

    public func cancelRecording() {
        let fileToDelete = currentFilePath
        _ = stopRecording()
        if let file = fileToDelete {
            try? FileManager.default.removeItem(at: file)
        }
        currentFilePath = nil
        currentDuration = 0
    }

    private func startTimers() {
        stopTimers()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder, recorder.isRecording else { return }
            recorder.updateMeters()
            // Chuyển db [-160, 0] sang float [0, 1]
            let db = recorder.averagePower(forChannel: 0)
            let linear = max(0.05, min(1.0, (db + 50) / 50.0))
            self.delegate?.audioRecorderDidUpdateMeters(amplitude: linear)
        }

        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder, recorder.isRecording else { return }
            self.currentDuration = recorder.currentTime
        }
    }

    private func stopTimers() {
        meterTimer?.invalidate()
        meterTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
    }

    // Xử lý khi có cuộc gọi đến hoặc thiết bị khác ngắt audio session
    private func setupAudioSessionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        if type == .began {
            if status == .recording {
                pauseRecording()
            }
        } else if type == .ended {
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) && status == .paused {
                    resumeRecording()
                }
            }
        }
    }
}
