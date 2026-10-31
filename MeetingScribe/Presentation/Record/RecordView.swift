//
//  RecordView.swift
//  MeetingScribe
//
//  Màn hình ghi âm + Waveform thời gian thực + Điều khiển Pause/Resume/Stop
//

import SwiftUI

public struct RecordView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorder.shared
    @State private var amplitudes: [CGFloat] = Array(repeating: 0.1, count: 40)
    @State private var showingStopAlert = false
    @State private var navigateToDetailId: Int64?
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // 1. Đồng hồ thời gian
                Text(formattedTime(recorder.currentDuration))
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)

                // 2. Trạng thái
                Text(statusText)
                    .font(.headline)
                    .foregroundColor(statusColor)

                // 3. Waveform Audio Bars
                HStack(spacing: 4) {
                    ForEach(0..<amplitudes.count, id: \.self) { idx in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(recorder.status == .recording ? Color.red : Color.gray.opacity(0.5))
                            .frame(width: 4, height: max(6, amplitudes[idx] * 120))
                            .animation(.easeOut(duration: 0.08), value: amplitudes[idx])
                    }
                }
                .frame(height: 130)
                .padding(.horizontal, 24)

                Spacer()

                // 4. Cụm nút điều khiển
                HStack(spacing: 40) {
                    // Nút Hủy
                    Button(action: cancelRecording) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.gray.opacity(0.8))
                            .clipShape(Circle())
                    }

                    // Nút Dừng & Lưu
                    Button(action: { showingStopAlert = true }) {
                        Image(systemName: "stop.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .frame(width: 76, height: 76)
                            .background(Color.red)
                            .clipShape(Circle())
                            .shadow(color: Color.red.opacity(0.4), radius: 8, x: 0, y: 4)
                    }

                    // Nút Pause / Resume
                    Button(action: togglePause) {
                        Image(systemName: recorder.status == .recording ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                }
                .padding(.bottom, 48)
            }
            .navigationTitle("Ghi âm cuộc họp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Đóng") {
                        if recorder.status == .idle {
                            dismiss()
                        } else {
                            cancelRecording()
                        }
                    }
                }
            }
            .alert("Lưu cuộc họp?", isPresented: $showingStopAlert) {
                Button("Lưu và xem chi tiết", action: finishRecording)
                Button("Hủy bỏ", role: .cancel) {}
            } message: {
                Text("Bạn có muốn dừng ghi âm và lưu cuộc họp này?")
            }
            .alert("Lỗi", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Đồng ý", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                startNewRecording()
            }
            .onDisappear {
                AudioRecorder.shared.delegate = nil
            }
        }
    }

    private var statusText: String {
        switch recorder.status {
        case .idle: return "Sẵn sàng"
        case .recording: return "Đang ghi âm..."
        case .paused: return "Đang tạm dừng"
        }
    }

    private var statusColor: Color {
        switch recorder.status {
        case .idle: return .gray
        case .recording: return .red
        case .paused: return .orange
        }
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func startNewRecording() {
        Task {
            let granted = await recorder.requestPermission()
            guard granted else {
                errorMessage = "Ứng dụng cần quyền Microphone để ghi âm cuộc họp."
                return
            }

            recorder.delegate = RecorderDelegateBridge { amp in
                DispatchQueue.main.async {
                    if amplitudes.count > 0 {
                        amplitudes.removeFirst()
                        amplitudes.append(CGFloat(amp))
                    }
                }
            }

            do {
                _ = try recorder.startRecording()
            } catch {
                errorMessage = "Không thể khởi động ghi âm: \(error.localizedDescription)"
            }
        }
    }

    private func togglePause() {
        if recorder.status == .recording {
            recorder.pauseRecording()
        } else if recorder.status == .paused {
            recorder.resumeRecording()
        }
    }

    private func finishRecording() {
        let durationMs = Int64(recorder.currentDuration * 1000)
        guard let url = recorder.stopRecording() else {
            dismiss()
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        let title = "Cuộc họp \(formatter.string(from: Date()))"

        let meeting = Meeting(
            title: title,
            audioFilePath: url.path,
            durationMs: durationMs,
            status: .recorded
        )

        _ = MeetingStore.shared.insert(meeting: meeting)
        dismiss()
    }

    private func cancelRecording() {
        recorder.cancelRecording()
        dismiss()
    }
}

class RecorderDelegateBridge: AudioRecorderDelegate {
    let onAmplitude: (Float) -> Void

    init(onAmplitude: @escaping (Float) -> Void) {
        self.onAmplitude = onAmplitude
    }

    func audioRecorderDidUpdateMeters(amplitude: Float) {
        onAmplitude(amplitude)
    }

    func audioRecorderStatusDidChange(status: RecorderStatus) {}
}
