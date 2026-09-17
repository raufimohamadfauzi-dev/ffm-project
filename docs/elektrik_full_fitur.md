# PANDUAN EKSEKUSI & DOKUMENTASI LENGKAP: Token Listrik PLN 100% Full Fitur In-Chatbot & UI Transaksi

> ⚡ **STATUS**: **SELESAI (COMPLETED & VERIFIED)**
> Seluruh fitur Token Listrik PLN telah diimplementasikan, diverifikasi dengan test suite hijau, analyzer clean, dan penamaan telah disederhanakan menjadi **"Token Listrik"** di seluruh aplikasi.

---

## 1. Arsitektur & Prinsip Utama
1. **Penamaan Resmi ("Token Listrik")**:
   - Seluruh label UI, menu pengaturan, backup, tooltip, pesan validasi, dan dialog asisten menggunakan nama **"Token Listrik"** (menggantikan istilah lama "Buku Saku Meteran" atau "Profil Keluarga").
2. **Kebenaran Finansial Deterministik (Non-Halusinasi)**:
   - Nilai pengeluaran, kWh, estimasi sisa hari, dan burn-rate dihitung 100% secara deterministis oleh repository (`UtilityMeterRepository`), bukan tebakan AI.
3. **Multi-IDPEL & Multi-Rumah Safety**:
   - Asisten AI tidak akan pernah salah memasukkan token/meteran ke rumah yang salah. Jika ada >1 rumah terdaftar tanpa nomor meter/IDPEL spesifik, sistem otomatis menyajikan tombol pilihan instan (quick choice chips) per rumah.
4. **LLM Groundedness**:
   - Gemini Cloud menerima konteks `buildElectricityDigest` yang menyertakan rincian belanja per rumah (`per_house=[...]`), pembacaan meter terakhir, dan burn rate, sehingga analisa komparatif konsumsi antar-rumah selalu grounded.

---

## 2. Rincian Fitur yang Telah Diimplementasikan

### Layer 1: Halaman & Repositori Token Listrik (UI & Data)
- [x] **1.1 Grafik Konsumsi Multi-Periode (Harian, Mingguan, Bulanan)**:
  - Komponen `MiniMonthlyBarChart` dilengkapi toggle chips `[Bln]` (12 bulan terakhir), `[Mgg]` (8 minggu terakhir), dan `[Hr]` (14 hari terakhir).
  - Repositori `summarizeUsageByPeriod` mengagregasi data berdasarkan filter periode yang dipilih secara reaktif.
- [x] **1.2 Burn-Rate (Laju Konsumsi kWh/Hari) & Estimasi Sisa Pulsa Token**:
  - Model `ElectricityBurnRate` menghitung rata-rata pemakaian kWh/hari berdasarkan selisih pembacaan meter fisik atau frekuensi pembelian token.
  - Kartu meteran di UI menampilkan badge indikator laju konsumsi dan estimasi sisa hari token sebelum habis.
- [x] **1.3 Pindai Meteran Fisik via Kamera (OCR Gemini)**:
  - Tombol ikon kamera pada dialog "Catat Meteran Fisik" terhubung dengan `GeminiService.extractTextFromReceipt` untuk membaca angka kWh LCD meteran PLN secara otomatis tanpa ketik manual.
- [x] **1.4 Ekspor & Bagikan Laporan Konsumsi Per Meter**:
  - Tombol bagikan pada kartu meteran memanggil `exportMeterReport` untuk membuat ringkasan rapi (IDPEL, tarif/daya, pengeluaran 12 bulan, pembacaan terakhir, burn rate) dan menyalinnya langsung ke clipboard dengan konfirmasi SnackBar.

### Layer 2: Asisten AI & Grounded In-Chatbot Experience
- [x] **2.1 Pencatatan Meteran Fisik Bahasa Alami In-Chat**:
  - Pengguna dapat mengetik: `"catat meteran rumah utama 10250 kwh"` atau `"catat meteran 10250 kwh"`.
  - Interpreter memetakan ke draft `meterReading` secara otomatis, meminta klarifikasi jika rumah belum jelas, dan menyimpannya ke database saat dikonfirmasi tanpa meninggalkan chat.
- [x] **2.2 Analisis Grounded Multi-Rumah untuk Gemini Cloud & Offline Assistant**:
  - `buildElectricityDigest` di `FfmAssistantFinancialSnapshotService` menyuplai ringkasan lengkap per properti rumah (`per_house=[Rumah Utama=Rp200.000, Ruko=Rp400.000]`).
  - Read capability `read.electricity` menyediakan data konsumsi, burn-rate, dan perbandingan properti dengan pengeluaran tertinggi untuk menjawab pertanyaan analitis pengguna.
- [x] **2.3 Tombol Pilihan Instan (Quick Choice Chips)**:
  - Saat pengguna mengetik `"beli token listrik 100rb"` dan memiliki banyak rumah, asisten menampilkan tombol pilihan instan (misal: `[beli token listrik 100000 untuk Rumah Utama]`, `[beli token listrik 100000 untuk Ruko]`).

### Layer 3: Konsistensi Penamaan ("Token Listrik")
- [x] AppBar & Banner di `utility_meter_page.dart` ➔ **"Token Listrik"**.
- [x] Menu Pengaturan di `other_menu_page.dart` ➔ **"Token Listrik"**.
- [x] Ringkasan Data di `backup_page.dart` ➔ **"Token Listrik"**.
- [x] Katalog Destinasi & Context Bar Asisten ➔ **"Token Listrik"**.
- [x] Pesan Validasi & Umpan Balik Konfirmasi Asisten ➔ **"Token Listrik"**.

---

## 3. Checklist Verifikasi & Pengujian
- [x] `test/electricity_meter_resolution_test.dart` (25/25 tests passed).
- [x] `flutter analyze lib test` (Clean, 0 errors, 0 warnings).
- [x] Non-interferensi: Fitur BBM tidak tersentuh sama sekali.
