# Status Implementasi FFM + SLM Lokal

Tanggal pemeriksaan: **23 Agustus 2026**.

## Implementasi yang telah selesai

Fase 0 Qwen2-VL telah diverifikasi dengan aset release di luar source project. Ukuran byte eksak, SHA-256 streaming, header GGUF v3, provenance, pin llama.cpp b10581/commit `2115b73d8ebdbd659075cce66c609506863bc826`, ABI arm64, dan lisensi tercatat pada `docs/qwen2_vl_phase0_verification.md`.

Model manager menyimpan bundle pada application support/storage privat. Download GitHub memakai file `.part`, metadata resume, HTTP Range, If-Range, ETag/Last-Modified, hash streaming 256 KiB, validasi ukuran dan header GGUF, staging directory, rename atomik, dan manifest `verified`. File parsial tidak dianggap sebagai model terpasang.

Distribusi **Opsi B** sekarang tersedia di halaman Model Asisten Lokal: pengguna tetap dapat mengunduh dari GitHub, atau mengimpor file `.ffmbundle` yang dibagikan secara offline. Ekspor menggunakan ZIP store-only berbasis file stream; impor membaca central directory dengan `RandomAccessFile`, menolak path traversal dan kompresi yang tidak diizinkan, mengekstrak bertahap 256 KiB ke staging, memvalidasi SHA-256/header/ukuran, lalu memasang secara atomic. Tombol `Bagikan bundle` memakai share sheet perangkat.

**Update Redesign Impor Satu per Satu:**
FFM kini mendukung impor file GGUF secara terpisah tanpa harus merakitnya menjadi `.ffmbundle` ZIP. 
- Pengguna dapat memilih `model.gguf` atau `projector.gguf` dari UI.
- Sistem memvalidasi hash secara on-the-fly, dan menyimpan ke folder `.staging`.
- UI menampilkan *checklist* status file yang sudah ada di *staging*.
- Setelah kedua file masuk, pengguna dapat menekan tombol **Rakit dan Pasang SLM** yang akan memvalidasi ulang, mensintesis `verified_manifest.json`, dan memindahkannya ke direktori final.

Kontrak respons model teks telah dipisahkan dari catatan bebas. Model hanya mengembalikan proposal/draft atau target/query terstruktur. `FfmAssistantInterpreter` menjalankan guard deterministik terlebih dahulu untuk PIN, diagnostik, konfirmasi, kalender, help, query, dan navigasi yang sudah dikenali; setelah itu SLM lokal dicoba untuk teks biasa maupun gambar. Draf SLM tetap melewati validasi deterministic dan tidak pernah menulis database. Target navigasi divalidasi melalui katalog lokal. Kegagalan model biasa kembali ke aturan lokal; pembatalan pengguna diteruskan sebagai cancellation dan tidak berubah menjadi fallback.

Bridge native telah diperbaiki. Source llama.cpp b10581 yang diperlukan kini berada di `third_party/llama.cpp`; CMake tidak lagi bergantung pada `/home/ubuntu/llama.cpp`, dan model GGUF tidak dimasukkan ke APK/source vendor. C++ memakai mutex session tunggal, RAII untuk string JNI, pengecekan alokasi, CPU fallback, `n_ctx = 2048`, input budget 1900 token, dan output maksimum 1024 token. Kotlin memakai satu executor serial dan hanya satu pemanggilan native untuk setiap request. Package Kotlin bridge disamakan dengan `com.ffm_manager`, sesuai package aplikasi dan simbol JNI.

UI chat menampilkan readiness manifest (`AI lokal siap • offline`, pemeriksaan, atau `Aturan lokal • model belum siap`) serta mode aktual pada kartu pemahaman: `AI lokal di perangkat` atau `aturan lokal`. UI tidak menyatakan model siap hanya karena file model ada.

Riwayat chat dasar kini disimpan lokal dengan batas retensi 100 entry dan dapat dihapus melalui Reset chat. Lampiran gambar disalin ke storage privat aplikasi dan ditampilkan sebagai thumbnail inline yang dapat dibuka lebih besar. Ini belum mengubah riwayat chat menjadi bagian dari Agent Knowledge Pack.

Registry Capability dan Action Plan telah ditambahkan sebagai kontrak domain. Registry mencakup seluruh destination navigasi, capability baca, drafting, mutation, dan setup model. Planner membuat langkah navigate/read/draft/save/verify dengan risk gate, plan ID dan idempotency key deterministik; controller memiliki plan ID deterministik dan menolak konfirmasi ganda. Adapter read-only untuk summary, transactions, accounts, categories, dan analysis serta adapter mutation income/expense/transfer telah dipasang ke dependency injection dan diuji melalui alur planner → confirmation → executor → database in-memory → verify. Page context kini dapat menyediakan snapshot berisi destination, capability IDs, ringkasan aman, dan filter aktif. Snapshot tersebut diteruskan ke jalur model-first SLM.

## Widget Home Screen Android

Widget Android kini menyediakan shortcut `Asisten`, `Ringkasan`, `Transaksi`, `Scan nota`, `Aktivitas`, dan `Anggaran`. Action diteruskan ke AppShell melalui allowlist enum; action asing diabaikan. SummaryPage mengirim ringkasan pemasukan/pengeluaran yang telah dipadatkan dan disanitasi melalui channel lokal agar dapat ditampilkan pada widget. Widget tidak menjalankan Qwen2-VL di background, tidak mengunduh model otomatis, dan tidak memiliki jalur langsung untuk menyimpan mutation. Draft atau mutation dari Home Screen harus diteruskan ke aplikasi untuk preview dan konfirmasi resmi.

## Validasi yang telah dilakukan

| Pemeriksaan | Hasil |
|---|---|
| `flutter analyze lib test` | Lulus tanpa issue |
| Full Flutter test suite | **252 test lulus** |
| Runtime knowledge registry dan self-check seluruh katalog/schema bounded | Lulus |
| Reasoning context bounded dan self-description capability dinamis | Lulus |
| Report orchestration: preview, JSON data, prompt narasi SLM, preview chat | Lulus |
| Recommendation engine facts/insight/risk/expiry read-only | Lulus |
| Kebijakan FFM + Literasi Keuangan dan respons penolakan di luar domain | Lulus |
| Test widget protocol, sync service, adapter, dan orchestrator read integration | Lulus |
| Mutation income/expense/transfer preview-confirm-execute-verify | Lulus |
| Test UI action plan dan capability executor serial/refactor | Lulus |
| Test filter opt-in privacy backup chat history | Lulus |
| Analisis kemampuan pinjaman (Loan Affordability Query Tool) | Lulus |
| Evidence finansial lokal, fallback data kosong, edukasi keuangan, dan context SLM bounded | Lulus |
| Renderer Markdown chat dan ekspor file JSON/Markdown/PDF offline | Lulus |
| Limit Action Plan eksplisit, serial sub-command, partial failure, dan read transaction wrapper | Lulus |
| Test model manager (termasuk staging import parsial) | Lulus |
| Test parser Proposal JSON v2 termasuk navigation/read_query/help | Lulus |
| Test edukasi finansial dan pengiriman snapshot agregat ke SLM | Lulus |
| Test execution budget, partial failure, dan read snapshot wrapper | Lulus |
| Test routing SLM teks dengan fake gateway | Lulus |
| Test cancellation queue | Lulus |
| Test impor bundle rusak/path traversal | Lulus |
| Debug APK arm64 | Lulus |
| Release APK arm64 signed | Lulus |
| Verifikasi APK Signature Scheme v2 | Lulus |
| Package ID/version | `com.ffm_manager`, `0.1.70`, versionCode `70` |
| Library native dalam APK | `lib/arm64-v8a/libffm_local_model_bridge.so` |

Warning Drift tentang beberapa instance database in-memory masih muncul pada suite test, tetapi tidak menyebabkan kegagalan. Warning KGP dari plugin `speech_to_text` juga masih muncul sebagai warning build.

Build release arm64 signed menghasilkan APK pada `/home/ubuntu/FFM-v0.1.70-70-arm64-release-final.apk`. Key release hanya dipasang selama fase signing final dan sudah dihapus dari project, direktori temporer, serta workspace signing setelah verifikasi. Key tidak dimasukkan ke source archive atau attachment.

## Status gap utama sebelum release berikutnya

Orchestrator sudah memiliki runtime knowledge registry untuk katalog halaman, domain, workflow, literasi keuangan, analisis kemampuan cicilan, dan 31 tabel schema bounded; reasoning context bounded yang dibangun dari interpreter, snapshot evidence finansial agregat, dan diteruskan sebagai satu context ke gateway SLM; self-description capability dinamis; report service untuk preview/payload JSON/prompt narasi serta preview di chat; recommendation engine read-only; registry/planner; executor serial; adapter read-only; serta adapter mutation income/expense/transfer yang diuji pada database in-memory. Executor melewati navigasi sebagai handoff UI, memproses prepare draft, memblokir mutation tanpa confirmation, menyimpan dengan idempotency key deterministik, dan melakukan verify melalui pembacaan ulang. Callback confirmation penuh dari form resmi, verifier saldo/hasil domain yang lebih kaya, integrasi narrative SLM yang menghasilkan file final langsung dari chat, dan adapter mutation untuk domain lain belum selesai. Widget masih berupa shortcut/handoff, bukan input bebas atau jalur eksekusi mutation mandiri.

Fitur opt-in privasi pada halaman Backup Penuh telah ditambahkan agar riwayat chat tidak ikut terekspor kecuali pengguna mencentangnya, dan path gambar lokal dipisahkan dari JSON ekspor agar aman saat dipindahkan ke perangkat baru. Context User Model juga telah diperluas untuk menyimpan identitas/preferensi approved yang disuntikkan ke gateway SLM, namun controlled learning/background observation masih memerlukan UI approval, review workflow, dan mekanisme rollback yang lebih kuat.

Source telah melewati seluruh validasi sebelum rilis: kualitas orchestrator agent, kebijakan FFM + Literasi Keuangan, runtime knowledge/reasoning/report/recommendation layer, renderer Markdown chat, ekspor JSON/Markdown/PDF offline, limit Action Plan eksplisit, partial failure, read transaction wrapper, widget protocol, dan kode Dart (252 test lulus, analyzer bersih). Build release final dilakukan setelah fase source selesai, memakai target arm64 Android modern.

## Evaluasi Android Intent

Evaluasi `ACTION_SET_ALARM` dan `ACTION_SEND` dicatat pada `docs/android_intent_evaluation.md`. Evaluasi menyimpulkan `ACTION_SEND`/Sharesheet layak untuk berbagi laporan. **Audit 23 Agustus 2026** mengoreksi bahwa FFM *memang* menjadwalkan exact alarm untuk pengingat internal menggunakan `AndroidScheduleMode.exactAllowWhileIdle`, sehingga `SCHEDULE_EXACT_ALARM` dan `INTERNET` wajib dipertahankan.

## Batas validasi yang masih harus dinyatakan

Tidak ada physical Android device atau emulator yang menjalankan inference Qwen end-to-end pada sesi ini. Release build final membuktikan compile, link, packaging, dan signature APK arm64; belum membuktikan loading model/inference Qwen Android end-to-end, validasi temperatur, tekanan memori, waktu inferensi, lifecycle activity, atau foto nyata pada perangkat.

## Hasil Audit dan Perbaikan Cacat (23 Agustus 2026)
APK v83 (`0.1.67+67`) sebelumnya dilaporkan cacat karena kurangnya permission INTERNET dan kegagalan impor Android SAF. Perbaikan yang telah diterapkan dan divalidasi dengan test:
1. **Manifest**: Menambahkan `android.permission.INTERNET` agar download GitHub berfungsi.
2. **Import Bundle**: Menggunakan byte stream dari Android SAF agar impor content URI 2+ GB tidak gagal karena path null.
3. **Timeout & Error Handling**: Memberikan pesan error yang jelas terkait ruang penyimpanan dan koneksi, alih-alih exception mentah.
4. **Sanitasi Label**: Mengganti "Pusat Latihan Asisten" menjadi "Pengetahuan Asisten" dan menghapus istilah cloud vendor dari UI transaksi.
5. **Redesign Impor Satu per Satu**: Memungkinkan pengguna memilih dan mengimpor file `model.gguf` dan `projector.gguf` secara terpisah, lalu merakitnya secara internal di aplikasi.
6. **Kesiapan**: Source telah bersih, 252 test lulus, dan siap untuk build release APK kecil arm64 yang baru. APK lama yang cacat tidak boleh dipakai lagi.
