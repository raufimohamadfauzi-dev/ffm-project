# Handoff: Gemini-first Conversation, Agent-safe Execution

**Status:** tahap 2 selesai — loop Gemini read-only bounded sudah dimiliki orkestrator.
**Diperbarui:** 28 Agustus 2026 (Asia/Jakarta).  
**Pemilik arsitektur:** fitur `lib/features/assistant/`.

Dokumen ini adalah titik lanjut untuk agent berikutnya. Baca bersama `AGENTS.md`, `docs/assistant_routing_hardening.md`, dan `docs/ffm_local_llm_architecture.md` sebelum mengubah router atau capability asisten.

## Keputusan produk

Gemini Cloud adalah lawan bicara utama saat pengguna memilih mode **Gemini Cloud**. Agent FFM bukan chatbot saingan; ia adalah lapisan aplikasi yang:

- membangun konteks terbatas dan aman;
- memvalidasi JSON proposal dari model;
- membaca fakta finansial secara deterministik;
- membuat draft, meminta konfirmasi, menjalankan capability, dan memverifikasi hasil;
- tidak pernah memberikan akses database, kredensial, SQL, atau mutasi langsung kepada Gemini.

Mode **Agent** tetap menjadi jalur lokal/offline yang memakai aturan deterministik dan, bila siap, SLM lokal.

```text
Pengguna
  → Gemini (memahami bahasa dan membuat jawaban/proposal)
  → Validator + Capability Agent (fakta, draft, konfirmasi, eksekusi)
  → Gemini (opsional: merangkai jawaban dari hasil terverifikasi)
  → Pengguna
```

## Yang sudah dikerjakan

### Routing Gemini-first

`FfmAssistantInterpreter.interpret` sekarang mendeteksi `FfmAssistantRoutingMode.geminiCloud` dan, setelah memproses JSON proposal yang ditempel langsung serta normalisasi aman, meneruskan percakapan ke `_tryGeminiResponse` **sebelum** FAQ, katalog, sapaan, query lokal, dan harness Agent.

Hasil Gemini masih diproses oleh `FfmAssistantProposalJsonService`:

- teks biasa → respons `geminiCloud`;
- proposal `transaction`, `master_data`, `activity`, atau `memory` → draft/teaching proposal yang tetap divalidasi FFM;
- Gemini tidak pernah memanggil executor atau menulis state aplikasi.

File utama: `lib/features/assistant/data/ffm_assistant_interpreter.dart`.

### Regressi sapaan dan dialog diperbaiki

Sebelumnya resolver dialog lokal menganggap kata seperti `mau`, `bisa`, `sip`, atau `sudah` di dalam pertanyaan singkat sebagai respons atas sapaan. Contoh `Mau investasi apa sekarang?` dapat menghasilkan template "Aku siap membantu" tanpa memanggil Gemini.

Perbaikan:

- resolver dialog tidak berjalan dalam mode Gemini;
- dalam mode Agent, afirmasi/penolakan hanya cocok jika seluruh pesan adalah respons pendek yang berdiri sendiri;
- pemulihan riwayat selesai sebelum sapaan kontekstual dibuat;
- jika riwayat dipulihkan, sapaan tidak menimpa riwayat atau `lastAssistantText`.

File utama: `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart` dan `lib/features/assistant/data/ffm_assistant_interpreter.dart`.

### Aktivitas mengikuti mode Gemini

`_tryHandleActivityRequest` tidak lagi mengambil alih percakapan saat mode Gemini aktif. Gemini menerima pertanyaan/perintah Aktivitas, tetapi proposal hasilnya tetap masuk ke pipeline draft dan konfirmasi Agent.

### Loop capability read-only Gemini → Agent → Gemini

Tahap awal capability loop telah dipasang dengan dua capability saja:

1. Gemini dapat mengembalikan JSON `ffm-assistant-capability-request-v1` untuk `read.summary` atau `read.transactions` pada `current_month`.
2. `FfmAssistantProposalJsonService` memvalidasi format, ID capability, dan periode melalui allowlist sempit.
3. `FfmGeminiCloudOrchestrator` meminta adapter Agent membaca snapshot agregat dari `FfmAssistantFinancialSnapshotService`.
4. `read.summary` hanya mengirim fakta bounded (`income`, `expenses`, jumlah transaksi, cicilan aktif, dan quality). `read.transactions` hanya mengirim maksimal delapan fakta tanggal/jenis/nominal, tanpa merchant, rekening, kategori, catatan, maupun ID.
5. Gemini membuat jawaban naratif final. Semua capability selain dua ID tersebut, termasuk `mutate.*`, ditolak tanpa panggilan kedua atau perubahan data.

Eksekusi capability dibungkus dalam `lib/features/assistant/data/ffm_gemini_read_capability_service.dart`. Loop Gemini (panggilan pertama → capability → panggilan akhir) berada di `lib/features/assistant/data/ffm_gemini_cloud_orchestrator.dart`; interpreter hanya membangun konteks dan mengubah hasil tervalidasi menjadi intent/draft. File validator tetap `lib/features/assistant/data/ffm_assistant_proposal_json_service.dart`.

### Privasi dan latensi Agent lokal

Pencarian memory Supabase hanya dilakukan untuk mode Gemini. Mode Agent tidak lagi memanggil cloud memory hanya untuk kemudian memberi jawaban lokal deterministik.

## Kontrak yang tidak boleh dilanggar

1. Model tidak boleh memutasi state, memanggil repository, menjalankan SQL, atau menerima secret.
2. Nilai finansial resmi selalu berasal dari query/komputasi FFM, bukan teks Gemini.
3. Semua mutasi harus melalui: proposal → validasi → draft → konfirmasi pengguna → executor → verifikasi.
4. `FfmAssistantProposalJsonService` adalah gerbang JSON Gemini saat ini. Jangan menerima capability atau field baru tanpa validator eksplisit.
5. Capability yang tidak tersedia pada halaman/konteks saat ini harus ditolak oleh aplikasi, bukan dipercayai karena disebut Gemini.
6. Jangan mengirim seluruh database, raw chat history tanpa batas, token, PIN, atau kredensial ke Gemini.

## Status pekerjaan

| Area | Status | Keterangan |
|---|---|---|
| Gemini menjadi percakapan utama | Selesai | Mode Gemini merutekan percakapan ke Gemini lebih awal. |
| Agent sebagai batas mutasi | Selesai | Proposal JSON tetap menjadi draft tervalidasi dan butuh konfirmasi. |
| Dialog/sapaan tidak menelan pertanyaan | Selesai | Ada regression test khusus. |
| Riwayat vs sapaan | Selesai | Riwayat dipulihkan sebelum sapaan; `lastAssistantText` diselaraskan. |
| Aktivitas di mode Gemini | Selesai | Tidak lagi dipotong parser UI lokal. |
| Tool/result loop Gemini ↔ Agent | Selesai (lingkup awal) | `read.summary` dan `read.transactions` / bulan berjalan melalui loop dua panggilan. |
| Respons final Gemini dari hasil capability | Selesai (lingkup awal) | Jawaban akhir Gemini memakai snapshot atau digest bounded. |
| Structured output capability allowlist | Selesai (lingkup awal) | Allowlist eksplisit hanya memuat `read.summary` dan `read.transactions`; capability lain ditolak. |
| Pengujian API Gemini nyata | Belum | Tes memakai fake Gemini; jangan klaim koneksi produksi sudah terbukti. |
| Uji perangkat Android ARM64 | Belum | Belum memvalidasi alur Gemini-first pada perangkat nyata. |

## Langkah berikutnya yang direkomendasikan

### 1. Perluas kontrak read capability secara bertahap

Jangan memberi Gemini akses umum. Berikutnya tambahkan hanya request read yang dapat diizinkan, satu per satu, misalnya `read.transactions` dengan parameter tanggal/kategori yang tervalidasi:

```json
{
  "formatVersion": "ffm-assistant-proposal-v2",
  "kind": "capability_request",
  "capabilityId": "read.monthly_summary",
  "arguments": { "period": "current_month" },
  "userFacingReply": "Saya cek ringkasan bulan ini dulu."
}
```

Implementasi harus:

1. memvalidasi format, `capabilityId`, dan argumen melalui allowlist lokal;
2. menjalankan hanya capability **read-only**;
3. membatasi serta mensanitasi hasilnya;
4. mengirim fakta hasil query ke Gemini dalam panggilan kedua;
5. menampilkan jawaban Gemini hanya sebagai penjelasan fakta tersebut.

Jangan tambahkan capability mutation ke kontrak ini. Mutasi tetap memakai proposal draft v1 yang sudah ada.

### 2. Perluas orchestrator tanpa memperlebar hak akses

`FfmGeminiCloudOrchestrator` sudah menangani loop dua panggilan. Tahap berikutnya hanya boleh menambah capability read setelah memiliki validator allowlist, adapter evidence bounded, dan regression test:

```text
Gemini proposal/read request
  → validator proposal
  → capability executor (read-only)
  → bounded verified result
  → Gemini final narrative
```

Gunakan timeout, cancellation, dan satu batas concurrency yang ada. Bila panggilan kedua gagal, tampilkan hasil deterministik dari Agent dengan label yang jujur; jangan menyamarkannya sebagai Gemini.

### 3. Perjelas status UI

Tampilkan sumber final berdasarkan `FfmAssistantResponseOrigin` aktual:

- `Gemini Cloud` untuk respons/penceritaan Gemini;
- `Data lokal FFM` bila Agent menjawab dari capability;
- `Menunggu konfirmasi` untuk draft;
- `Gemini tidak tersedia` untuk kegagalan cloud.

Teks progress tidak boleh mengklaim request sudah dikirim jika yang sedang dilakukan adalah validasi/draft lokal.

### 4. Tambahkan test integrasi

Minimal test yang wajib ditambahkan sebelum tahap 2 dianggap selesai:

- Gemini mode + sapaan + pertanyaan pendek tetap memanggil Gemini.
- Gemini mode + perintah Aktivitas tetap memanggil Gemini, lalu proposalnya menjadi draft.
- JSON capability yang tidak ada di allowlist ditolak dan tidak menjalankan executor.
- Capability read menghasilkan fakta bounded; Gemini hanya menerima fakta tersebut.
- JSON mutasi tidak bisa mencapai persistence tanpa konfirmasi.
- Riwayat tersimpan tidak tertimpa sapaan ketika sheet dibuka ulang.
- timeout/format JSON Gemini buruk menghasilkan fallback jujur tanpa mutasi.

## Validasi terakhir

Dijalankan pada perubahan tahap 2:

```powershell
flutter test --no-pub test/ffm_agent_local_slm_test.dart test/ffm_gemini_routing_test.dart
dart analyze lib/features/assistant/data/ffm_assistant_interpreter.dart lib/features/assistant/data/ffm_gemini_cloud_orchestrator.dart lib/features/assistant/data/ffm_gemini_read_capability_service.dart lib/features/assistant/data/ffm_assistant_proposal_json_service.dart
```

Hasil: seluruh test yang disebut lulus; pemeriksaan `dart analyze` bersih. Ini bukan bukti koneksi Gemini produksi maupun uji perangkat Android.

## Catatan kondisi working tree

Working tree sudah memiliki perubahan lain yang belum di-commit sebelum tahap ini, termasuk file DI, UI Aktivitas, Gemini service, serta beberapa test. Jangan melakukan `reset`, `checkout --`, atau menghapus perubahan yang tidak berkaitan. Tinjau `git diff` per file sebelum membuat commit.
