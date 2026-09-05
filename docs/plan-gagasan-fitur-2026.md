# Plan Gagasan Fitur 2026 — Fokus Lanjut: B1 + C1 (Halaman Chatbot)

Dokumen perencanaan (tanpa coding). Ruang lingkup hanya **keputusan LANJUT**, dikerjakan di
**halaman chatbot asisten** (`FfmAssistantSheet`). Fitur ditunda/cadangan (A1 QRIS MPM, B3 Portfolio,
Subscription Tracker, eksplorasi Android OS) **tidak** dibahas di sini dan bukan bagian dari lingkup.

---

## 0. Analisa Baseline Halaman Chatbot (terukur)

Baseline dari pembacaan kode, dipakai sebagai titik ukur sebelum/sesudah perubahan:

| Aspek | Kondisi Saat Ini | Lokasi |
|---|---|---|
| UI chat | `FfmAssistantSheet` + bubble `FfmAssistantMessageCard` | `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart`, `.../chat/ffm_assistant_message_card.dart` |
| Penyimpanan riwayat | **SharedPreferences JSON** (`ffm_assistant_chat_history_v1`, `ffm_assistant_chat_conversations_v1`), maks 30 percakapan / 100 entri — **bukan** DB Drift/SQLite | `lib/features/assistant/data/ffm_assistant_chat_history_repository.dart` |
| Model entri | `FfmAssistantChatEntry`: `isUser`, `text`, `createdAt?`, `processTrace?` (origin/elapsed/tokenUsage), `verifiedFacts`, `analysisResults`, `feedback*`, `filePath?`/`fileFormat?` (**hanya file keluaran asisten**, bukan upload user) | `lib/features/assistant/domain/ffm_assistant_models.dart:539` |
| OCR/struk | Ditolak eksplisit oleh interpreter: *"Asisten saat ini hanya menerima perintah teks"* | `lib/features/assistant/data/ffm_assistant_interpreter.dart:~1982` |
| Input chat | Hanya teks; **tidak ada tombol lampirkan foto/galeri/kamera** | `ffm_assistant_sheet.dart` |
| Draft transaksi | Sudah ada `FfmAssistantDraft` + `FfmAssistantDraftValidator` + `FfmAssistantDraftFeedbackService` + preview/edit dialog; repository draft punya `addIfNotDuplicate` (**idempoten**) | `lib/features/assistant/data/ffm_assistant_draft_validator.dart`, `.../payment_draft_repository.dart:145` |
| Cloud reasoning | `FfmGeminiCloudOrchestrator` dengan read terbatas (`read.summary`, `read.transactions` maks 8 item, tanpa detail merchant/kategori/akun) | orchestrator existing |

**Kesimpulan analisa**: B1 dan C1 adalah dua perbaikan halaman chatbot yang saling melengkapi —
B1 menambah **kanal input gambar→draft terstruktur**; C1 menambah **transparansi eksekusi**
(waktu & model) tanpa mencemari tampilan. Keduanya tidak menyentuh DB Drift (riwayat chat = JSON lokal).

---

## 1. B1 — AI Receipt Scanner (Prioritas 1, LANJUT)

### Tujuan terukur
Foto/PDF struk di dalam percakapan → draft transaksi multi-baris (item + kategori) → konfirmasi 1 ketukan → executor atomik.

### Perubahan halaman chatbot (C1/UI)
1. Tombol lampirkan di input chat (ikon lampir): **Photo Picker** (tanpa izin seluruh galeri) + kamera → kirim gambar/PDF sebagai pesan user (`FfmAssistantChatEntry` + `filePath` user-side, baru bagi input).
2. Bubble user menampilkan pratinjau gambar; bubble asisten menampilkan **preview draft multi-baris** memakai komponen `FfmAssistantDraftPreview` yang sudah ada + tombol "Simpan".

### Alur pipeline
1. **Input**: lampir foto/PDF struk → entry user dgn `filePath`/`fileFormat`.
2. **OCR** (routing alami): jalur cloud `Gemini` (bounded: gambar + konteks terbatas, tanpa full DB); **fallback on-device `ML Kit Text Recognition`** saat offline/cloud gagal.
3. **Strukturisasi deterministik**: parser OCR → daftar item (nama, qty, harga satuan, total) + merchant + tanggal + PPN; `total struk == Σ baris ± toleransi Rp<100` **harus divalidasi deterministik**, else minta ulang (bukan tebakan LLM).
4. **Kategori**: saran via algoritma lokal + memori personal; user bisa ganti di edit dialog.
5. **Draft & konfirmasi**: `FfmAssistantDraft` → validator → preview → 1 ketukan "Simpan" → executor atomik (dukung `linkedActivityId` bila sesi aktif).
6. **Deduplikasi**: hash gambar + tanggal + total, pakai jalur idempoten repository draft (`addIfNotDuplicate`).
7. **Belajar**: koreksi kategori/item → `FfmPersonalMemoryService` (struk berikutnya makin tepat).

### Target ukuran penerimaan (measurable)
| Metrik | Target |
|---|---|
| Validasi total vs Σ baris | 100% kasus tervalidasi (selisih ≠ 0 → minta ulang, tidak disimpan) |
| Waktu ke-draft pertama (cloud, P50) | ≤ 3 detik (draft preview tampil), P95 ≤ 8 detik |
| Waktu ke-draft pertama (offline ML Kit) | ≤ 1,5 detik |
| Dedup struk sama di-scan 2× | 0 duplikat masuk DB |
| Test baru (unit parser + validasi + dedup + integrasi mutasi) | ≥ 12 test |
| Interpreter | blok penolakan OCR diganti route ke receipt-intent (+ test alur) |

---

## 2. C1 — Chat Metadata: Waktu Kirim/Terima + Model (Prioritas 2, LANJUT)

### Tujuan terukur
Setiap entri menyimpan **waktu dikirim**, **waktu tiba**, dan **model/alur** jawaban; tersembunyi dari UI,
muncul **saat bubble ditekan**. Transparansi eksekusi (AGENTS.md §14) tanpa mencemari percakapan.

### Perubahan storage (bukan migrasi SQLite)
- `FfmAssistantChatEntry` (ffm_assistant_models.dart:539) + fields:
  - `sentAt?` (waktu dikirim), `receivedAt?` (waktu tiba, meaningful utk pesan bot),
  - `modelUsed?` (id human-readable: `gemini-cloud` / `agent` / `local`), fallback = derive dari `processTrace.origin`.
- Repository (`_encodeEntry`/`_decodeEntry`) diperpanjang **backward-compatible** (default null → data lama tetap terbaca; fallback `sentAt = createdAt`). DB Drift/`user_version` **tidak disentuh**.

### Perubahan halaman chatbot (UI)
- Bubble dibungkus tap (InkWell/GestureDetector): tap → baris metadata kecil tanpa scroll.
  - User: `sentAt`. Bot: `sentAt` + `receivedAt(+durasi respons)` + `modelUsed`.
- Tap bubble lain / auto-hide ~3 detik menutup metadata.

### Target ukuran penerimaan
| Metrik | Target |
|---|---|
| Round-trip encode/decode field baru | 100% konsisten (test round-trip) |
| Baca data legacy (tanpa field baru) | 0 error, fallback `createdAt` |
| UI reveal | tap show / tap lain + auto-hide, tanpa scroll ulang |
| Test baru (repo + UI state) | ≥ 8 test |

---

## 3. Ringkasan Perubahan Halaman Chatbot (B1 + C1)

| Area | Ubah | File |
|---|---|---|
| Model entri | + `sentAt`, `receivedAt`, `modelUsed` | `ffm_assistant_models.dart` |
| Repo riwayat | encode/decode backward-compatible | `ffm_assistant_chat_history_repository.dart` |
| Bubble | tap-to-reveal metadata; pratinjau gambar user | `chat/ffm_assistant_message_card.dart` |
| Sheet | tombol lampir (Photo Picker/kamera); route hasil OCR ke draft; set timestamp saat append | `ffm_assistant_sheet.dart` |
| Interpreter | ganti blok tolak OCR → intent receipt; sediakan route | `ffm_assistant_interpreter.dart` |
| **NEW** pipeline OCR | service OCR (Gemini + ML Kit), parser struktur, builder draft multi-baris | modul baru di `lib/features/assistant/data/` |
| Test | parser, validasi, dedupe, roundtrip repo, mutasi integrasi | `test/` |

**Config**: strip cloud ke bounded context (gambar + parameter); tidak mengirim DB penuh ke model.

---

## Definition of Done (umum, sesuai AGENTS.md)
- Boundary dipatuhi: validasi → konfirmasi → eksekutor (mutasi hanya lewat executor atomik).
- Nilai keuangan deterministik lokal; struktur struk divalidasi, bukan angka tebakan model.
- Tidak ada secret di source code.
- `flutter analyze lib test` (0 errors) + full test suite hijau; release ARM64 tetap buildable.
- Data lama terbaca (backward-compatible decode); tidak ada migrasi DB Drift baru.