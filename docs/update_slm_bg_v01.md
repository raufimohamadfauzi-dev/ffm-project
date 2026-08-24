# Update SLM BG v01

## Sudah dikerjakan

Download SLM sekarang memiliki pilihan background Android. Model utama dan projector tetap diunduh ketika aplikasi diminimalkan, dengan progres di notifikasi HP.

Saat halaman Model Asisten Lokal dibuka kembali, aplikasi membaca hasil download. File selesai dipindahkan ke staging dan diverifikasi memakai hash, ukuran, dan header GGUF yang sama dengan impor manual. Pengguna tetap menekan Rakit dan Pasang SLM sebelum model dianggap aktif.

Tombol pembatalan download juga sudah ditambahkan. URL background memakai konfigurasi bundle yang sama dengan download biasa, sehingga tidak ada dua alamat model yang berbeda.

## Validasi

Analyzer Dart: lulus, No issues found.

Seluruh test Flutter: lulus, 254 test.

## Belum diuji

APK belum dibuat. Notifikasi dan download background belum diuji pada HP Android nyata. Build native Android juga belum dijalankan karena build APK hanya dilakukan setelah perintah pengguna.

Personal Life Manager belum dikerjakan pada update ini.
