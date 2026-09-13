# Identitas build pada diagnostik

- Versi dan nomor build dibaca dari paket aplikasi terpasang melalui `package_info_plus`, kemudian disimpan bersama setiap error.
- Setiap APK yang dibagikan harus memiliki nomor build baru. Dua APK dengan versi/nomor yang sama dan tanpa metadata commit tidak dapat dibedakan oleh diagnostik.
- Commit opsional dapat disertakan pada build dari source yang sudah di-commit dan working tree bersih:

  ```powershell
  $commit = git rev-parse HEAD
  flutter build apk --target-platform android-arm64 --release --dart-define=FFM_BUILD_COMMIT=$commit
  ```

- Jangan mengisi commit HEAD untuk source yang masih memiliki perubahan lokal: itu akan mengidentifikasi kode yang berbeda. Bila tidak disertakan, laporan menyatakan commit tidak tersedia.
- Log lama tanpa metadata tetap berstatus build tidak diketahui. Identitas APK terbaru tidak ditambahkan secara retroaktif.
- Retensi dijalankan ketika log dibaca atau error dicatat: maksimum 30 hari dan 100 catatan terbaru. Penghapusan manual tetap tersedia.
- Riwayat build lain disembunyikan dalam bagian yang dapat dibuka; laporan salin tetap menyertakan seluruh log yang masih dalam retensi, identitas masing-masing build, dan waktu UTC.
- Tidak adanya error baru bukan bukti bahwa alur telah diuji atau perbaikan telah berhasil. Cocokkan identitas build dengan perubahan kode dan hasil uji ulang.
