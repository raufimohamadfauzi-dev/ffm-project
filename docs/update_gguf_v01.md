# Update GGUF v01

## Sudah dikerjakan

User sekarang dapat memilih satu atau dua file `.gguf` sekaligus dari folder Download melalui tombol **Pilih GGUF dari Download**.

Aplikasi hanya menerima file yang hash, ukuran, dan header-nya cocok dengan model utama atau projector Qwen2-VL resmi. File lain ditolak. Setelah dua file cocok, keduanya masuk staging dan user menekan **Rakit dan Pasang SLM**.

User tidak perlu membuat folder, mengganti nama, membuat ZIP, atau menggabungkan file manual. `.ffmbundle` tetap dibuat oleh aplikasi melalui tombol Bagikan bundle setelah model terpasang dan terverifikasi.

## Validasi

Analyzer Dart lulus tanpa issue. Seluruh test Flutter lulus: 254 test.

Git lokal sudah menyimpan perubahan ini pada commit `cc403d0`.

APK dan test perangkat Android belum dibuat atau dijalankan.
