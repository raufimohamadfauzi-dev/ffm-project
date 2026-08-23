# Audit APK dan Kesiapan SLM

Tanggal audit: 23 Agustus 2026.

## Temuan utama

### 1. Download SLM gagal karena permission INTERNET tidak masuk APK

APK release sebelumnya memiliki tombol `Unduh dari GitHub` dan service HTTP, tetapi `aapt dump permissions` tidak menemukan `android.permission.INTERNET`. Akibatnya, request `HttpClient` untuk dua aset GGUF tidak dapat berjalan di Android. Source diperbaiki pada `android/app/src/main/AndroidManifest.xml` dengan menambahkan permission INTERNET.

URL GitHub yang dikunci di `FfmQwen2VlBundle` merespons HTTP 200 untuk aset model dan projector ketika diperiksa dari environment audit. Model sekitar 936 MB dan projector sekitar 1.33 GB, sehingga download membutuhkan jaringan stabil, ruang kosong cukup, dan waktu lama.

### 2. Import bundle tidak aman terhadap content URI Android

Implementasi lama di `ffm_local_model_service.dart` hanya mengambil `PlatformFile.path`. Pada Android Storage Access Framework, `PlatformFile.path` dapat bernilai null karena file disediakan sebagai URI non-file. Source kini memakai `PlatformFile.readAsByteStream()` dan menyalin stream ke file sementara di storage privat sebelum menjalankan validasi bundle. File besar tidak dimuat seluruhnya ke RAM.

### 3. SCHEDULE_EXACT_ALARM bukan keanehan yang boleh dihapus

Audit menemukan FFM memakai `AndroidScheduleMode.exactAllowWhileIdle` untuk pengingat pada `reminder_notification_service.dart`. Karena itu `android.permission.SCHEDULE_EXACT_ALARM` tetap dipertahankan. Service sudah memeriksa dan meminta permission exact alarm sebelum menjadwalkan pengingat. Permission ini tidak berkaitan dengan download SLM dan tidak berarti FFM memakai `ACTION_SET_ALARM`.

### 4. Error Model Manager terlalu mudah menjadi exception yang tidak informatif

Status awal, download, import, dan export kini memiliki fallback UI yang aman. Error teknis mentah tidak ditampilkan sebagai exception lengkap; pengguna menerima instruksi yang dapat ditindaklanjuti seperti memeriksa koneksi, ruang penyimpanan, format bundle, atau membuka ulang halaman.

### 5. Istilah training dan vendor eksternal membingungkan

Halaman “Pusat Latihan Asisten” sebenarnya menyimpan alias, aturan, contoh, dan knowledge pack yang disetujui; halaman tersebut tidak melatih ulang bobot Qwen. Label diubah menjadi “Pengetahuan Asisten (opsional)” dan penjelasan UI menyatakan bahwa review AI eksternal hanya opsional. Penyebutan Gemini/Claude pada laporan dan JSON transaksi diubah menjadi AI eksternal atau JSON batch. SLM lokal tetap menjadi jalur utama bila bundle telah terverifikasi.

### 6. Mismatch APK versus source

APK final yang diaudit dibuat sebelum perbaikan permission INTERNET dan content URI import. Oleh sebab itu APK tersebut tidak merepresentasikan source terbaru dan tidak boleh dianggap sebagai APK perbaikan. APK harus dibuild ulang hanya setelah source/test milestone ini selesai.

## Yang belum dapat diverifikasi tanpa perangkat

Audit source dan static APK tidak membuktikan file picker Android fisik, akses content URI dari Google Files/Files by Google, share sheet, download 2+ GB pada jaringan seluler, ruang storage penuh, permission exact alarm pada Android 14+, serta inference Qwen end-to-end. Semua itu memerlukan smoke test perangkat Android arm64.

## Status SLM tanpa bundle

Jika bundle belum terpasang atau manifest/hash/header tidak lolos, `FfmQwen2VlGateway` menolak inisialisasi native dan interpreter menggunakan aturan lokal/fallback. Model tidak dianggap siap hanya karena path lama atau metadata tidak lengkap.

## Sumber bukti source

- `android/app/src/main/AndroidManifest.xml`: permission jaringan, notifikasi, boot, dan exact alarm.
- `lib/features/assistant/data/ffm_local_model_service.dart`: URL, SHA-256, download streaming/resume, import bundle, dan content URI stream.
- `lib/features/assistant/presentation/pages/local_model_page.dart`: tombol download/import/export, progress, dan fallback error.
- `lib/features/reminder/data/services/reminder_notification_service.dart`: penggunaan exact alarm dan permission check.
- `lib/features/assistant/presentation/pages/assistant_training_page.dart`: controlled knowledge, approval, dan label baru.
