# 💎 FFM — Family Financial Management

> **Aplikasi pengelola keuangan keluarga Offline-First untuk Android dengan AI Assistant/Agent sebagai pusat kecerdasan, didukung Local SQLite (Drift), Gemini Cloud Orchestrator, dan opsional Supabase Cloud Memory.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Database](https://img.shields.io/badge/Database-SQLite%20(Drift)-003B57?style=for-the-badge&logo=sqlite&logoColor=white)](https://drift.simonbinder.eu/)
[![AI](https://img.shields.io/badge/AI-Gemini%20Cloud-4285F4?style=for-the-badge&logo=google)](https://ai.google.dev/)
[![Cloud Sync](https://img.shields.io/badge/Cloud%20Memory-Supabase%20(Optional)-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com)
[![Android](https://img.shields.io/badge/Android-ARM64-3DDC84?style=for-the-badge&logo=android&logoColor=white)](#-build-release)

---

## 🎯 Arah Produk & Filosofi Arsitektur

FFM bukan sekadar aplikasi pencatat keuangan biasa dengan chatbot tambahan. 

**AI Assistant/Agent adalah lapisan kecerdasan utama produk.**

Aplikasi dibangun dengan prinsip **Offline-First & Hybrid Intelligence**:

1. **100% Offline-First Data & Security**:
   - Seluruh data keuangan (transaksi, rekening, anggaran, hutang & piutang, aset, dan target) tersimpan secara lokal dan privat di perangkat pengguna menggunakan **SQLite melalui Drift ORM**.
   - Keamanan akses menggunakan **PIN & Biometrik lokal** (`AppPinService`), tanpa bergantung pada server autentikasi eksternal.
   - Aplikasi dapat beroperasi penuh tanpa koneksi internet.

2. **Hybrid Intelligence**:
   - **Deterministic Logic & Harness Engine**: Komputasi aritmatika, saldo, rasio anggaran, evaluasi status jatuh tempo, dan 14 Agent Plugins (Mata/Sense, Tangan/Actuator, Logika/Logic) berjalan secara instan dan aman di perangkat tanpa internet.
   - **Gemini Cloud (Bounded Reasoning)**: Saat online, asisten memanfaatkan Gemini Cloud via Orchestrator untuk pemahaman bahasa alami (Bahasa Indonesia santun & natural), penalaran finansial kompleks, perumusan proposal/draft transaksi, dan ringkasan insight. Data yang dikirim ke cloud selalu dibatasi (*bounded & privacy-safe*).
   - **Supabase (Opsional Cloud Memory)**: Digunakan secara opsional sebagai pencadangan dan sinkronisasi memori asisten AI (`assistant_memories_cloud`) bagi pengguna yang mengaktifkannya di pengaturan.

---

## 🤖 AI Assistant / Agent

Assistant adalah fitur P0 dan menjadi pusat pengalaman pengguna.

### Kemampuan Utama

- **Percakapan Natural**: Memahami perintah kasual, instruksi jamak, dan konteks finansial dalam Bahasa Indonesia.
- **DeepSeek-style Agent Harness**: Dilengkapi 14 plugin lokal (Mata/Sense, Tangan/Actuator, Logika/Logic) untuk merespons pertanyaan saldo, cek sisa hutang/piutang, menghitung rasio dana darurat, hingga membuka halaman secara offline.
- **Action Planning & Safe Proposals**: Menghasilkan draf terstruktur untuk pencatatan transaksi, hutang baru, piutang baru, cicilan hutang, pencatatan target, anggaran, maupun catatan harian.
- **Personal Memory Berizin**: Mengingat preferensi pengguna dengan konfirmasi eksplisit pengguna.
- **Proactive Insights & Agent Inbox**: Memberikan peringatan jatuh tempo tagihan dan deteksi anomali pengeluaran langsung ke inbox asisten.

### Batasan Eksekusi AI

Model AI **tidak pernah diizinkan memutasi database secara langsung**. Seluruh tindakan yang mengubah data wajib melalui alur aman:

```text
User Request / Chat
    ↓
Assistant Understanding (Local Harness / Gemini Cloud)
    ↓
Reasoning / Planning
    ↓
Structured Action Plan / Proposal
    ↓
Validation (Domain Rules & Business Constraints)
    ↓
User Confirmation (Preview / Modal Dialog)
    ↓
Capability Executor (Atomic DB Transaction)
    ↓
Local SQLite Mutation (Drift)
    ↓
Post-Execution Verification
    ↓
Assistant Result & Feedback
```

---

## 📊 Fitur Keuangan Lengkap

- **Multi Rekening & Dompet**: Manajemen kas tunai, rekening bank, dan dompet digital (e-wallet).
- **Manajemen Transaksi**: Pemasukan, pengeluaran, transfer antar rekening dengan biaya admin, filter multi-kriteria, dan input batch cepat.
- **Hutang & Piutang (Debt & Receivable Management)**:
  - Pelacakan status deterministik: *Semua, Aktif, Terlambat (Overdue), Jatuh Tempo 0-7 Hari, 8-30 Hari, >30 Hari, dan Lunas*.
  - Alur pembayaran cicilan dan pelunasan terintegrasi langsung dengan mutasi kas secara atomik.
- **Budget Guard & Daily Burn Rate**: Penetapan batas pos anggaran bulanan dengan deteksi dini risiko *overbudget*.
- **Financial Goals (Target Finansial)**: Target tabungan terencana dengan alokasi berkala dan pelacakan progres.
- **Net Worth & Asset Tracker**: Valuasi aset keluarga dan estimasi kekayaan bersih.
- **Laporan Bulanan Komprehensif**: Analisis arus kas, rasio tabungan, Debt Service Ratio (DSR), evaluasi kesehatan finansial, serta ekspor dokumen **PDF & Excel**.
- **Transaksi Berkala (Recurring)**: Penjadwalan transaksi rutin otomatis.
- **Catatan Harian & Manajemen Aktivitas**: Pelacakan sesi kegiatan produktif/tani, durasi, dan catatan harian keluarga.
- **Kalender Hijriah & Masehi**: Penanggalan ganda terintegrasi untuk kebutuhan finansial keluarga Muslim.
- **Audit Trail**: Jejak audit komprehensif atas setiap perubahan data penting.

---

## 🏗️ Struktur Arsitektur Direktori

```text
lib/
├── core/                  # Database SQLite (Drift), tema, keamanan PIN/biometrik, DI
├── features/
│   ├── activity/          # Aktivitas dan rutinitas waktu riil
│   ├── advisor/           # Rekomendasi & penasehat keuangan
│   ├── asset/             # Pencatatan dan valuasi aset
│   ├── assistant/         # AI Agent Engine, Harness plugins, Gemini Orchestrator, UI
│   ├── audit/             # Audit log jejak perubahan data
│   ├── backup/            # Ekspor/impor data, laporan PDF & Excel
│   ├── budget/            # Anggaran dan pemantauan burn rate
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

## 🔐 Keamanan & Privasi Data

- **Zero Secret in Code**: API keys Gemini dan konfigurasi Supabase tidak pernah di-hardcode ke source code; pengguna menginput kunci pribadi langsung di halaman pengaturan terenkripsi (`flutter_secure_storage`).
- **Privacy-Safe Prompts**: Hanya ringkasan data yang diizinkan pengguna yang dikirim ke AI; data rahasia/kredensial tidak pernah keluar dari perangkat.
- **Local Biometrics & PIN**: Proteksi pembukaan aplikasi dengan sensor sidik jari/wajah atau PIN 6 digit lokal.

---

## 🚀 Local Setup & Development

### Prasyarat

- **Flutter SDK**: Sesuai `pubspec.yaml` (Flutter 3.x / Dart 3.13+)
- **Android Studio / VS Code**
- **JDK 17+**

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

---

## 👨‍💻 Pengembang

- **Pembuat & Pengembang Utama**: [raufimohamadfauzi-dev](https://github.com/raufimohamadfauzi-dev) (Rafi Mohamad Fauzi)
- **Platform Konten Resmi**: Clipsmart

---

## 📄 Lisensi & Hak Cipta

Hak Cipta © 2026 **Rafi Mohamad Fauzi / FFM Project**. Seluruh hak cipta dilindungi undang-undang.  
Pustaka pihak ketiga diatur berdasarkan lisensi masing-masing yang tercantum di [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
