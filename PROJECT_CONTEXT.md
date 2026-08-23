# PROJECT CONTEXT — FFM Local SLM

## Identitas

- Nama proyek: **Family Finance Manager (FFM)**
- Versi manifest: `0.1.67+67`
- Package ID: `com.ffm_manager`
- Direktori kerja persisten: `/home/ubuntu/FFM-source-2d123ad-v67`
- Arsip sumber asli yang harus dipreservasi: `FFM-source-2d123ad-v67.original.zip`
- SHA-256 arsip asli: `496004935d86b0037ef8415edf19fc25b818feb4ad03c6d370eeaaeaaf1ee16e`

## Status tervalidasi per 23 Agustus 2026

Fase 0 Qwen2-VL lulus dengan dua aset nyata yang diverifikasi ukuran, SHA-256 streaming, header GGUF v3, provenance, pin llama.cpp b10581/commit `2115b73d8ebdbd659075cce66c609506863bc826`, ABI arm64, dan lisensi. Model tidak dibundel ke APK atau source archive.

Model Manager menyimpan bundle pada storage privat, memakai `.part`, resume Range/ETag/Last-Modified, hash streaming 256 KiB, header validation, staging, rename atomik, dan manifest verified. Opsi B telah selesai: halaman model dapat mengunduh dari GitHub, mengimpor `.ffmbundle` offline yang dibagikan, dan mengekspor bundle terverifikasi melalui share sheet. Impor menolak path traversal, entry ZIP terkompresi, manifest/hash/header/ukuran yang tidak cocok.

Chat teks kini model-first setelah guard deterministik. Gateway tidak menerima daftar rekening atau DB list. Respons model hanya proposal/draft terstruktur serta target/query terpisah. Draf tetap divalidasi dan memerlukan preview/konfirmasi; tidak ada auto-save atau CRUD model. Guard PIN, diagnostik, kalender, query, help, konfirmasi, dan navigasi yang sudah dikenali tetap deterministic. Native/model failure fallback ke aturan lokal; cancellation tidak fallback dan hasil native yang selesai setelah cancel dibuang.

`FfmAssistantIntent` membawa `responseMode` (`localModel`/`localRules`). UI header menampilkan readiness manifest dan setiap kartu pemahaman menampilkan mode aktual. Model readiness tidak diasumsikan dari keberadaan file saja.

Native layer memakai vendor source llama.cpp yang dipin di `third_party/llama.cpp`, bukan `/home/ubuntu/llama.cpp` absolut. CMake CPU/static, arm64, mtmd; C++ memakai mutex session tunggal, RAII JNI string, allocation checks, CPU fallback, `n_ctx=2048`, input budget 1900 token, output max 1024 token. Kotlin package disamakan ke `com.ffm_manager` dan plugin memakai satu executor serial tanpa generate ganda. Library native sekarang dimuat lazy saat SLM benar-benar dipakai; ABI yang tidak memiliki library dikembalikan sebagai `NATIVE_UNAVAILABLE`, bukan crash saat plugin dibuat.

## Rencana Offline Agent FFM

Aplikasi sedang bertransisi menjadi Offline Agent penuh. Pada status ini, Orchestrator akan menjadi planner utama yang menggunakan SLM Qwen2-VL sebagai reasoning engine. Agent akan memiliki akses capability level aplikasi, tetapi tidak ada perubahan final tanpa konfirmasi. Data pembelajaran agent dipisahkan dari transaksi dan disertakan dalam backup JSON.

Dokumen desain yang menjadi referensi:
- `docs/offline_agent_audit_v68.md`
- `docs/offline_agent_knowledge_base.md`
- `docs/offline_agent_action_plan.md`
- `docs/offline_agent_learning_and_migration.md`
- `PLAN-MAXIMIZE-AGENT-NO-BUILD.md`

Fondasi runtime yang sudah ditambahkan setelah desain: `ffm_assistant_capabilities.dart`, `ffm_assistant_action_plan.dart`, `ffm_assistant_action_planner.dart`, `ffm_assistant_user_model_service.dart`, `ffm_assistant_learning_candidate_service.dart`, dan `ffm_assistant_proactive_service.dart`. Page context kini dapat membawa snapshot capability, ringkasan aman, dan filter aktif ke sheet/interpreter/gateway SLM.

## Validasi

- `flutter analyze lib test`: lulus tanpa issue.
- Full Flutter test suite terbaru: **248 test lulus**; analyzer bersih. Release APK final dibuat setelah validasi source selesai. Tambahan mencakup kebijakan FFM + Literasi Keuangan untuk menolak pertanyaan murni di luar domain secara elegan, alat query analisis kemampuan pinjaman offline (Loan Affordability), runtime knowledge registry, reasoning context bounded dengan snapshot finansial agregat, self-description dinamis, edukasi finansial lokal, analisis kemampuan cicilan, renderer Markdown chat, ekspor file JSON/Markdown/PDF offline dengan preview dan share sheet, limit Action Plan eksplisit (1 inferensi aktif, 1 plan aktif/request, 8 step/plan, 3 sub-command/pesan, 1 eksekusi/step), partial failure, read transaction wrapper, report orchestration/preview chat, recommendation read-only, protocol widget, sinkronisasi ringkasan widget, adapter read-only, serta integration test mutation income/expense/transfer melalui planner → confirmation → executor → database lokal → verify.
- Persistensi riwayat chat menggunakan SharedPreferences telah ditambahkan dan diuji.
- Preview gambar inline di chat (thumbnail yang dapat diperbesar) telah diimplementasikan.
- Modul backup JSON kini `ffm-v23-full` yang mencakup memory, learning, unanswered questions, serta optional `assistant_chat_history` melalui flow backup UI.
- Registry capability mencakup navigation/read/draft/mutation/setup model dengan risk dan confirmation policy. Widget Home Screen Android kini memiliki shortcut Asisten, Ringkasan, Transaksi, Scan nota, Aktivitas, dan Anggaran; action diteruskan melalui allowlist enum, SummaryPage menyinkronkan ringkasan aman melalui channel lokal, dan widget tetap hanya gateway/handoff untuk mutation.
- Action Planner membuat langkah navigate/read/draft/save/verify; plan ID dan idempotency key deterministik, status awaiting confirmation, navigasi yang ditangani AppShell ditandai skipped, dan duplicate execution ditolak. Adapter read-only untuk summary, transactions, accounts, categories, dan analysis serta adapter mutation income/expense/transfer telah dipasang ke DI dan diuji pada database in-memory. Runtime knowledge registry mencakup katalog halaman, domain, workflow, dan 31 tabel schema bounded. Reasoning context menyatukan request, page context, filter, capability, approved user context, status SLM, dan hasil step dengan batas karakter. Self-description dinamis membedakan capability tersedia dan gap. Report service menyiapkan preview laporan, payload data JSON, serta prompt narasi SLM dari exporter lokal; intent exportReport kini menampilkan preview di chat. Recommendation engine read-only memisahkan facts, insight, opsi, risk, dan expiry.
- User model lokal untuk profile/preference/alias dapat disimpan setelah approval dan dipakai sebagai context terbatas untuk SLM.
- Candidate workflow dapat disimpan pending, disetujui, atau ditolak; workflow pending tidak aktif.
- Saran proaktif read-only berbasis halaman dapat muncul saat chat baru tanpa menjalankan mutation otomatis.
- Destination Asisten kini 24, dan seluruh destination memiliki halaman akar dengan `FfmAssistantPageContext`.
- Katalog `FfmAssistantCatalog.otherMenuItems` berisi tepat 18 menu Lainnya.
- Test tambahan: routing SLM teks, Proposal JSON non-transaksi, cancellation queue, bundle invalid/path traversal: lulus.
- Build debug arm64-only setelah filter ABI di build.gradle.kts (abiFilters.clear()): lulus dan bebas library x86_64.
- Deduplikasi voice gate dengan fingerprint teks berhasil diuji unit.
- Release APK final arm64 signed: lulus; artefak `/home/ubuntu/FFM-v0.1.67-67-arm64-release-final.apk`, sekitar 36 MB.
- APK signature: APK Signature Scheme v2 terverifikasi; satu signer. Badging memuat compileSdk 37 dan native-code hanya `arm64-v8a`.
- Package/version release tetap `com.ffm_manager`, `0.1.67+67`; build final dilakukan pada gerbang akhir setelah fase source selesai.
- Native library terpaket: `lib/arm64-v8a/libffm_local_model_bridge.so` (tidak ada arsitektur lain).
- APK lama v0.1.70 tidak merepresentasikan perubahan widget/orchestrator/mutation terbaru dan tidak dipakai sebagai deliverable final. Build final baru dilakukan setelah seluruh fase source dan validasi selesai; material key dibersihkan kembali dan tidak masuk source/archive/attachment.

## Batasan yang wajib disebutkan

Belum ada physical Android device/emulator inference test. Debug/release build membuktikan compile, link, packaging, dan signature; smoke test desktop membuktikan loading mtmd native, bukan inference Android end-to-end. Belum ada profiling temperatur, tekanan memori, latency, lifecycle activity, atau foto nyata pada perangkat. Target runtime yang tervalidasi tetap `android-arm64`; multi-ABI belum diklaim selesai. Startup health marker lokal sudah ditambahkan untuk menandai bootstrap terputus dan menampilkan `STARTUP_INTERRUPTED` saat aplikasi berhasil dibuka kembali; marker tidak dapat mendeteksi crash sebelum marker sempat ditulis.

## Preservasi

Jangan menghapus/menimpa `FFM-source-2d123ad-v67.original.zip`. Perubahan dilakukan pada direktori hasil ekstraksi. Key release tidak boleh dipulihkan ke project kecuali ada fase signing final yang eksplisit.

Dokumen status rinci: `docs/implementation_status.md`. Checkpoint native/bundle: `docs/phase3_phase5_checkpoint.md`.
