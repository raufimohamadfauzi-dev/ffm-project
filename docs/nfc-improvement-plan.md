# Rencana Perbaikan NFC FFM

## Fakta Implementasi Saat Ini

- Metadata kartu dan snapshot NFC disimpan di database lokal; `SharedPreferences` tidak lagi dipakai oleh runtime NFC.
- Data kartu belum terhubung ke `accounts` pada Data Utama.
- Scan pertama hanya menyimpan saldo baseline.
- Scan berikutnya hanya menghitung selisih saldo dan membuat `PaymentDraft`.
- Tombol `Simpan Transaksi` saat ini hanya mengubah status draft menjadi `confirmed`; belum menulis ke tabel `transactions`.
- Saldo kartu tidak menyediakan riwayat transaksi per transaksi.
- Reader Android mencoba APDU beberapa kartu e-money, tetapi belum membuktikan dukungan semua varian kartu.
- KTP belum didukung dan tidak boleh diperlakukan sebagai kartu e-money.

## Target Pengalaman Pengguna

1. Pengguna cukup menempelkan kartu dan menekan tombol yang tersedia.
2. Aplikasi mengenali issuer/jenis kartu dari data chip jika memungkinkan.
3. Pengguna tidak perlu mengisi profil e-money secara manual.
4. Jika rekening FFM yang cocok belum ada, aplikasi membuat atau menyiapkan rekening secara otomatis dengan nama issuer.
5. Jika saldo tidak dapat dibaca, aplikasi tetap menyimpan identitas issuer tanpa mengarang saldo.
6. Setiap transaksi yang akan disimpan tetap melalui preview dan konfirmasi pengguna.

## Desain Data

- Tambahkan tabel metadata kartu NFC yang memiliki `accountId`, issuer, tipe kartu, identifier yang di-hash, saldo terakhir, dan waktu scan terakhir.
- Tambahkan tabel snapshot scan untuk menyimpan saldo dan periode scan.
- Hubungkan metadata kartu ke rekening pada `accounts`, bukan membuat saldo finansial terpisah.
- Simpan transaksi hasil konfirmasi di tabel `transactions` dengan `source = nfc` dan `sourceId` yang idempotent.
- Jangan menyimpan UID kartu mentah bila hash sudah cukup untuk identifikasi.

## Aturan Periode Auto-Draft

- Scan pertama pada sebuah kartu menjadi baseline dan tidak membuat transaksi.
- Baseline baru dibuat pada awal bulan atau ketika pengguna memilih reset periode.
- Scan dalam bulan yang sama menghitung selisih dari snapshot terakhir yang valid.
- Draft diberi tanggal scan dan label sebagai agregat NFC, bukan riwayat transaksi resmi.
- Scan atau konfirmasi yang sama tidak boleh menghasilkan duplikasi.
- Jika saldo turun, buat draft pengeluaran; jika saldo naik, buat draft top-up/transfer.
- Jika saldo tidak tersedia atau hasil baca tidak valid, jangan membuat draft nominal.

## Dukungan Kartu

- E-money hanya boleh dianggap didukung setelah diuji pada perangkat nyata per issuer dan varian kartu.
- Kartu debit/kredit dapat dideteksi sebatas teknologi/issuer/AID yang terlihat oleh chip.
- Saldo kartu debit/kredit tidak boleh diasumsikan tersedia melalui NFC; biasanya memerlukan layanan bank atau autentikasi tambahan.
- Jika saldo tidak tersedia, tampilkan nama bank/issuer dan status “saldo tidak tersedia melalui NFC”.
- Unknown NFC tag harus ditampilkan sebagai tag tidak dikenal, bukan dipaksa menjadi kartu bank.

## KTP dan Privasi

- KTP bukan target tahap pertama.
- Pembacaan KTP membutuhkan protokol, autentikasi, dasar hukum, dan pengujian keamanan terpisah.
- Jangan mengirim data KTP ke Gemini, Supabase, atau layanan eksternal.
- Jangan menyimpan NIK mentah; gunakan enkripsi lokal dan simpan data minimum bila fitur resmi disetujui.
- Akses data identitas harus dilindungi PIN/biometrik serta memiliki fungsi hapus permanen.

## Tahapan Implementasi

1. Tandai ketersediaan saldo dari hasil pembacaan NFC dan cegah nominal palsu untuk kartu tanpa saldo. **Selesai tahap awal.**
2. Migrasikan metadata kartu ke database lokal dan hubungkan ke `accounts`. **Selesai: runtime NFC menggunakan database sebagai sumber tunggal.**
3. Tambahkan resolver issuer dan pembuatan/link rekening otomatis.
4. Tambahkan snapshot bulanan dan batas periode auto-draft. **Selesai: snapshot database dan baseline otomatis bulan baru tersedia.**
5. Implementasikan adapter konfirmasi NFC ke `SaveTransaction` dengan idempotency.
6. Perbaiki parser APDU berdasarkan spesifikasi dan matriks pengujian perangkat nyata.
7. Tambahkan test unit, integrasi database, dan test duplikasi/pergantian bulan.
8. Dokumentasikan dukungan aktual per kartu; jangan menyatakan semua kartu didukung sebelum validasi.

## Kriteria Selesai

- Scan NFC dapat membuat atau menghubungkan rekening tanpa form profil manual.
- Saldo yang tidak tersedia tidak pernah diganti dengan angka tebakan.
- Konfirmasi draft benar-benar membuat satu transaksi utama.
- Auto-draft hanya menggunakan periode yang ditentukan dan tidak menggandakan transaksi.
- Kartu debit/kredit yang tidak memberi saldo tetap dapat menampilkan issuer secara jujur.
- KTP tetap terlindungi dan tidak diaktifkan sebelum persyaratan keamanan terpenuhi.
