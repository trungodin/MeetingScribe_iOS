#include "whisper_bridge.h"
#include "whisper.h"
#include <string>
#include <sstream>
#include <algorithm>
#include <cstring>
#include <cstdlib>
#include <thread>

static bool is_non_speech(const std::string &text) {
    size_t begin = text.find_first_not_of(" \t\r\n");
    if (begin == std::string::npos) return true;

    size_t end = text.find_last_not_of(" \t\r\n");
    std::string trimmed = text.substr(begin, end - begin + 1);
    if (trimmed.empty()) return true;

    char first = trimmed.front();
    char last = trimmed.back();
    if ((first == '[' && last == ']') || (first == '(' && last == ')') ||
        (first == '*' && last == '*')) {
        return true;
    }

    static const char *noise[] = {
        "BLANK_AUDIO", "inaudible", "music", "Music", "nhạc", "Nhạc",
        "tiếng động", "Tiếng động", "Silence", "silence"
    };
    for (const char *needle : noise) {
        if (trimmed == needle) return true;
    }
    return false;
}

struct ProgressBridgeData {
    ms_whisper_progress_callback cb;
    void* user_data;
};

static void native_progress_trampoline(struct whisper_context * /*ctx*/, struct whisper_state * /*state*/, int progress, void * user_data) {
    auto *data = reinterpret_cast<ProgressBridgeData*>(user_data);
    if (data && data->cb) {
        data->cb(progress, data->user_data);
    }
}

extern "C" {

void* ms_whisper_init(const char* model_path) {
    if (!model_path) return nullptr;

    struct whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = false; // CPU NEON inference on Apple Silicon

    struct whisper_context *ctx = whisper_init_from_file_with_params(model_path, cparams);
    return reinterpret_cast<void*>(ctx);
}

char* ms_whisper_transcribe(
    void* ctx_ptr,
    const float* samples,
    int n_samples,
    ms_whisper_progress_callback progress_cb,
    void* user_data
) {
    if (!ctx_ptr || !samples || n_samples <= 0) {
        return strdup("");
    }

    auto *ctx = reinterpret_cast<struct whisper_context *>(ctx_ptr);

    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.print_realtime = false;
    params.print_progress = false;
    params.print_special = false;
    params.print_timestamps = false;
    params.no_timestamps = true;
    params.no_context = true;
    params.translate = false;
    params.suppress_blank = true;
    params.suppress_nst = true;
    params.language = "vi";
    params.temperature = 0.0f;
    params.temperature_inc = 0.0f; // Tắt loop fallback nhiệt độ, tăng tốc giải mã gấp 4-5 lần
    params.greedy.best_of = 1;
    params.beam_search.beam_size = 1;

    // Dùng đúng 1 luồng (single thread) chuyên dụng trên iOS:
    // Bỏ qua 100% threadpool và ggml_barrier (vốn bị lỗi spinlock deadlock trên iOS khi không có OpenMP).
    // Nhân hiệu năng cao của chip Apple A16 Bionic xử lý NEON cực nhanh mà không bị khóa luồng.
    params.n_threads = 1;

    ProgressBridgeData pdata = { progress_cb, user_data };
    if (progress_cb) {
        params.progress_callback = native_progress_trampoline;
        params.progress_callback_user_data = &pdata;
    }

    int result = whisper_full(ctx, params, samples, n_samples);
    if (result != 0) {
        return strdup("");
    }

    std::ostringstream full_transcript;
    const int n_segments = whisper_full_n_segments(ctx);
    int kept_segments = 0;

    for (int i = 0; i < n_segments; ++i) {
        const char *raw = whisper_full_get_segment_text(ctx, i);
        if (!raw) continue;

        std::string text(raw);
        if (is_non_speech(text)) continue;

        size_t begin = text.find_first_not_of(" \t\r\n");
        if (begin == std::string::npos) continue;

        if (kept_segments > 0) full_transcript << "\n";
        full_transcript << text.substr(begin);
        ++kept_segments;
    }

    std::string str_res = full_transcript.str();
    char* c_res = (char*)malloc(str_res.size() + 1);
    if (c_res) {
        std::memcpy(c_res, str_res.c_str(), str_res.size() + 1);
    }
    return c_res;
}

void ms_whisper_free_string(char* str) {
    if (str) {
        free(str);
    }
}

void ms_whisper_free(void* ctx_ptr) {
    if (ctx_ptr) {
        auto *ctx = reinterpret_cast<struct whisper_context *>(ctx_ptr);
        whisper_free(ctx);
    }
}

} // extern "C"
