# Plan Perbaikan & Fitur Listrik (Token PLN / Meteran)

> **Dibuat**: 2026-09-17
> **Status**: Fase 1-3, 5 selesai. Fase 4 belum dikerjakan.
> **Estimasi total**: ~2 jam (Fase 1–4)
> **Instruksi**: Centang checkbox `[ ]` → `[x]` hanya setelah kode di-commit + `flutter analyze lib test` + `flutter test` pass. Setiap perbaikan harus diuji atau minimal diverifikasi lewat analyzer + test yang relevan.

---

## Quick Start untuk Agent

### Project overview
- **FFM** = Family Finance Manager, Flutter Android app (ARM64 only)
- **Stack**: Flutter + Drift (SQLite) + Supabase backend + Gemini AI
- **Bahasa kode**: Dart. Bahasa UI/UX: Indonesia.

### Cara menjalankan & test
```bash
# Install dependencies
flutter pub get

# Analyze (wajib sebelum commit)
flutter analyze lib test

# Run specific test files
flutter test test/electricity_meter_resolution_test.dart
flutter test test/electricity_sqlite_integration_test.dart
flutter test test/receipt_scanner_service_test.dart

# Run FULL test suite (~1500+ tests, ~5 menit)
flutter test

# Build release APK (ARM64 only)
flutter build apk --target-platform android-arm64 --release
```

### Struktur file yang relevan untuk plan ini
```
lib/
├── core/
│   ├── database/
│   │   ├── tables.dart              ← Drift table definitions
│   │   ├── app_database.dart        ← DB class, migrations, indexes (schema version 66)
│   │   └── app_database.g.dart      ← Generated code (jangan edit manual)
│   └── di/injection.dart            ← Service locator (getIt)
├── features/
│   ├── assistant/
│   │   ├── data/
│   │   │   ├── ffm_assistant_interpreter.dart       ← Intent parsing, draft building (~11000 baris)
│   │   │   ├── receipt_scanner_service.dart         ← OCR scanner, PLN extraction (~350 baris)
│   │   │   ├── ffm_assistant_capability_adapters.dart ← Capability handler registry
│   │   │   └── ffm_gemini_read_capability_service.dart
│   │   ├── domain/
│   │   │   └── ffm_assistant_capabilities.dart     ← Capability definitions
│   │   └── presentation/widgets/
│   │       ├── ffm_assistant_sheet.dart             ← Chat UI, scan handling (~4000 baris)
│   │       └── chat/ffm_assistant_draft_preview.dart
│   ├── settings/
│   │   ├── data/
│   │   │   └── utility_meter_repository.dart        ← Meter CRUD, anomaly detection (~750 baris)
│   │   ├── domain/entities/
│   │   │   └── utility_meter_models.dart            ← UtilityMeter entity
│   │   └── presentation/pages/
│   │       └── utility_meter_page.dart              ← Meter list UI, meter cards (~900 baris)
│   └── advisor/presentation/pages/
│       └── summary_page.dart                        ← Bar chart pattern reference
test/
├── electricity_meter_resolution_test.dart    ← 12 tests (resolver, anomali, interpreter)
├── electricity_sqlite_integration_test.dart  ← 2 tests (1:1 transaksi, rollback)
├── receipt_scanner_service_test.dart         ← 20+ tests (OCR, batch, multi-token)
└── ... (1500+ tests total)
```

### Pola kode yang perlu diketahui
1. **Repository pattern**: `UtilityMeterRepository` wrap Drift DAO. Method async, return `Future<T>`.
2. **Draft flow**: User text → `_resolveElectricityPurchase` → `resolveMeterTarget` → proposal → draft → validation → confirmation → executor.
3. **Anomaly check**: `scanPurchaseAnomalies` return `List<String>` (warnings). Bukan exception.
4. **Test pattern**: Pakai `flutter_test`, in-memory database (`AppDatabase(NativeDatabase.memory())`), mock Gemini via `_FakeHttpClient`.
5. **Naming**: File snake_case, class PascalCase, method camelCase. Test description pakai Bahasa Indonesia.
6. **Import**: Relative imports (`../../core/...`) untuk file dalam package yang sama.

### Catatan penting
- **Jangan edit** `app_database.g.dart` — generated code, akan di-overwrite.
- **Schema version** harus di-bump setiap kali ada table/index change (saat ini: 65).
- **Unique index** di `app_database.dart` dikontrol via raw SQL, bukan Drift annotations.
- **Tabel `ElectricityMeterReadings`** sudah ada tapi dormant — jangan hapus, nanti dipakai di Fase 3.
- **`flutter analyze` harus clean** sebelum commit. Zero tolerance untuk warnings di file yang diubah.

---

## Fase 1 — Perbaikan anomali Kritis (Data Integrity)

> **Prioritas**: TERTINGGI. Harus selesai sebelum Fase 2–4.
> **Alasan**: Bug ini menyebabkan data salah, crash, atau anomali yang tidak terdeteksi. Tanpa fondasi ini, fitur baru akan menumpuk di atas data yang tidak konsisten.

### 1.1 Samakan regex parsing nomor meter: interpreter vs repository

- [x] **File**: `lib/features/assistant/data/ffm_assistant_interpreter.dart` + `lib/features/settings/domain/entities/utility_meter_models.dart`
- **Masalah**: Regex di `_utilityProposalFromText` (line 9369) hanya menerima `\b(\d{11,12})\b`, tapi `resolveMeterTarget` di repository menerima 9–13 digit. User sebut "meteran 1401234567890" (13 digit) → tidak ter-parse → asisten tidak bisa resolve target. Juga: doc comment di `UtilityMeter.meterNumber` (utility_meter_models.dart:31) tertulis "11–12 digit" yang juga konsisten dengan regex lama, tapi TIDAK konsisten dengan repository (9-13 digit).
- **Perbaikan**:
  1. Ganti regex di interpreter dari `r'\b(\d{11,12})\b'` → `r'\b(\d{9,13})\b'`
  2. Update doc comment di `utility_meter_models.dart:31` dari "11–12 digit" → "9–13 digit"
- **Verifikasi**: `flutter analyze lib test` clean + test `electricity_meter_resolution_test.dart` existing tetap pass + tambah test case: "beli token listrik 50rb meteran 1401234567890" (13 digit) → ter-parse.

### 1.2 Fix unique index `normalized_meter_number` vs `isArchived`

- [x] **File**: `lib/core/database/app_database.dart` (index di lines 743-744, migration di line 127)
- **Masalah**: Index unik `idx_electricity_meters_number` pada `(household_id, normalized_meter_number)` berlaku untuk SEMUA baris (termasuk archived). Jika user arsipkan meter "Rumah A" (nomor X) lalu buat meter baru dengan nomor yang sama → crash constraint violation (unhandled). Index ini dibuat di `_createElectricityIndexes()` (line 743-744), BUKAN di `tables.dart`.
- **Perbaikan**: Tambah migration baru `if (from < 66)` di `onUpgrade` (setelah block `from < 65` di line 127):
  1. `schemaVersion` di line 78 harus diupdate dari `65` → `66`.
  2. Di migration `from < 66`:
     ```dart
     await customStatement('DROP INDEX IF EXISTS idx_electricity_meters_number');
     await customStatement(
       'CREATE UNIQUE INDEX IF NOT EXISTS idx_electricity_meters_number '
       'ON electricity_meters (household_id, normalized_meter_number) '
       'WHERE is_archived = 0',
     );
     ```
     Ini adalah unique **partial** index — hanya berlaku untuk baris aktif (bukan archived). SQLite mendukung partial unique index.
  3. Panggil `_createElectricityIndexes()` di akhir migration `from < 66` untuk memastikan semua index tercipta (karena `IF NOT EXISTS`, index lain tidak duplikat).
- **Catatan**: Pattern `DROP INDEX` belum ada di codebase ini, tapi ini satu-satunya cara SQLite mengubah index. Test di `electricity_sqlite_integration_test.dart` belum ada coverage untuk unique index ini — **tambah test**:
  - Test 1: Simpan meter, arsipkan (`isArchived = true`), buat meter baru nomor sama → berhasil.
  - Test 2: Simpan dua meter nomor sama tanpa arsipkan → error constraint.
- **Verifikasi**: `flutter analyze lib test` clean. `flutter test test/electricity_sqlite_integration_test.dart` pass + test baru pass.

### 1.3 Perluas cek duplikat token ke seluruh history

- [x] **File**: `lib/features/settings/data/utility_meter_repository.dart`
- **Masalah**: `scanPurchaseAnomalies` (line ~331) hanya scan 100 record terakhir via `getPurchaseHistory(householdId, limit: 100)`. Token duplikat yang lebih tua terlewat.
- **Perbaikan**: Query langsung ke `utilityTokenPurchases` dengan `SELECT 1 FROM utility_token_purchases WHERE household_id = ? AND token_code = ? LIMIT 1` (tanpa limit 100). Jika ada → flag duplikat. Pertimbangkan: tambahkan timestamp pembelian lama di pesan anomali ("Token ini pernah dipakai pada [tanggal]").
- **Verifikasi**: `flutter analyze lib test` clean. Test: beli token X, buat 150 transaksi lain, beli token X lagi → anomali terdeteksi.

### 1.4 Fix cek same-day duplikat: query langsung ke tabel pembelian

- [x] **File**: `lib/features/settings/data/utility_meter_repository.dart`
- **Masalah**: Cek same-day duplikat (line ~344–361) hanya membandingkan `meter.lastAmount` dan `meter.lastPurchasedAt`. Jika user beli nominal sama dua kali sehari → yang kedua tidak terdeteksi (karena `lastAmount` sudah diupdate ke yang kedua).
- **Perbaikan**: Query langsung: `SELECT COUNT(*) FROM utility_token_purchases WHERE household_id = ? AND meter_id = ? AND amount = ? AND date(purchased_at) = date(?) AND transaction_id != ?`. Jika count > 0 → flag "Kemungkinan duplikat: ada pembelian Rp [amount] yang sama pada hari ini".
- **Verifikasi**: `flutter analyze lib test` clean. Test: beli token 50rb untuk meter A jam 10:00, beli lagi 50rb untuk meter A jam 14:00 → anomali terdeteksi di yang kedua.

### 1.5 Persempit range anomali tarif Rp/kWh

- [x] **File**: `lib/features/settings/data/utility_meter_repository.dart`
- **Masalah**: Range `250-4000` Rp/kWh terlalu lebar. Tarif PLN normal:
  - Subsidi lifeline R1/450VA: ~Rp415/kWh
  - Subsidi R1/900VA: ~Rp605/kWh
  - Non-subsidi R1/1300VA: ~Rp1.046/kWh
  - Non-subsidi R1/2200VA: ~Rp1.352/kWh
  - Komersial B1: ~Rp1.500-1.700/kWh
  - Industri: ~Rp1.500-1.800/kWh
  - Upper reasonable: ~Rp2.000/kWh
- **Perbaikan**: Ganti `rate < 250 || rate > 4000` → `rate < 300 || rate > 2000`. Alasan:
  - Lower bound 300: di bawah ini hampir pasti anomali (bahkan subsidi 450VA ~Rp415)
  - Upper bound 2000: di atas ini melebihi tarif komersial tertinggi
  - **JANGAN pakai 800** sebagai lower bound — akan false warning untuk pelanggan bersubsidi (450VA/900VA)
  - Jika `creditedKwh == null`, skip rate check (sudah benar di kode saat ini)
- **Verifikasi**: `flutter analyze lib test` clean. Test: tarif 415 (450VA) → normal, tarif 605 (900VA) → normal, tarif 1400 → normal, tarif 200 → anomali, tarif 2500 → anomali, tarif null kWh → skip.

---

## Fase 2 — Point 6: Penanganan Struk Kualitas Rendah

> **Prioritas**: TINGGI. Langsung setelah Fase 1.
> **Alasan**: User scan struk buram → token/kWh hilang → draft tanpa data PLN → user bingung. Fitur ini membuat asisten lebih cerdas saat OCR gagal parsial.

### 2.1 Retry mechanism untuk field yang hilang

- [x] **File**: `lib/features/assistant/data/receipt_scanner_service.dart`
- **Masalah**: Scanner single-pass. Jika Gemini return JSON valid tapi `token_code` atau `kwh` null → data hilang permanen, tidak ada retry.
- **Perbaikan**: Di dalam `scanImage()`, setelah parse batch berhasil, cek setiap entry PLN (type expense + merchant PLN + budgetName Listrik). Jika `token_code` atau `kwh` null pada entry:
  1. Kirim follow-up Gemini call dengan prompt: `"Pada gambar struk ini, temukan nomor token 20 digit dan jumlah kWh. Jika tidak ada, tulis null. Format JSON: {token_code: ..., kwh: ...}"`
  2. Parse response, merge ke entry yang sudah ada (jika Gemini menghasilkan null juga → tetap null, tidak crash).
  3. Batasi max 1 retry per scan (hemat token).
- **Output field baru** pada `ReceiptBatchImport`: `bool hadOcrRetry` untuk tracking.
- **Verifikasi**: `flutter analyze lib test` clean. Test: mock Gemini return 2x — pertama token null, kedua token ada → merge berhasil.

### 2.2 Ekstrak kWh dari chat input

- [x] **File**: `lib/features/assistant/data/ffm_assistant_interpreter.dart`
- **Masalah**: `_utilityProposalFromText` (line ~9353–9389) tidak mengekstrak kWh dari chat. "beli token 200rb kwh 50" → amount tertangkap, kWh hilang.
- **Perbaikan**: Di `_utilityProposalFromText`, tambahkan regex: `r'(?:kwh|kW\s*H)\s*[:=]?\s*(\d+(?:[.,]\d+)?)'` → extract ke `creditedKwh`. Jika ada koma → convert ke titik (desimal).
- **Verifikasi**: `flutter analyze lib test` clean. Test: "beli token listrik 200rb kwh 50" → `creditedKwh = 50.0`.

### 2.3 Warning saat token/kWh tidak terbaca

- [x] **File**: `lib/features/assistant/data/ffm_assistant_interpreter.dart`
- **Masalah**: Response draft selalu bilang "Pembelian token listrik untuk [target] dipersiapkan" meskipun token tidak terbaca. User tidak tahu ada data yang kurang.
- **Perbaikan**: Di `_resolveElectricityPurchase`, setelah build proposal, cek:
  - Jika `tokenCode == null` → tambahkan warning ke response: "⚠️ Kode token tidak terbaca dari struk. Pastikan sudah benar di preview sebelum konfirmasi."
  - Jika `creditedKwh == null` → tambahkan: "ℹ️ Jumlah kWh tidak terdeteksi. Kamu bisa mengisinya manual di preview."
  - Jika `meterNumber == null && meterId == null` → ini sudah ditangani oleh `resolveMeterTarget` (clarification).
- **Verifikasi**: `flutter analyze lib test` clean. Test: teks "beli token listrik 50rb" tanpa token → response mengandung warning.

### 2.4 Tombol "Foto Ulang" saat scan gagal

- [x] **File**: `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart`
- **Masalah**: Saat `outcome.ok == false` (line ~2568–2593), hanya tampilkan pesan error. User harus manual mulai ulang scan.
- **Perbaikan**: Setelah pesan error scan, tambahkan button "📷 Foto Ulang" yang memanggil `_handleImageUpload()` lagi (buka kamera/galeri). Pattern: ikuti pola tombol existing di sheet (mis. `TextButton` atau `ActionButton` yang sudah ada).
- **Verifikasi**: `flutter analyze lib test` clean. Visual check: error scan → ada tombol foto ulang.

### 2.5 Perbaiki routing "cek struk ini"

- [x] **File**: `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart`
- **Masalah**: `_isBroadVisualQuestion` (line ~2489–2502) menangkap "cek struk ini" → route ke visual Q&A, padahal harusnya ke receipt scan.
- **Perbaikan**: Di `_isBroadVisualQuestion`, tambahkan exclusion: jika teks mengandung "struk" DAN ada lampiran gambar → `return false` (biar masuk receipt scan path). Atau lebih spesifik: exclude pola `cek.*struk|lihat.*struk|cek.*bon`.
- **Verifikasi**: `flutter analyze lib test` clean. Test: "cek struk ini" + gambar → masuk receipt scan, bukan visual Q&A.

### 2.6 Perlebar regex kWh — terima tanpa suffix unit

- [x] **File**: `lib/features/assistant/data/receipt_scanner_service.dart`
- **Masalah**: `extractPlnKwh` (line ~109–116) membutuhkan suffix `kWh` atau `kwh`. Jika OCR menghapus unit → value hilang.
- **Perbaikan**: Tambah fallback regex: setelah regex utama gagal, coba `r'(\d+(?:[.,]\d+)?)\s*(?:kwh|kW\s*H)?'` dengan context check — hanya match jika ada keyword "pemakaian" atau "jumlah" di sekitarnya (untuk hindari false positive angka lain).
- **Verifikasi**: `flutter analyze lib test` clean. Test: "Jumlah KWH: 63,70" → 63.7, "Pemakaian 63.70" → 63.7, "Rp 63.700" → null (bukan kWh).

### 2.7 Tambahkan `read.electricity` ke capability adapter handlers

- [x] **File**: `lib/features/assistant/data/ffm_assistant_capability_adapters.dart`
- **Masalah**: `read.electricity` ada di Gemini allowlist (`ffm_assistant_capabilities.dart:64`) tapi tidak ada handler di adapter registry (line ~141–265). Agent mode tidak bisa execute capability ini.
- **Perbaikan**: Tambah handler di `handlers` map:
  ```dart
  'read.electricity': (params) async {
    final meterRef = params['meter'] as String?;
    final dateFrom = params['dateFrom'] as String?;
    final dateTo = params['dateTo'] as String?;
    // Query UtilityMeterRepository → summarizeUsage + getPurchaseHistory
    // Return structured result
  },
  ```
- **Verifikasi**: `flutter analyze lib test` clean. Test: panggil handler dengan params → return data.

---

## Fase 3 — Grafik Penggunaan Listrik per IDPEL

> **Prioritas**: SEDANG. Setelah Fase 1–2.
> **Alasan**: User ingin visualisasi tren belanja listrik per rumah. Data sudah ada di repository, tinggal聚agregasi + visualisasi.

### 3.1 Repository: tambah method time-based aggregation

- [x] **File**: `lib/features/settings/data/utility_meter_repository.dart` + `lib/features/settings/domain/entities/utility_meter_models.dart`
- **Class baru `PeriodUsage`**: Tambahkan di `utility_meter_models.dart` setelah class `UtilityMeter` (setelah line 143). File ini sudah berisi domain entities untuk meteran, jadi tempat yang tepat.
  ```dart
  class PeriodUsage {
    final String label;       // "Sep 2026", "Minggu 3 Sep"
    final DateTime dateFrom;
    final DateTime dateTo;
    final int totalCost;      // Total Rp
    final double totalKwh;    // Total kWh
    final int purchaseCount;  // Jumlah pembelian
    const PeriodUsage({required this.label, required this.dateFrom, required this.dateTo, required this.totalCost, required this.totalKwh, required this.purchaseCount});
  }
  ```
- **Metode baru di repository**: `Future<List<PeriodUsage>> summarizeUsageByPeriod(String householdId, {required String meterId, String period = 'monthly', int limit = 6})`
- **Query SQL**: `SELECT strftime('%Y-%m', purchased_at) AS period, SUM(amount) AS total_cost, COALESCE(SUM(credited_kwh), 0) AS total_kwh, COUNT(*) AS count FROM utility_token_purchases WHERE household_id = ? AND meter_id = ? AND purchased_at >= ? GROUP BY period ORDER BY period DESC LIMIT ?`
- **Label**: Format `"MMM YYYY"` (Indonesia) untuk monthly, `"minggu N MMM"` untuk weekly.
- **Test**: Tambah di `electricity_sqlite_integration_test.dart`: 3 pembelian di 2 bulan berbeda → return 2 `PeriodUsage` dengan total benar.
- **Verifikasi**: `flutter analyze lib test` clean. `flutter test test/electricity_sqlite_integration_test.dart` pass.

### 3.2 UI: mini bar chart di meter card

- [x] **File**: `lib/features/settings/presentation/pages/utility_meter_page.dart`
- **Masalah**: Meter card hanya tampilkan total all-time. Tidak ada tren visual.
- **Perbaikan**: Di `_buildMeterCard`, setelah summary section (line ~776–810), tambahkan **MiniMonthlyBarChart** widget:
  - Pattern: ikuti pola `_MonthlyExpenseBarChart` di `summary_page.dart` (line ~937) — bar chart pakai `Row` + `Expanded` + `AnimatedContainer`, tanpa library chart.
  - Data: panggil `summarizeUsageByPeriod` dengan `period: 'monthly', limit: 6`.
  - Layout: 6 bar horizontal (Rp), warna biru untuk bulan ini, abu-abu untuk bulan lalu. Label bulan di bawah.
  - Jika data kosong atau 1 pembelian saja → sembunyikan chart (tidak perlu).
- **Widget baru**: `MiniMonthlyBarChart` di file yang sama (private widget) atau di `shared/widgets/` jika mau reusable.
- **Verifikasi**: `flutter analyze lib test` clean. Visual check: meter card dengan ≥2 bulan data → tampil chart.

### 3.3 Repository: muat data chart di `_loadMeters`

- [x] **File**: `lib/features/settings/presentation/pages/utility_meter_page.dart`
- **Perubahan**: Di `_loadMeters()`, setelah `summarizeUsage`, tambahkan:
  ```dart
  final periodData = <String, List<PeriodUsage>>{};
  for (final meter in list) {
    periodData[meter.id] = await _repository.summarizeUsageByPeriod(
      householdId, meterId: meter.id, period: 'monthly', limit: 6,
    );
  }
  ```
- Simpan ke `_periodDataByMeter` (field baru `Map<String, List<PeriodUsage>>`).
- Pass ke `_buildMeterCard` → `MiniMonthlyBarChart`.
- **Verifikasi**: `flutter analyze lib test` clean.

---

## Fase 5 — Input Pembacaan Meter Aktual (Level 2)

> **Prioritas**: SEDANG-TINGGI. Setelah Fase 3.
> **Alasan**: Estimasi dari pola beli (Level 1) sudah jalan. Level 2 menambah akurasi dengan data aktual dari display meter fisik. Tanpa ini, grafik hanya menampilkan estimasi.
> **Penting**: Saat banyak meter terdaftar, asisten WAJIB mengklarifikasi meter mana yang dimaksud sebelum membuat draft. Jangan tebak. Ini berlaku untuk both token purchase DAN meter reading.

### 5.1 Repository: aktifkan tabel `ElectricityMeterReadings`

- [x] **File**: `lib/features/settings/data/utility_meter_repository.dart` + `lib/core/database/tables.dart`
- **Masalah**: Tabel `ElectricityMeterReadings` sudah ada di schema (`tables.dart:250-261`) tapi belum ada repository method yang memakainya. Dormant.
- **Struktur tabel** (sudah ada): `id`, `householdId`, `meterId`, `readingKwh`, `recordedAt`, `source` (enum: manual/photo), `note`
- **Method baru di repository**:
  ```dart
  Future<void> recordMeterReading({
    required String householdId,
    required String meterId,
    required double readingKwh,
    DateTime? recordedAt,
    String source = 'manual',
    String? note,
  });
  
  Future<List<MeterReading>> getMeterReadings(
    String householdId, {
    required String meterId,
    int limit = 30,
  });
  
  Future<MeterReading?> getLatestReading(String householdId, String meterId);
  
  Future<double?> calculateActualUsage(
    String householdId, {
    required String meterId,
    required DateTime from,
    required DateTime to,
  });
  ```
- **`calculateActualUsage`**: Selisih antara reading terakhir SEBELUM `from` dan reading pertama SESUDAH `to`. Jika tidak ada data cukup → return null (fallback ke estimasi pola beli).
- **Class baru `MeterReading`**: Tambahkan di `utility_meter_models.dart` setelah `PeriodUsage`.
- **Verifikasi**: `flutter analyze lib test` clean. Test: simpan 2 reading → hitung selisih → benar.

### 5.2 UI: tombol "Catat Pembacaan" di meter card + panduan baca meter

- [x] **File**: `lib/features/settings/presentation/pages/utility_meter_page.dart`
- **Masalah**: User tidak ada cara untuk input pembacaan meter aktual. Selain itu, user perlu tahu **angka kWh itu dari mana dan cara bacanya**.
- **Perubahan**: Di `_buildMeterCard`, setelah bar chart (atau setelah summary), tambahkan tombol "📝 Catat Pembacaan" yang buka dialog:
  - **Header dialog**: "Catat Pembacaan Meter" + ikon meter ⚡
  - **Panduan visual** (sebelum input field):
    - Tampilkan ilustrasi sederhana meter PLN (atau teks berformat):
      ```
      📍 Di mana lihat angka kWh?
      ┌─────────────────────────┐
      │  Layar digital meter    │
      │  ┌───────────────────┐  │
      │  │   1 0 1 1 2 . 3   │  │  ← Angka ini (di layar meter)
      │  └───────────────────┘  │
      │  KWh                    │
      └─────────────────────────┘
      ```
    - Atau minimal helper text: "Angka kWh ada di layar digital meter Anda. Biasanya 5-6 digit sebelum titik desimal."
  - **Field input**: angka kWh (number input, required, hint: "contoh: 10112")
  - **Field tanggal**: date picker (default hari ini)
  - **Field catatan**: optional (mis. "setelah perbaikan listrik")
  - **Validasi real-time**: Jika input < reading terakhir → warning merah "⚠️ Reading lebih rendah dari sebelumnya (terakhir: 10.112 kWh). Pastikan angka sudah benar."
  - Tombol "Simpan" → panggil `repository.recordMeterReading()`
- **Tampilkan reading terakhir**: Di meter card, setelah "KWH TERCATAT", tampilkan: "Pembacaan terakhir: 10.112 kWh (17 Sep 2026)" jika ada.
- **Verifikasi**: `flutter analyze lib test` clean. Visual: tap "Catat Pembacaan" → dialog muncul dengan panduan → user tahu harus lihat di mana → simpan → data terlihat di card.

### 5.3 Asisten: route pembacaan meter via teks/foto

- [x] **File**: `lib/features/assistant/data/ffm_assistant_interpreter.dart` + `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart`
- **Masalah**: Asisten belum bisa memproses input "pembacaan meter 10.112 kWh untuk rumah A" atau foto display meter → simpan ke `ElectricityMeterReadings`.
- **Path teks** (interpreter):
  - Deteksi intent: pola `baca(???)?\s*method\s*meter\s*(\d+[\d.,]*)\s*kwh` atau `pembacaan\s*meter\s*(\d+[\d.,]*)\s*kwh` atau `meter\s*show\s*(\d+[\d.,]*)\s*kwh`
  - Route ke draft dengan type `meterReading` (bukan `expense`). Draft berisi: `readingKwh`, `meterId`/`meterNumber`, `recordedAt`.
  - **Penting**: Jika banyak rumah dan tidak ada target jelas → klarifikasi dulu (sama seperti flow token listrik). Jangan tebak.
  - Guard: perintah `pembacaan meter` tidak boleh di-bajak oleh flow token listrik.
- **Path foto** (sheet):
  - Saat user kirim foto display meter + caption "pembacaan meter" atau "catat meter" → route ke `askVisualQuestion` dengan prompt: "Baca angka kWh pada display meter ini. Balas hanya angka tanpa unit."
  - Extract angka → buat draft `meterReading` → konfirmasi → simpan.
  - **Response asisten harus menjelaskan**: "Saya melihat angka **10.112 kWh** pada display meter di foto Anda. Apakah ingin saya catat sebagai pembacaan meter [nama meter]?" — user tahu angka itu dari mana.
  - Jika banyak rumah → tanyakan meter mana (gunakan `resolveMeterTarget`).
- **Verifikasi**: `flutter analyze lib test` clean. Test: teks "pembacaan meter 10112 kWh untuk rumah A" → draft meterReading terbuat.

### 5.4 Integration: gabungkan Level 1 + Level 2 di grafik

- [x] **File**: `lib/features/settings/presentation/pages/utility_meter_page.dart` + `lib/features/settings/data/utility_meter_repository.dart`
- **Masalah**: Grafik saat ini hanya menampilkan estimasi dari pola beli. Jika ada data pembacaan aktual, harus ditampilkan juga.
- **Perubahan**:
  1. Di `summarizeUsageByPeriod`, tambahkan parameter `includeReadings: false`. Jika `true`, gabungkan data pembelian dengan data pembacaan aktual.
  2. Di `MiniMonthlyBarChart`, jika ada reading aktual → tampilkan garis overlay (line) di atas bar chart. Garis solid = aktual, bar = estimasi.
  3. Jika tidak ada reading → tetap tampilkan bar chart saja (Level 1).
- **Alternatif simpler**: Tampilkan aktual dan estimasi sebagai 2 series berbeda dalam bar chart (side-by-side bars).
- **Verifikasi**: `flutter analyze lib test` clean. Visual: meter dengan data aktual → grafik tampil 2 series. Meter tanpa aktual → grafik 1 series.

### 5.6 UI tambahan: panduan "Cara Membaca Meter" di meter card

- [x] **File**: `lib/features/settings/presentation/pages/utility_meter_page.dart`
- **Masalah**: User baru mungkin bingung cara baca meter PLN. Perlu panduan singkat yang mudah diakses.
- **Perubahan**: Di `_buildMeterCard`, di bawah "Pembacaan terakhir", tambahkan link/text yang bisa di-expand:
  ```
  💡 Cara membaca meter →
  ```
  Saat di-tap, tampilkan panduan singkat:
  ```
  📍 Angka kWh ada di layar digital meter
  📊 Biasanya 5-6 digit (contoh: 10.112)
  ⚠️ Catat angka yang terlihat, JANGAN tekan tombol apa pun
  🔄 Catat setiap bulan untuk grafik akurat
  ```
  - Style: card kecil dengan background abu-abu muda, font kecil, bisa di-collapse.
  - Tampilkan hanya sekali per sesi (atau selalu jika user mau).
- **Verifikasi**: `flutter analyze lib test` clean. Visual: panduan terlihat jelas tapi tidak mengganggu UX utama.

### 5.5 Test: coverage pembacaan meter

- [x] **File**: `test/electricity_sqlite_integration_test.dart`
- **Test baru**:
  1. Simpan 2 reading untuk meter yang sama → `calculateActualUsage` return selisih benar.
  2. Simpan reading yang lebih rendah dari sebelumnya → warning / error.
  3. Reading untuk meter yang tidak ada → error.
  4. `getLatestReading` return reading terbaru.
  5. `getMeterReadings` return list terurut dari yang terbaru.
- **Verifikasi**: `flutter test test/electricity_sqlite_integration_test.dart` pass.

---

## Fase 4 — Cleanup & Polish

> **Prioritas**: RENDAH. Optional tapi menambah kualitas.

### 4.1 Default nama meter lebih deskriptif

- [x] **File**: `lib/features/settings/data/utility_meter_repository.dart`
- **Masalah**: `recordLinkedPurchase` line ~538 default `'Meteran PLN $meterNumber'` — generic, membingungkan jika banyak meter auto-create.
- **Perbaikan**: Jika `proposedMeterName` kosong, gunakan `"Meteran PLN (${meterNumber.substring(meterNumber.length - 4)})"` (4 digit terakhir). Atau tanyakan ke user via clarification sebelum create.
- **Verifikasi**: `flutter analyze lib test` clean.

### 4.2 Handle `_updateLatest` silent failure

- [x] **File**: `lib/features/settings/data/utility_meter_repository.dart`
- **Masalah**: `_updateLatest` (line ~457–473) silently return jika meter tidak ditemukan. User tidak tahu update gagal.
- **Perbaikan**: Return `bool` (success/failure). Jika false → log warning atau return error ke caller. Atau minimal, di `recordLinkedPurchase`, cek hasil `_updateLatest` dan handle.
- **Verifikasi**: `flutter analyze lib test` clean.

### 4.3 Tambahkan `kWh` ke response chat saat resolve

- [x] **File**: `lib/features/assistant/data/ffm_assistant_interpreter.dart`
- **Masalah**: Saat resolve meter target成功, response tidak menampilkan kWh yang terbaca.
- **Perbaikan**: Jika `creditedKwh != null`, tambahkan ke response: "KWH tercatat: 63.7 kWh".
- **Verifikasi**: `flutter analyze lib test` clean.

---

## Catatan untuk Agent yang Mengerjakan

### Urutan pengerjaan WAJIB
1. **Fase 1** (1.1 → 1.2 → 1.3 → 1.4 → 1.5) — **WAJIB dulu**. Fix data integrity sebelum tambah fitur.
2. **Fase 2** (2.1 → 2.2 → 2.3 → 2.4 → 2.5 → 2.6 → 2.7) — Setelah Fase 1 hijau.
3. **Fase 3** (3.1 → 3.2 → 3.3) — Setelah Fase 2 hijau.
4. **Fase 4** (4.1 → 4.2 → 4.3) — Optional, kapan saja setelah Fase 1.
5. **Fase 5** (5.1 → 5.2 → 5.3 → 5.4 → 5.5) — Setelah Fase 3 hijau. Input pembacaan meter aktual.

### Validasi wajib per task
```
flutter analyze lib test
flutter test test/electricity_meter_resolution_test.dart
flutter test test/electricity_sqlite_integration_test.dart
flutter test test/receipt_scanner_service_test.dart
flutter test   # full suite (harus semua pass)
```

### File yang diubah per fase
| Fase | File utama |
|------|-----------|
| 1.1 | `interpreter.dart` |
| 1.2 | `tables.dart`, `app_database.dart` |
| 1.3–1.5 | `utility_meter_repository.dart` |
| 2.1, 2.6 | `receipt_scanner_service.dart` |
| 2.2–2.3 | `interpreter.dart` |
| 2.4–2.5 | `ffm_assistant_sheet.dart` |
| 2.7 | `capability_adapters.dart` |
| 3.1 | `utility_meter_repository.dart` |
| 3.2–3.3 | `utility_meter_page.dart` |
| 4.1–4.3 | various |
| 5.1 | `utility_meter_repository.dart`, `tables.dart`, `utility_meter_models.dart` |
| 5.2 | `utility_meter_page.dart` |
| 5.3 | `interpreter.dart`, `ffm_assistant_sheet.dart` |
| 5.4 | `utility_meter_page.dart`, `utility_meter_repository.dart` |
| 5.5 | `electricity_sqlite_integration_test.dart` |

### Strategi test
- Setiap perbaikan di Fase 1: tambah 1–2 test case di `electricity_meter_resolution_test.dart` atau `electricity_sqlite_integration_test.dart`.
- Setiap perbaikan di Fase 2: tambah test di `receipt_scanner_service_test.dart` atau `electricity_meter_resolution_test.dart`.
- Setiap perbaikan di Fase 3: tambah test di `electricity_sqlite_integration_test.dart` untuk query `summarizeUsageByPeriod`.
- Fase 5: tambah 5 test di `electricity_sqlite_integration_test.dart` untuk `recordMeterReading`, `getLatestReading`, `calculateActualUsage`.
- Setelah setiap fase: jalankan full `flutter test` + `flutter build apk --target-platform android-arm64 --release`.

### Test coverage yang sudah ada (per 2026-09-17)
- `electricity_sqlite_integration_test.dart` (4 tests): 1:1 transaksi-token, rollback kWh invalid, period aggregation, archive+recreate
- `electricity_meter_resolution_test.dart` (19 tests): resolver target, anomalies, interpreter flow
- `receipt_scanner_service_test.dart` (21 tests): OCR, batch, multi-token, retry
- **Belum ada test untuk**: unique index constraint, duplikat meter, `summarizeUsageByPeriod` sudah ada test
- **Tabel `ElectricityMeterReadings`**: sudah ada di schema tapi belum ada aplikasi code yang pakai (dormant) — akan diaktifkan di Fase 5

### Referensi kode penting (sudah diverifikasi ulang 2026-09-17)
- `resolveMeterTarget`: `utility_meter_repository.dart:245-299`
- `scanPurchaseAnomalies`: `utility_meter_repository.dart:304-363`
- `recordLinkedPurchase`: `utility_meter_repository.dart:477-570`
- `_resolveElectricityPurchase`: `interpreter.dart:9255-9351`
- `_utilityProposalFromText`: `interpreter.dart:9353-9389`
- `_hasElectricityPurchaseIntent`: `interpreter.dart:9241-9272`
- `extractPlnToken/extractPlnMeterNumber/extractPlnKwh`: `receipt_scanner_service.dart:40-117`
- `_appendScanOutcome`: `sheet.dart:2686-3031`
- `_isBroadVisualQuestion`: `sheet.dart:2489-2503`
- `ElectricityUsageSummary`: `utility_meter_repository.dart:34-46`
- `summarizeUsage`: `utility_meter_repository.dart:587-607`
- `UtilityPurchaseHistory`: `utility_meter_repository.dart:10-32`
- `ElectricityMeterReadings` table: `tables.dart:250-261` (dormant, akan diaktifkan di Fase 5.1)
- Pattern bar chart: `summary_page.dart:916-1067` (`_MonthlyExpenseTrendCard`)
- `UtilityMeter.meterNumber` doc comment: `utility_meter_models.dart:31`
- `_createElectricityIndexes`: `app_database.dart:741-758`
- Unique index `idx_electricity_meters_number`: `app_database.dart:743-744`
- Schema version: `app_database.dart:78` (saat ini 66)
- Migration block terakhir: `app_database.dart:127` (`if (from < 65)`)

---

## Prompt Siap Pakai

> Copy-paste prompt di bawah ke agent lain (atau ke session baru) agar langsung mulai mengerjakan.

### Prompt: Mulai Fase 1

```
Baca file PLAN_ELECTRICITY_FIXES.md di root project. Mulai kerjakan Fase 1 (task 1.1 sampai 1.5) secara berurutan. 

Untuk setiap task:
1. Baca deskripsi masalah dan lokasi kode di file tersebut
2. Baca kode sumber di path yang tercantum untuk memahami konteks
3. Implementasi perbaikan
4. Jalankan verifikasi yang tercantum (flutter analyze + test yang relevan)
5. Centang checkbox [ ] → [x] di file MD jika semua verifikasi pass

Jangan skip task. Jangan lanjut ke task berikutnya sebelum task sekarang hijau. 
Setelah Fase 1 selesai, jalankan full `flutter test` untuk memastikan tidak ada regresi.

Jika menemukan anomali tambahan yang tidak ada di plan, catat di bagian bawah file MD.
```

### Prompt: Mulai Fase 2

```
Baca file PLAN_ELECTRICITY_FIXES.md di root project. Fase 1 sudah selesai. 
Mulai kerjakan Fase 2 (task 2.1 sampai 2.7) secara berurutan.

Untuk setiap task:
1. Baca deskripsi masalah dan lokasi kode di file tersebut
2. Baca kode sumber di path yang tercantum untuk memahami konteks
3. Implementasi perbaikan
4. Jalankan verifikasi yang tercantum (flutter analyze + test yang relevan)
5. Centang checkbox [ ] → [x] di file MD jika semua verifikasi pass

Setelah Fase 2 selesai, jalankan full `flutter test` + `flutter build apk --target-platform android-arm64 --release`.
```

### Prompt: Mulai Fase 3

```
Baca file PLAN_ELECTRICITY_FIXES.md di root project. Fase 1-2 sudah selesai.
Mulai kerjakan Fase 3 (task 3.1 sampai 3.3) secara berurutan.

Fase 3 menambahkan grafik penggunaan listrik per IDPEL. 
Ikuti pola bar chart yang sudah ada di summary_page.dart (lihat referensi di file MD).

Untuk setiap task:
1. Baca deskripsi masalah dan lokasi kode di file tersebut
2. Baca kode sumber di path yang tercantum untuk memahami konteks
3. Implementasi perbaikan
4. Jalankan verifikasi yang tercantum (flutter analyze + test yang relevan)
5. Centang checkbox [ ] → [x] di file MD jika semua verifikasi pass

Setelah Fase 3 selesai, jalankan full `flutter test` + `flutter build apk --target-platform android-arm64 --release`.
```

### Prompt: Mulai Fase 4

```
Baca file PLAN_ELECTRICITY_FIXES.md di root project. Fase 1-3 sudah selesai.
Mulai kerjakan Fase 4 (task 4.1 sampai 4.3) secara berurutan.

Fase 4 adalah cleanup & polish — optional tapi menambah kualitas.
Ikuti deskripsi di file MD.

Untuk setiap task:
1. Baca deskripsi masalah dan lokasi kode di file tersebut
2. Baca kode sumber di path yang tercantum untuk memahami konteks
3. Implementasi perbaikan
4. Jalankan verifikasi yang tercantum (flutter analyze + test yang relevan)
5. Centang checkbox [ ] → [x] di file MD jika semua verifikasi pass

Setelah Fase 4 selesai, jalankan full `flutter test` + `flutter build apk --target-platform android-arm64 --release`.
```

### Prompt: Mulai Fase 5

```
Baca file PLAN_ELECTRICITY_FIXES.md di root project. Fase 1-3 sudah selesai.
Mulai kerjakan Fase 5 (task 5.1 sampai 5.5) secara berurutan.

Fase 5 menambahkan input pembacaan meter aktual (Level 2). 
Tabel ElectricityMeterReadings sudah ada di schema tapi dormant.
Task 5.1 mengaktifkannya dengan repository method baru.

Untuk setiap task:
1. Baca deskripsi masalah dan lokasi kode di file tersebut
2. Baca kode sumber di path yang tercantum untuk memahami konteks
3. Implementasi perbaikan
4. Jalankan verifikasi yang tercantum (flutter analyze + test yang relevan)
5. Centang checkbox [ ] → [x] di file MD jika semua verifikasi pass

Setelah Fase 5 selesai, jalankan full `flutter test` + `flutter build apk --target-platform android-arm64 --release`.
```

### Prompt: Kerjakan Semua Sekaligus

```
Baca file PLAN_ELECTRICITY_FIXES.md di root project. Kerjakan SEMUA Fase (1-5) secara berurutan.

Urutan: Fase 1 → Fase 2 → Fase 3 → Fase 4 → Fase 5.

Untuk setiap task:
1. Baca deskripsi masalah dan lokasi kode di file tersebut
2. Baca kode sumber di path yang tercantum
3. Implementasi perbaikan
4. Jalankan verifikasi (flutter analyze + test)
5. Centang checkbox [ ] → [x] di file MD jika pass

Jangan skip task. Jangan lanjut ke fase berikutnya sebelum fase sekarang hijau.
Setelah setiap fase, jalankan full `flutter test`.
Setelah semua selesai, jalankan `flutter build apk --target-platform android-arm64 --release`.
```

### Prompt: Cek Status Plan

```
Baca file PLAN_ELECTRICITY_FIXES.md di root project. 
Berapa banyak checkbox yang sudah dicentang [x] vs yang masih kosong [ ]?
Tuliskan progress: "[X/24] task selesai" dan sebutkan task mana yang belum dikerjakan.
```
