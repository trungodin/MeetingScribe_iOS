#ifndef WHISPER_BRIDGE_H
#define WHISPER_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

// Khởi tạo model từ đường dẫn file GGML (.bin)
// Trả về con trỏ (opaque pointer) tới whisper_context, hoặc NULL nếu thất bại
void* ms_whisper_init(const char* model_path);

// Nhận dạng giọng nói tiếng Việt từ mảng mẫu âm thanh 16kHz mono (float [-1.0, 1.0])
// Trả về con trỏ chuỗi UTF-8 (cần giải phóng bằng ms_whisper_free_string)
char* ms_whisper_transcribe(void* ctx, const float* samples, int n_samples);

// Giải phóng chuỗi đã cấp phát
void ms_whisper_free_string(char* str);

// Giải phóng bộ nhớ và whisper_context
void ms_whisper_free(void* ctx);

#ifdef __cplusplus
}
#endif

#endif // WHISPER_BRIDGE_H
