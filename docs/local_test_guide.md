# Menjalankan Test FFM Secara Lokal

Panduan ini memverifikasi source FFM dari GitHub tanpa membuat APK, AAB, atau data keuangan contoh. Jalankan seluruh perintah dari **terminal** pada komputer pengembang.

## Prasyarat

Proyek saat ini memakai Flutter **3.47.0** dan Dart **3.13.0**; `pubspec.yaml` juga meminta SDK Dart `^3.13.0`. Gunakan Flutter stable yang kompatibel dan pastikan `flutter doctor` tidak menunjukkan masalah utama pada SDK atau toolchain platform yang ingin dipakai.

| Pemeriksaan | Perintah |
|---|---|
| Flutter dan Dart | `flutter --version` |
| Kondisi toolchain | `flutter doctor -v` |
| Git | `git --version` |

## Ambil Source Terbaru

Clone sekali bila proyek belum ada. Bila sudah pernah clone, gunakan blok pembaruan agar checkout lokal tidak menimpa pekerjaan Anda yang belum disimpan.

```bash
git clone https://github.com/raufimohamadfauzi-dev/ffm-project.git
cd ffm-project
git checkout main
git pull --ff-only origin main
flutter pub get
```

Untuk clone yang sudah ada:

```bash
cd ffm-project
git status -sb
git fetch origin
git log --oneline HEAD..origin/main
git pull --ff-only origin main
flutter pub get
```

> Jangan memakai `git reset --hard` bila ada file atau perubahan lokal yang ingin disimpan. Selesaikan, commit, atau pindahkan perubahan tersebut terlebih dahulu.

## Jalankan Pemeriksaan Bertahap

Mulai dari analyzer. Setelah itu jalankan regresi area yang baru diubah bila ingin iterasi cepat, lalu jalankan suite penuh secara serial sebagai validasi checkpoint.

```bash
# 1. Pemeriksaan statis seluruh source.
flutter analyze

# 2. Regresi fokus cooldown saran proaktif.
flutter test --concurrency=1 \
  test/ffm_assistant_proactive_service_test.dart \
  test/ffm_assistant_proactive_cooldown_test.dart

# 3. Seluruh suite, satu test proses pada satu waktu.
flutter test --concurrency=1
```

Perintah terakhir adalah perintah yang menghasilkan **497 test lulus** pada checkpoint `de295f3` di lingkungan validasi. Jumlah dapat bertambah setelah source atau test baru ditambahkan; yang penting adalah proses berakhir dengan `All tests passed!` dan exit code `0`.

## Bila Ada Kegagalan

Jangan menebak perbaikannya. Simpan keluaran terminal lengkap, lalu ulangi satu test yang disebutkan Flutter menggunakan perintah yang dicetak setelah kegagalan. Sebelum melaporkan masalah, kirimkan tiga informasi berikut: hash commit (`git log -1 --oneline`), keluaran `flutter --version`, dan error lengkap tanpa PIN, database keluarga, maupun file cadangan asli.

| Gejala | Tindakan aman |
|---|---|
| Dependency belum tersedia | Jalankan `flutter pub get`, lalu ulangi test. |
| Cache build bermasalah | Jalankan `flutter clean`, kemudian `flutter pub get` dan test lagi. Jangan hapus data aplikasi keluarga. |
| Test tertentu gagal | Jalankan hanya file test itu dengan `flutter test --concurrency=1 test/nama_file_test.dart`. |
| Peringatan Drift multi-database in-memory, font PDF Helvetica Unicode, atau diagnostik SLM tidak terdaftar pada test timeout | Catat sebagai baseline yang telah dikenal bila suite tetap lulus; bukan alasan untuk mengabaikan kegagalan test lain. |

## Batas Perintah Ini

Test lokal tidak sama dengan pengujian Android nyata. Notifikasi, deep link status bar, izin mikrofon/kamera, audio, PIN, file picker, dan model lokal tetap perlu diuji di perangkat memakai `android_device_validation_checklist.md`.
