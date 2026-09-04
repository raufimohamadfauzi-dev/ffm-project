# Rencana Lanjutan Fitur Akses Perangkat Android (NFC, Kalender & Quick Settings)

Dokumen ini memuat peta jalan pengembangan 3 fitur utama akses perangkat Android yang diprioritaskan untuk memperkuat otomatisasi dan kapabilitas **Asisten AI FFM (Family Finance Manager)**.

---

## 1. Urutan Prioritas & Garis Besar Fitur

| Prioritas | Nama Fitur | Komponen Android OS | Nilai Tambah bagi Asisten FFM |
| :---: | :--- | :--- | :--- |
| **P0 (Ke-1)** | **NFC e-Money Reader & Adaptasi Saldo Otomatis** | `android.permission.NFC`, `NfcAdapter`, `IsoDep` | Membaca saldo kartu fisik e-Money/Flazz saat ditempelkan ke HP, lalu secara otomatis menghitung selisih saldo (pengeluaran / top-up) dan membuatkan draft transaksi. |
| **P1 (Ke-2)** | **Integrasi Kalender Sistem & Smartwatch Sync** | `android.permission.WRITE_CALENDAR`, `CalendarProvider` | Menyinkronkan jatuh tempo tagihan ke Google Calendar HP, sehingga pengingat/timer tembus ke luar aplikasi hingga ke jam tangan pintar (*smartwatch*). |
| **P2 (Ke-3)** | **Quick Settings Tile (Bar Atas Android)** | `android.service.quicksettings.TileService` | Menambahkan tombol pintas di Control Center (bar notifikasi atas HP) untuk memicu perekaman suara atau catat cepat FFM dalam 1 ketukan dari mana saja. |

---

## 2. Rincian Konsep Fitur

### A. Fitur 1: NFC e-Money Reader & Adaptasi Saldo Otomatis
- **Target Kartu:** e-Money Mandiri, Flazz BCA, TapCash BNI, Brizzi BRI.
- **Alur Kerja:**
  1. Pengguna menempelkan kartu fisik ke bagian belakang HP.
  2. Native Kotlin NFC Service membaca *Card ID* unik dan sisa saldo dalam Rupiah.
  3. FFM membandingkan saldo terbaru dengan catatan saldo sebelumnya untuk kartu yang sama.
  4. Jika saldo berkurang (misal $\text{Rp } 100.000 \rightarrow \text{Rp } 80.000$), FFM secara otomatis mendeteksi **Pengeluaran Rp 20.000** (Kategori otomatis: *Transportasi / Parkir / Tol*).
  5. Jika saldo bertambah, FFM mendeteksi **Top-Up / Isi Ulang**.
  6. Menyajikan **Draft Transaksi 1-Ketukan** untuk disetujui pengguna.

---

### B. Fitur 2: Integrasi Kalender Sistem & Smartwatch Sync
- **Target Integrasi:** Google Calendar & Android System Calendar Provider.
- **Alur Kerja:**
  1. Saat Asisten AI mendeteksi atau pengguna mencatat pengingat tagihan/rutin (misal: *Listrik, Indihome, BPJS, Cicilan*), FFM membuat jadwal di `CalendarProvider`.
  2. Sistem Android otomatis mempublikasikan pengingat ke Google Calendar.
  3. Notifikasi pengingat/timer otomatis tembus ke jam tangan pintar (*Galaxy Watch, Garmin, Mi Band, Apple Watch*) pada waktu jatuh tempo.

---

### C. Fitur 5: Quick Settings Tile (Bar Atas Android)
- **Target Akses:** Panel *Control Center / Notification Shade* Android.
- **Alur Kerja:**
  1. FFM mendaftarkan `TileService` resmi di sistem Android.
  2. Pengguna dapat menambahkan tombol **"Catat FFM"** / **"Suara FFM"** di bar atas HP.
  3. Ketika diketuk saat pengguna sedang berada di aplikasi lain (Instagram, YouTube, Browser), FFM langsung membuka dialog catat cepat/perekam suara Asisten AI.

---

## 3. Dokumen Rincian Eksekusi

Rincian langkah demi langkah (*step-by-step*) dengan checklist untuk masing-masing paket teknis disimpan secara terpisah:
- **Paket Teknis Fitur #1 (NFC e-Money):** [`docs/utama/rencana_paket_nfc_emoney_1.md`](file:///C:/Users/naya/Documents/ffm-project/docs/utama/rencana_paket_nfc_emoney_1.md) *(Fokus Pengerjaan Pertama)*.
- **Paket Teknis Fitur #2 (Kalender & Smartwatch):** [`docs/utama/rencana_paket_kalender_smartwatch_2.md`](file:///C:/Users/naya/Documents/ffm-project/docs/utama/rencana_paket_kalender_smartwatch_2.md) *(Menyusul setelah Fitur #1 selesai)*.
- **Paket Teknis Fitur #5 (Quick Settings Tile):** Menyusul setelah Fitur #2 selesai.
