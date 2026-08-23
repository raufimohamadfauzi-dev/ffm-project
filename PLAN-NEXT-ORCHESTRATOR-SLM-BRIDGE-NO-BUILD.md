# Tahap Berikutnya — Jembatan Orchestrator–SLM Tanpa Build

## Tujuan

Membuat hubungan orchestrator–SLM menjadi nyata dan terstruktur. Orchestrator tetap menjadi pengendali policy, capability, data, Action Plan, konfirmasi, dan verifikasi; SLM lokal dipakai untuk memahami bahasa/gambar, menyusun reasoning, membuat narasi laporan, dan menjelaskan rekomendasi dari fakta yang sudah disiapkan aplikasi.

Tidak ada build APK/debug/release/signing pada tahap ini. Setelah milestone valid, buat source ZIP bersih tanpa key, model GGUF, APK/AAB, cache, artefak build, log build, atau arsip source asli.

## Pekerjaan utama

### 1. Satukan reasoning context dengan gateway SLM

Gunakan `FfmAssistantReasoningContext` sebagai sumber konteks terstruktur untuk prompt gateway, menggantikan penggabungan string yang tersebar. Context harus mencakup request, halaman aktif, filter, capability allowlist, user memory approved, status model, dan hasil step sebelumnya.

Tambahkan protocol output terstruktur untuk membedakan:

- pemahaman maksud;
- fakta/field yang diekstrak;
- pertanyaan klarifikasi;
- insight narasi;
- capability yang disarankan;
- alasan/tingkat confidence;
- status yang harus tetap ditangani orchestrator.

Output SLM harus divalidasi terhadap schema dan allowlist. SLM tidak boleh menentukan capability yang tidak aktif, melewati konfirmasi, menjalankan SQL, atau mengubah angka sumber.

### 2. Hubungkan recommendation engine ke insight SLM

Recommendation facts dihitung deterministic oleh aplikasi. Jika model siap, kirim facts bounded ke SLM untuk menyusun penjelasan bahasa Indonesia dan opsi tindakan. Simpan insight sebagai hasil sementara/session, bukan memory otomatis.

Jika SLM tidak siap, gunakan insight deterministic dan beri status yang jelas. Recommendation tetap read-only, memiliki deduplication/expiry, dan pilihan tindakan yang mengubah data harus menjadi draft Action Plan.

### 3. Perkuat report workflow dari chat

Gunakan `FfmAssistantReportService` dari intent report untuk menghasilkan preview. SLM menerima JSON laporan sebagai satu-satunya sumber angka dan menghasilkan narasi terpisah dari data asli. UI harus membedakan DATA ASLI, PERHITUNGAN, dan INTERPRETASI SLM.

Tambahkan export/share final hanya setelah aksi eksplisit user. Jangan menyebut file telah dibuat jika exporter belum benar-benar menghasilkan file.

### 4. Peningkatan pemahaman user yang aman

Masukkan approved user context ke reasoning context dengan minimisasi. Preferensi hanya mengubah gaya/format/resolusi alias, bukan izin atau angka. Tambahkan feedback event terstruktur untuk koreksi user; feedback menjadi candidate learning pending, tidak langsung mengubah workflow aktif.

### 5. Perluasan adapter read domain

Setelah jembatan SLM stabil, tambahkan adapter read untuk budget, target, aset, utang/piutang, recurring, reminder, aktivitas, audit, dan status privacy/model. Semua hasil harus berupa ringkasan bounded yang dapat dipakai report/recommendation.

## Test plan

Tambahkan test untuk:

- reasoning context diteruskan ke gateway dengan redaction dan batas ukuran;
- output SLM invalid/unauthorized ditolak oleh validator;
- capability yang tidak aktif tidak dapat dipilih SLM;
- recommendation facts tidak berubah ketika dinarasikan SLM;
- report prompt melarang angka fiktif dan preview tidak menulis database;
- approved user context memengaruhi format, tetapi tidak policy/izin;
- feedback menjadi pending candidate dan tidak aktif sebelum approval;
- fallback deterministic bekerja ketika SLM belum siap atau gagal;
- adapter read domain baru hanya mengirim summary, bukan raw rows.

## Validasi dan dokumentasi

Jalankan `dart format`, `flutter analyze lib test`, targeted tests, lalu full `flutter test`. Tidak menjalankan `flutter build`, Gradle, signing, APK inspection, atau source archive lama. Perbarui `PROJECT_CONTEXT.md` dan `docs/implementation_status.md` hanya berdasarkan hasil validasi aktual. Buat ZIP source milestone di akhir.

## Risiko dan batasan

SLM tetap tidak menjadi sumber kebenaran atau eksekutor langsung. Physical Android inference Qwen2-VL belum tervalidasi pada perangkat. Narrative report dan recommendation tidak boleh disebut selesai penuh sebelum jalur SLM/fallback serta UI status diuji. Adapter read domain dapat dilakukan bertahap; jangan mengaktifkan capability hanya karena tercatat di katalog jika handler belum terpasang.

## Kriteria selesai

Milestone selesai jika orchestrator mengirim satu reasoning context bounded ke SLM, output SLM tervalidasi dan tidak dapat melewati policy, recommendation/report memakai facts lokal dengan narasi terpisah, user context approved diterapkan secara aman, fallback tanpa SLM berjalan, tests lulus, analyzer bersih, dokumentasi akurat, dan ZIP source tersedia tanpa build APK.
