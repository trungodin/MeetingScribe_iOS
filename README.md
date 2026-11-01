# MeetingScribe VN (Bản iOS - Giai đoạn A MVP)

Ứng dụng ghi âm và tóm tắt biên bản cuộc họp tiếng Việt theo chuẩn **Nghị định 30/2020/NĐ-CP** trên nền tảng iOS (SwiftUI + AVFoundation + Keychain). Được chuyển đổi (port) trực tiếp từ bản Android [Record_andr](https://github.com/trungodin/Record_andr).

---

## 1. Cấu trúc thư mục (Clean Architecture)
```text
MeetingScribe_iOS/
├── Package.swift                             # Cấu hình Swift Package Manager (iOS 16+)
└── MeetingScribe/
    ├── App/
    │   └── MeetingScribeApp.swift            # Điểm khởi chạy ứng dụng SwiftUI
    ├── Domain/
    │   ├── Model/
    │   │   ├── Meeting.swift                 # Thực thể cuộc họp
    │   │   ├── MeetingStatus.swift           # Trạng thái (Ghi âm, Phiên âm, Tóm tắt, Xuất)
    │   │   └── MeetingSummary.swift          # Schema JSON biên bản cuộc họp
    │   └── Prompt/
    │       └── PromptBuilder.swift           # Bộ sinh Prompt trích xuất bóc tách Nghị định 30
    ├── Data/
    │   ├── Local/
    │   │   ├── KeychainManager.swift         # Lưu khóa API key an toàn vào iOS Keychain
    │   │   └── MeetingStore.swift            # Quản lý dữ liệu bền vững (JSON Storage)
    │   └── Remote/
    │       ├── AiEndpoints.swift             # URL cấu hình Groq, DeepSeek, Gemini, Relay
    │       ├── GroqAsrService.swift          # Engine ASR online (Whisper large-v3-turbo)
    │       └── DeepSeekSummarizerService.swift # Engine tóm tắt (deepseek-flash)
    ├── Audio/
    │   └── AudioRecorder.swift               # Ghi âm M4A AAC 16kHz + Đo sóng âm Waveform
    ├── Presentation/
    │   ├── Home/HomeView.swift               # Màn hình danh sách cuộc họp
    │   ├── Record/RecordView.swift           # Màn hình ghi âm + Waveform thời gian thực
    │   ├── Detail/DetailView.swift           # Chi tiết: bố cục chung + trạng thái
    │   │   ├── DetailView+Audio.swift        # Thẻ trình phát, tua 5 giây, chia sẻ audio gốc
    │   │   ├── DetailView+Transcript.swift   # Tab Văn bản gốc + sửa tay trước khi tóm tắt
    │   │   ├── DetailView+Summary.swift      # Tab Tóm tắt AI (biên bản NĐ 30)
    │   │   ├── DetailView+Processing.swift   # Thẻ tiến trình, huỷ job, chạy nền
    │   │   ├── DetailView+AI.swift           # Chạy chuyển văn bản (ASR) / tóm tắt
    │   │   └── DetailView+Export.swift       # Xuất Word NĐ 30 / PDF, chia sẻ file
    │   ├── Settings/SettingsView.swift       # Cài đặt chọn Engine và nhập API Key
    │   └── Settings/DiagnosticsView.swift    # Chẩn đoán: tự kiểm tra + xem log trên máy
    └── Resources/
        └── Templates/
            └── bien_ban_ND30.docx            # Mẫu biên bản Word chuẩn NĐ 30/2020/NĐ-CP
```

---

## 2. Cách mở và chạy dự án

### Trên máy Mac có Xcode:
1. Mở Xcode -> Chọn **File** -> **Open...**
2. Trỏ tới thư mục `d:\MeetingScribe_iOS\Package.swift` (hoặc tạo một Xcode App Project mới và kéo thư mục `MeetingScribe` vào).
3. Trong mục **Signing & Capabilities**: Chọn Team nhà phát triển Apple của bạn.
4. Thêm mục vào file `Info.plist`:
   * `Privacy - Microphone Usage Description`: *"Ứng dụng cần sử dụng Microphone để ghi âm cuộc họp."*
   * `Required background modes`: `App plays audio or streams audio/video using AirPlay` (để ghi âm nền liên tục).
5. Chọn thiết bị iPhone (hoặc iPhone Simulator) rồi nhấn **Run (Cmd + R)**.

