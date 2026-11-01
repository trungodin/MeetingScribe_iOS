//
//  DetailView.swift
//  MeetingScribe
//
//  Màn hình Chi tiết cuộc họp: trạng thái + bố cục chung (trình phát audio, 2 tab nội dung,
//  thanh nút hành động). Phần chi tiết được tách sang các file cùng thư mục:
//    DetailView+Audio.swift       – thẻ trình phát, phát/tua, chia sẻ audio gốc
//    DetailView+Transcript.swift  – tab Văn bản gốc + sửa tay
//    DetailView+Summary.swift     – tab Tóm tắt AI
//    DetailView+Processing.swift  – thẻ tiến trình, huỷ, chạy nền, trạng thái
//    DetailView+AI.swift          – chạy ASR / tóm tắt
//    DetailView+Export.swift      – xuất Word NĐ 30 / PDF, chia sẻ file
//

import SwiftUI
import AVFoundation
import UIKit

public struct DetailView: View {
    let meetingId: Int64

    /// Cỡ chữ trợ năng: một số hàng trong biên bản phải xếp dọc thay vì ngang để không bị cắt chữ
    @Environment(\.dynamicTypeSize) var typeSize

    @StateObject var store = MeetingStore.shared
    @State var meeting: Meeting?
    @State var selectedTab = 0 // 0: Transcript, 1: Tóm tắt biên bản

    // Audio Player
    @State var audioPlayer: AVAudioPlayer?
    @State var isPlaying = false
    @State var playbackPosition: Double = 0
    @State var totalDuration: Double = 0
    @State var playbackTimer: Timer?

    // Tiến trình AI
    @State var isProcessing = false
    @State var progressPercent: Double = 0
    @State var statusMessage = ""
    @State var errorMessage: String?
    // Giữ handle để huỷ job đang chạy + mốc thời gian bắt đầu (hiển thị "đã chạy bao lâu")
    @State var processingTask: Task<Void, Never>?
    @State var processingStartedAt: Date?
    // Lần cuối nhận được mốc tiến trình mới (để biết app còn "sống" hay đã treo)
    @State var lastProgressAt: Date?

    // Giữ app được iOS cho chạy tiếp khi người dùng chuyển sang app khác giữa lúc AI đang xử lý
    @State var processingBgTaskId: UIBackgroundTaskIdentifier = .invalid

    // Sửa tay văn bản ASR (tên riêng, số liệu luôn có lỗi → phải sửa được trước khi tóm tắt)
    @State var isEditingTranscript = false
    @State var transcriptDraft = ""

    // Xuất file & Edit trước khi xuất
    @State var showingEditExportSheet = false

    // Dữ liệu chỉnh sửa trước khi xuất
    @State var editTitle = ""
    @State var editOrg = ""
    @State var editChair = ""
    @State var editSecretary = ""
    @State var editTime = ""
    @State var editLocation = ""
    @State var editConclusions = ""

    public init(meetingId: Int64) {
        self.meetingId = meetingId
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let m = meeting {
                // 1. Trình phát Audio (Audio Player Card đầy đủ Seekbar + Tua 5s)
                audioPlayerCard(meeting: m)

                // 2. Thanh chuyển Tab (Văn bản / Tóm tắt)
                Picker("", selection: $selectedTab) {
                    Text("Văn bản gốc").tag(0)
                    Text("Tóm tắt AI").tag(1)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Nội dung hiển thị")
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // 3. Nội dung Tab
                TabView(selection: $selectedTab) {
                    transcriptTabView(meeting: m)
                        .tag(0)

                    summaryTabView(meeting: m)
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // 4. Thanh nút hành động phía dưới (Xuất Word, Chia sẻ)
                bottomActionBar(meeting: m)
            } else {
                ProgressView()
                    .frame(maxHeight: .infinity)
            }
        }
        .navigationTitle(meeting?.title ?? "Chi tiết cuộc họp")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let m = meeting, !m.exportFilePath.isEmpty {
                    Button(action: shareExportedFile) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Chia sẻ file đã xuất")
                }
            }
        }
        .sheet(isPresented: $showingEditExportSheet) {
            editExportModalView
        }
        .alert("Thông báo", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            loadMeetingData()
        }
        .onDisappear {
            stopAudio()
        }
    }

    func loadMeetingData() {
        meeting = store.getMeeting(id: meetingId)
        setupAudioPlayer()
    }
}
