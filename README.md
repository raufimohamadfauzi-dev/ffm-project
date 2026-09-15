# FFM - Family Finance Manager

FFM adalah aplikasi Flutter untuk pencatatan keuangan keluarga pada Android.
Project ini memiliki database lokal berbasis Drift/SQLite, fitur asisten, pencatatan
transaksi, aktivitas, anggaran, aset, tujuan, hutang/piutang, pengingat, backup,
dan integrasi Android tertentu.

## Status Project

- Versi aplikasi: `0.1.90+90`
- Package Android: `com.ffm_manager`
- Minimum Android: API 26
- Target release: Android ARM64 (`arm64-v8a`)
- SDK: Dart `^3.13.0`

Sebagian fitur bergantung pada izin Android, konfigurasi perangkat, API key,
koneksi jaringan, atau layanan pihak ketiga. Keberadaan kode dan dependency tidak
dianggap sebagai validasi end-to-end pada semua perangkat atau layanan tersebut.

## Komponen Utama

- Database lokal Drift/SQLite untuk data keuangan aplikasi.
- Asisten dan action plan dengan validasi aplikasi sebelum mutasi data.
- Parser notifikasi pembayaran lokal dan Android `NotificationListenerService`.
- Draft pembayaran yang dapat ditinjau, dikoreksi, lalu dikonfirmasi pengguna.
- Pembacaan NFC dan pencatatan aktivitas.
- Transaksi, rekening/dompet, kategori, anggaran, aset, tujuan, hutang, piutang,
  recurring transaction, dan pengingat.
- Backup/restore JSON serta ekspor PDF dan Excel.
- Integrasi opsional untuk Gemini Cloud, Supabase, notifikasi lokal, dan pekerjaan
  background sesuai konfigurasi aplikasi.

## Deteksi Pembayaran

Alur deteksi notifikasi pembayaran adalah:

```text
Android notification
    -> allowlist package
    -> parser lokal
    -> PaymentDraft tersimpan lokal
    -> review/edit pengguna
    -> konfirmasi pengguna
    -> transaksi disimpan ke database
```

Parser menolak notifikasi yang tidak memenuhi konteks transaksi, termasuk sebagian
notifikasi promo, saldo, OTP, keamanan, gagal, atau pending. Hasil parser adalah
kandidat/draft, bukan transaksi final. Pengguna tetap memegang kontrol untuk
mengubah nominal, merchant, dan tipe pemasukan/pengeluaran sebelum menyimpan.

Draft saat ini disimpan melalui `SharedPreferences`. Isi notifikasi mentah dapat
tersimpan sebagai bagian dari draft untuk audit dan koreksi lokal; aplikasi tidak
boleh mengirimkannya ke cloud kecuali melalui alur lain yang memang dikonfigurasi.

## Arsitektur Keamanan

- Model atau parser tidak menyimpan transaksi final secara langsung.
- Mutasi transaksi dilakukan oleh kode aplikasi melalui executor database.
- Draft pembayaran memerlukan konfirmasi eksplisit.
- Perhitungan nominal dan signed amount dilakukan oleh kode aplikasi.
- ID draft notifikasi dibuat menggunakan UUID.
- Package sumber notifikasi harus termasuk dalam allowlist parser dan Android.
- Akun dan kategori harus tersedia agar transaksi dapat disimpan dengan benar;
  pemilihan otomatis tetap perlu ditinjau pengguna.

## Struktur Direktori

```text
lib/
  core/       database, dependency injection, tema, keamanan, utilitas
  features/   assistant, transaksi, advisor, activity, budget, asset,
              goal, liability, receivable, reminder, backup, settings, dan lain-lain
android/      integrasi native Android dan NotificationListenerService
test/         unit test dan widget test
integration_test/
tool/         script validasi/build release
assets/       font dan branding aplikasi
```

## Setup

Prasyarat:

- Flutter SDK dengan Dart sesuai `pubspec.yaml`.
- Android SDK dan JDK 17 atau lebih baru.
- Perangkat/emulator Android API 26 atau lebih baru untuk pengujian Android.

```bash
git clone https://github.com/raufimohamadfauzi-dev/ffm-project.git
cd ffm-project
flutter pub get
```

## Validasi

```bash
flutter analyze lib test
flutter test
```

Test fokus untuk deteksi dan draft pembayaran:

```bash
flutter test test/payment_notification_parser_test.dart
flutter test test/pending_payment_drafts_card_test.dart
```

Test otomatis tidak menggantikan pengujian izin notifikasi, NFC, background
processing, koneksi cloud, atau perangkat Android nyata.

## Build Release

Target release resmi adalah Android ARM64:

```bash
flutter build apk --target-platform android-arm64 --release
```

Output standar Flutter:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Script `tool/build_release_arm64.sh` menambahkan pemeriksaan ABI, checksum, dan
signature jika dijalankan pada lingkungan yang menyediakan Android SDK, `zipinfo`,
dan `apksigner`. Jangan menyimpan API key, service credential, atau credential
signing ke repository.

## Batasan Validasi

- Keberhasilan analyzer/test tidak membuktikan semua integrasi hardware dan cloud.
- Kompatibilitas format notifikasi bank/e-wallet dapat berubah sewaktu-waktu.
- Parser notifikasi berbasis pola dapat memiliki false positive atau false negative;
  karena itu hasilnya selalu masuk ke draft review.
- Validasi perangkat nyata diperlukan untuk Notification Access, NFC, notifikasi
  background, kamera, dan layanan eksternal.

## Repository

GitHub: https://github.com/raufimohamadfauzi-dev/ffm-project
