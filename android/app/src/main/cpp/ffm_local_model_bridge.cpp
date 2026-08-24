#include <jni.h>
#include <android/log.h>

#include <mutex>
#include <string>

#include "mtmd-helper.h"
#include "mtmd.h"

#define LOG_TAG "FfmLocalModelBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

// One native session at a time. Kotlin and the Dart queue must not create
// overlapping llama contexts, and destroy waits for an active generation.
std::mutex g_session_mutex;
llama_model *g_model = nullptr;
mtmd_context *g_ctx_vision = nullptr;

class ScopedUtfChars {
 public:
  ScopedUtfChars(JNIEnv *env, jstring value)
      : env_(env), value_(value), chars_(value == nullptr ? nullptr
                                                          : env->GetStringUTFChars(value, nullptr)) {}
  ~ScopedUtfChars() {
    if (chars_ != nullptr) env_->ReleaseStringUTFChars(value_, chars_);
  }
  ScopedUtfChars(const ScopedUtfChars &) = delete;
  ScopedUtfChars &operator=(const ScopedUtfChars &) = delete;
  const char *get() const { return chars_; }
  bool valid() const { return value_ != nullptr && chars_ != nullptr; }

 private:
  JNIEnv *env_;
  jstring value_;
  const char *chars_;
};

jstring ErrorString(JNIEnv *env, const char *message) {
  std::string json = "{\"error\":\"";
  json += message;
  json += "\"}";
  return env->NewStringUTF(json.c_str());
}

}  // namespace

extern "C" JNIEXPORT jint JNICALL
Java_com_ffm_1manager_FfmLocalModelBridge_initNative(JNIEnv *env,
                                                       jobject /*unused*/,
                                                       jstring modelPath,
                                                       jstring mmprojPath) {
  std::lock_guard<std::mutex> lock(g_session_mutex);
  if (g_model != nullptr || g_ctx_vision != nullptr) {
    LOGE("Model sudah diinisialisasi. Harus dipanggil destroyNative dulu.");
    return -1;
  }

  ScopedUtfChars model_path(env, modelPath);
  ScopedUtfChars mmproj_path(env, mmprojPath);
  if (!model_path.valid() || !mmproj_path.valid()) {
    LOGE("Path model atau mmproj kosong/tidak dapat dibaca.");
    return -4;
  }

  mtmd_helper_log_set(nullptr, nullptr);
  llama_model_params model_params = llama_model_default_params();
  g_model = llama_model_load_from_file(model_path.get(), model_params);
  if (g_model == nullptr) {
    LOGE("Gagal memuat model LLM dari %s", model_path.get());
    return -2;
  }

  mtmd_context_params context_params = mtmd_context_params_default();
  context_params.use_gpu = false;  // CPU fallback deterministik untuk rilis awal.
  context_params.n_threads = 2;
  context_params.warmup = false;
  context_params.image_max_tokens = 1024;
  g_ctx_vision = mtmd_init_from_file(mmproj_path.get(), g_model, context_params);
  if (g_ctx_vision == nullptr) {
    LOGE("Gagal memuat mmproj");
    llama_model_free(g_model);
    g_model = nullptr;
    return -3;
  }

  LOGI("Model dan mmproj berhasil dimuat.");
  return 0;
}

extern "C" JNIEXPORT void JNICALL
Java_com_ffm_1manager_FfmLocalModelBridge_destroyNative(JNIEnv * /*env*/,
                                                         jobject /*unused*/) {
  std::lock_guard<std::mutex> lock(g_session_mutex);
  if (g_ctx_vision != nullptr) {
    mtmd_free(g_ctx_vision);
    g_ctx_vision = nullptr;
  }
  if (g_model != nullptr) {
    llama_model_free(g_model);
    g_model = nullptr;
  }
  LOGI("Resource model dibebaskan.");
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_ffm_1manager_FfmLocalModelBridge_generateSingleShotNative(
    JNIEnv *env,
    jobject /*unused*/,
    jstring systemPrompt,
    jstring userPrompt,
    jstring imagePath) {
  std::lock_guard<std::mutex> lock(g_session_mutex);
  if (g_model == nullptr || g_ctx_vision == nullptr) {
    LOGE("Model belum dimuat.");
    return ErrorString(env, "Model belum dimuat.");
  }

  ScopedUtfChars system_prompt(env, systemPrompt);
  ScopedUtfChars user_prompt(env, userPrompt);
  ScopedUtfChars image_path(env, imagePath);
  if (!system_prompt.valid() || !user_prompt.valid()) {
    return ErrorString(env, "Prompt tidak valid.");
  }
  const bool has_image = image_path.valid() && image_path.get()[0] != '\0';

  std::string prompt = std::string(system_prompt.get()) + "\n\n" + user_prompt.get();
  if (has_image) {
    prompt = mtmd_get_marker(g_ctx_vision) + std::string("\n") + prompt;
  }

  mtmd_input_text input_text{};
  input_text.text = prompt.data();
  input_text.text_len = prompt.size();
  input_text.add_special = true;
  input_text.parse_special = true;

  mtmd_helper_bitmap_wrapper bitmap_wrapper{nullptr, nullptr};
  const mtmd_bitmap *bitmaps[1] = {nullptr};
  size_t bitmap_count = 0;
  if (has_image) {
    bitmap_wrapper = mtmd_helper_bitmap_init_from_file(g_ctx_vision, image_path.get(), false);
    if (bitmap_wrapper.bitmap != nullptr) {
      bitmaps[0] = bitmap_wrapper.bitmap;
      bitmap_count = 1;
    } else {
      LOGE("Gagal memuat gambar dari %s", image_path.get());
      return ErrorString(env, "Gagal memuat gambar.");
    }
  }

  mtmd_input_chunks *chunks = mtmd_input_chunks_init();
  if (chunks == nullptr) {
    if (bitmap_wrapper.bitmap != nullptr) mtmd_bitmap_free(bitmap_wrapper.bitmap);
    return ErrorString(env, "Gagal mengalokasikan input model.");
  }

  const int32_t tokenize_result =
      mtmd_tokenize(g_ctx_vision, chunks, &input_text, bitmaps, bitmap_count);
  if (bitmap_wrapper.bitmap != nullptr) mtmd_bitmap_free(bitmap_wrapper.bitmap);
  if (tokenize_result != 0) {
    LOGE("Tokenisasi gagal: %d", tokenize_result);
    mtmd_input_chunks_free(chunks);
    return ErrorString(env, "Gagal tokenisasi input.");
  }

  const size_t total_tokens = mtmd_helper_get_n_tokens(chunks);
  LOGI("Total token input: %zu", total_tokens);
  if (total_tokens > 1900) {
    LOGE("Token input (%zu) terlalu besar, melebihi budget context aman.", total_tokens);
    mtmd_input_chunks_free(chunks);
    return ErrorString(env, "Input terlalu panjang untuk diproses aman di perangkat.");
  }

  llama_context_params context_params = llama_context_default_params();
  context_params.n_ctx = 2048;  // Batas mutlak.
  context_params.n_batch = 512;
  context_params.n_threads = 2;
  context_params.n_threads_batch = 2;
  llama_context *context = llama_init_from_model(g_model, context_params);
  if (context == nullptr) {
    mtmd_input_chunks_free(chunks);
    return ErrorString(env, "Gagal inisialisasi context memori.");
  }

  llama_pos n_past = 0;
  const int32_t eval_result = mtmd_helper_eval_chunks(
      g_ctx_vision, context, chunks, 0, 0, context_params.n_batch, true, &n_past);
  mtmd_input_chunks_free(chunks);
  if (eval_result != 0) {
    LOGE("Evaluasi chunk gagal: %d", eval_result);
    llama_free(context);
    return ErrorString(env, "Gagal evaluasi prompt.");
  }

  llama_sampler *sampler =
      llama_sampler_chain_init(llama_sampler_chain_default_params());
  if (sampler == nullptr) {
    llama_free(context);
    return ErrorString(env, "Gagal menyiapkan sampler.");
  }
  llama_sampler_chain_add(sampler, llama_sampler_init_greedy());

  std::string response;
  const llama_vocab *vocab = llama_model_get_vocab(g_model);
  for (int i = 0; i < 1024; ++i) {
    const llama_token token = llama_sampler_sample(sampler, context, -1);
    llama_sampler_accept(sampler, token);
    if (llama_vocab_is_eog(vocab, token)) break;

    char buffer[128];
    const int piece_size =
        llama_token_to_piece(vocab, token, buffer, sizeof(buffer), 0, true);
    if (piece_size < 0) {
      std::string piece(static_cast<size_t>(-piece_size), '\0');
      llama_token_to_piece(vocab, token, piece.data(), piece.size(), 0, true);
      response += piece;
    } else if (piece_size > 0) {
      response.append(buffer, static_cast<size_t>(piece_size));
    }

    llama_token next_token = token;
    llama_batch batch = llama_batch_get_one(&next_token, 1);
    if (llama_decode(context, batch) != 0) {
      LOGE("Decode gagal pada token ke-%d", i);
      break;
    }
  }

  llama_sampler_free(sampler);
  llama_free(context);
  return env->NewStringUTF(response.c_str());
}
