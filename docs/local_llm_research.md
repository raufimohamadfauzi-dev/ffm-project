# Temuan Runtime LLM Lokal untuk FFM

## Sumber primer

1. Google AI Edge, **LiteRT-LM Android**: <https://developers.google.com/edge/litert-lm/android>
   - Diakses 21 Agustus 2026.
   - API Kotlin LiteRT-LM untuk Android/JVM mendukung akselerasi GPU dan NPU, multimodalitas, serta tools use.
   - NPU Android dapat memakai `context.applicationInfo.nativeLibraryDir` bila pustaka NPU dibundel bersama aplikasi.

2. Google AI Edge, **LiteRT-LM Flutter API**: <https://developers.google.com/edge/litert-lm/flutter>
   - Diakses 21 Agustus 2026.
   - Dokumentasi menyatakan LiteRT-LM untuk Flutter tersedia melalui paket komunitas `flutter_gemma`.
   - Integrasi Flutter perlu diperlakukan sebagai dependensi komunitas; untuk jalur aplikasi finansial yang ketat, adapter internal dan test kontrak tetap diperlukan.

3. Google AI Edge, **MediaPipe LLM Inference Android**: <https://developers.google.com/edge/mediapipe/solutions/genai/llm_inference/android>
   - Hasil pencarian 21 Agustus 2026 menyatakan API berada pada mode maintenance-only dan menyarankan migrasi ke LiteRT-LM Android API.

## Konsekuensi rancangan FFM

- Runtime yang paling layak dievaluasi lebih dulu: **LiteRT-LM**, dengan adapter Flutter yang dikendalikan FFM atau bridge Kotlin internal bila API Flutter belum memenuhi kebutuhan produksi.
- Model harus menjadi komponen pemahaman dan perencanaan saja. Ia tidak boleh memanggil Drift, use case simpan transaksi, atau API Android untuk menulis data.
- Model dapat dibundel atau diunduh sebagai paket model opsional yang diverifikasi checksum dan persetujuan pengguna. APK dasar tetap harus berjalan sepenuhnya tanpa model.

## Perbandingan alternatif

| Runtime | Bukti dokumentasi | Implikasi untuk FFM |
|---|---|---|
| LiteRT-LM | Dokumentasi Android dan Flutter aktif pada 2026. Flutter memakai adapter komunitas `flutter_gemma`. | Kandidat utama karena API Android resmi, akselerasi GPU/NPU, serta dukungan percakapan dan tool use. Gunakan adapter internal agar perubahan package komunitas tidak masuk ke domain finansial. |
| MLC LLM | SDK Android mendokumentasikan bundling bobot dan runtime; build memerlukan NDK, Rust, CMake, dan GPU fisik untuk performa bermakna. | Alternatif bila LiteRT-LM tidak cocok dengan model yang dipilih. Biaya toolchain serta testing perangkat lebih tinggi, sehingga bukan pilihan implementasi pertama. |

LiteRT-LM mendistribusikan model sebagai kontainer `.litertlm` yang menyatukan model TFLite, tokenizer, bobot eksternal, dan metadata. Hal ini cocok untuk paket model terpisah yang diverifikasi manifest dan checksum sebelum dipakai FFM.
