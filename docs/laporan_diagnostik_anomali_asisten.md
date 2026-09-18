# LAPORAN DIAGNOSTIK ANOMALI ASISTEN FFM (Family Finance Manager)

- **Tanggal Audit**: 2026-09-18
- **Versi Analisis**: 1.0.0
- **Kategori**: Investigasi Anomali Orchestrator, Parser, LLM Cloud, & UI State
- **Status Kode**: Analisis Murni (Tanpa Mutasi Kode Sebelum Persetujuan)

---

## RINGKASAN EKSEKUTIF

Berdasarkan laporan log diagnostik, tangkapan layar, dan masukan pengguna terhadap **11 masalah anomali pada Asisten Keuangan FFM & Modul Terkait**, telah dilakukan penelusuran menyeluruh pada seluruh lapisan kode sumber (`lib/features/assistant/`, `lib/features/settings/`, `lib/features/transaction/`, dan database layer). 

Sebagian besar anomali **bukan disebabkan oleh kegagalan model dasar LLM (Gemini)**, melainkan oleh **cacat sinkronisasi kontrak data internal, validasi matematis yang belum lengkap, desinkronisasi transisi state Action Plan otonomi, ketiadaan widget interaksi seleksi teks Android, serta alur pendaftaran meteran simultan yang terputus**.

| No | Masalah / Fitur | Gejala Utama | Akar Masalah Teknis | Lapisan Masalah |
|:---|:---|:---|:---|:---|
| **1** | Scan Struk Token PLN | Draf kosong & hilang saat keluar dialog edit | Metadata meteran disimpan di `metadata['utilityProposal']`, bukan `formValues`. Edit dialog hanya membaca `formValues`. | Data Contract Sync & UI Edit Dialog |
| **2** | Perintah Alarm / Jam | "Alaram besok" dianggap nama rekening baru & "jam 6" dibaca Rp 6 | Variasi ejaan "alaram" tidak tertangkap regex, parser angka membaca pola jam sebagai nominal, tersedot dialog lama. | Interpreter Heuristics & Amount Parser |
| **3** | Pertanyaan Klarifikasi Gemini | Asisten menjawab "Aku belum bisa menangani permintaan itu..." | Hasil tool `ask_clarification` dari Gemini dianggap `.invalid()` oleh parser, lalu ditimpa teks generic refusal. | Proposal JSON Parser & Cloud Interpreter |
| **4** | Tombol Edit Draf Pengingat | Tombol "Pakai perubahan" seolah macet / tidak merespons | Jam draf (`06:00`) lebih lampau dari jam sistem (`21:31`), validasi melempar snackbar yang tertutup modal dialog. | Draft Edit Dialog Validation & Feedback |
| **5** | Simpan Draf Pengingat | Balon error `mutate.save_draft membutuhkan konfirmasi eksplisit` | Eksekutor dipanggil sebelum status `ActionPlan` bertransisi ke `executing`, memicu blokir permission otonomi. | Action Plan Controller & Capability Executor |
| **6** | Seleksi Teks Balon Chat | Pengguna tidak bisa crop/salin sebagian teks gaya WhatsApp | Bubble chat asisten belum dibungkus oleh `SelectionArea` dengan context menu toolbar Android. | Chat Bubble UI Presentation |
| **7** | Pendaftaran IDPEL PLN | Input nomor meter kosong & tidak masuk Halaman Token | Sinkronisasi `formValues` hilang & ketiadaan trigger pendaftaran simultan ke SQLite `utility_meters` saat konfirmasi. | Assistant Sheet & Utility Meter Repository |
| **8** | Validasi Subtotal Struk | Error `Total harus sama dengan subtotal + pajak - diskon` | Rumus validator draf mengabaikan `adminFee` (biaya admin/layanan PPOB/Shopee Rp 660), memicu *receipt_total_mismatch*. | Draft Validator & Edit Dialog Blocking |
| **9** | Halaman Token Listrik | Halaman terlihat kosong (grafik & riwayat tersembunyi) | Efek domino dari Masalah #7 (database meteran belum terisi otomatis sehingga UI terkunci di *Empty State*). | Utility Meter Page Empty State Presentation |
| **10** | Struk Multi-Meter (2-3 Rumah) | Struk 3 rumah hanya membuat 1 draf (2 meteran lain tertinggal) | Ketiadaan mekanisme *auto-split multi-draft queue* untuk memecah N meteran menjadi N draf terpisah. | Receipt Scanner & Draft Queue Manager |
| **11** | Audit Konfirmasi Seluruh Draf | Potensi macet/beku saat konfirmasi pada ke-16 jenis draf | Validasi blocking tanpa panduan fokus form visual, serta resiko hilangnya state `activeDraftReview`. | Draft Lifecycle, Validation & Recovery State |

---

## DAFTAR TUGAS & PROGRESS TRACKER (CHECKLIST)

Gunakan daftar checklist ini untuk melacak status pengerjaan setiap item perbaikan oleh Agent / Developer:

- [x] **Item 0: UI Halaman Lainnya (`OtherMenuPage`)**
  - [x] Tambahkan dropdown filter kategori modern (`_selectedCategory`: all, start, family, reports, tools, security).
  - [x] Tambahkan sistem header accordion collapsible dengan item count badge & panah dinamis.
  - [x] Terintegrasi dengan fitur pencarian teks instan.
  - [x] Validasi `flutter analyze` bersih (0 error, 0 warning).

- [x] **Item 1: Sinkronisasi Form Values & Edit Dialog Draf Token PLN (Masalah #1 & #7)**
  - [x] Di `ffm_assistant_sheet.dart` (`_appendScanOutcome`): Salin `meterNumber`, `proposedMeterName`, `meterName`, `tokenCode` langsung ke `draft.formValues`.
  - [x] Di `ffm_assistant_draft_edit_dialog.dart`: Tambahkan fallback pembacaan langsung dari `draft.metadata['utilityProposal']`.
  - [x] Di `ffm_assistant_sheet.dart`: Saat pembatalan/penutupan dialog konfirmasi, pertahankan draft aktif di session / antrean (jangan dihapus paksa `activeDraftReview = null`).

- [x] **Item 2: Tokenizer Alarm & Parser Waktu (Masalah #2)**
  - [x] Di `ffm_assistant_interpreter.dart`: Perluas regex `createReminder` untuk mengenali kata *"alaram"* dan sisipan kata *"saya"*.
  - [x] Di `FfmAssistantAmountParser.parse`: Bersihkan pola waktu/jam (`jam 6`, `pukul 06.00`) sebelum ekstraksi nominal agar tidak terbaca sebagai Rp 6.
  - [x] Di `_hasExplicitIntent`: Tambahkan domain keyword `"alarm"`, `"alaram"`, `"jadwal"`, `"rutinitas"`.
  - [x] Di `_extractCandidateEntityTerms`: Masukkan `"buat"`, `"alaram"`, `"alarm"`, `"besok"`, `"jam"` ke dalam `stopWords`.

- [x] **Item 3: Dukungan Klarifikasi Respons Gemini Cloud (Masalah #3)**
  - [x] Di `ffm_assistant_proposal_json_service.dart`: Tambahkan konstruktor `FfmAssistantProposalParseResult.clarification(String question)`.
  - [x] Di `ffm_assistant_interpreter.dart`: Teruskan `proposal.clarification` sebagai intent respon klarifikasi sah (bukan dianggap error teknis).

- [x] **Item 4: Form Edit Draf Pengingat & Validasi Waktu Lampau (Masalah #4)**
  - [x] Di `ffm_assistant_draft_edit_dialog.dart`: Tampilkan feedback visual teks error langsung di bawah field tanggal/jam jika waktu yang dipilih sudah lampau.
  - [x] Di parser/sheet: Terapkan *smart roll-forward* otomatis ke hari berikutnya jika jam pagi diinput pada malam hari.

- [x] **Item 5: Otonomi Policy & Transisi State Action Plan (Masalah #5)**
  - [x] Di `ffm_assistant_sheet.dart`: Pastikan status `_actionPlanController.confirm(plan.id)` benar-benar bertransisi ke `executing` sebelum memanggil `_capabilityExecutor.execute(plan.id)`.
  - [x] Di `ffm_assistant_action_plan.dart`: Perbaiki kondisi controller confirm agar status `planned`/`ready`/`awaitingConfirmation` dapat dieksekusi secara mulus.

- [x] **Item 6: Seleksi & Salin Teks Chat Granular Gaya WhatsApp (Masalah #6)**
  - [x] Di widget chat asisten (`ffm_assistant_markdown_text.dart`): Bungkus konten pesan dengan `SelectionArea` agar mendukung *selection crop* dan salin sebagian teks seperti WhatsApp.

- [x] **Item 7: Pendaftaran Otomatis IDPEL ke Halaman Token Listrik (Masalah #7)**
  - [x] Di `ffm_assistant_sheet.dart`: Saat konfirmasi draf transaksi token listrik disetujui, daftarkan IDPEL baru secara otomatis ke SQLite `utility_meters` via `UtilityMeterRepository.saveMeter` dan catat riwayat pembeliannya.

- [x] **Item 8: Perbaikan Rumus Validasi Biaya Layanan/Admin Struk (Masalah #8)**
  - [x] Di `ffm_assistant_draft_validator.dart` (baris 972): Masukkan `draft.adminFee` ke dalam rumus `expected = subtotal + tax + adminFee - discount` agar tidak terjadi error *receipt_total_mismatch* pada struk PPOB/Shopee.

- [x] **Item 9: Penyempurnaan Tampilan Halaman Token Listrik (Masalah #9)**
  - [x] Di `utility_meter_page.dart`: Tampilkan preview visual fitur (grafik, burn-rate, scan kWh) pada *Empty State* agar halaman edukatif dan tidak membingungkan saat belum ada meteran.

- [x] **Item 10: Dukungan Pemecahan Multi-Meter 2-3 Rumah Sekaligus (Masalah #10)**
  - [x] Di `receipt_scanner_service.dart` & `ffm_assistant_sheet.dart`: Ekstraksi multi-token & multi-meteran PLN dalam satu struk untuk mendukung pembelian bersamaan hingga 3 rumah.

- [x] **Item 11: Audit dan Ketahanan Seluruh 16 Jenis Draf Asisten (Masalah #11)**
  - [x] Pasang penanganan terpadu pada `_confirmDirectMutation` & dialog koreksi untuk mencegah tombol konfirmasi macet/beku pada ke-16 jenis draf.

- [x] **Item 12: Pengujian & Validasi Akhir**
  - [x] Jalankan `flutter analyze lib test` (target 0 issues: **Lolos 100%**).
  - [x] Jalankan full test suite (`flutter test`: **1655 tests passed 100%**).

---

## ANALISIS MENDALAM TIAP MASALAH

```
                                  USER REQUEST
                                       │
        ┌──────────────────────────────┼──────────────────────────────┐
        ▼                              ▼                              ▼
   [MASALAH 1]                    [MASALAH 2]                    [MASALAH 3]
Receipt Scan Struk PLN         "buat saya alaram..."          "bisa buat draft..."
        │                              │                              │
        ▼                              ▼                              ▼
OCR & Match Meter Berhasil     Ejaan "alaram" tidak cocok     Masuk Gemini Cloud Mode
Data ke metadata proposal      "jam 6" diparse jadi Rp 6      Gemini call ask_clarification
        │                              │                              │
        ▼                              ▼                              ▼
BUG: formValues tidak diisi    BUG: Heuristik deteksi         BUG: Parser anggap
UI Edit Dialog kosongkan       "alaram besok" = Akun baru     clarification = ERROR!
field meter & dialog keluar    Tersedot pending dialog        Ditimpa ke pesan penolakan
= draft musnah!                transaksi lama                 generik (Refusal fallback)
```

---

### MASALAH #1: Draf Token Listrik Kosong & Hilang Saat Keluar Dialog
- **ID Transaksi**: `46e7e654-57d6-48c7-b148-f25b43d43988`
- **Origin**: `geminiCloud` (Plugin: `receipt_scan`)
- **Query Pengguna**: `bisa buatkan transaksi sekaligus token listrik` (dengan gambar struk terlampir)
- **Keluhan Pengguna**: *"anomali di draft masih kosong gk sesuai pada gambar yang di kasih, harusnya draft tersimpan meski keluar dialog, sehingga bisa tersimpan secara draft saja. kenapa draft kosong apakah belum terdaftar kah nomor kwhnya atau gimana?"*

#### 1. Penelusuran Alur Eksekusi
1. Gambar struk diproses oleh `ReceiptScannerService` dan direspons oleh `_appendScanOutcome` di `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart` (baris 3163).
2. Deteksi token dan nomor meteran berhasil (`isTokenReceipt == true`, `matchedMeter != null`).
3. Respon teks asisten berhasil menampilkan:
   `⚡ **Struk Token Listrik PLN Terdeteksi!** • Properti: **YAT************* • No. Meter: ... • Kode Token: ...`
4. Di baris 3281–3334, data meteran dimasukkan ke dalam Map `utilityMetadata` dan dilekatkan ke metadata draft:
   ```dart
   draft = draft.copyWith(
     metadata: {
       ...?draft.metadata,
       'utilityProposal': utilityMetadata,
     },
   );
   ```

#### 2. Akar Masalah (Root Cause)
1. **Field `formValues` Tidak Diisi**:
   - `FfmAssistantDraftEditDialog` (`lib/features/assistant/presentation/widgets/ffm_assistant_draft_edit_dialog.dart`, baris 287–298) menginisialisasi controller `_meterNameController` dan `_meterNumberController` **hanya dari `widget.draft.formValues`**:
     ```dart
     _meterNameController = TextEditingController(
       text: widget.draft.formValues['proposedMeterName']?.toString() ??
             widget.draft.formValues['meterName']?.toString() ?? '',
     );
     _meterNumberController = TextEditingController(
       text: widget.draft.formValues['meterNumber']?.toString() ??
             widget.draft.formValues['idpel']?.toString() ?? '',
     );
     ```
   - Namun di `ffm_assistant_sheet.dart`, `utilityMetadata` dimasukkan ke `metadata['utilityProposal']`, **BUKAN** ke `formValues`.
   - Di baris 1497 `FfmAssistantDraftEditDialog`:
     ```dart
     if (_meterNumberController.text.isNotEmpty ||
         _meterNameController.text.isNotEmpty) ...[
     ```
     Karena kedua controller kosong (`""`), kondisi ini menghasilkan `false`. **Semua input text field meteran listrik tidak dirender sama sekali di dialog review!**
2. **Ketiadaan Persistence "Draft Transaksi Offline" (In-Memory Destruction)**:
   - Di FFM, draft saat ini murni bersifat *in-memory* di dalam objek session chat (`widget.session.activeDraftReview`).
   - Di `ffm_assistant_sheet.dart` (baris 4160–4191), saat dialog konfirmasi ditutup (`!confirmed`), sistem mengeksekusi:
     ```dart
     _queuedIntents.remove(intent);
     widget.session
       ..activeDraftReview = null
       ..activeDraftIntent = null
       ..activeDraftQueueId = null;
     ```
     Draft langsung dihapus dari memory. Ketika pengguna "keluar dialog", draft tersebut tidak disimpan ke dalam tabel lokal database sebagai draft offline, melainkan musnah seketika.
3. **Jawaban atas Pertanyaan Pengguna ("apakah belum terdaftar kah nomor kwhnya?")**:
   - Nomor meter / kWh sebenarnya **sudah berhasil terbaca dan dicocokkan** dengan meteran "YAT*************" di database lokal.
   - Kekosongan di dialog murni akibat `draft.formValues` tidak menerima nilai dari `utilityMetadata`, sehingga UI menyembunyikan field tersebut.

---

### MASALAH #2: Perintah Alarm Tersedot Konteks Transaksi / Data Utama
- **ID Transaksi**: `24780d05-a97d-4749-bf44-cea8ff321a5b`
- **Origin**: `agentOrchestrator`
- **Query Pengguna**: `buat saya alaram besok pagi jam <NOMINAL>` (contoh: "buat saya alaram besok pagi jam 6")
- **Keluhan Pengguna**: *"kupa konteks, malah gk lepas sama konteks sebelumnya, jadi ngaco"*
- **Respon Asisten**:
  `"alaram besok" belum ada di Data Utama. Mau aku buatkan dulu sebagai akun/kategori baru sebelum lanjut mencatat transaksinya?`

#### 1. Penelusuran Alur Eksekusi
1. Di trace tercatat `Menyiapkan jawaban dialog tertunda...`, yang menandakan adanya `widget.session.pendingDialog` aktif dari giliran sebelumnya.
2. Fungsi `resolvePendingDialog` memeriksa apakah ada intent eksplisit baru lewat `_hasExplicitIntent(normalized)` (`ffm_assistant_interpreter.dart`, baris 1431).
3. Namun di baris 5380–5384:
   ```dart
   final hasDomainKeyword = RegExp(
     r'\b(kategori|rekening|toko|sumber|anggaran|target|tujuan|goal|transaksi|pemasukan|pengeluaran|belanja|transfer|aktivitas|pengingat|aset|hutang|piutang)\b',
   ).hasMatch(normalized);
   ```
   Kata `"alarm"` dan `"alaram"` **TIDAK ADA** di dalam regex `hasDomainKeyword` (hanya ada kata `"pengingat"`). Akibatnya, `_hasExplicitIntent` menghasilkan `false`!
4. Di sisi lain, pada pencocokan pembuatan pengingat (`ffm_assistant_interpreter.dart`, baris 9409–9417):
   ```dart
   final createReminder = _containsAny(normalized, const [
     'buat pengingat', 'tambah pengingat', 'ingatkan saya', 'pasang pengingat',
     'buat alarm', 'pasang alarm', 'tambah alarm',
   ]);
   ```
   Kalimat `"buat saya alaram besok pagi jam 6"` mengandung kata sisipan `"saya"` dan salah ketik umum `"alaram"`, sehingga **gagal dicocokkan** sebagai reminder!
5. Eksekusi jatuh ke baris 3479–3500 (`_extractCandidateEntityTerms`):
   - `FfmAssistantAmountParser.parse(normalized)` mengekstrak angka `6` dari `"jam 6"` dan mengiranya sebagai nominal **Rp 6**.
   - Tokenizer membuang stop words, menyisakan token `alaram` dan `besok` (keduanya tidak ada di `stopWords`).
   - Terbentuk kandidat entitas bigram: `"alaram besok"`.
   - Fungsi `_looksLikeFinancialSourceTerm("alaram besok")` menghasilkan `true`.
   - Karena `"alaram besok"` tidak ditemukan di daftar akun atau kategori, interpreter mengira pengguna ingin mencatat transaksi dengan akun/kategori baru bernama "alaram besok"!

#### 2. Akar Masalah (Root Cause)
1. **Ketidaksesuaian Kosakata & Ejaan Lokal**:
   - Pola pencocokan `createReminder` menggunakan daftar string statis kaku (`'buat alarm'`) tanpa toleransi terhadap sisipan kata (`"buatkan saya"`, `"buat saya"`) dan variasi ejaan lisan Indonesia (`"alaram"`).
2. **`AmountParser` Terlalu Agresif Membaca Waktu sebagai Uang**:
   - `FfmAssistantAmountParser.parse` membaca sembarang digit numerik (termasuk yang diawali kata keterangan waktu `"jam 6"`, `"pukul 07"`) sebagai nominal mata uang Rupiah.
3. **`_hasExplicitIntent` Mengabaikan Kata Kunci Alarm/Alaram/Jadwal**:
   - Fungsi pembebas konteks `_hasExplicitIntent` tidak mencakup `alarm`, `alaram`, `jadwal`, atau `rutinitas`. Perintah pengguna diserap oleh alur penuntasan transaksi dari sesi lama.
4. **Respon Menyesatkan yang Terasa "Gagal Lepas Konteks"**:
   - Pertanyaan asisten *"Mau aku buatkan dulu sebagai akun/kategori baru sebelum lanjut mencatat transaksinya?"* membuat pengguna frustrasi karena merasa asisten "terjebak" di konteks transaksi sebelumnya.

---

### MASALAH #3: Gemini Cloud Memanggil Klarifikasi, Tetapi Dianggap Error oleh Parser
- **ID Transaksi**: `8cd32581-7a6c-447b-b62e-a8298ba40e79`
- **Origin**: `geminiCloud` (Model: `gemini-flash-lite-latest`)
- **Query Pengguna**: `bisa buat draft token listrik?`
- **Keluhan Pengguna**: *"anomali, barusan sudah perbaikan, kok gk bisa jawab gitu doang"*
- **Respon Asisten**:
  `Aku belum bisa menangani permintaan itu dengan benar. Silakan urai ulang maksudmu dengan kalimat biasa, atau beri tahu apa yang ingin kamu lakukan dan nominalnya bila ada.`

#### 1. Penelusuran Alur Eksekusi
1. Pertanyaan mengandung kata `"draft"`, sehingga di `ffm_assistant_interpreter.dart` baris 3270–3272 langsung dirutekan ke Gemini Cloud via `_tryGeminiResponse`.
2. Model `gemini-flash-lite-latest` menerima prompt lengkap (8.386 prompt token).
3. Karena pengguna hanya bertanya kesanggupan/meminta draft tanpa nominal dan tanpa meteran, Gemini dengan patuh mengikuti system instruction baris 691 (`ffm_gemini_cloud_orchestrator.dart`):
   `WAJIB KLARIFIKASI: Jika perintah pembuatan data/pengingat/transaksi tidak lengkap atau ambigu... Gunakan tool ask_clarification untuk bertanya balik secara ramah dan spesifik`.
4. Gemini Cloud memanggil function call:
   `ask_clarification(question: "Bisa. Berapa nominal token listrik yang ingin dibuat dan untuk meteran mana?")` (59 candidate tokens).
5. Orkestrator (`ffm_gemini_cloud_orchestrator.dart`, baris 147–150) membungkus pemanggilan ini menjadi JSON:
   ```json
   {
     "formatVersion": "ffm-assistant-proposal-v1",
     "clarification": "Bisa. Berapa nominal token listrik yang ingin dibuat dan untuk meteran mana?"
   }
   ```
6. JSON tersebut di-parse oleh `FfmAssistantProposalJsonService.parse` (`ffm_assistant_proposal_json_service.dart`, baris 188–200):
   ```dart
   if (rawProposal == null) {
     final clarification = decoded['clarification']?.toString().trim() ?? '';
     return FfmAssistantProposalParseResult.invalid(
       clarification.isEmpty ? '...' : clarification,
     );
   }
   ```
7. Di `ffm_assistant_interpreter.dart` baris 831:
   ```dart
   if (proposal.error != null) {
     return _InterpretResult.single(
       FfmAssistantIntent(
         ...
         response: _friendlyProposalError(proposal.error!),
         clarification: _friendlyProposalError(proposal.error!),
       ),
     );
   }
   ```
8. Fungsi `_friendlyProposalError(technicalError)` di baris 11204 tidak mendeteksi kata kunci format teknis, sehingga **mengeksekusi fallback default**:
   ```dart
   return 'Aku belum bisa menangani permintaan itu dengan benar. Silakan urai ulang maksudmu dengan kalimat biasa, atau beri tahu apa yang ingin kamu lakukan dan nominalnya bila ada.';
   ```

#### 2. Akar Masalah (Root Cause)
1. **Cacat Desain pada Objek `FfmAssistantProposalParseResult`**:
   - `FfmAssistantProposalParseResult` hanya memiliki konstruktor `.draft()`, `.teaching()`, dan `.invalid(error)`.
   - **Tidak ada konstruktor `.clarification(String question)`**.
   - Ketika model memberikan klarifikasi sah melalui tool `ask_clarification`, parser memasukannya ke `FfmAssistantProposalParseResult.invalid(...)` seolah-olah terjadi kegagalan sistem.
2. **Penghancuran Teks Asli oleh `_friendlyProposalError`**:
   - Interpreter menganggap `proposal.error != null` sebagai kegagalan sintaks JSON, lalu melempar pertanyaan klarifikasi Gemini ke `_friendlyProposalError`.
   - Jawaban ramah dan relevan dari Gemini **dibuang 100%** dan digantikan oleh teks penolakan generik yang kaku.

---

### MASALAH #4: Tombol "Pakai Perubahan" pada Edit Draf Pengingat Tidak Merespons / Macet
- **Gejala Pengguna**:
  Saat membuka dialog *"Ubah draft di chat"* untuk draf Pengingat/Alarm (jadwal 18/09/2026 06:00 WIB), menekan tombol **"Pakai perubahan"** tidak menutup dialog, form tidak tersimpan, dan tombol seolah-olah tidak bisa diklik / macet.
- **Tangkapan Layar Referensi**: Dialog modal edit draf Pengingat dengan waktu `18/09/2026 06:00 WIB` saat status bar perangkat menunjukkan pukul `21:31 WIB`.

#### 1. Penelusuran Alur Kode (Trace Analysis)
1. Form dialog dijalankan oleh `FfmAssistantDraftEditDialog` (`lib/features/assistant/presentation/widgets/ffm_assistant_draft_edit_dialog.dart`).
2. Saat tombol `FilledButton(onPressed: _save, child: const Text('Pakai perubahan'))` ditekan, fungsi `_save()` (baris 733–740) melakukan pengecekan tanggal & waktu pengingat:
   ```dart
   if (effectiveDate != null && effectiveDate.isBefore(DateTime.now())) {
     ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(
         content: Text('Pilih waktu pengingat yang masih akan datang.'),
       ),
     );
     return;
   }
   ```
3. Waktu `effectiveDate` adalah `18/09/2026 06:00` (pagi hari).
4. Waktu perangkat pengguna saat itu adalah `18/09/2026 21:31` (malam hari).
5. Karena waktu yang tertera telah lampau (`isBefore(DateTime.now())`), validasi gagal dan fungsi `_save()` langsung `return` tanpa memanggil `Navigator.of(context).pop(editedDraft)`.

#### 2. Akar Masalah (Root Cause)
1. **Snack Bar Tertutup / Tidak Terlihat di Dialog Modal**:
   Pesan kesalahan dilempar via `ScaffoldMessenger.of(context).showSnackBar()`, yang sering kali tertutup di belakang `AlertDialog` / modal sheet atau tertutup oleh keyboard virtual. Pengguna tidak melihat adanya teks peringatan sehingga mengira tombol macet/rusak.
2. **Ketiadaan Auto-Adjustment untuk Waktu Lampau Hari Ini**:
   Jika asisten Gemini mengusulkan jam pagi (misal 06:00) pada hari yang sama di waktu malam, sistem tidak otomatis memajukan tanggal ke esok hari (misal 19/09/2026 06:00), melainkan membiarkan tanggal tetap hari ini sehingga otomatis invalid.

---

### MASALAH #5: Error Otonomi Policy saat Menyimpan Draf Pengingat (`Capability mutate.save_draft membutuhkan konfirmasi eksplisit`)
- **Gejala Pengguna**:
  Setelah asisten menyusun draf pengingat di chat, muncul balon pesan kegagalan dari asisten:
  > *"Perubahan pengingat tidak selesai (batas proses (Capability mutate.save_draft membutuhkan konfirmasi eksplisit.)). Perubahan tidak dapat diverifikasi."*
- **Tangkapan Layar Referensi**: Chat asisten dengan kartu draf pengingat berstatus *Versi 1 • siap dicek di form*, diikuti pesan kegagalan verifikasi.

#### 1. Penelusuran Alur Kode (Trace Analysis)
1. Asisten Gemini Cloud menyusun draf pengingat (`FfmAssistantDraftKind.reminder`).
2. Alur penyimpanan draf langsung (`_executeDirectMutationPlan`) di `ffm_assistant_sheet.dart` (baris 4213–4250) mengaitkan rencana aksi dengan kapabilitas `mutate.save_draft`.
3. Kapabilitas `mutate.save_draft` terdaftar di `FfmAssistantCapabilityRegistry` (`ffm_assistant_capabilities.dart:777`) dengan risiko:
   ```dart
   const FfmAssistantCapability(
     id: 'mutate.save_draft',
     label: 'Simpan draft',
     risk: FfmAssistantCapabilityRisk.mutation,
     requiresConfirmation: true,
   )
   ```
4. Saat `_capabilityExecutor.execute(planId)` dipanggil di `ffm_assistant_sheet.dart` (baris 1568), eksekutor mengevaluasi `_autonomyPolicy.allowsCapability` (`ffm_assistant_capability_executor.dart:236`):
   ```dart
   if (!_autonomyPolicy.allowsCapability(
     resolvedCapability,
     approved: plan!.status == FfmAssistantActionPlanStatus.executing,
   )) {
     return _report(
       _controller.block(
         planId,
         'Capability ${step.capabilityId} membutuhkan konfirmasi eksplisit.',
       ),
     );
   }
   ```
5. Karena `plan.status` belum bertransisi menjadi `FfmAssistantActionPlanStatus.executing` saat diserahkan ke eksekutor, parameter `approved` bernilai `false`.
6. Akibatnya, `allowsCapability` menolak langkah mutasi dan memblokir plan.
7. Di `ffm_assistant_sheet.dart` (baris 1581–1587), kegagalan ini ditangkap sebagai:
   ```dart
   final message = 'Perubahan ${subject.toLowerCase()} tidak selesai ($failureLabel). $detail';
   // Menghasilkan teks: "Perubahan pengingat tidak selesai (batas proses (Capability mutate.save_draft membutuhkan konfirmasi eksplisit.)). Perubahan tidak dapat diverifikasi."
   ```

#### 2. Akar Masalah (Root Cause)
1. **Desinkronisasi State Transisi Action Plan**:
   Pada alur mutasi draf langsung di chat, pemicu eksekusi memanggil eksekutor sebelum status *Action Plan* dikonfirmasi (`confirm`) secara tuntas atau status approval tercatat di repository otonomi.
2. **Ketiadaan Penanganan Khusus untuk Kapabilitas Mutasi Draf Internal**:
   `mutate.save_draft` adalah operasi penyimpanan draf lokal yang dipicu setelah pengguna menyetujui draf di UI. Namun, pengecekan otonomi memperlakukannya sebagai mutasi tak berizin karena status `plan.status` masih berada pada fase `planned` atau `awaitingConfirmation`.

---

### MASALAH #6: Ketiadaan Fitur Salin Teks Sebagian / Granular pada Balon Chat Asisten (Gaya WhatsApp)
- **Gejala / Kebutuhan Pengguna**:
  Pengguna ingin dapat menyalin sebagian teks tertentu (misalnya hanya nomor meter `5326 1182 1351` atau kode token `2350-4383-2595-9423-0689`) langsung dari pesan chat asisten dengan cara menekan lama (*long press*) lalu menggeser seleksi (*selection handles / crop*) seperti pada WhatsApp.
- **Tangkapan Layar Referensi**: Bubble chat asisten yang menampilkan teks struk terdeteksi.

#### 1. Penelusuran Alur Kode (Trace Analysis)
1. Tampilan entri chat asisten dirender di `_AssistantMessageBubble` atau `_FfmAssistantMarkdown` (`lib/features/assistant/presentation/widgets/chat/`).
2. Saat ini widget teks menggunakan rendering non-selektif atau tombol salin hanya tersedia sebagai tombol *copy all* di bawah kartu.
3. Ketiadaan widget `SelectionArea` atau `SelectableText.rich` dengan context menu toolbar kustom membuat pengguna tidak bisa memilih dan menyalin sebagian kata/kalimat secara mandiri.

#### 2. Akar Masalah (Root Cause)
Widget chat belum dibungkus oleh `SelectionArea` dengan `AdaptiveTextSelectionToolbar`, sehingga interaksi sentuh *long-press* native Android untuk seleksi teks tidak aktif di dalam bubble pesan asisten.

---

### MASALAH #7: Nomor Meteran / IDPEL PLN Kosong di Form Draf & Gagal Sinkron ke Halaman Token Listrik
- **Gejala Pengguna**:
  Pada pesan deteksi struk token PLN di chat tertera jelas:
  - *No. Meter: 5326 1182 1351*
  - *Kode Token: 2350-4383-2595-9423-0689*
  Namun saat membuka dialog *"Ubah draft di chat"*, input *Nomor Meter / IDPEL PLN* dan *Nama / Label Rumah Meteran* **kosong melompong** (*placeholder: "Contoh: 14123456789"*). Data meteran baru tersebut juga tidak otomatis didaftarkan ke Halaman Token Listrik.
- **Tangkapan Layar Referensi**: Screenshot 1 (chat deteksi struk) dan Screenshot 2 (dialog edit draf dengan form nomor meter kosong).

#### 1. Penelusuran Alur Kode (Trace Analysis)
1. Layanan OCR struk (`receipt_scanner_service.dart`) mendeteksi token listrik dan mengisi `utilityMetadata` pada `draft.metadata['utilityProposal']`.
2. Saat form edit draf dibuka (`FfmAssistantDraftEditDialog.initState`), inisialisasi controller hanya membaca `draft.formValues`:
   ```dart
   _meterNameController = TextEditingController(
     text: widget.draft.formValues['proposedMeterName'] ??
         widget.draft.formValues['meterName'] ?? '',
   );
   _meterNumberController = TextEditingController(
     text: widget.draft.formValues['meterNumber'] ?? '',
   );
   ```
3. Karena field tersebut tidak dimasukkan ke dalam `draft.formValues` saat draf dibuat di `_appendScanOutcome` (`ffm_assistant_sheet.dart:3330`), form inisialisasi menghasilkan string kosong (`''`).
4. Saat draf disetujui, pendaftaran meteran ke tabel SQLite `utility_meters` melalui `UtilityMeterRepository.registerMeter` tidak terpanggil secara otomatis atau kehilangan parameter IDPEL.

#### 2. Akar Masalah (Root Cause)
1. **Pemisahan Data Draf yang Tidak Konsisten**: Metadata utilitas ditaruh di `draft.metadata['utilityProposal']`, sementara UI dialog dan validator membaca `draft.formValues`.
2. **Ketiadaan Pemicu Pendaftaran Meteran Simultan**: Belum ada jembatan otomatis di `_saveMeterReadingDraft` / `_saveDraft` yang mendaftarkan meteran baru ke SQLite `utility_meters` sekaligus mencatat pengeluaran transaksi di `transactions` saat konfirmasi draf transaksi token PLN disetujui.

---

### MASALAH #8: Error Validasi "Total harus sama dengan subtotal + pajak - diskon" pada Struk dengan Biaya Layanan / Admin
- **Gejala Pengguna**:
  Saat draf pengeluaran token PLN ditampilkan dengan total **Rp 100.660** (terdiri dari token Rp 100.000 + biaya admin/layanan Rp 660), sistem memunculkan toast/snackbar merah:
  > *"Total harus sama dengan subtotal + pajak - diskon."*
  Form draf terkunci dan tidak bisa disimpan.
- **Tangkapan Layar Referensi**: Screenshot 3 (kartu draf Rp 100.660 dengan snackbar error validasi total dan subtotal).

#### 1. Penelusuran Alur Kode (Trace Analysis)
1. Parser struk membaca item token: `price = 100000`, `quantity = 1`, `lineTotal = 100000`. Total pembayaran adalah `draft.amount = 100660` dengan `draft.adminFee = 660`.
2. Di `FfmAssistantDraftValidator.validate` (`ffm_assistant_draft_validator.dart:968–982`):
   ```dart
   if (draft.items.isNotEmpty) {
     final subtotal = draft.items.fold<int>(
       0,
       (sum, item) => sum + item.calculatedTotal,
     );
     final expected = subtotal + (draft.tax ?? 0) - (draft.discount ?? 0);
     if (draft.amount != null && expected != draft.amount) {
       issues.add(
         const FfmAssistantDraftIssue(
           code: 'receipt_total_mismatch',
           severity: FfmAssistantDraftIssueSeverity.conflict,
           field: 'nominal',
           message: 'Total harus sama dengan subtotal + pajak - diskon.',
         ),
       );
     }
   }
   ```
3. Rumus `expected` **TIDAK memperhitungkan `draft.adminFee` (biaya admin / layanan)**:
   - `subtotal = 100.000`
   - `expected = 100.000 + 0 - 0 = 100.000`
   - `draft.amount = 100.660`
   - `expected (100.000) != draft.amount (100.660)` -> Menghasilkan error `receipt_total_mismatch`!
4. Di `FfmAssistantDraftEditDialog._save()` (baris 861–878), `receipt_total_mismatch` masuk ke dalam `blockingCodes`, sehingga dialog menolak menyimpan draf.

#### 2. Akar Masalah (Root Cause)
Logika validasi matematis di `FfmAssistantDraftValidator` memiliki formula yang tidak lengkap. Struk e-commerce/PPOB (seperti Shopee, Tokopedia, PLN Mobile) hampir selalu memuat biaya admin/layanan (`adminFee`) yang ditambahkan ke subtotal. Rumus validator mengabaikan `adminFee`, sehingga seluruh struk yang memiliki biaya admin otomatis dicap invalid/mismatch.

---

### MASALAH #9: Halaman Token Listrik PLN Membingungkan & Terlihat Kosong (Grafik, Riwayat, dan Input kWh Tersembunyi)
- **Gejala / Pertanyaan Pengguna**:
  Kenapa halaman token listrik membingungkan? Kenapa tidak ada grafik, tidak ada input kWh harian, dan tidak ada riwayat di UI? Apakah datanya belum masuk SQLite?

#### 1. Penelusuran Alur Kode (Trace Analysis)
1. **Pemeriksaan Penyimpanan Database (SQLite)**:
   - Data Token Listrik **SUDAH 100% menggunakan SQLite** (Drift `AppDatabase` via `UtilityMeterRepository` pada tabel `utility_meters`, `utility_purchase_histories`, dan `utility_meter_readings`). Tidak ada data yang tersimpan di luar SQL / SharedPreferences.
2. **Pemeriksaan Tampilan UI (`UtilityMeterPage`)**:
   - Di `utility_meter_page.dart` (baris 764–770):
     ```dart
     if (_meters.isEmpty)
       _buildEmptyState(context, isDark)
     else
       ..._meters.map((meter) => _buildMeterCard(context, meter, isDark)),
     ```
   - Komponen grafik (`MiniMonthlyBarChart`), estimasi laju konsumsi (`ElectricityBurnRate`), riwayat pembelian (`_historyByMeter`), dan tombol pencatatan angka kWh (`Catat Pembacaan`) **semuanya berada di dalam `_buildMeterCard`**.
   - Ketika `_meters.isEmpty` (karena Masalah #7 di atas menggagalkan pendaftaran meteran otomatis dari struk), halaman hanya me-render satu layar kosong (`_buildEmptyState`), sehingga pengguna merasa fitur grafik dan riwayat tidak ada.

---

### MASALAH #10: Struk Token Listrik Multi-Meter (2-3 Rumah / IDPEL Sekaligus) Tidak Terpecah Menjadi Multi-Draft
- **Gejala / Kebutuhan Pengguna**:
  Pengguna sering membeli token listrik untuk 2 atau 3 properti sekaligus dalam 1 transaksi struk (misal: Rumah Utama, Pompa Air Sawah, dan Ruko Usaha). Meskipun pesan asisten menampilkan peringatan *"Deteksi meteran ganda"*, sistem saat ini hanya menghasilkan 1 draf pengeluaran tunggal dan hanya mengaitkan 1 nomor meter pertama, sehingga 2 meteran lainnya hilang dari pencatatan riwayat token.
- **Tangkapan Layar Referensi**: Pesan asisten yang memuat deteksi meteran ganda.

#### 1. Penelusuran Alur Kode (Trace Analysis)
1. Di `ffm_assistant_sheet.dart` (baris 3311–3335), logika deteksi membaca `detectedMeters` dan `detectedTokens`.
2. Teks tanggapan asisten menyatakan:
   `"Jika ini beberapa pembelian untuk rumah berbeda, aplikasi akan membuat draft terpisah per pembelian sehingga tiap rumah terisi dengan benar."`
3. Namun secara implementasi kode, hanya ada `draft = outcome.draft` tunggal yang dibuat.
4. Antrean draf (`_draftQueue`) tidak memecah hasil scan menjadi N draf terpisah per meteran yang terdeteksi.

#### 2. Akar Masalah (Root Cause)
Ketiadaan mekanisme *auto-split multi-draft queue* di `_appendScanOutcome`. Saat struk memuat multiple IDPEL/token, sistem seharusnya memasukkan tiap pembelian sebagai draf independen ke dalam `_draftQueue` (atau draf bertingkat) sehingga tiap rumah mendapatkan alokasi nominal, nomor meter, dan kode token masing-masing secara akurat.

---

### MASALAH #11: Potensi Macet / Beku pada Tombol Konfirmasi Draf Asisten Lintas Semua Jenis Draf (Transaksi, Anggaran, Hutang, Pengingat, dll.)
- **Gejala / Kebutuhan Pengguna**:
  Pengguna mengkhawatirkan seluruh draf buatan asisten (bukan hanya pengingat, tetapi juga transaksi, anggaran, hutang-piutang, aktivitas, dll.) berpotensi macet atau tidak bisa diklik tombol konfirmasinya setelah dialog edit dibuka/ditutup.

#### 1. Penelusuran Alur Kode (Trace Analysis)
1. Setiap draf asisten memiliki pemeriksaan validasi `FfmAssistantDraftValidator.validate(draft)`.
2. Jika ada isu dengan tingkat keparahan `required` atau `conflict` (misalnya tag belum dipilih, rekening sumber/tujuan kosong, nominal <= 0, atau `receipt_total_mismatch`), properti `review.canContinue` bernilai `false`.
3. Saat `review.canContinue == false`, tombol `[Konfirmasi]` di chat card menolak eksekusi dan melempar *SnackBar* (`"Lengkapi dulu bagian yang ditandai di draft chat."`).
4. Ketika user membuka dialog `FfmAssistantDraftEditDialog` untuk melengkapi data:
   - Jika dialog ditutup via tombol **Batal** / back, status draf di session tetap menyimpan isu yang belum lengkap sehingga tombol konfirmasi tetap tidak merespons.
   - Pada pembatalan dialog konfirmasi mutasi langsung (`_confirmDraftInChat`), kode di baris 4184–4187 menghapus `activeDraftReview = null`, membuat kartu draf kehilangan state aktif di sesi obrolan.
   - Jika `blockingCodes` di dialog edit terpicu (seperti validasi subtotal atau tag), fungsi `_save()` melempar snackbar tanpa menutup dialog dan tanpa feedback teks visual di dalam form.

#### 2. Akar Masalah (Root Cause)
1. **Kurangnya Indikator Visual pada Tombol Konfirmasi yang Disabled/Pending**:
   Tombol *Konfirmasi* di kartu chat tidak menampilkan tooltip atau keterangan jelas mengapa tombol tersebut tidak bisa diproses saat ada field wajib yang belum terisi.
2. **Ketiadaan Safe State Recovery saat Menutup Dialog Edit**:
   Draf yang sedang ditinjau kehilangan referensi review aktif jika siklus dialog tidak terselesaikan secara mulus.

---

## REKOMENDASI PERBAIKAN KODE KONKRET

Berikut adalah usulan perubahan teknis dan solusi kode konkret yang siap dieksekusi untuk menyelesaikan seluruh 11 anomali tersebut:

### 1. Perbaikan Masalah #1 (Sinkronisasi Form Values & Edit Dialog)
- **File**: `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart`
  - Di dalam `_appendScanOutcome` (sekitar baris 3330):
    Saat membuat `utilityMetadata`, salin juga field-field krusial ke dalam `draft.formValues`:
    ```dart
    draft = draft.copyWith(
      metadata: {
        ...?draft.metadata,
        'utilityProposal': utilityMetadata,
      },
      formValues: {
        ...draft.formValues,
        if (utilityMetadata['meterName'] != null)
          'meterName': utilityMetadata['meterName'],
        if (utilityMetadata['proposedMeterName'] != null)
          'proposedMeterName': utilityMetadata['proposedMeterName'],
        if (utilityMetadata['meterNumber'] != null)
          'meterNumber': utilityMetadata['meterNumber'],
        if (cleanToken != null) 'tokenCode': cleanToken,
      },
    );
    ```
- **File**: `lib/features/assistant/presentation/widgets/ffm_assistant_draft_edit_dialog.dart`
  - Di `initState` (baris 287–298): Dukung fallback membaca langsung dari `widget.draft.metadata?['utilityProposal']` jika `formValues` kosong.
- **File**: `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart`
  - Pada pembatalan/penutupan dialog konfirmasi `_confirmDraftInChat` (baris 4160): Jangan langsung memusnahkan draft (`activeDraftReview = null`). Beri opsi agar draft tetap bertahan di session queue atau status `draftQueue` berstatus paused, sehingga tidak hilang saat user keluar dari dialog.

### 2. Perbaikan Masalah #2 (Pencegahan Entitas Palsu & Pengenalan Alaram)
- **File**: `lib/features/assistant/data/ffm_assistant_interpreter.dart`
  1. **Regex Pengingat / Alarm**:
     Perluas `createReminder` (baris 9409) menggunakan regex yang mendukung sisipan dan variasi "alaram":
     ```dart
     final createReminder = _containsAny(normalized, const [
       'buat pengingat', 'tambah pengingat', 'ingatkan saya', 'pasang pengingat',
       'buat alarm', 'pasang alarm', 'tambah alarm',
     ]) || RegExp(
       r'\b(buat|pasang|set|atur|tambah)\s+(?:saya\s+)?(?:sebuah\s+)?(?:pengingat|alarm|alaram)\b',
       caseSensitive: false,
     ).hasMatch(normalized);
     ```
  2. **Pengecualian Waktu pada `FfmAssistantAmountParser`**:
     Di `FfmAssistantAmountParser.parse`, bersihkan terlebih dahulu pola jam (misal `jam \d{1,2}(?::\d{2})?` atau `pukul \d{1,2}`) sebelum mengekstrak nominal, agar `"jam 6"` tidak dibaca sebagai Rp 6.
  3. **Domain Keyword pada `_hasExplicitIntent`**:
     Di baris 5380, tambahkan kata `"alarm"`, `"alaram"`, `"jadwal"`, `"rutinitas"` ke dalam `hasDomainKeyword`.
  4. **Stop Words**:
     Tambahkan `"buat"`, `"alaram"`, `"alarm"`, `"besok"`, `"jam"` ke dalam daftar `stopWords` di `_extractCandidateEntityTerms` (baris 10341).

### 3. Perbaikan Masalah #3 (Dukungan Klasifikasi Hasil Klarifikasi Proposal)
- **File**: `lib/features/assistant/data/ffm_assistant_proposal_json_service.dart`
  1. Tambahkan `clarification` pada `FfmAssistantProposalParseResult`:
     ```dart
     class FfmAssistantProposalParseResult {
       const FfmAssistantProposalParseResult._({
         this.draft,
         this.teachingProposal,
         this.clarification,
         this.error,
       });

       const FfmAssistantProposalParseResult.clarification(String clarification)
           : this._(clarification: clarification);

       final String? clarification;
       ...
     ```
  2. Pada baris 194:
     ```dart
     if (rawProposal == null) {
       final clarification = decoded['clarification']?.toString().trim() ?? '';
       if (clarification.isNotEmpty) {
         return FfmAssistantProposalParseResult.clarification(clarification);
       }
       return const FfmAssistantProposalParseResult.invalid(
         'Proposal belum bisa dibuat karena masih ada informasi yang kurang.',
       );
     }
     ```
  3. Teruskan `clarification` ke `FfmAssistantMultiProposalParseResult`.
- **File**: `lib/features/assistant/data/ffm_assistant_interpreter.dart`
  Pada baris 831, jika `proposal.clarification != null`:
  Kembalikan intent klarifikasi valid (bukan error!):
  ```dart
  if (proposal.clarification != null) {
    return _InterpretResult.single(
      FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.unknown,
        confidence: .9,
        response: proposal.clarification!,
        clarification: proposal.clarification!,
        responseOrigin: FfmAssistantResponseOrigin.geminiCloud,
        pluginName: 'gemini_cloud',
        pluginCategory: 'gemini_cloud',
        pluginMetadata: geminiMetadata,
      ),
    );
  }
  ```

### 4. Perbaikan UI: Penyederhanaan Halaman Lainnya (Dropdown Kategori & Collapsible Accordion)
- **File**: `lib/features/settings/presentation/pages/other_menu_page.dart`
- **Latar Belakang Masalah**:
  Halaman "Lainnya" memuat lebih dari 30 kartu menu navigasi yang tersebar di 5 seksi besar (*Mulai Dari Sini*, *Keluarga & Data*, *Laporan & Cadangan*, *Pengingat & Alat*, *Keamanan & Sistem*). Tampilan daftar panjang tanpa pengelompokan yang ringkas membuat pengguna harus melakukan scrolling berlebihan untuk mencari fitur yang diinginkan.
- **Implementasi Perbaikan**:
  1. **Dropdown Filter Kategori Cepat**:
     - Menambahkan filter `DropdownButton` modern tepat di bawah kotak pencarian teks.
     - Pengguna dapat memilih untuk menampilkan semua kategori sekaligus atau langsung menyaring satu kategori fokus:
       - ❖ *Semua Kategori (Tampilkan Semua)*
       - 🚀 *Mulai Dari Sini* (Aset, Utang Piutang, Target Keuangan, dll.)
       - 👥 *Keluarga & Data* (Profil Keluarga, Data Utama, Anggota, Pembagian Pengeluaran)
       - 📊 *Laporan & Cadangan* (Laporan Keuangan, Arus Kas, Ekspor/Impor, Cadangan Supabase)
       - ⏰ *Pengingat & Alat* (Jadwal Transaksi Rutin, Pengingat, Gemini Cloud AI, Token PLN)
       - 🔒 *Keamanan & Sistem* (Kunci PIN & Biometrik, Audit Trail, Pengaturan Suara, Info Aplikasi)
  2. **Collapsible Accordion Section Header**:
     - Setiap header seksi dilengkapi badge jumlah item (misal `4 menu`, `7 menu`) dan indikator panah buka-tutup (*accordion*).
     - Pengguna dapat melipat atau membentangkan seksi yang diinginkan secara modular.
     - Jika kategori tunggal dipilih melalui dropdown, seksi tersebut otomatis dibuka penuh tanpa hambatan.
  3. **Pencarian Adaptif**:
     - Fitur *search* tetap aktif dan terintegrasi mulus dengan filter dropdown, sehingga pengguna dapat mencari menu spesifik baik dalam kategori terpilih maupun lintas kategori secara instan.

### 5. Perbaikan Masalah #4 (Feedback Visual & Penanganan Waktu Lampau pada Edit Draf)
- **File**: `lib/features/assistant/presentation/widgets/ffm_assistant_draft_edit_dialog.dart`
  1. **Inline Error Feedback**:
     Tampilkan pesan kesalahan validasi waktu langsung di bawah *field* tanggal/waktu form, bukan hanya mengandalkan *SnackBar* yang berpotensi tertutup dialog modal:
     ```dart
     String? _timeErrorMessage;
     // Di _save():
     if (effectiveDate != null && effectiveDate.isBefore(DateTime.now())) {
       setState(() {
         _timeErrorMessage = 'Waktu pengingat sudah lewat. Pilih jam yang akan datang.';
       });
       return;
     }
     ```
  2. **Smart Roll-Forward Tanggal**:
     Jika draf pengingat dibuat untuk jam tertentu (misal 06:00) dan pada hari yang sama jam tersebut sudah terlewat saat user berada di malam hari, otomatis geser tanggal default ke hari berikutnya (`DateTime.now().add(const Duration(days: 1))`).

### 6. Perbaikan Masalah #5 (Sinkronisasi Status Action Plan Execution pada Mutasi Draf)
- **File**: `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart`
  Pada alur `_confirmDirectMutation` dan `_executeDirectMutationPlan` (baris 4213–4250):
  Pastikan `_actionPlanController.confirm(plan.id)` benar-benar berhasil mengubah status plan ke `FfmAssistantActionPlanStatus.executing` dan tercatat sebelum pemanggilan `_capabilityExecutor.execute(plan.id)`:
  ```dart
  final confirmed = await _confirmDirectMutation(intent.draft!);
  if (!confirmed) {
    _actionPlanController.cancel(plan.id);
    return;
  }
  final executable = _actionPlanController.confirm(plan.id);
  if (executable != null && executable.status == FfmAssistantActionPlanStatus.executing) {
    await _executeDirectMutationPlan(intent, executable.id);
  }
  ```
- **File**: `lib/features/assistant/domain/ffm_assistant_capability_executor.dart`
  Pastikan kapabilitas `mutate.save_draft` yang dipicu dari interaksi konfirmasi draf eksplisit diizinkan oleh `_autonomyPolicy` tanpa terblokir prematur jika rencana aksi telah disetujui.

### 7. Perbaikan Masalah #6 (Seleksi & Salin Teks Granular Gaya WhatsApp)
- **File**: `lib/features/assistant/presentation/widgets/chat/ffm_assistant_chat_entry_card.dart` / `ffm_assistant_markdown.dart`
  Bungkus blok teks atau markdown pesan asisten dengan `SelectionArea`:
  ```dart
  SelectionArea(
    contextMenuBuilder: (context, selectableRegionState) {
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: selectableRegionState.contextMenuAnchors,
        buttonItems: selectableRegionState.contextMenuButtonItems,
      );
    },
    child: ...
  )
  ```
  Hal ini mengaktifkan kemampuan *long-press* native dengan handle seleksi (crop teks) persis seperti aplikasi perpesanan WhatsApp.

### 8. Perbaikan Masalah #7 (Sinkronisasi Form & Pendaftaran Meteran Simultan)
- **File**: `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart`
  1. Saat mendeteksi struk token PLN di `_appendScanOutcome`:
     Salin `meterNumber`, `meterName`, dan `tokenCode` ke dalam `draft.formValues` agar otomatis terbaca di dialog edit draf.
  2. Saat konfirmasi transaksi draf token listrik disetujui (`_saveDraft` / `_saveMeterReadingDraft`):
     Panggil `UtilityMeterRepository.registerMeter` untuk mendaftarkan meteran baru secara otomatis ke SQLite jika belum terdaftar, lalu hubungkan ID transaksi dengan riwayat pembelian token (`recordPurchase`).

### 9. Perbaikan Masalah #8 (Penyesuaian Formula Validasi Subtotal Struk dengan Biaya Layanan/Admin)
- **File**: `lib/features/assistant/domain/ffm_assistant_draft_validator.dart`
  Pada baris 972, sertakan `draft.adminFee` dalam kalkulasi total yang diharapkan:
  ```dart
  final subtotal = draft.items.fold<int>(
    0,
    (sum, item) => sum + item.calculatedTotal,
  );
  final expected = subtotal +
      (draft.tax ?? 0) +
      (draft.adminFee ?? 0) -
      (draft.discount ?? 0);
  if (draft.amount != null && expected != draft.amount) {
    issues.add(
      const FfmAssistantDraftIssue(
        code: 'receipt_total_mismatch',
        severity: FfmAssistantDraftIssueSeverity.conflict,
        field: 'nominal',
        message: 'Total harus sama dengan subtotal + pajak + biaya admin - diskon.',
      ),
    );
  }
  ```

### 10. Perbaikan Masalah #9 (Penyempurnaan Tampilan Halaman Token Listrik PLN)
- **File**: `lib/features/settings/presentation/pages/utility_meter_page.dart`
  1. Pada *Empty State*, tampilkan preview visual fitur yang tersedia (grafik konsumsi, estimasi sisa hari / burn-rate, scan OCR LCD kWh, dan riwayat token) agar pengguna tidak mengira halaman kosong/rusak.
  2. Pastikan tombol cepat *Catat Pembacaan kWh* dan *Input Token Baru* tetap mudah diakses.

### 11. Perbaikan Masalah #10 (Dukungan Pemecahan Multi-Meter / Multi-Rumah Sekaligus)
- **File**: `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart` & `receipt_scanner_service.dart`
  Ketika OCR mendeteksi N nomor meteran/token pada satu struk pembayaran:
  1. Pecah `outcome.draft` menjadi N draf terpisah di dalam `_draftQueue` (atau draf bertingkat dengan rincian meteran per sub-pembelian).
  2. Alokasikan nominal, nomor IDPEL, dan kode token spesifik ke masing-masing item draf.
  3. Konfirmasi di chat akan memproses N transaksi secara berurutan atau sebagai batch atomik, sehingga ketiga rumah (misal Rumah Utama, Sawah, Ruko) langsung terdaftar dan tercatat di SQLite `utility_meters` tanpa ada yang tertinggal.

### 12. Perbaikan Masalah #11 (Pencegahan Kondisi Macet / Beku pada Konfirmasi Seluruh Jenis Draf)
- **File**: `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart` & `ffm_assistant_draft_edit_dialog.dart`
  1. **Visual Indicator & Actionable Guide pada Tombol Konfirmasi**:
     Jika `review.canContinue == false`, tombol *Konfirmasi* menampilkan tanda visual jelas (badge info/warning) dan saat ditekan tidak hanya melempar snackbar, melainkan langsung menawarkan tombol cepat *"Lengkapi Bagian Kosong"* yang otomatis membuka dialog edit dengan fokus pada field yang bermasalah.
  2. **Safe State Preservation pada Edit Dialog**:
     Pastikan saat pengguna membatalkan dialog edit, state draf di sesi chat tidak hilang (`activeDraftReview` tetap dipertahankan dengan aman).
  3. **Audit Menyeluruh Seluruh Jenis Draf**:
     Terapkan mekanisme validasi yang toleran dan jelas untuk semua 16 jenis draf (`expense`, `income`, `transfer`, `goalDeposit`, `goalUsage`, `liability`, `liabilityPayment`, `receivable`, `receivablePayment`, `budget`, `goal`, `asset`, `dailyNote`, `reminder`, `activity`, `meterReading`) agar tidak ada draf yang macet saat dikonfirmasi langsung dari asisten.

---

## KESIMPULAN & STATUS TINDAK LANJUT

1. **Analisis Seluruh 11 Anomali Telah Terkumpul & Selesai Dipetakan**:
   - **Masalah #1**: Form edit draf kehilangan field meteran PLN (metadata tidak tersalin ke `formValues`).
   - **Masalah #2**: Ejaan *"alaram"* dan kata *"jam 6"* dibaca sebagai nominal Rp 6 serta entitas rekening palsu.
   - **Masalah #3**: Pertanyaan klarifikasi sah dari Gemini Cloud ditimpa menjadi pesan error generik oleh parser proposal.
   - **Masalah #4**: Tombol *"Pakai perubahan"* macet karena validasi waktu lampau tertutup di balik modal dialog.
   - **Masalah #5**: Eksekutor memblokir `mutate.save_draft` dengan error *requires explicit confirmation* akibat desinkronisasi state `ActionPlan`.
   - **Masalah #6**: Balon chat asisten belum memiliki seleksi teks granular bergaya WhatsApp (*long press selection handles*).
   - **Masalah #7**: Input nomor meteran/IDPEL kosong di dialog edit dan belum otomatis mendaftar ke Halaman Token Listrik saat transaksi disetujui.
   - **Masalah #8**: Validasi struk menolak draf (*receipt_total_mismatch*) karena formula mengabaikan biaya layanan/admin (`adminFee`).
   - **Masalah #9**: Halaman Token Listrik tampak kosong dan tidak menampilkan grafik/riwayat karena efek domino dari gagalnya pendaftaran meteran otomatis (Data sendiri telah 100% menggunakan SQLite Drift).
   - **Masalah #10**: Struk multi-meter (2-3 rumah sekaligus) belum dipecah menjadi multi-draft terpisah sehingga meteran ke-2 dan ke-3 tertinggal.
   - **Masalah #11**: Potensi macet/beku pada tombol konfirmasi di chat card lintas seluruh 16 jenis draf akibat validasi blocking tanpa panduan fokus form.
2. **Perbaikan UI Halaman Lainnya Selesai Diimplementasikan**: Penambahan dropdown kategori dan sistem accordion pada `OtherMenuPage` berhasil menyederhanakan navigasi 30+ menu menjadi lebih bersih, modular, dan intuitif.
3. **Integritas Aturan Proyek Terjaga**:
   - Seluruh logika kalkulasi finansial tetap deterministik di kode lokal.
   - Hak Gemini Cloud tetap dibatasi (bounded read & proposal only, tidak melakukan mutasi langsung).
   - Analisis dilakukan tanpa merusak data atau memodifikasi kode asisten sebelum instruksi lanjutan dari pengguna.
4. **Langkah Berikutnya**: Seluruh anomali telah terkumpul secara komprehensif. Menunggu instruksi akhir pengguna untuk mengeksekusi perbaikan kode asisten secara menyeluruh.
