# 💎 FFM — Family Financial Management

> **Aplikasi Pengelola Keuangan Keluarga Modern, 100% Offline-First, Dilengkapi Asisten Cerdas Bergaya Claude & AI Vision On-Device.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![SQLite Drift](https://img.shields.io/badge/Database-SQLite%20Drift-003B57?style=for-the-badge&logo=sqlite&logoColor=white)](https://drift.simonbinder.eu/)
[![Privacy](https://img.shields.io/badge/Privacy-100%25%20Offline-00D18F?style=for-the-badge&logo=shield&logoColor=white)](#-keamanan--privasi-100-offline)
[![AI On-Device](https://img.shields.io/badge/AI-Qwen2--VL%202B%20GGUF-FF6F00?style=for-the-badge&logo=openai&logoColor=white)](#-asisten-finansial-cerdas-on-device)

---

## 🌟 Fitur Utama

### 🛡️ Keamanan & Privasi 100% Offline
* **Zero Cloud Dependency**: Seluruh data transaksi, rekening, anggaran, aset, dan catatan hutang disimpan secara lokal di internal storage perangkat menggunakan database **SQLite terenkripsi**.
* **Tanpa Pelacakan**: Tidak ada data keuangan yang dikirim ke server pihak ketiga atau cloud mana pun.

### 🤖 Asisten Finansial Cerdas (Claude-Style Thinking Tree)
* **Pohon Jejak Penalaran Vertikal (*Thinking Tree*)**: Menampilkan proses berpikir asisten secara transparan, waktu komputasi (ms), dan tabel SQLite yang diakses (`transactions`, `accounts`, `budgets`).
* **Format Percakapan Alami**: Merespons dalam bahasa Indonesia yang luwes dengan format Markdown terstruktur.
* **3 Rekomendasi Pertanyaan Pintar (*Follow-up Suggestions*)**: Rekomendasi pertanyaan interaktif di atas kolom input yang langsung siap diklik atau disalin.

### 🧠 Mode Penyimpanan Pribadi (*Personal Memory Mode*)
* **Pembelajaran Cerdas & Transparan**: Asisten mendeteksi preferensi pengguna dari percakapan (seperti tanggal gajian, nama panggilan, pekerjaan, target tabungan).
* **Konfirmasi Aman**: Setiap fakta baru wajib disetujui pengguna melalui kartu konfirmasi *"Boleh aku ingat ini?"* sebelum disimpan ke memori lokal.
* **Manajemen Memori (🧠)**: Panel khusus untuk melihat, memfilter, dan menghapus ingatan asisten kapan saja.

### 📷 AI Vision Pembaca Struk On-Device
* **Qwen2-VL 2B GGUF**: Model multimodal yang berjalan langsung di CPU/GPU ponsel tanpa internet untuk mengekstrak nama toko, tanggal, item belanja, dan total transaksi dari foto struk fisik.

### 📊 Manajemen Keuangan Keluarga Komprehensif
* **Multi Rekening & Dompet**: Manajemen kas, rekening bank, dan e-wallet.
* **Budget Guard & Daily Burn Rate**: Pemantauan laju pengeluaran harian dan peringatan potensi overbudget.
* **Net Worth & Asset Tracker**: Menghitung estimasi kekayaan bersih dari aset fisik dan keuangan.
* **Pencatatan Hutang & Piutang**: Pengingat jatuh tempo lokal dan pemantauan sisa pelunasan.
* **Target Tabungan (*Financial Goals*)**: Alokasi dana berkala menuju impian keluarga.
* **Kalender Masehi & Hijriah**: Dilengkapi algoritma konversi Hisab lokal untuk penanggalan Islam.

---

## 🏗️ Arsitektur Teknologi

```
lib/
├── core/                  # Database Drift SQLite, Tema, & Dependency Injection
├── features/
│   ├── activity/          # Pelacak aktivitas & rutinitas harian
│   ├── assistant/         # Agent Engine, Interpreter NLP, UI Claude Sheet & SLM Gateway
│   ├── auth/              # Kunci PIN & keamanan biometrik lokal
│   ├── budget/            # Logika batas anggaran & alokasi kategori
│   ├── goal/              # Perencanaan target finansial keluarga
│   ├── home/              # Dashboard ringkasan arus kas & navigasi
│   ├── liability/         # Pelacak hutang & piutang
│   └── transaction/       # Mutasi pemasukan, pengeluaran, & transfer
```

---

## 🚀 Memulai (Local Setup)

### Prasyarat
* **Flutter SDK**: `^3.27.0` atau lebih baru
* **Dart SDK**: `^3.6.0`
* **Android Studio / VS Code**
* **JDK**: Versi 17 atau 21

### Langkah Instalasi
1. **Clone Repositori**:
   ```bash
   git clone https://github.com/raufimohamadfauzi-dev/ffm-project.git
   cd ffm-project
   ```

2. **Pasang Dependensi**:
   ```bash
   flutter pub get
   ```

3. **Jalankan Pengujian Unit**:
   ```bash
   flutter test
   ```

4. **Jalankan di Perangkat / Emulator**:
   ```bash
   flutter run
   ```

---

## 👨‍💻 Pengembang & Kontributor

* **Pembuat & Pengembang Utama**: [raufimohamadfauzi-dev](https://github.com/raufimohamadfauzi-dev) (**Rafi Sinkkat**)
* **Platform Konten Resmi**: YouTube & TikTok Clipsmart

---

## 📄 Lisensi & Hak Cipta

Hak Cipta © 2026 **Rafi Mohamad Fauzi / FFM Project**. Seluruh hak cipta dilindungi undang-undang.
Pustaka pihak ketiga diatur berdasarkan lisensi masing-masing yang tercantum di [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
