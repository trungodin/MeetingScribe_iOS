#include "whisper_bridge.h"
#include "whisper.h"
#include <string>
#include <sstream>
#include <algorithm>
#include <cstring>
#include <cstdlib>
#include <thread>
#include <atomic>

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

// Số luồng suy diễn: 0 = tự động
static std::atomic<int> g_n_threads{0};
// Cờ yêu cầu huỷ (được kiểm tra bên trong whisper_full)
static std::atomic<bool> g_abort_requested{false};

static int ms_whisper_resolve_n_threads() {
    const int forced = g_n_threads.load();
    if (forced > 0) return forced;

    unsigned hw = std::thread::hardware_concurrency();
    if (hw == 0) hw = 2;
    // 4 luồng là điểm ngọt: nhanh hơn single-thread 4-6 lần mà không bị nhiệt/pin.
    return static_cast<int>(std::min<unsigned>(4u, std::max<unsigned>(2u, hw)));
}

static bool ms_whisper_abort_trampoline(void* /*user_data*/) {
    return g_abort_requested.load();
}

static void native_progress_trampoline(struct whisper_context * /*ctx*/, struct whisper_state * /*state*/, int progress, void * user_data) {
    auto *data = reinterpret_cast<ProgressBridgeData*>(user_data);
    if (data && data->cb) {
        data->cb(progress, data->user_data);
    }
}

extern "C" {

void* ms_whisper_init(const char* model_path) {
    if (!model_path) return nullptr;

    try {
        struct whisper_context_params cparams = whisper_context_default_params();
        cparams.use_gpu = false; // CPU NEON inference on Apple Silicon

        struct whisper_context *ctx = whisper_init_from_file_with_params(model_path, cparams);
        return reinterpret_cast<void*>(ctx);
    } catch (...) {
        return nullptr;
    }
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

    try {
        auto *ctx = reinterpret_cast<struct whisper_context *>(ctx_ptr);

        whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
        params.print_realtime = false;
        params.print_progress = false;
        params.print_special = false;
        params.print_timestamps = false;
        // QUAN TRỌNG: params.no_timestamps PHẢI là false!
        // Whisper cần sinh các token timestamp để xác định seek_delta và trượt sliding window (30s) tiến tới.
        // Nếu để true, seek_delta = 0 khiến whisper_cpp rơi vào vòng lặp vô tận (seek += 0) gây đứng ở 96%.
        // Hàm whisper_full_get_segment_text() đã chỉ trả về văn bản sạch, không kèm timestamp text.
        params.no_timestamps = false;
        params.no_context = true;
        params.translate = false;
        params.suppress_blank = true;
        params.suppress_nst = true;
        params.language = "vi";
        params.temperature = 0.0f;
        params.temperature_inc = 0.0f; // Tắt loop fallback nhiệt độ, tăng tốc giải mã gấp 4-5 lần
        params.greedy.best_of = 1;
        params.beam_search.beam_size = 1;

        // Trước đây ép n_threads = 1 nên chỉ dùng 1 lõi CPU (chậm). Nguyên nhân thật của việc
        // "đứng ở 96%" là no_timestamps = true -> seek_delta = 0 (xem chú thích phía trên), không phải thread.
        // ggml bản này dùng barrier nội bộ bằng atomic (ggml-cpu.c: ggml_barrier), không cần OpenMP,
        // nên chạy đa luồng bình thường trên iOS. 4 luồng nhanh hơn 1 luồng khoảng 4-6 lần.
        params.n_threads = ms_whisper_resolve_n_threads();

        // Cho phép người dùng huỷ giữa chừng (nút "Huỷ" trong DetailView)
        g_abort_requested.store(false);
        params.abort_callback = ms_whisper_abort_trampoline;
        params.abort_callback_user_data = nullptr;

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
    } catch (...) {
        return strdup("");
    }
}

void ms_whisper_set_n_threads(int n_threads) {
    g_n_threads.store(n_threads > 0 ? n_threads : 0);
}

void ms_whisper_request_abort(void) {
    g_abort_requested.store(true);
}

void ms_whisper_reset_abort(void) {
    g_abort_requested.store(false);
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
