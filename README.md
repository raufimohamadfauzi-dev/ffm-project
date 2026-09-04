# 💎 FFM — Family Financial Manager

> **Aplikasi Pengelola Keuangan Keluarga dan AI Financial Agent untuk Android berbasis Hybrid AI (logika lokal, model lokal opsional, dan Gemini Cloud Orchestrator), dengan pembaca NFC e-Money, pendeteksi notifikasi bank/QRIS, serta integrasi kalender.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Database](https://img.shields.io/badge/Database-SQLite%20(Drift)-003B57?style=for-the-badge&logo=sqlite&logoColor=white)](https://drift.simonbinder.eu/)
[![AI](https://img.shields.io/badge/AI-Gemini%20Cloud-4285F4?style=for-the-badge&logo=google)](https://ai.google.dev/)
[![Android](https://img.shields.io/badge/Android-ARM64%20(API%2026%2B)-3DDC84?style=for-the-badge&logo=android&logoColor=white)](#-build-release)
[![YouTube](https://img.shields.io/badge/YouTube-Clipsmart-FF0000?style=for-the-badge&logo=youtube&logoColor=white)](https://youtube.com/@clipsmartt?si=T4-4Zja6FZlcgdDe)
[![TikTok](https://img.shields.io/badge/TikTok-@clip.smarts-000000?style=for-the-badge&logo=tiktok&logoColor=white)](https://www.tiktok.com/@clip.smarts?_r=1&_t=ZS-997Uzi7kXma)

---

## 📌 Status Proyek

- **Versi aplikasi**: `0.1.90+90`
- **Package ID**: `com.ffm_manager`
- **Target runtime yang divalidasi**: Android ARM64 (`arm64-v8a`)
- **Minimum Android**: API 26 (Android 8.0)
- **Status**: aktif dikembangkan; sebagian integrasi native memerlukan validasi pada perangkat Android nyata.

---

## 📱 Saluran Media Sosial & Konten Resmi

Dapatkan tutorial, demo fitur AI Agent, dan pembaharuan FFM langsung melalui saluran resmi kami:

- 📺 **YouTube Channel**: [YouTube @clipsmartt](https://youtube.com/@clipsmartt?si=T4-4Zja6FZlcgdDe)
- 🎵 **TikTok Official**: [TikTok @clip.smarts](https://www.tiktok.com/@clip.smarts?_r=1&_t=ZS-997Uzi7kXma)
- 👨‍💻 **Pengembang Utama**: **Rafi Sinkkat** *(Clipsmart)*

---

## 🎯 Arah Produk & Filosofi Arsitektur

FFM bukan sekadar aplikasi pencatat keuangan biasa dengan chatbot tambahan. 

**AI Financial Assistant/Agent adalah lapisan kecerdasan utama produk.**

Aplikasi dibangun dengan prinsip **Offline-First & Hybrid AI Architecture**. Alur keuangan inti tetap lokal, sedangkan kemampuan cloud dan data eksternal bersifat opsional:

1. **Data Keuangan Lokal & Keamanan Perangkat**:
   - Seluruh data keuangan (transaksi, rekening, anggaran, hutang & piutang, aset, dan target) tersimpan secara lokal dan privat di perangkat pengguna menggunakan **SQLite melalui Drift ORM**.
   - Keamanan menggunakan **PIN 6-digit & Biometrik lokal** (`AppPinService`), tanpa bergantung pada server eksternal.
    - Alur keuangan inti dapat digunakan tanpa koneksi internet. Gemini Cloud, sinkronisasi Supabase, dan data pasar terbaru memerlukan jaringan.

2. **Hybrid AI & Bounded Orchestrator**:
    - **Deterministic Financial Logic & Agent Harness**: Komputasi aritmatika, saldo, rasio anggaran, evaluasi status jatuh tempo, serta capability dan Action Plan berjalan melalui aturan aplikasi yang dapat divalidasi.
    - **Gemini Cloud Orchestrator (bounded reasoning)**: Digunakan untuk pemahaman bahasa alami, penalaran, proposal/draft, dan penjelasan setelah API key serta model berhasil diverifikasi. Data yang dikirim ke cloud dibatasi dan tidak memberi model akses mutasi database langsung.
    - **Supabase Cloud Memory (opsional)**: Dipakai untuk kebutuhan memori atau persistence cloud sesuai konfigurasi pengguna, bukan sebagai sumber kebenaran transaksi lokal.

---

## 🚀 Fitur Otomatisasi & Kecerdasan Terdepan

### 💳 1. Pembaca NFC e-Money & Adaptasi Saldo Otomatis (Fitur #1)
- **Pembacaan APDU ISO 7816-4 secara lokal:** Menyediakan profil pembacaan untuk kartu e-Money dan fallback kartu NFC generik. Dukungan aktual bergantung pada tipe kartu, perangkat, dan validasi APDU; kompatibilitas setiap merek belum diklaim sebagai validasi end-to-end.
- **Engine Adaptasi Saldo Otomatis (`oldBalance - newBalance`):**
  - Menganalisis selisih saldo saat kartu discan ulang setelah lewat tol, parkir, KRL, atau minimarket.
  - Otomatis menghasilkan **Draft Transaksi Pengeluaran / Top-Up (1-Ketukan)** tanpa input manual.

### 🔔 2. Pendeteksi Notifikasi Pembayaran QRIS & Bank (Fitur #02)
- **Android `NotificationListenerService` 100% Lokal:** Memantau notifikasi transaksi resmi dari 11+ bank dan e-wallet utama Indonesia (**BCA, myBCA, Mandiri Livin', BRImo, BNI Mobile, Wondr BNI, GoPay, OVO, DANA, ShopeePay, SeaBank**).
- **Engine Regex Lokal:** Menganalisis nominal Rupiah, nama merchant, jenis mutasi (debit/kredit), saran kategori otomatis, serta dilengkapi **window deduplication 5 menit** dan filter notifikasi OTP/keamanan.

### ⚡ 3. Quick Settings Tile Bar Atas Android (Fitur #5)
- **Android `TileService` (`BIND_QUICK_SETTINGS_TILE`):** Menambahkan tombol pintas **"Catat FFM"** di Control Center (bar notifikasi atas HP) pada perangkat API 26+.
- **1-Ketukan dari Mana Saja:** Tile membuka alur quick note/asisten FFM dari panel Quick Settings. Voice recorder atau pemindai NFC kemudian dipilih dari alur aplikasi yang tersedia.

### 📅 4. Integrasi Kalender Sistem & Smartwatch Sync (Fitur #2)
- **Android `CalendarProvider` (`WRITE_CALENDAR`):** Menyinkronkan tanggal jatuh tempo tagihan, cicilan, dan pengingat rutin secara langsung ke Google Calendar HP.
- **Smartwatch:** Event dapat diteruskan ke wearable jika akun kalender, aplikasi vendor, izin runtime, dan sinkronisasi perangkat telah aktif. Pengiriman ke Galaxy Watch, Garmin, Mi Band, atau Apple Watch belum divalidasi secara fisik oleh proyek.

### 📊 5. Halaman Anggaran Pintar & Adaptif (Smart Budget System)
- **Smart Dynamic Baseline Budgeting:** Secara otomatis menghitung **Rata-Rata Bergerak 3 Bulan Terakhir (*3-Month Moving Average*)** per kategori dari transaksi riil pengguna. Halaman Anggaran tidak lagi bernilai `Rp 0` kosong, melainkan terisi secara realistis tanpa perlu diinput manual secara kaku.
- **Smart Envelope Rebalance (1-Ketukan):** Mendeteksi pos anggaran yang menipis ($>85\%$) vs melimpah ($<40\%$) dan menyajikan kartu aksi pergeseran anggaran 1-ketukan.
- **Smart Runway & Burn-Rate Velocity:** Menghitung kecepatan bakar uang di pertengahan bulan, tanggal proyeksi anggaran habis, dan **Batas Belanja Harian Aman** ($\text{Sisa Anggaran} / \text{Sisa Hari}$).
- **Simulator "What-If" Anggaran:** Pengguna dapat bersimulasi keputusan pembelian di chat Asisten AI (*"Kalau saya beli laptop 5 juta bulan depan, gimana dampaknya ke anggaranku?"*).

### 🤖 6. Kecerdasan Agen Otonom, Self-Learning, & Agent Inbox
- **Self-Learning dari Koreksi Pengguna (Modul 3A):** Setiap kali pengguna mengoreksi draf transaksi (kategori toko, judul, atau rekening sumber), Agen AI secara otonom mengekstrak aturan personal di `FfmPersonalMemoryService` agar transaksi berikutnya otomatis tepat.
- **Pengaman Memori Anti-Kebingungan (*Anti-Bloat Guardrails*):**
  - **Deduplikasi Otomatis (*Upsert by Key*):** Aturan lama ditimpa saat preferensi diperbarui, mencegah data bertentangan di database lokal.
  - **Konteks Dibatasi Ketat (*Bounded Context*):** Memori yang diinjeksikan ke prompt LLM dibatasi maksimal 8 item paling relevan dan terpotong maksimal 700 karakter di cloud envelope.
  - **Lookup Deterministik Cepat:** Aturan yang sudah dipelajari dijalankan langsung oleh kode program Dart tanpa membebani LLM (bebas halusinasi & nol latensi).
- **Detektor Kebocoran Halus Otonom / *Latte Factor* (Modul 3B):** Menganalisis pengeluaran kecil berulang (< Rp 30.000) dan akumulasi biaya admin transfer/top-up 14 hari terakhir, lalu memproyeksikan laju bulanan (*burn-rate*) ke *Agent Inbox*.
- **Orkestrator Rencana Aksi Bertahap / *Multi-Step Action Plan* (Modul 3C):** Merancang rencana aksi multi-langkah (misal Target Dana Darurat + Alokasi Pos Hiburan + Pengingat Otomatis) dengan verifikasi berurutan per mutasi dan tombol konfirmasi 1-ketukan `[ ✅ Jalankan Rencana Aksi ]`.
- **Kotak Masuk Asisten & 6 Detektor Wawasan (*Agent Inbox*):**
  - Header chatbot dilengkapi tombol kotak masuk dengan badge angka notifikasi unread.
  - `AutonomousEvaluationCoordinator` memindai 6 aspek finansial: (1) *Predictive Runway*, (2) *Intelligent Envelope Rebalance*, (3) *Anomaly Spike*, (4) *Micro-Expense Leak*, (5) *Debt Service Ratio*, dan (6) *Goal Progress Risk*.
  - Menampilkan kartu wawasan di `AgentInboxPage` dengan opsi *Tindak Lanjuti, Tunda 1 Hari*, atau *Abaikan*.
- **Notifikasi Proaktif Sistem Android & Integrasi Telegram Bot:**
  - Peringatan berprioritas tinggi otomatis dikirim ke bar status Android via channel resmi *Kotak Masuk Asisten* (`ffm_assistant_insights` High Importance).
  - Mendukung penerusan notifikasi ke **Telegram Bot Pribadi** pengguna secara real-time.
- **Deteksi Tema Alami Bahasa Indonesia (Dark Mode WCAG-Compliant):**
  - Agen memahami perintah ganti tema dalam ragam bahasa Indonesia santun ("mode gelap", "tema redup", "ganti warna malam", "mode terang") dengan eksekusi instan tanpa perlu restart.

### 📈 7. Radar Pasar Emas, Valas, Kripto, & Warta Berita (Drawer Slide Kiri)
- **Navigation Drawer Pasar & Berita:** Cukup menggeser layar dari sisi kiri (*slide drawer*) di halaman utama untuk membuka Radar Pasar.
- **Live Ticker Finansial:**
  - Nilai tukar mata uang asing: **USD/IDR, EUR/IDR, SGD/IDR, SAR/IDR**.
  - Kripto acuan: **Bitcoin (BTC), Ethereum (ETH), Tether (USDT)** via CoinGecko.
  - Estimasi harga pasar **Emas Murni 24K Antam** dan harga *buyback* terkini berbasis kurs acuan.
- **Warta Berita & Cuaca Terkurasi:** Kabar penting sektor pertanian/pangan, prakiraan cuaca & bencana BMKG, serta stabilitas moneter dengan dukungan *offline cache* tanpa risiko crash (*Zero-Crash Fallback*).

### ⏱️ 8. Pelacak Aktivitas & Sesi Finansial (*Real-Time Activity Tracker*)
- **Pelacakan Sesi Lapangan Waktu Riil:** Mengaktifkan sesi aktivitas saat belanja bulanan, dinas luar kota, panen, atau proyek usaha dengan stopwatch timer.
- **Tautan Transaksi Otomatis:** Setiap transaksi pengeluaran yang dicatat selama sesi berlangsung otomatis terhubung ke aktivitas terkait (`linkedActivityId`).
- **Lampiran Catatan & Audio Suara:** Menyimpan catatan finansial harian serta memo suara langsung di sesi aktivitas.

### 💾 9. Cadangan Lokal JSON Mandiri (*Offline JSON Backup & Restore*)
- **Pencadangan Penuh Tanpa Server:** Mengekspor seluruh database finansial keluarga ke file `.json` lokal yang dapat dipindahkan ke perangkat baru kapan saja.
- **Verifikasi Integritas SHA-256:** Memastikan data cadangan utuh dan aman saat proses pemulihan (*restore*).
- **Laporan Formal:** Dukungan ekspor laporan keuangan berkala dalam format dokumen **PDF** dan spreadsheet **Excel**.

### 🌾 10. Siklus Kas Fleksibel & Musiman (AgroTrack & Bisnis Musiman)
- **Profil Arus Kas Adaptif:** Solusi untuk keluarga dengan pola pendapatan non-bulanan (petani panen musiman, pedagang musiman, kontraktor proyek, dan pekerja lepas).
- **Estimasi Cadangan Kas Aman & Runway:** Menghitung sisa hari hingga musim panen/termin pencairan berikutnya, memproyeksikan laju belanja harian aman (*safe burn-rate*), dan menampilkan kartu adaptif `AdaptiveCashFlowCard` di Beranda.
- **Manajemen Profil Terintegrasi (`FlexibleCashFlowPage`):** Memungkinkan pengaturan target modal kerja, tanggal target pencairan/panen, dan alokasi dana darurat per siklus.

---

## 🤖 Alur Eksekusi AI & Batasan Keamanan

Model AI **tidak pernah diizinkan memutasi database secara langsung**. Seluruh tindakan yang mengubah data wajib melalui alur aman:

```text
User Request / Chat / Scan NFC / Notifikasi Bank
    ↓
Assistant Understanding (Local Harness / Regex Parser / Gemini Cloud)
    ↓
Reasoning / Planning / Selisih Saldo
    ↓
Structured Action Plan / PaymentDraft
    ↓
Validation (Domain Rules & Business Constraints)
    ↓
User Confirmation (1-Ketukan Preview / Dialog)
    ↓
Capability Executor (Atomic DB Transaction)
    ↓
Local SQLite Mutation (Drift)
    ↓
Post-Execution Verification
```

---

## 📊 Fitur Keuangan Lengkap

- **Multi Rekening & Dompet Digital**: Kas tunai, rekening bank, dan e-wallet.
- **Manajemen Transaksi Komprehensif**: Pemasukan, pengeluaran, transfer antar rekening dengan biaya admin, filter multi-kriteria, input batch cepat, serta impor JSON batch.
- **Hutang & Piutang (Debt & Receivable)**: Pelacakan status *Aktif, Terlambat (Overdue), Jatuh Tempo, Lunas*, serta alur pembayaran cicilan atomik yang memotong saldo rekening secara langsung.
- **Target Finansial (Financial Goals)**: Target tabungan terencana dengan alokasi berkala dan integrasi kontribusi tabungan dari transaksi.
- **Valuasi Aset & Net Worth**: Pelacakan nilai kekayaan bersih keluarga (termasuk emas 24K Antam, valas, dan barang bernilai).
- **Siklus Kas Fleksibel & Musiman**: Manajemen profil keuangan berbasis siklus panen/proyek dengan pemantauan runway adaptif.
- **Jurnal Keuangan Harian (Daily Notes)**: Catatan harian, mood, dan evaluasi arus kas harian keluarga.
- **Sesi Aktivitas Finansial (Real-Time Tracker)**: Pelacakan transaksi berbasis sesi kegiatan, proyek lapangan, dengan stopwatch waktu riil dan memo rekaman suara.
- **Integrasi Telegram Bot Pribadi**: Pengiriman wawasan berprioritas tinggi dan peringatan radar pengeluaran langsung ke chat/grup Telegram keluarga.
- **Ekspor Laporan PDF & Excel**: Laporan bulanan, mingguan, dan analisis rasio kesehatan keuangan (Financial Health Score).
- **Penanggalan Ganda (Masehi & Hijriah)**: Konversi penanggalan Islam dengan koreksi hisab/rukyat Hilal (-2 s/d +2 hari).
- **Pengingat Lokal (Local Reminders)**: Pengingat pembayaran tagihan dan agenda keuangan dengan alarm notifikasi lokal.
- **Audit Log & Activity History**: Jejak audit komprehensif atas setiap aksi penambahan, perubahan, dan rekonsiliasi data keuangan keluarga.
- **Keamanan Aplikasi**: Sensor Biometrik (sidik jari/wajah) dan PIN 6 digit lokal (`AppPinService`).
- **Mode Gelap Kontras Tinggi (High Contrast Dark Mode)**: Memenuhi standar WCAG AAA/AA, dapat diaktifkan manual atau diperintahkan lewat agen AI secara natural.

---

## 🏗️ Struktur Direktori Proyek

```text
lib/
├── core/                  # Database SQLite (Drift), tema, keamanan PIN/biometrik, DI
├── features/
│   ├── activity/          # Aktivitas dan rutinitas waktu riil
│   ├── advisor/           # Smart Budget Engine, Rebalance, & Penasehat Keuangan
│   ├── budget/            # Halaman anggaran, baseline, runway, & proyeksi belanja
│   ├── asset/             # Valuation Aset & Radar Pasar Emas/Valas
│   ├── assistant/         # Agent, capability, Action Plan, model lokal, Gemini, NFC, & notification listener
│   ├── audit/             # Audit log jejak perubahan data
│   ├── backup/            # Ekspor/impor data, laporan PDF & Excel
│   ├── goal/              # Target finansial (saving goals)
│   ├── hijri/             # Penanggalan Islam / Hijriah
│   ├── liability/         # Pencatatan hutang & pembayaran cicilan
│   ├── receivable/        # Pencatatan piutang & penerimaan pembayaran
│   ├── recurring_transaction/ # Transaksi otomatis berulang
│   ├── reminder/          # Pengingat dan jadwal lokal
│   ├── settings/          # Pengaturan data master, profil, Gemini Key, & Supabase
│   └── transaction/       # Pemasukan, pengeluaran, transfer, filter & batch
```

---

## 🚀 Local Setup & Development

### Prasyarat

- **Flutter SDK**: Sesuai `pubspec.yaml` (Flutter 3.x / Dart 3.13+)
- **Android Studio / VS Code**
- **JDK 17+**
- **Android SDK**: compile SDK 37; perangkat minimum API 26

### Instalasi

```bash
git clone https://github.com/raufimohamadfauzi-dev/ffm-project.git
cd ffm-project
flutter pub get
```

### Validasi Kualitas Kode

```bash
# Menjalankan static analysis (wajib 0 issues)
flutter analyze lib test

# Menjalankan unit & integration tests
flutter test
```

---

## 📦 Build Release

**Release target resmi FFM adalah Android ARM64.**

Perintah rilis kanonikal:

```bash
flutter build apk --target-platform android-arm64 --release
```

Hasil keluaran file APK rilis:
```text
build/app/outputs/flutter-apk/app-release.apk (arm64-v8a)
```

Build release memerlukan `android/key.properties` dan keystore yang sesuai. Jangan menyimpan kredensial signing atau API key di source control.

## ⚠️ Batasan Validasi Saat Ini

- `flutter analyze lib test` dan `flutter test` memvalidasi kode serta test otomatis, bukan seluruh perilaku hardware.
- Belum ada profiling temperatur/memori/latensi atau pengujian foto nyata pada perangkat Android.
- Kompatibilitas APDU NFC, pengiriman notifikasi di background, izin CalendarProvider, sinkronisasi smartwatch, serta konektivitas Gemini/Supabase perlu diuji pada konfigurasi perangkat masing-masing.
- Build ARM64 membuktikan kompilasi, packaging, dan signature; tidak membuktikan keberhasilan koneksi cloud atau inference perangkat.

---

## 👨‍💻 Pengembang & Media Sosial

- **Pengembang Utama**: **Rafi Sinkkat** ([raufimohamadfauzi-dev](https://github.com/raufimohamadfauzi-dev))
- **YouTube Channel**: [YouTube @clipsmartt](https://youtube.com/@clipsmartt?si=T4-4Zja6FZlcgdDe)
- **TikTok Official**: [TikTok @clip.smarts](https://www.tiktok.com/@clip.smarts?_r=1&_t=ZS-997Uzi7kXma)
- **Platform Konten Resmi**: **Clipsmart**

---

## 📄 Lisensi & Hak Cipta

Hak Cipta © 2026 **Rafi Sinkkat / Clipsmart (FFM Project)**. Seluruh hak cipta dilindungi undang-undang.
Pustaka pihak ketiga mengikuti lisensi masing-masing yang tercantum pada distribusi dependency terkait.
