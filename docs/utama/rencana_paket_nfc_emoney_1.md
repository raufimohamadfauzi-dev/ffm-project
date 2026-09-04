# Rencana Paket Teknis: Pembaca NFC e-Money & Adaptasi Saldo Otomatis (Fitur #1 / Prioritas P0)

Dokumen ini memuat rincian langkah teknis, arsitektur data, perintah APDU NFC, logika adaptasi selisih saldo, dan checklist pengerjaan untuk **Fitur #1: Pembaca NFC e-Money & Adaptasi Saldo Otomatis**.

---

## 1. Latar Belakang & Nilai Tambah

Dalam penggunaan harian di Indonesia, kartu e-Money fisik (*e-Money Mandiri, Flazz BCA, TapCash BNI, Brizzi BRI*) digunakan secara intensif untuk:
1. Gerbang Tol (Toll Roads).
2. Parkir Gedung / Mall.
3. Transportasi Umum (TransJakarta, MRT, LRT, Commuter Line).
4. Minimarket (Alfamart / Indomaret).

**Tantangan Utama:**
Kartu e-Money tidak mengirim notifikasi push ke HP saat bertransaksi di mesin pembaca tol/parkir. Pengguna sering kali tidak mengetahui berapa sisa saldo kartu mereka atau lupa mencatat pengeluaran tol/parkir.

**Solusi Otomatisasi FFM:**
Dengan menempelkan kartu e-Money ke sensor NFC belakang HP:
* FFM secara lokal membaca **ID Unik Kartu** dan **Sisa Saldo Terkini**.
* FFM membandingkan saldo baru dengan catatan saldo sebelumnya.
* Jika saldo berkurang, FFM secara otomatis menghitung selisihnya dan membuatkan **Draft Transaksi Pengeluaran (1-Ketukan)**:
  > *"Terdeteksi pengeluaran e-Money Rp 20.000 (Sisa Saldo: Rp 80.000). Simpan ke Kategori Transportasi/Parkir? [ ✅ Simpan ] [ ❌ Abaikan ]"*
* Jika saldo bertambah, FFM secara otomatis membuatkan **Draft Isi Ulang / Top-Up**.

---

## 2. Arsitektur Teknis & Flowchart Data

```
[ Kartu e-Money Ditempelkan ke NFC HP ]
                   │
                   ▼ (Android NFC Adapter)
[ FfmNfcReaderService.kt (Kotlin) ]
  ├── 1. Mencegat Intent NFC (IsoDep / NfcA)
  ├── 2. Mengirimkan Perintah APDU Pembacaan Saldo & ID Kartu
  └── 3. Mengembalikan Card ID & Balance (Rupiah) via MethodChannel
                   │
                   ▼
[ NfcCardRepository & Balance Adapter (Dart) ]
  ├── 1. Mengambil Catatan Saldo Terakhir Kartu dari Local Store
  ├── 2. Menghitung Selisih: (Saldo Lama - Saldo Baru)
  └── 3. Menentukan Jenis Mutasi: Pengeluaran (Debit) atau Top-Up (Credit)
                   │
                   ▼
[ PaymentDraftRepository (Local Store) ]
  └── Membuat objek `PaymentDraft` baru
                   │
                   ▼
[ UI Dialog Scan NFC & Kartu Konfirmasi Asisten (1-Ketukan) ]
  └── Tampilkan Banner: "[ ✅ Simpan Transaksi ] [ ✏️ Edit ] [ ❌ Abaikan ]"
```

---

## 3. Rincian Checklist Step-by-Step Pengerjaan

- [ ] **Tugas 1.1: Konfigurasi Android Manifest & Izin NFC**
  - Mendaftarkan izin `<uses-permission android:name="android.permission.NFC" />` di `AndroidManifest.xml`.
  - Mendaftarkan fitur hardware `<uses-feature android:name="android.hardware.nfc" android:required="false" />`.
  - Menambahkan filter teknologi NFC (`nfc_tech_filter.xml`) untuk mendukung `IsoDep` dan `NfcA`.

- [ ] **Tugas 1.2: Native Kotlin NFC Reader Service (`FfmNfcReaderService.kt`)**
  - Membuat class handler NFC di Kotlin yang meng-implement `NfcAdapter.ReaderCallback`.
  - Mengirim perintah APDU standar untuk pembacaan saldo kartu e-Money Indonesia:
    - e-Money Mandiri (Command APDU Balance & Card Serial)
    - Flazz BCA (Command APDU Balance & Card Serial)
    - BNI TapCash / BRI Brizzi (Command APDU Balance)
  - Penanganan error aman jika kartu dilepas terlalu cepat saat pemindaian.

- [ ] **Tugas 1.3: Jembatan MethodChannel Flutter (`nfc_bridge.dart`)**
  - Membuka channel komunikasi `ffm/nfc_reader` antara Flutter dan Android Native.
  - Menyediakan fungsi:
    - `isNfcAvailable()`: Memeriksa apakah HP memiliki sensor NFC.
    - `isNfcEnabled()`: Memeriksa apakah NFC sedang dalam posisi ON di HP.
    - `startNfcSession()`: Memulai mode pemindaian NFC.
    - `stopNfcSession()`: Menghentikan mode pemindaian NFC.

- [ ] **Tugas 1.4: Repositori Saldo Kartu & Engine Adaptasi Selisih (`nfc_card_repository.dart`)**
  - Entity `NfcCardAccount`:
    - `cardId` (ID Unik Kartu e-Money)
    - `cardType` (`mandiri_emoney`, `flazz_bca`, `bni_tapcash`, `bri_brizzi`)
    - `lastKnownBalance` (Saldo terakhir yang dicatat)
    - `lastScannedAt` (Waktu pemindaian terakhir)
  - Logika Selisih Saldo (*Adaptation Engine*):
    - Jika `newBalance < lastKnownBalance` $\rightarrow$ Hasilkan `PaymentDraft` Pengeluaran sebesar `lastKnownBalance - newBalance` (Saran Kategori: *Transportasi / Parkir*).
    - Jika `newBalance > lastKnownBalance` $\rightarrow$ Hasilkan `PaymentDraft` Top-Up sebesar `newBalance - lastKnownBalance`.
    - Mengoperasikan pembaruan `lastKnownBalance = newBalance`.

- [ ] **Tugas 1.5: Interaksi UI Scan NFC & Modal Konfirmasi Draft 1-Ketukan**
  - Membuat UI Modal BottomSheet / Dialog **"Tempelkan Kartu e-Money Anda"** dengan animasi visual NFC.
  - Menampilkan hasil pembacaan saldo dengan animasi sukses:
    - Status Saldo Terkini (misal: *Rp 80.000*).
    - Kartu Aksi Transaksi Terdeteksi (misal: *Pengeluaran Rp 20.000*).
  - Tombol Konfirmasi 1-Ketukan: `[ ✅ Simpan Transaksi ]`, `[ ✏️ Edit ]`, `[ ❌ Abaikan ]`.

- [ ] **Tugas 1.6: Pengujian Unit & Simulasi (`test/nfc_emoney_parser_test.dart`)**
  - Uji perhitungan selisih saldo untuk skenario pengeluaran tol.
  - Uji perhitungan selisih saldo untuk skenario isi ulang / top-up.
  - Uji penanganan kartu baru (scan pertama kali) yang belum memiliki riwayat saldo sebelumnya.

---

## 4. Batasan Keamanan & Privasi (Compliance `AGENTS.md`)

1. **100% Lokal di Perangkat:** Pembacaan NFC dan kalkulasi selisih saldo dilakukan sepenuhnya di dalam perangkat pengguna.
2. **Tidak Menyimpan Informasi Keuangan Sensitif:** Hanya membaca nilai nominal saldo publik di kartu dan ID unik kartu untuk membedakan antar kartu e-Money.
3. **Konfirmasi Eksplisit (1-Ketukan):** Perubahan saldo tidak pernah langsung mengubah database transaksi sebelum pengguna mengetuk **Simpan Transaksi**.
