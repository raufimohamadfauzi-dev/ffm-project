# Peningkatan Otonomi Background FFM Assistant

Meningkatkan kapabilitas asisten di *background* agar lebih proaktif dalam menyiapkan draf tindakan, menganalisis dengan AI (pre-compute), dan mengonsolidasi memori tanpa harus menunggu user membuka aplikasi, dengan tetap mematuhi batasan mutasi data FFM.

## User Review Required

> [!IMPORTANT]
> **Kebijakan Konfirmasi (Sesuai AGENTS.md Aturan #6 & #10)**
> Sesuai instruksi arsitektur FFM, AI **TIDAK BOLEH** secara langsung mengubah data finansial (seperti mencatat pengeluaran atau memindah anggaran) tanpa konfirmasi user. Oleh karena itu, permintaan untuk "otonom dibebaskan tanpa konfirmasi" **hanya berlaku** untuk:
> 1. Mencatat *Insight* dan Notifikasi deterministik.
> 2. Membuat **Pengingat (Reminders)** ke dalam database SQLite secara otonom (ini diperbolehkan karena bersifat saran, bukan mutasi saldo finansial).
> 3. Menyiapkan **Draf Tindakan (Action Plan)** secara lengkap.
> 4. Mengolah **Memori** (sebagai *learning candidate*).
>
> Untuk eksekusi yang mengubah uang, asisten dapat menyiapkan segalanya di belakang layar (*super aktif*), tetapi eksekusi akhirnya tetap menunggu klik konfirmasi user (bisa dari tombol aksi notifikasi).

## Open Questions

- Apakah integrasi tombol aksi pada notifikasi Android (misal: tombol "Konfirmasi Draf") membutuhkan UI khusus di *Intent* Flutter saat aplikasi dibuka dari background?
- Apakah *Pre-computed AI Reasoning* (permintaan Gemini di background) harus dibatasi maksimal sekian kali per hari agar tidak menguras kuota/biaya API saat user sedang tidur?

## Proposed Changes

### 1. Peningkatan Detektor & Draf Otonom (Autonomous Action Drafting)
Memodifikasi koordinator evaluasi background untuk tidak sekadar menyimpan *insight*, tapi juga merakit draf/proposal tindakan.

#### [MODIFY] `lib/features/assistant/domain/autonomous_evaluation_coordinator.dart`
- Tambahkan integrasi dengan komponen *planner* atau *capability executor* mode draf.
- Saat *Insight* kritis terdeteksi, koordinator akan membuat struktur `ActionPlan` (misalnya: draf pemindahan anggaran) dan menyimpannya sebagai draf aktif sehingga siap langsung disetujui user.

### 2. Pre-computed AI Reasoning
Menjalankan analisis LLM secara *background* agar tidak ada *loading* saat user membuka notifikasi.

#### [MODIFY] `lib/features/assistant/data/ffm_assistant_autonomy_background_handler.dart`
- Jika terdeteksi insight baru berprioritas sangat tinggi, panggil `FfmGeminiCloudOrchestrator` di background.
- Simpan hasil penjelasan (*reasoning*) natural language ini ke dalam metadata *insight* atau asisten agar saat app dibuka, teks AI langsung tampil (*zero-loading*).

### 3. Background Memory Consolidation
Mengolah pola data user (memori) secara otonom di waktu senggang.

#### [MODIFY] `lib/features/assistant/data/ffm_assistant_autonomy_worker.dart`
- Tambahkan alur untuk membaca transaksi harian baru dan mengekstrak `LearningCandidate` (pola pengeluaran, langganan tersembunyi).
- Mematuhi Aturan #13 dengan menyimpannya sebagai temuan menunggu persetujuan (atau masuk otomatis ke personal memori).

### 4. Interactive Push Notifications
Memperbarui sistem notifikasi agar user dapat melakukan tindakan tanpa menavigasi menu yang dalam.

#### [MODIFY] `lib/features/reminder/data/services/reminder_notification_service.dart`
- Gunakan kapabilitas *Android Notification Actions* (via plugin notifikasi) untuk menaruh tombol seperti "Setujui Draf", "Abaikan", atau "Tanya Asisten" langsung di bawah notifikasi.

## Verification Plan

### Automated Tests
- Menambahkan pengujian di `test/features/assistant/domain/autonomous_evaluation_coordinator_test.dart` untuk memastikan koordinator menghasilkan draf valid tanpa melakukan eksekusi mutasi.

### Manual Verification
- Menyimulasikan eksekusi *background worker* secara manual.
- Mengamati bahwa notifikasi muncul dengan *Action Buttons* dan bahwa klik pada tombol tersebut mengeksekusi *Action Plan* yang sudah dirakit (di-*pre-compute*) di background dengan sukses.
