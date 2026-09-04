# Roadmap Pengembangan Lanjutan Agen Otonom FFM

Dokumen ini adalah dokumen master rencana pengembangan lanjutan untuk memperluas kapabilitas **Agen Otonom FFM (Family Finance Manager)** agar bekerja lebih proaktif, menjangkau komunikasi keluarga di luar aplikasi, dan beradaptasi dengan profil keuangan nyata pengguna (ritme pertanian & musiman).

Roadmap ini disusun berdasarkan urutan prioritas yang telah disepakati bersama: **1 ➡️ 4 ➡️ 3 ➡️ 2**.

---

## Ringkasan Master Checklist

- [x] **Fitur 01 (Prioritas 1)**: [Integrasi Telegram Bot Asisten Keluarga](#fitur-01---integrasi-telegram-bot-asisten-keluarga)
  - *Status*: Selesai Terverifikasi (100%)
  - *Dokumen Rincian*: [rencana_paket_telegram_bot_1.md](file:///c:/Users/naya/Documents/ffm-project/docs/utama/rencana_paket_telegram_bot_1.md)
  - *Ringkasan*: Laporan mingguan otomatis ke chat/grup Telegram Suami-Istri, peringatan instan radar boncos/anomali, dan integrasi frontend settings.
- [ ] **Fitur 02 (Prioritas 4)**: [Pendeteksi Notifikasi Pembayaran QRIS & Bank (Android Notification Listener)](#fitur-02---pendeteksi-notifikasi-pembayaran-qris--bank)
  - *Status*: Siap Dikerjakan (Dokumen Teknis Siap)
  - *Dokumen Rincian*: [rencana_paket_qris_notification_listener_4.md](file:///c:/Users/naya/Documents/ffm-project/docs/utama/rencana_paket_qris_notification_listener_4.md)
  - *Ringkasan*: Menangkap notifikasi pop-up pembayaran QRIS/m-banking di Android dan membuat draft transaksi 1-ketukan konfirmasi.
- [ ] **Fitur 03 (Prioritas 3)**: [Model Arus Kas Fleksibel & Siklus Pertanian / Musiman](#fitur-03---model-arus-kas-fleksibel--siklus-pertanian)
  - *Status*: Menunggu Penyelesaian Fitur 02
  - *Ringkasan*: Menghitung ketahanan modal dan cadangan kas keluarga (*Runway to Harvest*) tanpa asumsi kaku gajian tanggal 25.
- [ ] **Fitur 04 (Prioritas 2)**: [Akses Web Radar Pasar Terkini (Valuasi Emas & Kurs Valas)](#fitur-04---akses-web-radar-pasar-terkini)
  - *Status*: Menunggu Penyelesaian Fitur 03
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

### Fitur 04 - Akses Web Radar Pasar Terkini (Emas & Kurs)
* **Tujuan**: Memperbarui valuasi aset riil keluarga secara otomatis setiap hari.
* **Target Kemampuan**:
  1. Penjadwalan fetch harian data pasar publik (harga emas batangan Antam/Pegadaian per gram).
  2. Auto-kalkulasi nilai portofolio aset logam mulia pada total Kekayaan Bersih (*Net Worth*).
  3. Laporan wawasan pertumbuhan aset bulanan.

---

## Prosedur Pelaksanaan

1. Pengerjaan dilakukan secara terfokus satu per satu dimulai dari **Fitur 01 (Telegram Bot)**.
2. Setiap kali suatu sub-item selesai dan lolos pengujian (unit test & analisis statis), checkbox `[ ]` di dokumen rincian dan dokumen induk ini akan diperbarui menjadi `[x]`.
3. Tidak ada rilis build APK sebelum diizinkan oleh pengguna.
