# Rencana Paket Teknis: Halaman Anggaran Pintar & Adaptasi Agen Otonom (Smart Budget & Agent Adaptation)

Dokumen ini memuat arsitektur teknis, logika deterministik, dan integrasi kecerdasan LLM/Orkestrator untuk **Halaman Anggaran Pintar, Adaptif, dan Simulator Interaktif**.

---

## 1. Latar Belakang & Prinsip Produk

Halaman anggaran tradisional yang menggunakan angka patokan kaku (*hardcoded targets*) sering kali membuat pengguna tertekan dan malas mencatat karena pengeluaran dunia nyata selalu berubah-ubah.

**Solusi Smart & Adaptif FFM:**
Mengubah Halaman Anggaran menjadi **Sistem Pintar Berbasis Perilaku Riil Pengguna**, yang secara otomatis menghitung baseline kebiasaan, memberikan rekomendasi pergeseran anggaran (*rebalance*) 1-ketukan, memperhitungkan kecepatan bakar uang (*burn rate*), dan mampu diajak bersimulasi keputusan keuangan via Asisten AI.

---

## 2. Empat Pilar Utama Fitur & Arsitektur Teknis

### 🟢 1. Smart Dynamic Baseline Budgeting (Anggaran Otomatis Berdasarkan Kebiasaan)
- **Problem:** Default halaman anggaran kosong / bernilai `Rp 0` jika pengguna tidak menginput target kaku satu per satu.
- **Logika Deterministik:**
  - `SmartBudgetEngine` secara otomatis menghitung **Rata-Rata Bergerak 3 Bulan Terakhir (*3-Month Moving Average*)** dari riwayat transaksi pengguna per kategori.
  - Jika pengguna belum memiliki riwayat 3 bulan, engine menggunakan agregat 1 bulan terakhir atau median transaksi yang tersedia.
- **Hasil UI:** Halaman Anggaran langsung terisi secara **otomatis, fleksibel, dan realistis** sesuai kebiasaan riil pengguna tanpa mematok target kaku.

---

### 🟡 2. Smart Envelope Rebalance (Pergeseran Anggaran Otomatis 1-Ketukan)
- **Logika Adaptif:**
  - Keuangan rumah tangga fleksibel. Jika anggaran satu pos (misal: *Makanan*) menipis, namun pos lain (misal: *Hiburan*) masih tersisa banyak, sistem mendeteksi ketidakseimbangan ini.
- **Mekanisme 1-Ketukan:**
  - Asisten AI menyajikan kartu aksi interaktif:
    > *"Anggaran Makanan minggu ini tersisa 10%, namun pos Hiburan masih tersisa 60% (Rp 300.000). Geser Rp 150.000 dari Hiburan ke Makanan agar tetap aman?"*
    > `[ 🔄 Rebalance Otomatis 1-Ketukan ]`
  - Mengeksekusi penyesuaian anggaran secara aman tanpa merusak total batas bulanan.

---

### 🟠 3. Smart Runway & Burn-Rate Velocity Projection (Peringatan Dini & Batas Aman Harian)
- **Logika Deterministik:**
  - Menghitung **Kecepatan Bakar Uang (*Burn Rate Velocity*)** di pertengahan bulan (misal tanggal 10 atau 15) dengan rumus:
    $$\text{Laju Harian Rata-Rata} = \frac{\text{Total Pengeluaran Bulan Ini}}{\text{Jumlah Hari Berjalan}}$$
  - Memproyeksikan tanggal estimasi anggaran habis sebelum akhir bulan/gajian.
- **Indikator Kesehatan Halaman Anggaran:**
  - 🟢 **On-Track:** Laju belanja stabil.
  - 🟡 **Peringatan Dini:** *"Pengeluaran Makanan diproyeksikan habis pada tanggal 22 (8 hari sebelum gajian)."*
  - 💡 **Rekomendasi Batas Aman Harian:** *"Batas belanja aman Anda mulai hari ini: Rp 45.000/hari."*

---

### 🔴 4. Simulator "What-If" Anggaran & Adaptasi Asisten AI (LLM / Orchestrator)
- **Integrasi Agent & LLM:**
  - `FfmGeminiCloudOrchestrator` dan `FfmAgentHarness` diperbarui agar memahami konteks struktur anggaran dinamis.
- **Simulasi Interaktif:**
  - Pengguna dapat bertanya atau menguji simulasi langsung di chat Asisten AI:
    > **Pengguna:** *"Kalau saya mau beli laptop 5 juta bulan depan, gimana dampaknya ke anggaranku?"*
    > **Agent AI:** *"Jika membeli laptop Rp 5.000.000, alokasi Tabungan Anda berkurang 40%, namun pos Makanan & Tagihan Wajib tetap aman. Rekomendasi: Alokasikan cicilan Rp 1.670.000/bulan selama 3 bulan agar anggaran bulanan tetap stabil."*
- **Otonomi Adaptasi Agen:**
  - Agen AI secara otonom mengingat preferensi toleransi anggaran pengguna melalui `FfmPersonalMemoryService`.

---

## 3. Checklist Rencana Pengerjaan (`- [ ]`)

- [ ] **Tugas 1: Engine Perhitungan Anggaran Dinamis (`smart_budget_engine.dart`)**
  - [ ] Implementasi algoritma *3-Month Moving Average* per kategori.
  - [ ] Implementasi rumus *Burn Rate Velocity* dan batas belanja harian aman.
- [ ] **Tugas 2: Integrasi UI Halaman Anggaran Adaptif (`flexible_cash_flow_page.dart` / `budget_page.dart`)**
  - [ ] Menampilkan *Smart Dynamic Baseline* secara otomatis jika target manual kosong.
  - [ ] Menampilkan indikator laju belanja harian aman dan proyeksi sisa hari.
- [ ] **Tugas 3: Modul Rebalance Anggaran 1-Ketukan (`smart_envelope_rebalance.dart`)**
  - [ ] Deteksi otomatis pos anggaran menipis vs melimpah.
  - [ ] Kartu konfirmasi rebalance 1-ketukan untuk pengguna.
- [ ] **Tugas 4: Upgrade Orkestrator Gemini Cloud & Agent Harness untuk Simulator "What-If"**
  - [ ] Tambahkan kapabilitas intent `budget_what_if_simulation` pada `FfmGeminiCloudOrchestrator`.
  - [ ] Sertakan konteks *Smart Budget* ke dalam *Working Context* Asisten AI.
- [ ] **Tugas 5: Pengujian Unit & Verifikasi Analysis**
  - [ ] Buat unit test `test/smart_budget_engine_test.dart`.
  - [ ] Jalankan `flutter analyze lib test`.

---

## 4. Keamanan & Batasan (Compliance `AGENTS.md`)

1. **Finansial Deterministik:** Perhitungan rata-rata moving average, selisih rebalance, dan burn rate dilakukan oleh kode Dart deterministik (`SmartBudgetEngine`), bukan tebakan LLM.
2. **LLM untuk Interpretasi & Simulasi:** LLM Gemini digunakan untuk menjelaskan proyeksi, menjawab simulasi "What-If", dan memberikan rekomendasi yang ramah pengguna.
3. **Konfirmasi 1-Ketukan:** Setiap aksi pergeseran anggaran (*rebalance*) wajib memerlukan persetujuan eksplisit 1-ketukan dari pengguna.
