# Audit Data Utama FFM — Baseline v24

## Ringkasan

Baseline FFM v24 sudah memiliki tabel dan halaman Data Utama, tetapi halaman lama belum menjadi pusat master data yang konsisten. Kekurangan utamanya adalah tidak adanya FAB yang selalu terlihat, CRUD belum lengkap, filter master aktif belum seragam, form rekening belum mendukung jenis rekening dan saldo awal secara lengkap, serta tag masih dapat diisi sebagai teks bebas pada form transaksi.

## Status per tab sebelum perbaikan

| Tab | Status baseline | Gap utama | Perbaikan yang diterapkan |
|---|---|---|---|
| Kategori | Ada daftar dan input dasar | Parent category tidak jelas, aksi daftar terbatas, filter aktif pada transaksi belum seragam | Editor jenis pemasukan/pengeluaran, induk opsional, FAB, edit, arsip, pencarian, validasi duplikasi |
| Toko/tempat | Ada tabel dan daftar | Detail belum dikelola dari UI, daftar dapat memuat data nonaktif | Editor detail, FAB, edit, arsip, pencarian, validasi duplikasi, filter aktif |
| Tag | Ada tabel dan chip pilihan | Form transaksi masih menerima tag bebas; filter tag aktif belum seragam | CRUD master, arsip, pencarian, chip pilihan aktif dari Data Utama; input tag bebas dihapus dari review batch/voice |
| Rekening | Ada tabel dan dipakai untuk saldo/transfer | Jenis rekening dan saldo awal belum lengkap di UI; loader transaksi tidak membatasi household | Editor Tunai/Bank/E-Wallet, saldo awal, FAB, edit, arsip, pencarian, filter household aktif |
| Sumber pemasukan | Disimpan sebagai transaction party | Bisa tercampur dengan pihak penggunaan; belum ada UI master detail yang jelas | Tab khusus sumber pemasukan, detail opsional, filter `kind=income_source`, FAB, edit, arsip, pencarian |
| Profil keluarga | Ada di database dan halaman lama | Belum cukup terlihat sebagai konteks Data Utama | Kartu profil di atas tab, edit profil, sinkronisasi Suami/Istri ke party rincian |

## Perbaikan P0 yang diterapkan

1. FAB `Tambah ...` selalu terlihat di halaman Data Utama dan berubah sesuai tab aktif.
2. Setiap daftar memiliki pencarian inline, pull-to-refresh, state kosong, state tidak ketemu, edit, dan arsip.
3. Arsip dipakai untuk master yang mungkin sudah dirujuk histori; transaksi lama tidak dihapus.
4. Nama master divalidasi terhadap duplikasi aktif pada household yang sama.
5. Rekening mendukung Tunai, Bank, E-Wallet, serta saldo awal opsional.
6. Sumber pemasukan dipisahkan dari `Dipakai oleh`; sumber menggunakan `kind=income_source`.
7. Kategori memiliki jenis pemasukan/pengeluaran dan induk kategori opsional.
8. Semua loader dropdown transaksi utama, form transaksi, quick entry, dan review voice dibatasi ke household lokal serta data master aktif.
9. Tag pada quick entry dan review voice hanya dipilih melalui chip dari Data Utama; tag baru tidak lagi dibuat diam-diam lewat teks bebas.
10. Profil nama rumah tangga, Suami, dan Istri tetap konteks keluarga tunggal dan disinkronkan sebagai rincian party.

## Hal yang sengaja tidak ditambahkan

Tidak ada cloud sync, AI otomatis, modul pertanian, pemisahan saldo Suami/Istri, transaksi dummy, atau nominal dummy. Seed kategori dasar tetap dipertahankan sesuai kontrak V1.

## Perbaikan lintas fitur yang diterapkan

- Halaman Anggaran hanya memuat kategori aktif milik household lokal.
- Ringkasan hanya menganggap rekening aktif dan kategori aktif sebagai Data Utama yang siap dipakai.
- Metadata ekspor pintar dibatasi ke household yang diminta dan menyertakan status aktif/arsip untuk analisis histori.
- Filter kategori pada laporan hanya menampilkan kategori aktif household lokal.
- Label laporan dan bundle analisis dibatasi ke household lokal, sementara master arsip tetap dipertahankan agar transaksi lama tetap bisa diterjemahkan.
- Backup penuh database tidak diubah karena memang harus membawa histori dan data arsip untuk restore.

## Validasi final

- `flutter analyze`: `No issues found!`.
- `flutter test`: **19 test lulus**.
- Formatting Dart selesai pada seluruh file yang diubah.
- `git diff --check` tidak tersedia pada hasil ekstraksi karena ZIP baseline tidak menyertakan folder `.git`; pemeriksaan sintaks dan style dilakukan melalui formatter serta analyzer.
- Tidak ada perubahan schema Drift; schema v24 sudah menyediakan kolom yang dibutuhkan.

## Catatan distribusi

APK tidak dibuat ulang pada tahap ini. Keystore dan `key.properties` tidak dimasukkan ke ZIP source. Package ID tetap `com.ffm_manager`, nama aplikasi tetap `FFM`, dan fitur V1 tetap 100% offline-first.

**Status:** Implementasi P0 dan penyamaan dropdown/laporan selesai; source siap dikemas menjadi ZIP baru setelah pemeriksaan file akhir.
