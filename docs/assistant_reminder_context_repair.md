# Perbaikan P0 Asisten FFM: Context Halaman, Pengingat, Catatan Harian, dan CI

## Tujuan

Perbaiki Asisten FFM agar:

1. Pertanyaan tentang halaman aktif selalu menjawab halaman UI yang benar.
2. `pengingat` berarti **notifikasi biasa**, bukan alarm, kecuali pengguna menyebut alarm secara eksplisit.
3. Draft pengingat dapat dikonfirmasi dan disimpan dari chatbot setelah preview yang jelas.
4. Form UI Pengingat memakai seluruh data draft Asisten yang relevan.
5. Jawaban Catatan Harian tidak pernah membocorkan JSON/tool request ke pengguna.
6. Process trace hanya menyebut data yang benar-benar relevan, bukan template finansial.
7. Halaman Ringkasan memiliki badge merah untuk pengingat yang membutuhkan tindakan.
8. GitHub Actions menjalankan analyzer dan test Flutter pada setiap push ke `main`.

## Laporan masalah asli

### A. Pengingat berubah makna menjadi alarm

Input contoh:

```text
buat pengingat 1 jam ke depan
```

Perilaku yang diharapkan:

- Buat draft `reminder` dengan mode `notification`.
- Mode `alarm` hanya jika input eksplisit seperti `buat alarm`, `alarm nyaring`, atau user memilih Alarm pada UI.
- Draft harus memiliki judul, `scheduledAt/date`, `reminderMode`, dan `mode` yang konsisten.
- Setelah user melihat preview dan memilih konfirmasi, Asisten boleh mengeksekusi plan `draft -> save -> verify` secara lokal.
- Jangan mengubah/membuat transaksi keuangan.

### B. Pertanyaan halaman aktif salah menjawab Summary

Input contoh:

```text
jadi sekarang sedang di halaman apa
```

Masalah: Gemini Cloud bisa menjawab `Halaman Ringkasan` walaupun pengguna sedang berada di Aktivitas.

Perilaku yang diharapkan:

- `FfmAssistantPageContextController.currentDestination` adalah satu-satunya sumber kebenaran untuk halaman aktif.
- Pertanyaan label halaman aktif harus dijawab deterministik **sebelum** permintaan bebas dikirim ke Gemini Cloud.
- Jika konteks UI adalah `activity`, jawaban harus menyebut `Aktivitas`; tidak boleh fallback ke Summary.
- Navigasi dari chatbot harus menutup sheet, membuka halaman tujuan, dan halaman tujuan harus mengaktifkan `FfmAssistantPageContext`.

### C. Catatan Harian mengeluarkan JSON capability request

Input contoh:

```text
catatan harian isinya apa saja terbaru
```

Bug yang terjadi:

```json
{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.dailyNotes","arguments":{}}
```

Perilaku yang diharapkan:

- Gemini meminta `read.dailyNotes` melalui tool/read capability yang dibatasi.
- Orchestrator menjalankan capability secara lokal.
- Gemini lalu membuat jawaban natural dari evidence.
- Jika model mengulang capability request yang identik atau berhenti tanpa jawaban natural, tampilkan **evidence lokal** sebagai fallback aman.
- JSON internal tidak boleh masuk ke `FfmAssistantChatEntry.text` atau respons pengguna.

### D. Process trace bersifat template finansial

Masalah trace lama selalu memunculkan kalimat seperti:

```text
Membaca Data Finansial & Indeks Pencarian
Membaca Ringkasan Finansial & Saldo Aktif
Menghubungkan Profil Keluarga & Master Data
Memverifikasi Kebenaran Finansial & Grounding
```

Perilaku yang diharapkan:

- Pertanyaan halaman aktif: `Membaca konteks halaman aktif`.
- Catatan Harian: `Membaca konteks Catatan Harian`.
- Pengingat: `Membaca konteks Pengingat`.
- Pertanyaan finansial nyata baru boleh menyebut ringkasan finansial.
- Jangan mengatakan membaca data jika data tersebut tidak dipakai.

### E. UI Pengingat dan draft Asisten tidak sinkron

Masalah: halaman/form Pengingat lama tidak membawa semua nilai draft baru, terutama mode `notification` vs `alarm`.

Perilaku yang diharapkan:

- `ReminderPage` menerima prefill: judul, catatan, jadwal, recurrence, source, suara, dan mode.
- Dialog form menampilkan dropdown tipe pengingat:
  - `Notifikasi Biasa`
  - `Alarm Nyaring`
- Entitas yang disimpan mempertahankan mode terpilih.
- Pastikan schema/repository benar-benar memiliki dan menyimpan kolom mode bila fitur ini memang dipakai untuk membedakan perilaku notifikasi.

### F. Ringkasan belum punya penanda merah

Perilaku yang diharapkan:

- Ikon lonceng pada Halaman Ringkasan menampilkan badge merah bila ada riwayat pengingat berstatus `pending`, sudah `triggeredAt`, dan belum ditindaklanjuti.
- Badge berisi jumlah, maksimum tampilan `9+`.
- Klik badge membuka Halaman Pengingat.
- Badge berkurang/hilang setelah user memilih selesai atau tunda.

---

## File yang perlu diperiksa dan diperbaiki

| Area | File utama |
|---|---|
| Routing/context Cloud | `lib/features/assistant/data/ffm_assistant_interpreter.dart` |
| Knowledge routing | `lib/features/assistant/data/ffm_assistant_knowledge_index.dart` |
| Orchestrator capability Gemini | `lib/features/assistant/data/ffm_gemini_cloud_orchestrator.dart` |
| Parsing proposal JSON | `lib/features/assistant/data/ffm_assistant_proposal_json_service.dart` |
| Action plan save/verify | `lib/features/assistant/domain/ffm_assistant_action_planner.dart` |
| Konfirmasi chat | `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart` |
| Context halaman UI | `lib/features/assistant/presentation/widgets/ffm_assistant_page_context.dart` |
| Katalog halaman | `lib/features/assistant/domain/ffm_assistant_models.dart` |
| Form Pengingat | `lib/features/reminder/presentation/pages/reminder_page.dart` |
| Repository/schema Pengingat | `lib/features/reminder/data/repositories/reminder_repository.dart`, `lib/core/database/tables.dart`, migrasi Drift |
| Navigasi aplikasi | `lib/main.dart` |
| Badge Ringkasan | `lib/features/advisor/presentation/pages/summary_page.dart` |
| CI | `.github/workflows/flutter-ci.yml` |

---

## Instruksi implementasi

### 1. Prioritaskan context halaman aktif sebelum Gemini Cloud

- Temukan `_isCurrentPageRequest`, `_isCurrentPageLabelRequest`, dan `_currentPageContext`.
- Pada `interpret`, lakukan early return bila pertanyaan meminta label halaman aktif, `currentDestination != null`, dan tidak ada intent aksi eksplisit.
- Jalur ini harus berada sebelum blok general Gemini Cloud.
- Jangan ubah perintah aksi eksplisit menjadi pertanyaan context. Misalnya `buat aktivitas ...` tetap membuat draft aktivitas.

Acceptance:

- Dengan `currentDestination: FfmAssistantDestination.activity`, input `jadi sekarang sedang di halaman apa` menjawab Aktivitas.
- Gemini tidak dipanggil untuk kasus tersebut.

### 2. Perbaiki knowledge index

- Tambahkan source `page_context`.
- Keyword `catatan harian` dan `jurnal` harus menuju domain Aktivitas/Catatan Harian, bukan fallback `onboarding + summary`.
- Keyword halaman aktif harus menuju `page_context`, bukan Summary.
- Ubah label pengingat dari `Pengingat dan alarm` menjadi `Pengingat dan notifikasi`.

### 3. Pengingat default notifikasi

- Parser deterministic dan parser proposal Gemini wajib menulis:

```dart
'reminderMode': 'notification',
'mode': 'notification',
```

- Jika kata `alarm` eksplisit ditemukan atau UI memilih alarm, set keduanya menjadi `alarm`.
- Di katalog/teks bantuan jelaskan bahwa alarm bukan default.
- Jangan gunakan alarm sebagai sinonim default dari pengingat pada teks UX.

### 4. Konfirmasi dan penyimpanan dari chatbot

- Pastikan plan reminder punya urutan:

```text
read.reminders (jika diperlukan) -> draft.reminder -> mutate.save_draft -> verify.saved_draft
```

- Konfirmasi pengguna harus eksplisit setelah preview.
- Untuk `FfmAssistantDraftKind.reminder`, izinkan executor plan berjalan setelah konfirmasi chat.
- Dialog konfirmasi harus menyebut mode (`notifikasi biasa` atau `alarm nyaring`) dan judul pengingat.
- Tangani status plan gagal tanpa mengakses `failed.first` jika daftar gagal kosong.

### 5. Sinkronkan ReminderPage dengan draft

- Tambahkan/pertahankan parameter prefill `initialMode` pada `ReminderPage`, `_ReminderView`, dan `_ReminderDialog`.
- Pass mode dari `lib/main.dart` saat navigasi dari intent draft.
- Dropdown pada dialog harus memakai `ReminderMode.values` dan nilai existing/draft.
- Ketika save, masukkan `mode: _mode` ke `ReminderEntity`.

### 6. Verifikasi persistence mode

Ini wajib dicek karena UI/Entity saja tidak cukup.

- Periksa apakah tabel `Reminders` punya kolom `mode`.
- Jika belum ada, tambahkan `TextColumn get mode` dengan default `notification`.
- Tambahkan migrasi Drift yang aman untuk database lama.
- Perbarui `ReminderRepository.saveReminder` untuk menyimpan `entity.mode.storageValue`.
- Perbarui `_toReminder` untuk membaca `row.mode` dengan `ReminderModeX.fromStorage`.
- Tambahkan test repository/migration agar mode alarm tidak kembali menjadi notification setelah aplikasi dibuka ulang.

### 7. Cegah JSON capability request bocor

- Di `FfmGeminiCloudOrchestrator.run`, setelah setiap respons Gemini:
  - parse request capability;
  - jalankan hanya capability allowlisted;
  - berikan evidence ke Gemini pada turn berikutnya.
- Jika capability request identik muncul lagi, hentikan loop dan isi respons dengan evidence yang sudah didapat.
- Sebelum return success, parse sekali lagi. Bila teks akhir masih `read_capability_request`, ganti dengan fallback user-facing dari evidence.
- Jangan pernah mengembalikan payload JSON mentah ke layer chat.

### 8. Trace kontekstual

- Buat helper label progress berdasarkan intent/evidence scope.
- Jangan panggil `Membaca Ringkasan Finansial` bila `includeFinancialSummary == false`.
- Ganti label final menjadi netral, misalnya `Memverifikasi jawaban dengan konteks lokal`.

### 9. Badge merah Ringkasan

- Buat widget kecil, misalnya `_ReminderNotificationButton`.
- Amati tabel `reminderHistories` secara reaktif menggunakan Drift `watch()`.
- Hitung hanya record dengan:

```text
householdId = AppContext.householdId
triggeredAt IS NOT NULL
status = pending
```

- Lonceng tetap tampil tanpa badge saat jumlah 0.
- Saat jumlah > 0, tampilkan counter merah. Klik membuka `ReminderPage`.
- Tambahkan semantik/accessibility label.

### 10. GitHub Actions

Buat `.github/workflows/flutter-ci.yml`:

```yaml
name: Flutter CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

jobs:
  analyze-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter analyze lib test
      - run: flutter test
```

---

## Test regresi wajib

Tambahkan atau perbarui test berikut:

- `test/ffm_gemini_routing_test.dart`
  - Pertanyaan halaman aktif dengan destination Aktivitas tidak memanggil Gemini dan menjawab Aktivitas.
- `test/ffm_assistant_knowledge_index_test.dart`
  - Catatan Harian tidak memilih Summary fallback.
  - Pertanyaan halaman aktif memilih `page_context`, bukan Summary.
- `test/ffm_gemini_multi_function_and_grounding_test.dart`
  - Repeated `read.dailyNotes`/read request tidak mengembalikan JSON request.
  - Respons fallback berisi evidence lokal.
- Tambahkan test reminder:
  - `buat pengingat ...` menghasilkan mode `notification`.
  - `buat alarm ...` menghasilkan mode `alarm`.
  - mode tetap sama setelah repository save/read.
  - konfirmasi plan reminder menghasilkan save dan verify.
- Tambahkan widget test badge Ringkasan:
  - tidak tampil ketika tidak ada pending history;
  - tampil angka ketika ada pending triggered history;
  - klik membuka ReminderPage.

---

## Perintah verifikasi di PC atau GitHub Actions

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze lib test
flutter test
flutter build apk --target-platform android-arm64 --release
```

Jangan commit/push bila `flutter analyze` atau `flutter test` gagal.

## Checklist final

- [x] Pertanyaan halaman aktif memakai context UI aktual.
- [x] Gemini tidak dipanggil untuk label halaman aktif.
- [x] Catatan Harian dijawab natural, tanpa JSON internal.
- [x] `pengingat` default notifikasi.
- [x] `alarm` hanya eksplisit/user choice.
- [x] Mode reminder dipersistenkan di database.
- [x] Draft pengingat bisa dikonfirmasi dan disimpan dari chat.
- [x] UI Pengingat sesuai field draft.
- [x] Trace tidak mengklaim baca finansial untuk request non-finansial.
- [x] Badge merah Ringkasan hanya untuk pengingat pending yang benar-benar perlu tindakan.
- [x] CI GitHub Actions tersedia.
- [x] `flutter analyze lib test` lulus.
- [x] `flutter test` lulus.
- [x] Build Android arm64 release lulus.
