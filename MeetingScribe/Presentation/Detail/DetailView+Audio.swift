//
//  DetailView+Audio.swift
//  MeetingScribe
//
//  Thẻ trình phát audio (Seekbar + tua lùi/tới 5 giây) và toàn bộ logic phát/tua/chia sẻ audio gốc.
//

import SwiftUI
import AVFoundation
import UIKit

extension DetailView {

    // MARK: - 1. Audio Player Card (Seekbar + Tua lùi / tới 5s)

    @ViewBuilder
    func audioPlayerCard(meeting: Meeting) -> some View {
        // Audio đã bị xoá để giải phóng dung lượng (Cài đặt ➔ Dung lượng) → báo rõ thay vì hiện điều khiển chết
        if meeting.resolvedAudioURL == nil {
            HStack(spacing: 8) {
                Image(systemName: "speaker.slash")
                    .foregroundColor(.secondary)
                Text(meeting.durationMs > 0
                     ? "File ghi âm (\(meeting.formattedDuration)) đã được xoá để tiết kiệm dung lượng. Văn bản và biên bản vẫn giữ nguyên."
                     : "Không tìm thấy file ghi âm trên thiết bị này.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        } else {
            VStack(spacing: 8) {
                HStack {
                    Text(formatDuration(playbackPosition))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Đã phát " + formatDuration(playbackPosition))
                    Spacer()
    
                    // Nút chia sẻ file ghi âm gốc
                    Button(action: shareAudioFile) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Xuất audio")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
    
                    Spacer()
                    Text(formatDuration(totalDuration > 0 ? totalDuration : Double(meeting.durationMs) / 1000))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
    
                // Thanh tua thời gian Seekbar
                Slider(value: Binding(
                    get: { playbackPosition },
                    set: { newVal in
                        playbackPosition = newVal
                        if audioPlayer == nil {
                            setupAudioPlayer()
                        }
                        audioPlayer?.currentTime = newVal
                    }
                ), in: 0...max(1, totalDuration > 0 ? totalDuration : 1))
                    .accessibilityLabel("Vị trí phát")
                    .accessibilityValue(formatDuration(playbackPosition))
                    .accessibilityHint("Kéo để tua bản ghi âm")
    
                HStack(spacing: 32) {
                    // Tua lùi 5s
                    Button(action: { seekBy(-5) }) {
                        Image(systemName: "gobackward.5")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    .accessibilityLabel("Tua lùi 5 giây")
    
                    // Phát / Dừng
                    Button(action: togglePlayAudio) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)
                    }
                    .accessibilityLabel(isPlaying ? "Tạm dừng" : "Phát bản ghi âm")
                    .accessibilityHint(isPlaying ? "Dừng phát tạm thời" : "Nghe lại cuộc họp từ vị trí hiện tại")
    
                    // Tua tới 5s
                    Button(action: { seekBy(5) }) {
                        Image(systemName: "goforward.5")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    .accessibilityLabel("Tua tới 5 giây")
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }


    // MARK: - Audio Logic

    func setupAudioPlayer() {
        guard let audioURL = meeting?.resolvedAudioURL else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.prepareToPlay()
            self.audioPlayer = player
            self.totalDuration = player.duration
        } catch {
            AppLog.error("Không khởi tạo được trình phát audio", .record, error: error)
        }
    }

    func togglePlayAudio() {
        guard let audioURL = meeting?.resolvedAudioURL else {
            errorMessage = "File âm thanh không tồn tại trên thiết bị"
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            AppLog.error("Không đặt được AVAudioSession .playback", .record, error: error)
        }

        if isPlaying {
            audioPlayer?.pause()
            isPlaying = false
            playbackTimer?.invalidate()
        } else {
            if audioPlayer == nil {
                do {
                    let player = try AVAudioPlayer(contentsOf: audioURL)
                    player.prepareToPlay()
                    audioPlayer = player
                    totalDuration = player.duration
                } catch {
                    errorMessage = "Không thể phát audio: \(error.localizedDescription)"
                    return
                }
            }

            guard let player = audioPlayer else { return }

            // Nếu đã phát gần hết hoặc hết file, bấm play sẽ tua lại từ đầu
            if player.currentTime >= player.duration - 0.2 {
                player.currentTime = 0
                playbackPosition = 0
            }

            if player.play() {
                isPlaying = true
                startPlaybackTimer()
            } else {
                errorMessage = "Không thể bắt đầu phát âm thanh. Vui lòng thử lại."
            }
        }
    }

    func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let player = audioPlayer else { return }
            if player.isPlaying {
                playbackPosition = player.currentTime
            } else {
                // Đã dừng hoặc phát xong hết file
                isPlaying = false
                if player.currentTime >= player.duration - 0.2 {
                    playbackPosition = 0
                    player.currentTime = 0
                }
                playbackTimer?.invalidate()
            }
        }
    }

    func seekBy(_ seconds: Double) {
        if audioPlayer == nil {
            setupAudioPlayer()
        }
        guard let player = audioPlayer else { return }
        let target = max(0, min(player.duration, player.currentTime + seconds))
        player.currentTime = target
        playbackPosition = target
    }

    /// Tua tới đúng mốc thời gian của một câu trong transcript và phát tiếp từ đó.
    func seek(to seconds: Double, autoplay: Bool) {
        if audioPlayer == nil {
            setupAudioPlayer()
        }
        guard let player = audioPlayer else { return }

        let target = max(0, min(max(0, player.duration - 0.1), seconds))
        player.currentTime = target
        playbackPosition = target

        if autoplay && !isPlaying {
            togglePlayAudio()
        }
    }

    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playbackTimer?.invalidate()
    }

    /// Chia sẻ file ghi âm gốc.
    ///
    /// Trước đây hàm này bật một `.sheet` chứa UIActivityViewController nên trên iOS mới
    /// bảng chia sẻ hiện ra một ô ĐEN. Ngoài ra file ghi âm gốc nằm trong container của app
    /// (UUID thay đổi sau mỗi lần build) nên tên file rất xấu. Vì vậy:
    ///  1. Copy sang thư mục tạm với tên thân thiện = tên cuộc họp.
    ///  2. Present bảng chia sẻ trực tiếp từ UIKit (ShareSheetPresenter).
    func shareAudioFile() {
        guard let m = meeting else { return }
        guard let audioURL = m.resolvedAudioURL else {
            errorMessage = "File âm thanh không tồn tại trên thiết bị."
            return
        }

        let ext = audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension
        let prettyName = Self.safeFileName(m.title.isEmpty ? "Ghi am cuoc hop" : m.title) + "." + ext
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(prettyName)

        var urlToShare = audioURL
        do {
            try? FileManager.default.removeItem(at: tempURL)
            try FileManager.default.copyItem(at: audioURL, to: tempURL)
            urlToShare = tempURL
        } catch {
            // Copy lỗi thì vẫn chia sẻ file gốc
            urlToShare = audioURL
        }

        guard ShareSheetPresenter.presentFile(at: urlToShare) else {
            errorMessage = "Không mở được file âm thanh để chia sẻ. Vui lòng thử lại."
            return
        }
    }


    func formatDuration(_ sec: Double) -> String {
        let total = Int(sec)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
