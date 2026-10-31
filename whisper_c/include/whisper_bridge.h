#ifndef WHISPER_BRIDGE_H
#define WHISPER_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*ms_whisper_progress_callback)(int progress, void* user_data);

// Khởi tạo model từ đường dẫn file GGML (.bin)
// Trả về con trỏ (opaque pointer) tới whisper_context, hoặc NULL nếu thất bại
void* ms_whisper_init(const char* model_path);

// Nhận dạng giọng nói tiếng Việt từ mảng mẫu âm thanh 16kHz mono (float [-1.0, 1.0])
// Trả về con trỏ chuỗi UTF-8 (cần giải phóng bằng ms_whisper_free_string)
char* ms_whisper_transcribe(
    void* ctx,
    const float* samples,
    int n_samples,
    ms_whisper_progress_callback progress_cb,
    void* user_data
);

// Giải phóng chuỗi đã cấp phát
void ms_whisper_free_string(char* str);

// Cấu hình số luồng CPU dùng cho suy diễn.
// Truyền 0 để dùng chế độ tự động: min(4, số lõi CPU).
// Trước đây engine ép cứng 1 luồng nên chỉ dùng 1 lõi (chậm gấp 4-6 lần). Lưu ý: nguyên nhân
// gây "đứng ở 96%" là do params.no_timestamps = true khiến seek_delta = 0 (xem whisper_bridge.cpp).
void ms_whisper_set_n_threads(int n_threads);

// Yêu cầu dừng suy diễn đang chạy (thread-safe, gọi được từ luồng khác).
// whisper_full() sẽ trả về mã lỗi ở lần kiểm tra kế tiếp và ms_whisper_transcribe()
// trả về chuỗi rỗng. Dùng để hiện nút "Huỷ" cho người dùng.
void ms_whisper_request_abort(void);

// Xoá cờ abort trước khi bắt đầu một lượt suy diễn mới.
void ms_whisper_reset_abort(void);

// Giải phóng bộ nhớ và whisper_context
void ms_whisper_free(void* ctx);

#ifdef __cplusplus
}
#endif

#endif // WHISPER_BRIDGE_H
