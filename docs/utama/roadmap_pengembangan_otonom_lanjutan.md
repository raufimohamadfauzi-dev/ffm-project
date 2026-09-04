# Roadmap Pengembangan Lanjutan Agen Otonom FFM

Dokumen ini adalah dokumen master rencana pengembangan lanjutan untuk memperluas kapabilitas **Agen Otonom FFM (Family Finance Manager)** agar bekerja lebih proaktif, menjangkau komunikasi keluarga di luar aplikasi, dan beradaptasi dengan profil keuangan nyata pengguna (ritme pertanian & musiman).

Roadmap ini disusun berdasarkan urutan prioritas yang telah disepakati bersama: **1 ➡️ 4 ➡️ 3 ➡️ 2**.

---

## Ringkasan Master Checklist

- [x] **Fitur 01 (Prioritas 1)**: [Integrasi Telegram Bot Asisten Keluarga](#fitur-01---integrasi-telegram-bot-asisten-keluarga)
  - *Status*: Selesai Terverifikasi (100%)
  - *Dokumen Rincian*: [rencana_paket_telegram_bot_1.md](file:///c:/Users/naya/Documents/ffm-project/docs/utama/rencana_paket_telegram_bot_1.md)
  - *Ringkasan*: Laporan mingguan otomatis ke chat/grup Telegram Suami-Istri, peringatan instan radar boncos/anomali, dan integrasi frontend settings.
- [x] **Fitur 02 (Prioritas 4)**: [Pendeteksi Notifikasi Pembayaran QRIS & Bank (Android Notification Listener)](#fitur-02---pendeteksi-notifikasi-pembayaran-qris--bank)
  - *Status*: Selesai Terverifikasi (100%) ✅
  - *Ringkasan*: Menangkap notifikasi pop-up pembayaran QRIS/m-banking/e-wallet di Android dan membuat draft transaksi 1-ketukan konfirmasi di Beranda & Pengaturan.
- [x] **Fitur 03 (Prioritas 3)**: [Model Arus Kas Fleksibel & Siklus Pertanian / Musiman](#fitur-03---model-arus-kas-fleksibel--siklus-pertanian)
  - *Status*: Selesai Terverifikasi (100%) ✅
  - *Ringkasan*: Menghitung ketahanan modal dan cadangan kas keluarga (*Runway to Harvest*) tanpa asumsi kaku gajian tanggal 25 serta batas belanja aman dapur harian.
- [ ] **Fitur 04 (Prioritas 2)**: [Akses Web Radar Pasar Terkini (Valuasi Emas & Kurs Valas)](#fitur-04---akses-web-radar-pasar-terkini)
  - *Status*: Siap Dikerjakan (Dokumen Rencana Teknis Siap)
  - *Dokumen Rincian*: [rencana_paket_radar_pasar_emas_valas_4.md](file:///c:/Users/naya/Documents/ffm-project/docs/utama/rencana_paket_radar_pasar_emas_valas_4.md)
  - *Ringkasan*: Mengambil harga resmi emas Antam/Pegadaian & kurs harian untuk memperbarui valuasi nilai kekayaan bersih keluarga secara otomatis.

---

## Rincian Strategis Setiap Modul

### Fitur 01 - Integrasi Telegram Bot Asisten Keluarga
* **Tujuan**: Menghubungkan kecerdasan FFM dengan kanal komunikasi utama keluarga (Telegram), sehingga suami dan istri mendapatkan transparansi keuangan tanpa beban harus selalu membuka aplikasi.
* **Target Kemampuan**:
  1. Pengiriman otomatis *Laporan Mingguan Keuangan Keluarga* (setiap akhir pekan).
  2. Pengiriman peringatan instan (*Alarm Boncos*) saat pengeluaran melonjak atau pos anggaran menipis.
  3. Form pengaturan Bot Token & Chat ID di menu Pengaturan FFM disertai tombol *Tes Kirim Pesan*.
  4. (Fase Lanjutan) Pencatatan cepat pengeluaran/pemasukan lewat chat Telegram.
* **Kepatuhan AGENTS.md**: Bot hanya bertindak sebagai kanal pelaporan dan penyiapan draft. Tidak ada mutasi saldo tanpa persetujuan pengguna.

---

### Fitur 02 - Pendeteksi Notifikasi Pembayaran QRIS & Bank
* **Tujuan**: Mengotomasi pencatatan transaksi saat pengguna berbelanja via QRIS atau transfer bank di Android.
* **Target Kemampuan**:
  1. Memanfaatkan Android `NotificationListenerService` resmi.
  2. Mengenali notifikasi dari perbankan dan e-wallet populer Indonesia (BCA, Mandiri, BRI, BNI, GoPay, OVO, Dana, ShopeePay).
  3. Mengekstrak nominal, nama merchant/toko, dan rekening sumber.
  4. Memunculkan notifikasi interaktif 1-ketukan: `[ ✅ Simpan Transaksi ]` atau `[ ❌ Abaikan ]`.

---

### Fitur 03 - Model Arus Kas Fleksibel & Siklus Pertanian
* **Tujuan**: Mengadaptasi algoritma kesehatan finansial FFM untuk pengguna dengan arus kas musiman/pertanian yang tidak mengandalkan gaji bulanan tanggal 25.
* **Target Kemampuan**:
  1. Parameter target masa panen / penjualan komoditas (misal: estimasi panen 3–4 bulan ke depan).
  2. Perhitungan *Runway Musim Panen*: Memantau apakah kas operasional kebun + kebutuhan dapur keluarga mencukupi hingga hasil panen tiba.
  3. Batas belanja harian adaptif (*Safe-to-Spend Daily Limit*).

---

### Fitur 04 - Akses Web Radar Pasar Terkini (Emas Karat, Valas, Kripto) & Radar Warta Terpilih [x] Selesai Terverifikasi (100%) ✅
* **Tujuan**: Memperbarui valuasi aset riil keluarga (Emas batangan 24K, perhiasan 22K/18K/16K/10K, Valas USD/SGD/EUR/SAR, dan Kripto) serta menyediakan radar warta berita pertanian, BMKG, dan finansial.
* **Target Kemampuan**:
  1. [x] Fetch HTTP hening (<0.2s) harga pasar publik & kurs valas tanpa API key berbayar.
  2. [x] Standar kadar karat emas Indonesia (24K, 22K, 18K, 16K, 10K) dengan kalkulator valuasi deterministik.
  3. [x] Radar Berita & Peringatan Terpilih (Pertanian, BMKG Bencana/Cuaca, Finansial) dengan cache SharedPreferences sementara (auto-prune >48 jam, bebas database).
  4. [x] Ticker harga horizontal & asisten valuasi pasar di halaman Aset.
  5. [x] Halaman `MarketNewsRadarPage` (2 tab: Harga & Warta) dengan pengaturan kata kunci peringatan khusus.
  6. [x] Drawer kiri (`MarketNewsRadarDrawer`) yang dapat ditarik/digeser ke kanan dari layar utama untuk intip cepat warta dan pasar.

---

## Prosedur Pelaksanaan

1. Pengerjaan dilakukan secara terfokus satu per satu dimulai dari **Fitur 01 (Telegram Bot)**.
2. Setiap kali suatu sub-item selesai dan lolos pengujian (unit test & analisis statis), checkbox `[ ]` di dokumen rincian dan dokumen induk ini akan diperbarui menjadi `[x]`.
3. Tidak ada rilis build APK sebelum diizinkan oleh pengguna.
