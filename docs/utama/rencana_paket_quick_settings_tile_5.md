# Rencana Paket Teknis: Quick Settings Tile Bar Atas Android (Fitur #5 / Prioritas P2)

Dokumen ini memuat rincian langkah teknis, konfigurasi Android Service, penanganan intent pintasan, dan checklist pengerjaan untuk **Fitur #5: Quick Settings Tile (Bar Atas Android)**.

---

## 1. Latar Belakang & Nilai Tambah

Dalam penggunaan harian, pengguna sering kali ingin mencatat transaksi atau memindai kartu e-Money saat sedang berada di aplikasi lain (misal sedang membuka browser, Instagram, atau YouTube).

**Tantangan Utama:**
Harus kembali ke layar utama (*Home Screen*), mencari ikon FFM, dan membuka aplikasi membutuhkan beberapa langkah (high friction).

**Solusi Otomatisasi FFM:**
Menambahkan **Tombol Akses Cepat (*Quick Settings Tile*)** di panel notifikasi atas (*Control Center*) Android:
* Pengguna mengusap layar dari atas ke bawah di mana saja.
* Menggetuk tombol **"Catat FFM"** / **"Suara FFM"**.
* FFM langsung memicu perekam suara Asisten AI atau dialog catat cepat secara instan (1-ketukan dari mana saja).

---

## 2. Arsitektur Teknis

```
[ Usap Bar Atas HP Android & Ketuk Tile "Catat FFM" ]
                         │
                         ▼
[ FfmQuickTileService.kt (TileService) ]
  ├── 1. Menerima event `onClick()` dari Android Control Center
  └── 2. Menjalankan Intent / PendingIntent ke MainActivity
                         │
                         ▼
[ MainActivity.kt (Kotlin) ]
  └── Mengirimkan MethodChannel action: `"openQuickNote"` / `"openVoiceAssistant"`
                         │
                         ▼
[ FFM Assistant / Launcher UI (Flutter) ]
  └── Buka Perekam Suara Asisten AI / Dialog Catat Cepat secara instan
```

---

## 3. Rincian Checklist Step-by-Step Pengerjaan

- [ ] **Tugas 5.1: Konfigurasi Android Manifest & Quick Settings Service (`FfmQuickTileService.kt`)**
  - Mendaftarkan service di `AndroidManifest.xml` dengan permission `android.permission.BIND_QUICK_SETTINGS_TILE`.
  - Buat class `FfmQuickTileService.kt` yang meng-extend `TileService` (Android 7.0+ / API 24).
  - Penanganan state tile (`onStartListening`, `onClick`, `onStopListening`).

- [ ] **Tugas 5.2: Penanganan Intent Pintasan di `MainActivity.kt`**
  - Menangani peluncuran aktivitas dari tile saat layar terkunci atau terbuka.
  - Meneruskan aksi pintasan via `MethodChannel('ffm/widget')` / `ffm_quick_action`.

- [ ] **Tugas 5.3: Integrasi Handler Pintasan di Flutter (`ffm_assistant_global_launcher.dart`)**
  - Menangkap aksi pintasan saat aplikasi diluncurkan dari Quick Tile.
  - Membuka dialog perekam suara Asisten AI atau dialog pemindai NFC secara otomatis.

- [ ] **Tugas 5.4: Pengujian & Verifikasi Analysis**
  - Jalankan `flutter analyze lib test`.
  - Pengujian unit / simulasi intent pintasan tile.
