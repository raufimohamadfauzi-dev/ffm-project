# Rencana Paket Teknis: Halaman Anggaran Pintar & Upgrade Kecerdasan Agen Otonom

Dokumen ini memuat arsitektur teknis, logika deterministik, dan integrasi kecerdasan Orkestrator AI untuk **Halaman Anggaran Pintar & Adaptif** serta **3 Modul Upgrade Agen Otonom (3A, 3B, 3C)**.

---

## BAGIAN A: Halaman Anggaran Pintar & Adaptif (Smart Budget System)

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

### 🔴 4. Simulator "What-If" Anggaran via Asisten AI (LLM / Orchestrator)
- **Integrasi Agent & LLM:**
  - `FfmGeminiCloudOrchestrator` dan `FfmAgentHarness` diperbarui agar memahami konteks struktur anggaran dinamis.
- **Simulasi Interaktif:**
  - Pengguna dapat bertanya atau menguji simulasi langsung di chat Asisten AI:
    > **Pengguna:** *"Kalau saya mau beli laptop 5 juta bulan depan, gimana dampaknya ke anggaranku?"*
    > **Agent AI:** *"Jika membeli laptop Rp 5.000.000, alokasi Tabungan Anda berkurang 40%, namun pos Makanan & Tagihan Wajib tetap aman. Rekomendasi: Alokasikan cicilan Rp 1.670.000/bulan selama 3 bulan agar anggaran bulanan tetap stabil."*

---

## BAGIAN B: Upgrade Kecerdasan Agen Otonom & Orkestrator AI (3A, 3B, 3C)

### 🧠 1. Modul 3A: Agen Belajar Otonom dari Koreksi Pengguna (*Self-Learning from Corrections*)
- **Cara Kerja:**
  - Setiap kali pengguna merubah atau mengedit draft transaksi/NFC/notifikasi (misalnya mengubah nama merchant atau kategori dari *Lain-lain* menjadi *Kebutuhan Rumah Tangga*):
  - `FfmAssistantDraftFeedbackService` secara otomatis mencatat pola koreksi tersebut.
  - Agen AI secara otonom menyimpan **Aturan Personal Baru** ke `FfmPersonalMemoryService`.
- **Dampak:** Transaksi serupa berikutnya otomatis 100% tepat sesuai selera pengguna tanpa perlu diajari berulang kali.

---

### 🔍 2. Modul 3B: Detektor Kebocoran Halus Otonom (*Micro-Expense Leak & Burn Rate Detector*)
- **Cara Kerja:**
  - Dijalankan secara periodik di latar belakang oleh `AutonomousEvaluationCoordinator`.
  - Menganalisis pengeluaran kecil berulang (misal biaya admin transfer, langganan tersembunyi, jajan impulsif harian) yang terakumulasi menjadi angka besar.
- **Hasil Insight Otonom:**
  - Agen menyajikan kartu insight berprioritas di *Agent Inbox*:
    > 💡 *"Terdeteksi kebocoran halus sebesar Rp 180.000 bulan ini dari biaya admin transfer & jajan harian. Penghematan di pos ini dapat menambah saldo tabungan Anda sebesar 15%."*

---

### 🗺️ 3. Modul 3C: Orkestrator Rencana Aksi Bertahap (*Multi-Step Action Plan Orchestrator*)
- **Cara Kerja:**
  - Ketika pengguna memberikan instruksi atau tujuan keuangan kompleks (misal: *"Saya mau kumpulkan dana darurat 10 juta dalam 5 bulan"*):
  - `FfmGeminiCloudOrchestrator` tidak hanya membalas dengan teks biasa, melainkan merancang **Rencana Aksi Bertahap (*Structured Action Plan*)**:
    1. Buat Target Keuangan Baru "Dana Darurat" (Rp 2.000.000/bulan).
    2. Alokasikan Rp 300.000 dari penghematan pos hiburan.
    3. Pasang pengingat otomatis tiap tanggal 25.
  - Dilengkapi tombol konfirmasi 1-ketukan `[ ✅ Jalankan Rencana Aksi ]`.

---

## 3. Checklist Rencana Pengerjaan (`- [ ]`)

### Tahap 1: Halaman Anggaran Pintar & Adaptif (Smart Budget Engine)
- [ ] **Tugas 1.1:** Engine Perhitungan Anggaran Dinamis (`smart_budget_engine.dart` - 3-Month Moving Average & Burn Rate).
- [ ] **Tugas 1.2:** Integrasi UI Halaman Anggaran Adaptif (`flexible_cash_flow_page.dart` / `budget_page.dart`).
- [ ] **Tugas 1.3:** Modul Rebalance Anggaran 1-Ketukan (`smart_envelope_rebalance.dart`).
- [ ] **Tugas 1.4:** Upgrade Orkestrator Gemini Cloud & Agent Harness untuk Simulator "What-If" Anggaran.

### Tahap 2: Upgrade Kecerdasan Agen Otonom (3A, 3B, 3C)
- [x] **Tugas 2.1:** Modul 3A Self-Learning dari Koreksi Pengguna (`FfmAssistantDraftFeedbackService` & `FfmPersonalMemoryService`).
- [x] **Tugas 2.2:** Modul 3B Detektor Kebocoran Halus Otonom di `AutonomousEvaluationCoordinator`.
- [x] **Tugas 2.3:** Modul 3C Orkestrator Rencana Aksi Bertahap (`FfmAssistantActionPlanner`).
- [x] **Tugas 2.4:** Pengujian Unit Komprehensif (`test/smart_budget_engine_test.dart` & `test/autonomous_agent_upgrades_test.dart`) + `flutter analyze lib test`.

---

## 4. Keamanan & Batasan (Compliance `AGENTS.md`)

1. **Finansial Deterministik:** Perhitungan rata-rata moving average, selisih rebalance, dan burn rate dilakukan oleh kode Dart deterministik (`SmartBudgetEngine`), bukan tebakan LLM.
2. **LLM untuk Interpretasi & Simulasi:** LLM Gemini digunakan untuk menjelaskan proyeksi, menjawab simulasi "What-If", dan merancang *Structured Action Plan*.
3. **Konfirmasi 1-Ketukan:** Setiap aksi mutasi atau pergeseran anggaran (*rebalance*) wajib memerlukan persetujuan eksplisit 1-ketukan dari pengguna.
