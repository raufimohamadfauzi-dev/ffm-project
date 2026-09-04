# Rencana Paket Teknis: Pendeteksi Notifikasi Pembayaran QRIS & Bank (Fitur 02 / Prioritas 4)

Dokumen ini memuat rincian langkah teknis, arsitektur data, izin sistem Android, regex parser, dan checklist implementasi untuk **Fitur 02 (Prioritas 4 dalam urutan 1 ➡️ 4 ➡️ 3 ➡️ 2): Pendeteksi Notifikasi Pembayaran QRIS & Bank**.

---

## 1. Latar Belakang & Nilai Tambah

Dalam keseharian rumah tangga modern di Indonesia, mayoritas pengeluaran harian terjadi melalui:
1. **QRIS** di warung, pasar modern, kafe, dan minimarket (Alfamart/Indomaret).
2. **Transfer m-Banking** (BCA, Livin' Mandiri, BRImo, Wondr BNI).
3. **E-Wallet** (GoPay, OVO, DANA, ShopeePay).

**Tantangan Utama:**
Saat berada di kasir atau sedang bertransaksi di jalan, pengguna sering kali tidak sempat membuka aplikasi FFM untuk mencatat manual. Akibatnya, transaksi terlupakan dan saldo riil menjadi selisih dengan catatan di aplikasi.

**Solusi Otomatisasi FFM:**
Dengan memanfaatkan Android `NotificationListenerService`:
* FFM secara lokal menangkap notifikasi keberhasilan pembayaran dari aplikasi perbankan/e-wallet.
* Parser lokal mengekstrak **nominal pengeluaran**, **nama toko/merchant**, dan **rekening sumber**.
* FFM membuatkan **Draft Transaksi Interaktif (1-Ketukan)**:
  > *"Terdeteksi QRIS Rp 45.000 di Kopi Kenangan via BCA. Simpan Transaksi? [ ✅ Simpan ] [ ❌ Abaikan ]"*
* **100% Sesuai Aturan AGENTS.md:** Transaksi tidak pernah dimutasi secara diam-diam tanpa persetujuan pengguna. Selalu ada konfirmasi eksplisit 1-ketukan.

---

## 2. Arsitektur Teknis

```
[ Notifikasi HP dari Bank/E-Wallet ]
       │
       ▼ (Android OS)
[ FfmNotificationListenerService (Kotlin) ]
       │ (Cek Whitelist Package Name: BCA, Mandiri, BRI, GoPay, dll)
       ▼
[ PaymentNotificationParser (Dart) ]
       │ (Regex Ekstraksi: Nominal, Merchant, Jenis Mutasi Masuk/Keluar)
       ▼
[ PaymentDraftRepository (Drift / Local Store) ]
       │
       ├──► Munculkan Notifikasi Interaktif: "[ ✅ Simpan ] [ ❌ Abaikan ]"
       └──► Tampilkan Banner di Beranda / Asisten Inbox: "1 Transaksi Baru Siap Disimpan"
```

---

## 3. Rincian Sub-Tugas & Checklist Pengerjaan

- [ ] **Tugas 4.1: Konfigurasi Android Manifest & Service Kotlin (`FfmNotificationListenerService.kt`)**
  - Mendaftarkan service di `AndroidManifest.xml` dengan permission `android.permission.BIND_NOTIFICATION_LISTENER_SERVICE`.
  - Membuat class `FfmNotificationListenerService.kt` yang meng-extend `NotificationListenerService`.
  - Filter whitelist paket aplikasi terpercaya:
    - BCA Mobile (`com.bca`) & myBCA (`com.bca.mybca`)
    - Livin' by Mandiri (`com.bankmandiri.livin`)
    - BRImo (`id.co.bri.brimo`)
    - BNI Mobile / Wondr (`id.bni.mobile`, `id.co.bni.wondr`)
    - GoPay (`com.gojek.app`, `com.gopay.wallet`)
    - OVO (`ovo.id`)
    - DANA (`id.dana`)
    - ShopeePay (`com.shopee.id`)
  - Komunikasi ke Flutter via `EventChannel` / `MethodChannel` saat aplikasi aktif, atau penyimpanan buffer aman saat aplikasi di background.

- [ ] **Tugas 4.2: Pemeriksa & Pemicu Izin Android (`NotificationAccessBridge`)**
  - Menyediakan fungsi cek status izin: `isNotificationListenerEnabled()`.
  - Menyediakan intent buka layar pengaturan Android: `openNotificationListenerSettings()`.

- [ ] **Tugas 4.3: Engine Regex Ekstraksi Pembayaran (`payment_notification_parser.dart`)**
  - Regex deteksi nominal uang Indonesia:
    - Mendukung variasi: `Rp 45.000`, `Rp. 120.500`, `IDR 50,000`, `sebesar Rp 25.000`.
  - Regex deteksi Merchant / Lawan Transaksi:
    - Contoh: `"Pembayaran QRIS ke KOPI KENANGAN berhasil"` -> Merchant: `KOPI KENANGAN`.
    - Contoh: `"Transfer Rp 150.000 ke BUDI SANTOSO berhasil"` -> Penerima: `BUDI SANTOSO`.
    - Contoh: `"Kamu telah membayar Rp 24.000 di INDOMARET"` -> Merchant: `INDOMARET`.
  - Pemetaan Otomatis Rekening:
    - Notifikasi dari BCA -> otomatis pasang akun pembayaran `BCA`.
    - Notifikasi dari GoPay -> otomatis pasang akun pembayaran `GoPay`.
  - Rekomendasi Kategori Otomatis:
    - Keyword resto/makanan/kopi -> Kategori *Makanan & Minuman*.
    - Keyword alfamart/indomaret/supermarket -> Kategori *Kebutuhan Rumah Tangga*.
    - Keyword bensin/spbu/pertamina -> Kategori *Transportasi*.

- [ ] **Tugas 4.4: Model & Repositori Draft Transaksi (`payment_draft_repository.dart`)**
  - Entity `PaymentDraft`:
    - `id`, `sourceApp`, `rawTitle`, `rawContent`, `amount`, `merchantName`, `suggestedCategoryId`, `detectedAccountId`, `createdAt`, `status` (`pending`, `confirmed`, `dismissed`).
  - Pencegahan Duplikasi (*Deduplication*):
    - Mencegah notifikasi berulang mencatat draft ganda dalam rentang waktu singkat (5 menit yang sama).

- [ ] **Tugas 4.5: Antarmuka Pengaturan & Panduan Izin (`payment_detector_settings_page.dart`)**
  - Navigasi di menu *Lainnya* -> **Pendeteksi Bayar Otomatis (QRIS & Bank)**.
  - Status Izin Sistem (Aktif / Belum Diizinkan) dengan tombol panduan buka pengaturan Android.
  - Checklist filter aplikasi (bisa memilih bank/e-wallet mana yang ingin dipantau).
  - Riwayat tangkapan draft transaksi.

- [ ] **Tugas 4.6: Integrasi Konfirmasi 1-Ketukan di Beranda / Kotak Masuk Asisten**
  - Saat ada draft `pending`, tampilkan kartu interaktif di Beranda:
    - Kartu: *"Ditemukan pembayaran QRIS Rp 45.000 di Kopi Kenangan via BCA."*
    - Tombol: `[ ✅ Simpan ]` langsung mencatat transaksi tanpa form panjang.
    - Tombol: `[ ✏️ Edit ]` membuka form transaksi dengan isian yang sudah terisi otomatis.
    - Tombol: `[ ❌ Abaikan ]` menghapus draft.

- [ ] **Tugas 4.7: Pengujian Unit Komprehensif (`test/payment_notification_parser_test.dart`)**
  - Uji parser terhadap format notifikasi nyata dari 8 bank dan e-wallet Indonesia (BCA, Mandiri, BRI, BNI, GoPay, OVO, Dana, Shopee).
  - Uji penanganan string acak / non-transaksi (notifikasi promo, notifikasi login, notifikasi keamanan) agar tidak salah deteksi (*zero false positives*).
  - Uji deduplikasi transaksi.

---

## 4. Batasan Keamanan & Privasi (AGENTS.md Compliance)

1. **Privasi 100% Lokal di Perangkat:** Pemrosesan teks notifikasi dilakukan sepenuhnya di dalam perangkat pengguna menggunakan regex lokal. Tidak ada teks notifikasi atau data perbankan yang dikirim ke server luar atau cloud.
2. **Whitelist Ketat:** Hanya membaca notifikasi dari package ID perbankan dan e-wallet resmi. Notifikasi WhatsApp, SMS pribadi, email, dan aplikasi lain sepenuhnya diabaikan.
3. **Pemisahan Notifikasi Transaksi vs OTP:** Regex dirancang secara spesifik hanya menangkap notifikasi keberhasilan pembayaran (*payment success*). Notifikasi kode OTP atau verifikasi keamanan **wajib diabaikan** demi keamanan perbankan pengguna.
4. **Authoritative Execution Boundary:** Draft yang terdeteksi tidak langsung memotong saldo rekening atau mengubah database transaksi sebelum pengguna mengetuk tombol **Simpan Transaksi**.
