# Rencana Paket Teknis: Integrasi Kalender Sistem & Smartwatch Sync (Fitur #2 / Prioritas P1)

Dokumen ini memuat rincian langkah teknis, arsitektur data, integrasi CalendarProvider Android, sinkronisasi ke smartwatch, dan checklist pengerjaan untuk **Fitur #2: Integrasi Kalender Sistem & Smartwatch Sync**.

---

## 1. Latar Belakang & Nilai Tambah

**Tantangan Utama:**
Pengguna FFM sering memiliki pengingat tagihan rutin (Listrik, Indihome, BPJS, Cicilan) yang hanya ada di dalam aplikasi FFM. Ketika pengguna sedang tidak membuka aplikasi atau sedang beraktivitas di luar rumah, pengingat tersebut tidak tembus ke notifikasi sistem Android dan tidak muncul di jam tangan pintar (*smartwatch*).

**Solusi Otomatisasi FFM:**
Dengan integrasi ke CalendarProvider Android:
* FFM otomatis membuat jadwal pengingat tagihan di Google Calendar HP saat Asisten AI mendeteksi atau pengguna mencatat pengingat.
* Sistem Android mempublikasikan pengingat ke Google Calendar yang terhubung dengan akun pengguna.
* Notifikasi pengingat/timer otomatis tembus ke jam tangan pintar (*Galaxy Watch, Garmin, Mi Band, Apple Watch*) pada waktu jatuh tempo.
* Pengguna dapat melihat jadwal tagihan di aplikasi Kalender HP dan di smartwatch tanpa harus membuka FFM.

---

## 2. Arsitektur Teknis & Flowchart Data

```
[ Asisten AI Mendeteksi / Pengguna Mencatat Pengingat Tagihan ]
                   │
                   ▼
[ AssistantCalendarService (Dart) ]
  ├── 1. Menerima data tagihan: nama, tanggal jatuh tempo, nominal, kategori
  ├── 2. Validasi dan normalisasi data tagihan
  └── 3. Memanggil Calendar Integration Service
                   │
                   ▼
[ CalendarIntegrationService (Dart + MethodChannel) ]
  ├── 1. Mengirimkan data tagihan ke Android Native via MethodChannel
  └── 2. Menangani error dan retry logic
                   │
                   ▼
[ FfmCalendarService.kt (Kotlin) ]
  ├── 1. Mengakses CalendarProvider Android
  ├── 2. Membuat Calendar Event baru di kalender utama pengguna
  ├── 3. Mengatur reminder/notifikasi (15 menit, 1 jam, 1 hari sebelum jatuh tempo)
  └── 4. Mengembalikan Event ID ke Flutter
                   │
                   ▼
[ Sinkronisasi Otomatis Android ]
  ├── 1. Android CalendarProvider mempublikasikan event ke Google Calendar
  ├── 2. Google Calendar sinkronisasi ke semua perangkat yang terhubung
  └── 3. Notifikasi tembus ke smartwatch (Galaxy Watch, Garmin, Mi Band, Apple Watch)
                   │
                   ▼
[ UI Konfirmasi & Manajemen Pengingat ]
  ├── 1. Menampilkan status sinkronisasi kalender
  ├── 2. Memberikan opsi untuk menghapus pengingat dari kalender
  └── 3. Menampilkan log history sinkronisasi
```

---

## 3. Rincian Checklist Step-by-Step Pengerjaan

- [x] **Tugas 2.1: Konfigurasi Android Manifest & Izin Kalender**
  - Mendaftarkan izin `<uses-permission android:name="android.permission.READ_CALENDAR" />` di `AndroidManifest.xml`.
  - Mendaftarkan izin `<uses-permission android:name="android.permission.WRITE_CALENDAR" />` di `AndroidManifest.xml`.
  - Menambahkan dependency `permission_handler` di pubspec.yaml.

- [x] **Tugas 2.2: Native Kotlin Calendar Service (`FfmCalendarService.kt`)**
  - Membuat class handler Calendar di Kotlin yang mengakses `CalendarContract`.
  - Implementasi fungsi untuk memeriksa apakah kalender tersedia:
    - `isAvailable()`: Memeriksa apakah HP memiliki kalender terinstall.
    - `getDefaultCalendarId()`: Mengambil ID kalender utama pengguna.
  - Implementasi fungsi untuk membuat event:
    - `createBillReminderEvent(title, description, dueDate, amount, category)`: Membuat event pengingat tagihan.
    - `updateBillReminderEvent(eventId, title, description, dueDate, amount, category)`: Mengupdate event yang sudah ada.
    - `deleteBillReminderEvent(eventId)`: Menghapus event dari kalender.
  - Penanganan error aman jika izin ditolak atau kalender tidak tersedia.

- [x] **Tugas 2.3: Jembatan MethodChannel Flutter (`calendar_bridge.dart`)**
  - Membuka channel komunikasi `ffm/calendar_service` antara Flutter dan Android Native.
  - Menyediakan fungsi:
    - `isCalendarAvailable()`: Memeriksa ketersediaan kalender.
    - `requestCalendarPermissions()`: Meminta izin baca/tulis kalender ke pengguna.
    - `createBillReminder(BillReminderData)`: Membuat pengingat tagihan di kalender.
    - `updateBillReminder(int eventId, BillReminderData)`: Mengupdate pengingat yang sudah ada.
    - `deleteBillReminder(int eventId)`: Menghapus pengingat dari kalender.
    - `getBillReminders(DateTime startDate, DateTime endDate)`: Mengambil daftar pengingat tagihan dalam rentang tanggal.

- [x] **Tugas 2.4: Repositori Pengingat Tagihan & Model Data (`bill_reminder_repository.dart`)**
  - Entity `BillReminder`:
    - `id` (ID lokal FFM)
    - `calendarEventId` (ID event di CalendarProvider Android)
    - `billName` (Nama tagihan: "Listrik", "Indihome", "BPJS", "Cicilan")
    - `description` (Deskripsi tagihan)
    - `dueDate` (Tanggal jatuh tempo)
    - `amount` (Nominal tagihan)
    - `category` (Kategori tagihan)
    - `reminderSettings` (Konfigurasi pengingat: 15 menit, 1 jam, 1 hari sebelum)
    - `isSyncedToCalendar` (Status sinkronisasi ke kalender)
    - `syncedAt` (Waktu sinkronisasi terakhir)
  - Logika Sinkronisasi:
    - Saat pengingat baru dibuat → Otomatis sync ke CalendarProvider.
    - Saat pengingat diupdate → Update event di CalendarProvider.
    - Saat pengingat dihapus → Hapus event dari CalendarProvider.
    - Retry logic jika sinkronisasi gagal (network error, permission denied).
  - Upgrade database schema ke versi 52 dengan kolom calendar integration.

- [x] **Tugas 2.5: Integrasi dengan Asisten AI untuk Auto-Deteksi Tagihan**
  - Modifikasi logic Asisten AI untuk mendeteksi pola pembicaraan tagihan rutin:
    - "Tagihan listrik tanggal 5 setiap bulan"
    - "Ingatkan saya bayar BPJS tanggal 20"
    - "Cicilan motor tanggal 15"
  - Asisten AI otomatis membuat `BillReminder` dan memicu sinkronisasi ke kalender.
  - Konfirmasi ke pengguna:
    > *"Saya akan membuat pengingat tagihan di kalender Anda. Jatuh tempo: 5 setiap bulan. Notifikasi akan tembus ke smartwatch. [ ✅ Buat Pengingat ] [ ❌ Batal ]"*
  - Integrasi CalendarBridge ke FfmAssistantReminderMutationService untuk sinkronisasi otomatis.

- [x] **Tugas 2.6: Interaksi UI Pengaturan & Manajemen**
  - Membuat halaman **"Pengaturan Kalender & Smartwatch"** di settings FFM.
  - Menampilkan status sinkronisasi kalender:
    - Status: "Terhubung ke Google Calendar ✅" atau "Tidak terhubung ❌"
    - Kalender yang digunakan: "Kalender Utama (Gmail: user@gmail.com)"
  - Menampilkan daftar pengingat tagihan yang sudah disinkronkan:
    - Nama tagihan
    - Tanggal jatuh tempo berikutnya
    - Status sinkronisasi (Terakhir sync: [waktu])
    - Tombol: [ 🗑️ Hapus dari Kalender ] [ ✏️ Edit ]
  - Tombol toggle: "Otomatis sinkronkan pengingat baru ke kalender"
  - Tombol aksi: "Sinkronisasi Ulang" untuk pengingat yang belum disinkronkan.

- [x] **Tugas 2.7: Pengujian Unit & Simulasi (`test/calendar_integration_test.dart`)**
  - Uji pola deteksi tagihan dari asisten AI.
  - Uji penambahan marker sinkronisasi kalender ke bill reminders.
  - Uji logika deteksi sync to calendar.
  - Uji struktur data model (BillReminderData, CalendarOperationResult).
  - Uji validasi schema database (kolom calendar integration).
  - Uji flow integrasi lengkap dari reminder creation ke calendar sync.
  - Uji penanganan error dan retry logic.
  - All tests passed (12/12 tests).

- [ ] **Tugas 2.8: Pengujian pada Smartwatch (Opsional tapi Disarankan)**
  - Uji notifikasi tembus ke Galaxy Watch Samsung.
  - Uji notifikasi tembus ke Garmin.
  - Uji notifikasi tembus ke Mi Band.
  - Uji notifikasi tembus ke Apple Watch (jika pengguna menggunakan iPhone + Android hybrid setup).

---

## 4. Batasan Keamanan & Privasi (Compliance `AGENTS.md`)

1. **Izin Eksplisit:** Meminta izin baca/tulis kalender kepada pengguna sebelum mengakses CalendarProvider.
2. **Data Minimal:** Hanya menyimpan data yang diperlukan untuk pengingat tagihan (nama, tanggal, nominal, kategori).
3. **Tidak Menyimpan Informasi Keuangan Sensitif:** Nominal tagihan hanya ditampilkan di judul/deskripsi event kalender untuk referensi, bukan detail transaksi lengkap.
4. **Kontrol Pengguna:** Pengguna dapat mematikan sinkronisasi kalender kapan saja melalui settings.
5. **Local-First untuk Data Transaksi:** Data transaksi asli tetap disimpan di database lokal FFM, kalender hanya untuk pengingat.
6. **Tidak Mengakses Calendar Lain:** Hanya menulis ke kalender utama pengguna, tidak membaca atau menghapus event lain di kalender.

---

## 5. Catatan Teknis Tambahan

1. **Kompatibilitas Smartwatch:**
   - Sinkronisasi ke smartwatch bergantung pada ekosistem masing-masing (Samsung, Garmin, Xiaomi, Apple).
   - Notifikasi akan tembus jika smartwatch terhubung ke HP Android yang sama dan sinkronisasi Google Calendar aktif.
   - Tidak memerlukan integrasi khusus per-vendor smartwatch karena menggunakan jalur standar Android CalendarProvider → Google Calendar → Smartwatch.

2. **Multi-Event untuk Tagihan Rutin:**
   - Untuk tagihan rutin bulanan, FFM akan membuat series event di Google Calendar (misal: setiap tanggal 5).
   - Pengguna dapat mengedit atau menghapus series tersebut langsung dari Google Calendar app.

3. **Offline Fallback:**
   - Jika network tidak tersedia, FFM tetap membuat pengingat lokal dan akan mencoba sinkronisasi ulang saat network kembali tersedia.
   - Pengingat lokal tetap akan muncul di dalam aplikasi FFM meskipun belum sinkron ke kalender.

4. **Handling Timezone:**
   - Semua pengingat menggunakan timezone lokal perangkat pengguna.
   - FFM menyesuaikan waktu pengingat sesuai timezone saat pengguna berpindah lokasi.

---

## 6. Prioritas Pengerjaan

Urutan pengerjaan yang disarankan:
1. Tugas 2.1: Konfigurasi Android Manifest & Izin Kalender
2. Tugas 2.2: Native Kotlin Calendar Service
3. Tugas 2.3: Jembatan MethodChannel Flutter
4. Tugas 2.4: Repositori Pengingat Tagihan & Model Data
5. Tugas 2.5: Integrasi dengan Asisten AI
6. Tugas 2.6: Interaksi UI Pengaturan & Manajemen
7. Tugas 2.7: Pengujian Unit & Simulasi
8. Tugas 2.8: Pengujian pada Smartwatch (Opsional)