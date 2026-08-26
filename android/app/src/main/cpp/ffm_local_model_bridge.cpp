#include <jni.h>
#include <android/log.h>

#include <mutex>
#include <string>
#include <vector>

#include "llama.h"

#define LOG_TAG "FfmLocalModelBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

// One native session at a time. Kotlin and the Dart queue must not create
// overlapping llama contexts, and destroy waits for an active generation.
std::mutex g_session_mutex;
llama_model *g_model = nullptr;

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
                                                       jstring modelPath) {
  std::lock_guard<std::mutex> lock(g_session_mutex);
  if (g_model != nullptr) {
    LOGE("Model sudah diinisialisasi. Harus dipanggil destroyNative dulu.");
    return -1;
  }

  ScopedUtfChars model_path(env, modelPath);
  if (!model_path.valid()) {
    LOGE("Path model kosong/tidak dapat dibaca.");
    return -4;
  }

  llama_model_params model_params = llama_model_default_params();
  g_model = llama_model_load_from_file(model_path.get(), model_params);
  if (g_model == nullptr) {
    LOGE("Gagal memuat model LLM dari %s", model_path.get());
    return -2;
  }

  LOGI("Model berhasil dimuat.");
  return 0;
}

extern "C" JNIEXPORT void JNICALL
Java_com_ffm_1manager_FfmLocalModelBridge_destroyNative(JNIEnv * /*env*/,
                                                         jobject /*unused*/) {
  std::lock_guard<std::mutex> lock(g_session_mutex);
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
    jstring userPrompt) {
  std::lock_guard<std::mutex> lock(g_session_mutex);
  if (g_model == nullptr) {
    LOGE("Model belum dimuat.");
    return ErrorString(env, "Model belum dimuat.");
  }

  ScopedUtfChars system_prompt(env, systemPrompt);
  ScopedUtfChars user_prompt(env, userPrompt);
  if (!system_prompt.valid() || !user_prompt.valid()) {
    return ErrorString(env, "Prompt tidak valid.");
  }

  std::string prompt =
      std::string(system_prompt.get()) + "\n\n" + user_prompt.get();

  const llama_vocab *vocab = llama_model_get_vocab(g_model);

  const int n_prompt_tokens = -llama_tokenize(
      vocab, prompt.c_str(), static_cast<int32_t>(prompt.size()), nullptr, 0,
      true, true);
  if (n_prompt_tokens <= 0) {
    return ErrorString(env, "Gagal tokenisasi input.");
  }
  if (n_prompt_tokens > 1900) {
    LOGE("Token input (%d) terlalu besar, melebihi budget context aman.",
         n_prompt_tokens);
    return ErrorString(env, "Input terlalu panjang untuk diproses aman di perangkat.");
  }
  std::vector<llama_token> tokens(static_cast<size_t>(n_prompt_tokens));
  if (llama_tokenize(vocab, prompt.c_str(), static_cast<int32_t>(prompt.size()),
                     tokens.data(), static_cast<int32_t>(tokens.size()), true,
                     true) < 0) {
    return ErrorString(env, "Gagal tokenisasi input.");
  }

  llama_context_params context_params = llama_context_default_params();
  context_params.n_ctx = 2048;  // Batas mutlak.
  context_params.n_batch = 512;
  context_params.n_threads = 2;
  context_params.n_threads_batch = 2;
  llama_context *context = llama_init_from_model(g_model, context_params);
  if (context == nullptr) {
    return ErrorString(env, "Gagal inisialisasi context memori.");
  }

  llama_batch batch = llama_batch_get_one(tokens.data(),
                                          static_cast<int>(tokens.size()));
  if (llama_decode(context, batch) != 0) {
    LOGE("Decode prompt gagal.");
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
    llama_batch next_batch = llama_batch_get_one(&next_token, 1);
    if (llama_decode(context, next_batch) != 0) {
      LOGE("Decode gagal pada token ke-%d", i);
      break;
    }
  }

  llama_sampler_free(sampler);
  llama_free(context);
  return env->NewStringUTF(response.c_str());
}
