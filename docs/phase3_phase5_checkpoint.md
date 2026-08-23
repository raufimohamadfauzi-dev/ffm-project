# Checkpoint Fase 3–5

Tanggal validasi: 2026-08-22.

## Fase 3 native

Bridge C++ sekarang memakai source llama.cpp terpin di `third_party/llama.cpp` dan tidak lagi memakai path absolut `/home/ubuntu/llama.cpp` pada CMake. Source vendor hanya membawa direktori yang diperlukan untuk build (`ggml`, `include`, `src`, `vendor`, dan `tools/mtmd`); model GGUF dan direktori build tidak disalin ke source.

C++ memiliki mutex session tunggal yang mengserialisasi init, destroy, dan generate. JNI string memakai RAII, alokasi input/sampler/context diperiksa, `n_ctx` tetap 2048, token input dibatasi 1900, output dibatasi 1024 token, dan CPU fallback digunakan pada tahap ini. Kotlin plugin sudah satu executor serial dan tidak lagi memanggil generate dua kali. Package Kotlin bridge disamakan ke `com.ffm_manager`, sesuai simbol JNI dan `MainActivity`.

Validasi native: `flutter build apk --debug --target-platform android-arm64` berhasil dan APK memuat `lib/arm64-v8a/libffm_local_model_bridge.so` berukuran sekitar 5.9 MB. Ini membuktikan compile/link arm64 dan packaging library, bukan end-to-end inference pada perangkat Android. Belum ada physical device/emulator inference test.

Cancellation Dart diperkuat: queue membuang hasil JNI bila token dibatalkan selama operasi; cancellation exception diteruskan melalui gateway/interpreter dan tidak diubah menjadi fallback rule-based. JNI sendiri belum memiliki interrupt token native; operasi yang sedang berjalan diselesaikan lalu hasilnya dibuang.

## Fase 4 UI

`FfmAssistantIntent` memiliki `responseMode` dengan nilai `localModel` atau `localRules`. Hasil model-first yang tervalidasi ditandai `localModel`; seluruh fallback dan handler deterministik default ke `localRules`. Header chat memeriksa manifest terverifikasi melalui `FfmLocalModelService.getInstalled()` dan menampilkan `AI lokal siap • offline`, `Memeriksa AI lokal`, atau `Aturan lokal • model belum siap`. Kartu pemahaman pesan menampilkan mode aktual.

## Fase 5 bundle offline

Dependency `archive: 3.6.1` ditambahkan untuk ZIP I/O. API ekspor/impor sedang dibangun dengan ekstensi `.ffmbundle`. Bundle berisi `verified_manifest.json`, language model GGUF, dan mmproj GGUF. Ekspor memakai ZIP store-only dan file-stream encoder. Impor membaca central directory melalui `RandomAccessFile`, menolak path traversal, mewajibkan entry store-only berukuran tepat, mengekstrak bertahap 256 KiB ke staging, menjalankan hash/header validation existing, lalu memasang secara atomic. Manifest tetap harus cocok dengan bundle ID, SHA, ukuran, dan header GGUF yang dipin.
