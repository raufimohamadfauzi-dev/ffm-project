# Daftar Anomali dan Rencana Perbaikan Sistem FFM

Dokumen ini berisi hasil audit komprehensif anomali pada arsitektur, data, AI/Orkestrator, dan antarmuka aplikasi FFM (Family Finance Manager).
Setiap nomor dilengkapi checklist box `[ ]` agar dapat dieksekusi secara berurutan mulai dari nomor 1.

---

## 📋 Ringkasan Eksekutif & Jawaban Permintaan Pengguna

1. **Status Halaman Profil Personalisasi Asisten**:
   - `AssistantProfilePage` telah berhasil dihapus sepenuhnya dan dipusatkan ke `FamilyProfilePage` (`lib/features/settings/presentation/pages/family_profile_page.dart`) melalui widget `FfmAssistantProfileTools`. Routing di `main.dart` dan `other_menu_page.dart` telah dibersihkan.
2. **Status Rute Scan NFC (Apakah mengarah ke Data Utama jika kartu belum terdaftar?)**:
   - **TIDAK**. Saat ini, jika kartu belum terdaftar, `NfcCardRepository.processCardScan` secara otomatis langsung melakukan registrasi akun baru diam-diam (`_persistDatabaseScan`) ke tabel `accounts` dan `nfcCardAccounts` dengan label default. `NfcScanDialog` hanya menampilkan baseline saldo tanpa memberikan opsi navigasi atau pengalihan rute ke Data Utama (`MasterDataPage`).
3. **Penyebab Utama Fitur Gambar Belum Bisa Percakapan Luas**:
   - Input gambar di lembar asisten (`ffm_assistant_sheet.dart`) dicegat secara kaku dan dialihkan 100% ke `ReceiptScannerService` dengan prompt JSON struk belanja. Jika pengguna mengunggah gambar non-struk atau mengajukan pertanyaan santai/analisis luas tentang gambar, parser gagal (`ReceiptImportException`). `FfmGeminiCloudOrchestrator` sendiri sama sekali tidak memiliki parameter multimodal gambar.
4. **Penyebab Masalah Drift Database vs Kolom Aplikasi (Drift/Edit Mismatch)**:
   - OCR struk berhasil mengekstrak rincian item (`items`: nama, qty, harga satuan, total), diskon, pajak, nomor struk, dan kembalian.
   - Tabel Drift sebenarnya memiliki tabel `TransactionItems` dan kolom `Transactions` (`receiptPaidAmount`, `receiptChangeAmount`, `receiptNumber`).
   - Namun, `FfmAssistantDraft` membuang data item dan menggabungkannya ke teks judul flat (`title: entry.merchant ?? itemsText`). Dialog edit draft (`FfmAssistantDraftEditDialog`) tidak memiliki kolom/tabel editor item rincian, dan `FfmAssistantActionPlanner` mengabaikan parameter item sehingga rincian belanja hilang permanen saat disimpan.

---

## 🗂️ Checklist Anomali & Rencana Perbaikan Berurutan

### Pilar 1: Fitur Gambar, Multimodal AI, & Sinkronisasi Drift/Edit Struk (Paling Kritis / P0)

- [x] **1. Dukungan Multimodal Percakapan Luas pada Lembar Asisten (`ffm_assistant_sheet.dart`)**
  - **Lokasi Kode**: `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart` & `lib/features/assistant/data/receipt_scanner_service.dart`.
  - **Status Selesai**: Berhasil diimplementasikan via `askVisualQuestion` dan deteksi `_isBroadVisualQuestion` pada `ffm_assistant_sheet.dart`. Pertanyaan luas pengguna diproses secara multimodal tanpa dipaksa menjadi JSON transaksi struk, dan jika scan struk gagal saat pengguna memberi caption pertanyaan, sistem otomatis fallback ke mode percakapan visual cerdas.

- [x] **2. Integrasi Multimodal pada Orkestrator Gemini Cloud (`FfmGeminiCloudOrchestrator`)**
  - **Lokasi Kode**: `lib/features/assistant/data/ffm_gemini_cloud_orchestrator.dart`.
  - **Status Selesai**: Parameter opsional `GeminiImageInput? image` telah ditambahkan ke `run()` dan diteruskan ke `_chat()` -> `_gemini.chat()` sehingga orkestrator cloud siap menerima lampiran visual.

- [x] **3. Preservasi Konteks Gambar pada Percakapan Lanjutan (Multi-Turn Chat Context)**
  - **Lokasi Kode**: `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart`.
  - **Status Selesai**: Konteks visual (`[Lampiran Gambar/Struk: ... ]`) dan rincian item struk disimpan dan disematkan ke dalam riwayat percakapan (`_buildRecentConversationHistory()`), menjaga referensi visual pada multi-turn chat.

- [x] **4. Penyempurnaan Model `FfmAssistantDraft` untuk Rincian Item Belanja (`items`)**
  - **Lokasi Kode**: `lib/features/assistant/domain/ffm_assistant_models.dart`, `receipt_import_models.dart`, `receipt_import_service.dart`.
  - **Status Selesai**: `FfmAssistantDraft` diperkaya dengan `items` (`List<ReceiptOcrItem>`), `tax`, `discount`, `receiptPaidAmount`, `receiptChangeAmount`, dan `receiptNumber` lengkap dengan `copyWith()`. Parser batch struk juga memetakan field-field tersebut secara utuh.

- [x] **5. Penambahan Editor Rincian Item pada Dialog Edit Draft (`FfmAssistantDraftEditDialog`)**
  - **Lokasi Kode**: `lib/features/assistant/presentation/widgets/ffm_assistant_draft_edit_dialog.dart`.
  - **Status Selesai**: Dialog edit draft kini dilengkapi daftar interaktif item struk (tambah item, ubah nama/harga/qty, hapus item, auto-kalkulasi total nominal) serta input nomor struk, pajak (PPN), diskon, nominal bayar, dan kembalian.

- [x] **6. Penyaluran Rincian Item Struk melalui `FfmAssistantActionPlanner` ke Capability Executor**
  - **Lokasi Kode**: `lib/features/assistant/domain/ffm_assistant_action_planner.dart`.
  - **Status Selesai**: `_draftParameters()` menyerialisasikan `itemsJson`, `receiptNumber`, `receiptPaidAmount`, `receiptChangeAmount`, `tax`, dan `discount` sehingga `FfmAssistantCapabilityAdapters` langsung mengeksekusi penyimpanan ke tabel `TransactionItems` dan kolom detail struk di Drift SQLite.

---

### Pilar 2: Rute Fitur Scan NFC & Master Data

- [x] **7. Pengalihan Rute Scan NFC Kartu Baru ke Data Utama (`MasterDataPage`)**
  - **Lokasi Kode**: `lib/features/assistant/presentation/widgets/nfc_scan_dialog.dart` & `lib/features/assistant/data/nfc_card_repository.dart`.
  - **Status Selesai**: Pada modal `NfcScanDialog`, saat kartu baru terdeteksi (`result.isBaseline == true`), pengguna diberikan kartu aksi interaktif:
    1. *"Buka / Daftarkan di Data Utama"* (navigasi langsung ke `MasterDataPage` tab Rekening dengan saldo awal & tipe e-wallet otomatis terisi).
    2. *"Tautkan Rekening"* (menghubungkan kartu fisik ke rekening yang sudah ada dan membersihkan dummy account).
    3. *"Ubah Nama"* (mengubah alias kartu secara langsung).

- [x] **8. Sinkronisasi Dua Arah Alias Kartu NFC dan Master Data Akun**
  - **Lokasi Kode**: `lib/features/settings/data/account_repository.dart` & `lib/features/assistant/data/nfc_card_repository.dart`.
  - **Status Selesai**: Penambahan sinkronisasi dua arah: saat nama rekening diedit di Data Utama lewat `AccountRepository.updateFromUser` atau `updateName`, kolom `issuer` di `nfcCardAccounts` otomatis ikut terupdate. Begitu pula sebaliknya, `updateCardAlias` di `NfcCardRepository` mengupdate tabel `accounts` dan `nfcCardAccounts` secara atomik dalam transaksi database.

---

### Pilar 3: Anomali di Tiap Input & Validasi Form Aplikasi

- [x] **9. Normalisasi Input Angka Desimal & Mata Uang Asing / Emas**
  - **Lokasi Kode**: `lib/features/assistant/data/ffm_assistant_interpreter.dart` & `lib/shared/widgets/app_components.dart`.
  - **Status Selesai**: Ditambahkan dukungan cerdas untuk desimal titik dan koma pada `FfmAssistantAmountParser` (misal "2.5 juta", "2,5 jt", "75.5 rb") yang sebelumnya terpotong menjadi 25 juta (kesalahan 10x lipat), serta helper `parseDecimal` pada `app_components.dart` untuk input gram emas dan valas.

- [x] **10. Harmonisasi Kolom Pihak Tunggal (`partyName`) pada Form Input Transaksi & Hutang/Piutang**
  - **Lokasi Kode**: `lib/features/assistant/presentation/widgets/ffm_assistant_draft_edit_dialog.dart` & `lib/features/transaction/data/services/voice_transaction_parser.dart`.
  - **Status Selesai**: Kolom pihak distandardisasi menggunakan `partyName` di seluruh model draf, dialog edit draf asisten (`partyName = (_isTransaction || _isDebtOrReceivable) ? _textOrNull(_partyController) : widget.draft.partyName`), dan voice transaction parser, menjamin integritas data saat tipe draf berubah.

- [x] **11. Validasi Batas Nilai Wajar pada Input Suara (*Voice Input*)**
  - **Lokasi Kode**: `lib/features/transaction/presentation/widgets/voice_review_widgets.dart` & `lib/features/transaction/data/services/voice_transaction_parser.dart`.
  - **Status Selesai**: `VoiceTransactionParser` mendeteksi anomali nilai tidak wajar (`isUnusuallyHighAmount: amount >= 100000000 || lower.contains('triliun')`), menampilkan banner peringatan oranye visual pada kartu draf, dan memunculkan dialog konfirmasi pencegah salah tangkap audio sebelum batch disimpan ke database.

---

### Pilar 4: Anomali Transaksi & Sinkronisasi Pembukuan

- [x] **12. Pencegahan Tabrakan ID Transaksi Cepat (*Rapid Same-Microsecond Collision*)**
  - **Lokasi Kode**: `lib/core/database/audit_logger.dart`, `lib/features/reminder/presentation/pages/reminder_page.dart`, `lib/features/assistant/data/nfc_card_repository.dart`, & `lib/features/transaction/presentation/pages/transaction_pages.dart`.
  - **Status Selesai**: Sesuai Aturan 21 AGENTS.md, seluruh ID yang sebelumnya mengandalkan bare `DateTime.now().microsecondsSinceEpoch` telah dimigrasikan menggunakan UUID v4 (`const Uuid().v4()`) atau kombinasi `microsecondsSinceEpoch + counter / uuidSuffix` sehingga dijamin tidak pernah bertabrakan meskipun ada batch insert cepat dalam mikrodetik yang sama.

- [x] **13. Real-Time Refresh Plafon Anggaran Amplop Setelah Pembatalan / Hapus Transaksi**
  - **Lokasi Kode**: `lib/features/transaction/domain/usecases/transaction_crud_usecases.dart` & `lib/features/assistant/data/ffm_assistant_capability_adapters.dart`.
  - **Status Selesai**: Pembaruan `DeleteTransaction` dan `ArchiveTransaction` kini selalu menyertakan stempel waktu `updatedAt: Value(DateTime.now())` ke tabel Drift SQLite, memicu pembaruan reactive database stream dan perhitungan sisa dana anggaran amplop secara real-time.

---

### Pilar 5: Anomali Aktivitas & Otonom Sesi Harian

- [x] **14. Deteksi Irregularitas Sesi Timer Aktivitas (*Zombie Timer Protection*)**
  - **Lokasi Kode**: `lib/features/activity/presentation/pages/activity_page.dart` & `test/activity_smart_features_test.dart`.
  - **Status Selesai**: Ditambahkan deteksi zombie timer (`DateTime.now().difference(session.startedAt).inHours >= 8`) pada `_ActiveSessionCard` yang secara visual menampilkan banner peringatan oranye tegas dengan durasi jam berjalan, border kartu amber, tombol aksi cepat *"Hentikan Sekarang"*, dan tombol *"Koreksi Waktu"* agar statistik produktivitas harian tidak rusak karena lupa mematikan timer.

- [x] **15. Rekomendasi Pintar Rutinitas Pagi/Malam pada Empty State Halaman Aktivitas**
  - **Lokasi Kode**: `lib/features/activity/presentation/pages/activity_page.dart` & `test/activity_smart_features_test.dart`.
  - **Status Selesai**: Mengganti `AppEmptyState` statis dengan `_SmartRoutineEmptyState` yang menyesuaikan waktu secara dinamis (Pagi: Olahraga, Kebun/Tani, Belajar, Sarapan; Siang/Sore: Fokus Kerja, Belanja, Perawatan Lahan, Istirahat; Malam: Evaluasi Pengeluaran, Waktu Keluarga, Refleksi, Rencana Esok) dengan tombol chip aksi 1-ketukan untuk langsung memulai pencatatan.

---

### Pilar 6: Anomali Aset, Berita Pasar Finansial, & Valas

- [x] **16. Migrasi Warta Berita Kurasi Statis ke Integrasi RSS Real-Time**
  - **Lokasi Kode**: `lib/features/asset/data/services/market_news_radar_service.dart` & `test/market_news_radar_service_test.dart`.
  - **Status Selesai**: Menambahkan fungsi parser XML RSS 2.0 (`parseRssFeed`) dengan pembersihan entitas HTML dan kategorisasi cerdas (bencana/cuaca, pertanian, finansial, umum) yang terhubung ke feed RSS publik (Antara News / BMKG) dengan degradasi anggun (*graceful fallback*) ke warta lokal terpilih saat offline tanpa crash.

- [x] **17. Penanganan Potensi Division-by-Zero pada Konversi Kurs Valas**
  - **Lokasi Kode**: `lib/features/asset/data/services/market_news_radar_service.dart` & `test/market_news_radar_service_test.dart`.
  - **Status Selesai**: Seluruh kalkulasi pembagian kurs valas (SGD, EUR, SAR) telah diproteksi dengan guard condition `rate > 0`. Jika nilai API bernilai 0, negatif, atau null, sistem otomatis mempertahankan kurs fallback tanpa memicu nilai `Infinity` atau kalkulasi tak terhingga.

- [x] **18. Integrasi Revaluasi Aset Otomatis ke Loop Otonom Background**
  - **Lokasi Kode**: `lib/features/asset/domain/usecases/asset_auto_valuation_service.dart`, `lib/features/assistant/data/autonomous_activity_repository.dart`, & `lib/features/assistant/domain/entities/autonomous_activity_models.dart`.
  - **Status Selesai**: Mendaftarkan `AutonomousActivityType.assetRevaluation` pada model aktivitas otonom dan menambahkan use case `revalueAndRecordAutonomously` yang mencatat ringkasan selisih nilai kekayaan bersih keluarga dan daftar aset yang terupdate ke `AutonomousActivityRepository` untuk ditampilkan di `AgentInboxPage`.

---

### Pilar 7: Anomali Hutang Piutang Beserta Fitur Otonomnya

- [x] **19. Pembuatan Tipe Aktivitas Otonom untuk Hutang & Piutang (`AutonomousActivityType.debtPayoff`)**
  - **Lokasi Kode**: `lib/features/assistant/domain/entities/autonomous_activity_models.dart`, `lib/features/assistant/data/autonomous_activity_repository.dart`, `lib/features/assistant/presentation/widgets/autonomous_activity_dialogs.dart`, & `lib/features/assistant/presentation/pages/agent_inbox_page.dart`.
  - **Status Selesai**: Menambahkan tipe aktivitas otonom `debtPayoff` dan `receivableReminder` ke `AutonomousActivityType`, mengintegrasikan pemulihan transaksi (`revertActivity`) dan penyesuaian koreksi (`correctActivity`), serta mendaftarkan ikon visual dan badge status di dialog koreksi dan `AgentInboxPage`.

- [x] **20. Rekomendasi Percepatan Pelunasan Hutang (Snowball vs Avalanche) ke Kotak Masuk Asisten**
  - **Lokasi Kode**: `lib/features/assistant/domain/detectors/debt_payoff_acceleration_detector.dart`, `lib/features/assistant/domain/autonomous_evaluation_coordinator.dart`, `lib/features/assistant/presentation/pages/agent_inbox_page.dart`, & `test/features/assistant/domain/debt_payoff_acceleration_detector_test.dart`.
  - **Status Selesai**: Dibuat detektor otonom `DebtPayoffAccelerationDetector` yang dieksekusi secara periodik oleh `AutonomousEvaluationCoordinator`. Saat terdapat sisa/surplus anggaran belanja, sistem menghitung perbandingan matematis percepatan pelunasan via Snowball vs Avalanche (bunga hemat dan bulan hemat) serta mengirimkan insight proaktif ke `AgentInboxPage` dengan tombol aksi langsung menuju pelunasan.

- [x] **21. Pengingat Otonom Jatuh Tempo Hutang/Piutang pada Audio Morning Briefing**
  - **Lokasi Kode**: `lib/features/assistant/domain/services/executive_morning_briefing_service.dart` & `test/features/assistant/domain/executive_morning_briefing_service_test.dart`.
  - **Status Selesai**: Menambahkan pemindaian otomatis terhadap seluruh hutang aktif yang memiliki tanggal jatuh tempo dalam rentang 3 hari ke depan (`current` s.d. `current + 3 hari`). Daftar tagihan tersebut dimasukkan ke dalam kartu visual ringkasan pagi serta dibacakan secara natural dalam naskah audio speech Text-To-Speech morning briefing.

---

## 🎯 Urutan Pengerjaan yang Direkomendasikan

Pengerjaan dapat diselesaikan secara berurutan mulai dari **Nomor 1**:
1. **Fase 1 (Nomor 1–6)**: Penyelesaian Fitur Gambar Multimodal & Sinkronisasi Drift/Edit Struk (Memastikan item belanja tidak hilang dan chat gambar bisa percakapan luas).
2. **Fase 2 (Nomor 7–8)**: Penyempurnaan Alur Scan NFC & Navigasi ke Data Utama.
3. **Fase 3 (Nomor 9–13)**: Pembenahan Input, Validasi Desimal, dan Sinkronisasi Transaksi.
4. **Fase 4 (Nomor 14–15)**: Penanganan Timer Aktivitas & Rekomendasi Rutinitas.
5. **Fase 5 (Nomor 16–18)**: Integrasi Revaluasi Aset & RSS Berita Real-Time.
6. **Fase 6 (Nomor 19–21)**: Integrasi Otonom Hutang Piutang & Pengingat Morning Briefing.
