# FFM History, Search, and Retention Plan

## Tujuan

Membuat seluruh riwayat FFM dapat dicari berdasarkan tanggal, kategori, teks,
dan filter lain tanpa batas waktu buatan seperti hanya satu bulan atau 100
baris. Data lama harus tetap dapat ditemukan dari halaman aplikasi maupun
Assistant, tanpa membuat aplikasi memuat seluruh database ke memori sekaligus.

Ruang lingkup utama:

- Transaksi dan transfer.
- Sesi aktivitas timer.
- Catatan aktivitas/history.
- Catatan Harian (`dailyNotes`).
- Pencarian dan filter dari Assistant.
- Arsip, ekspor, dan penghapusan data lama dengan kontrol pengguna.

## Status Implementasi

Audit terbaru per fase (per 2026-09-10):

### SELESAI (Phase 0, 2, 3, 5)

- Model periode bersama `FfmDatePeriod` + `FfmDatePeriodPreset` (12 preset)
  dengan `fromText`, `startOrEpoch`, `endOrMax`, end-exclusive, dan unit test.
- Parser periode dipakai di UI (filter Transaksi, halaman Aktivitas) dan query
  Assistant (`_activityPeriodBounds` lama diganti `FfmDatePeriod.fromText()`).
- Preset periode di filter sheet Transaksi (dropdown "Periode cepat").
- Filter range dan preset periode di halaman Aktivitas.
- `GetTransactionsPage` use case dengan limit/offset/date, terdaftar di DI,
  punya unit test pagination.
- `ActivityQueryLayer.queryEntriesPage()` dan `queryDailyNotesPage()` dengan
  limit/offset/date (belum dipakai UI — lihat tanggung jawab aktif).
- Pagination transaksi di halaman daftar: infinite scroll (threshold 300px) +
  tombol "Muat lebih banyak", `hasMore`, loading spinner, `ScrollController`.
- Grouping bulanan transaksi (`_buildGroupedTimeline`) dan aktivitas
  (`_buildGroupedSessionCards` + `_activityMonthLabel`).
- Tab sumber halaman Aktivitas: Semua / Timer / Catatan / Jurnal Harian /
  Otonom, lengkap dengan badge dan filter periode.
- Query Assistant untuk aktivitas dan catatan berdasarkan periode.
- Archive manager transaksi (`ArchiveManagerPage`) dengan pagination, select
  all/individual, restore, dan hapus permanen berkonfirmasi ganda.
- Semua test suite hijau (1339/1339) dan `flutter analyze lib test` bersih.
- **Migrasi reminder (schema 55→57) sudah ada di working tree** — menambah kolom
  `sourceType`, `sourceId` (schema 56) dan `origin` (schema 57) pada tabel
  `reminders`. Error `sourceType/sourceId` yang tadinya mengganjal worktree
  **sudah tuntas** (`dart analyze` bersih untuk `reminder_repository.dart`,
  `app_database.dart`, `tables.dart`).

### INDEX DATABASE — status terverifikasi 2026-09-10

Beberapa index **sudah ada** via `_createXIndexes()` di `app_database.dart`,
sisanya belum:

| Tabel | Index | Status |
|---|---|---|
| `transactions` | `(household_id, date, is_archived, is_deleted)` | ❌ BELUM ADA |
| `activity_sessions` | `(household_id, started_at, is_archived)` | ⚠️ PARSIAL — ada `(household_id, started_at)` tanpa `is_archived` |
| `activity_sessions` | `idx_activity_sessions_household_category`, `_group`, `_subject` | ✅ ADA |
| `activity_entries` | `(household_id, started_at, is_archived)` | ⚠️ PARSIAL — ada `(household_id, started_at, activity_type)` tanpa `is_archived` |
| `daily_notes` | `(household_id, note_date, is_archived)` | ✅ ADA (`idx_daily_notes_household_date`) |
| `tasks`, `daily_routines`, `schedule_entries`, dll. | berbagai index household | ✅ ADA |

Yang tersisa: tambahkan index compound `transactions (household_id, date,
is_archived, is_deleted)` melalui migration Drift, dan pastikan kolom
`is_archived` masuk index `activity_sessions`/`activity_entries`.

### BELUM DIKERJAKAN / PERLU DILANJUTKAN BESOK

- **Phase 3 (transaksi) — transfer tidak difilter di DB.**
  `transfers` dimuat penuh hanya dengan `isDeleted = false`, lalu difilter
  UI-side via `_matchesDateRange`. Pagination transfer tidak konsisten dengan
  filter periode di `_loadTransactions`. Perlu query transfer berpagination
  dengan tanggal di DB.
- **Phase 4 — menghubungkan UI Aktivitas ke query layer berpagination.**
  Halaman Aktivitas masih memakai `ActivityRepository.getSessions()/getEntries()/
  getDailyNotes()` yang memuat seluruh data non-arsip sekaligus. `ActivityQueryLayer
  .queryEntriesPage()`/`queryDailyNotesPage()` sudah ada dan terdaftar di DI
  (`injection.dart:226`) tetapi belum dipakai UI/Bloc. Filter hari/range
  (`_matchesDay`) hanya UI-side, bukan query ke DB. Belum ada infinite scroll/
  load-more untuk Aktivitas (tidak seperti Transaksi).
- **Phase 6 — batch arsip lintas entity.**
  Belum ada "Arsipkan semua data sebelum tanggal ..." dengan preview jumlah per
  jenis (transaksi + aktivitas + catatan harian). `ArchiveManagerPage` hanya
  mencakup transaksi.
- **Phase 6 — bulk permanent delete dengan backup gate.**
  `ArchiveManagerPage` punya hapus permanen berkonfirmasi ganda + audit log + baca
  ulang, TAPI belum ada gate "wajib backup/export sebelum penghapusan massal".
  Belum ada preview jumlah per jenis, dan belum ada flow "hapus permanent massal"
  versi lintas entity (hanya transaksi per item di arsip).
- **Phase 5 — deep link halaman dengan filter periode.**
  Assistant belum dapat mengirim deep link agar halaman langsung terbuka pada
  periode yang diminta.
- **Phase 7 — performance testing.**
  Belum ada benchmark database 1.000/10.000/100.000 records untuk ukur waktu
  query halaman pertama, search, filter, scroll.

## Keputusan Produk

### Tidak ada auto-delete dua tahun

FFM tidak boleh otomatis menghapus transaksi, aktivitas, atau catatan hanya
karena umur data sudah melewati dua tahun.

Alasannya:

- Riwayat keuangan dapat dibutuhkan untuk audit, pajak, perbandingan, dan
  keputusan keluarga.
- Penghapusan otomatis berisiko menghilangkan data yang masih penting.
- Data lama tidak membuat riwayat tidak rapi jika UI memiliki filter, grouping,
  dan pagination yang benar.

### Arsip berbeda dari hapus

- **Arsip** menyembunyikan data dari tampilan default, tetapi tetap dapat
  dicari melalui filter "termasuk arsip" dan tetap dapat dipulihkan.
- **Hapus permanen** hanya boleh dilakukan setelah preview, konfirmasi kuat,
  dan penjelasan dampak.
- Retensi default untuk transaksi adalah **tidak terbatas**.
- Retensi aktivitas dan catatan juga **tidak terbatas**, kecuali user memilih
  mengarsipkan atau menghapusnya.

### Unlimited bukan berarti unlimited memory

User boleh memasukkan rentang tanggal sejauh apa pun dan mencari semua hasil,
tetapi aplikasi tidak boleh mengambil jutaan baris sekaligus.

Implementasi yang benar:

- Query dilakukan di database.
- Hasil dikirim dalam halaman/cursor, misalnya 50 atau 100 baris per batch.
- Scroll berikutnya mengambil batch berikutnya.
- Search dan filter tetap berlaku di database, bukan hanya pada data yang sudah
  terlanjur dimuat.
- Tidak boleh ada batas waktu maksimum seperti "hanya dua tahun terakhir"
  untuk pencarian user.

## Kondisi Saat Ini

### Transaksi

- Data transaksi aktif saat ini dimuat sekaligus dan diurutkan berdasarkan
  tanggal terbaru.
- Sudah ada filter bulan berjalan dan rentang tanggal custom.
- Sudah ada filter jenis, rekening, kategori, merchant, pemilik, dan search.
- Belum ada preset cepat "tahun lalu", "3 bulan terakhir", atau "semua waktu".
- Perlu memastikan query default mengecualikan data `isArchived` dan
  `isDeleted` secara konsisten.

### Aktivitas

- Halaman sudah memiliki tab riwayat, filter kategori, mode Timer/Catatan,
  pencarian teks, dan pemilih satu tanggal.
- Belum ada filter rentang tanggal.
- Repository saat ini mengambil seluruh sesi dan entry aktif/non-arsip tanpa
  pagination.
- `ActivityQueryLayer` sudah memiliki dukungan filter tanggal, status, jenis,
  kategori, keyword, limit, dan offset, tetapi belum menjadi sumber utama
  halaman UI.

### Catatan

FFM memiliki dua konsep yang harus ditampilkan dengan jelas:

- Catatan/history pada sesi Aktivitas.
- Catatan Harian pada tabel `dailyNotes`.

Keduanya tidak boleh tercampur secara diam-diam. UI harus memberi label sumber
data agar user tahu apakah hasil berasal dari Aktivitas atau Catatan Harian.

### Assistant

- Query periode aktivitas dan catatan sudah dapat diproses secara deterministik
  dari database lokal.
- Gemini Cloud hanya boleh menerima context bounded dan capability read-only.
- Assistant harus memakai query database untuk filter tanggal, bukan meminta
  Gemini menebak atau menyaring daftar yang tidak lengkap.

## Desain Target

### Kontrak rentang waktu bersama

Buat satu model/parser periode yang dipakai halaman, query tools, dan Assistant.

Preset yang wajib didukung:

- Hari ini.
- Kemarin.
- Minggu ini.
- Bulan ini.
- Bulan lalu.
- 3 bulan terakhir.
- 6 bulan terakhir.
- 1 tahun terakhir.
- Tahun ini.
- Tahun lalu.
- Semua waktu.
- Rentang custom.

Definisi harus eksplisit:

- "1 tahun terakhir" berarti rolling period dari tanggal yang sama satu tahun
  sebelumnya sampai hari ini.
- "Tahun lalu" berarti 1 Januari sampai 31 Desember tahun kalender sebelumnya.
- End date memakai batas eksklusif agar data sepanjang hari terakhir tidak
  terpotong.

### Query database dan pagination

Tambahkan query repository/data layer yang konsisten:

- `householdId` wajib menjadi filter pertama.
- Default mengecualikan data archived/deleted.
- Filter tanggal dilakukan di SQL/Drift.
- Sorting stabil: tanggal terbaru lalu ID sebagai tie-breaker.
- Dukungan `limit`, `offset` atau cursor.
- Dukungan total count atau `hasMore`.
- Dukungan keyword, kategori, jenis, akun, status, dan sumber data.

Index yang perlu dievaluasi dan ditambahkan melalui migration:

- Transactions: `(householdId, date, isArchived, isDeleted)`.
- Activity sessions: `(householdId, startedAt, isArchived, status)`.
- Activity entries: `(householdId, startedAt, isArchived)`.
- Daily notes: `(householdId, noteDate, isArchived)`.

Jangan menambahkan index tanpa memeriksa schema Drift dan migration test.

### Halaman Transaksi

Perbaikan:

- Pertahankan filter custom yang sudah ada.
- Tambahkan preset periode yang sama dengan kontrak bersama.
- Tambahkan pilihan "Semua waktu".
- Ubah loading menjadi database pagination/infinite scroll.
- Tampilkan grouping berdasarkan bulan, misalnya `September 2026` dan
  `Agustus 2026`.
- Tampilkan jumlah hasil dan label periode aktif.
- Search harus tetap bekerja pada seluruh rentang yang dipilih, bukan hanya
  baris yang sudah dimuat.
- Transfer harus mengikuti filter tanggal dan akun yang sama.
- Sediakan tombol clear filter yang mengembalikan semua waktu.

Acceptance criteria:

- Transaksi dari lima tahun lalu dapat ditemukan dengan rentang custom.
- Hasil ke-101 dan seterusnya dapat dimuat tanpa mengubah filter.
- Tidak ada query yang mengambil seluruh transaksi ke memory untuk sekadar
  menampilkan halaman pertama.
- Transaksi archived/deleted tidak muncul pada default view.

### Halaman Aktivitas dan Catatan

Perbaikan:

- Ganti filter satu hari menjadi filter periode bersama.
- Pertahankan kemampuan memilih satu hari sebagai custom range satu hari.
- Tambahkan preset tahun lalu, 1 tahun terakhir, 3 bulan, dan semua waktu.
- Hubungkan halaman ke `ActivityQueryLayer` atau repository baru yang memiliki
  pagination; jangan membuat implementasi query kedua di widget.
- Gabungkan tampilan riwayat dengan source badge:
  - Aktivitas Timer.
  - Catatan Aktivitas.
  - Catatan Harian.
- Sediakan tab/filter sumber agar user dapat memilih satu jenis saja.
- Tambahkan grouping berdasarkan bulan.
- Search harus mencakup judul, isi/catatan, kategori, subject, dan keyword yang
  memang tersedia pada sumber data.
- Tampilkan empty state yang membedakan "tidak ada data pada periode ini" dan
  "data tersedia tetapi tidak cocok dengan keyword".
- Tambahkan pilihan "termasuk arsip" hanya jika user memang ingin melihat
  data arsip.

Acceptance criteria:

- Aktivitas atau catatan tahun lalu dapat ditemukan tanpa mengetahui tanggal
  tepatnya.
- Hasil lebih dari 100 per kategori dapat dimuat bertahap sampai selesai.
- Data aktivitas Timer dan Catatan tidak hilang hanya karena jenis filter
  halaman berubah.
- Catatan Harian tetap dapat dibedakan dari catatan sesi Aktivitas.

### Assistant dan Orchestrator

Perbaikan:

- Pertanyaan yang dapat dijawab dari database lokal harus memakai query
  deterministik terlebih dahulu.
- Parser periode Assistant harus memakai kontrak periode bersama dengan UI.
- Tambahkan query untuk:
  - `transaksi tahun lalu`.
  - `aktivitas 1 tahun terakhir`.
  - `catatan harian 3 bulan terakhir`.
  - `aktivitas kategori Kebun tahun lalu`.
- Assistant boleh mengembalikan hasil bertahap atau ringkasan jumlah ketika
  hasil terlalu banyak, lalu menawarkan filter yang lebih spesifik.
- Gemini tidak boleh menerima seluruh riwayat mentah. Gemini hanya menerima
  evidence bounded yang sudah difilter oleh aplikasi.
- Capability read harus memvalidasi rentang tanggal dan tetap read-only.
- Jika user meminta membuka halaman, Assistant dapat mengirim deep link/context
  filter agar halaman langsung terbuka pada periode yang diminta.

Contoh perilaku:

- User: "Cari semua transaksi tahun lalu."
- Assistant: menghitung rentang tahun kalender lalu secara lokal, menampilkan
  ringkasan dan tombol buka riwayat transaksi dengan filter tersebut.
- User: "Aktivitas kebun 2024."
- Assistant: melakukan query database berdasarkan rentang tanggal dan kategori,
  bukan mengandalkan daftar 5 atau 10 item terbaru.

## Retensi, Arsip, dan Hapus

### Arsip lama

Tambahkan fitur opsional:

- "Arsipkan semua data sebelum tanggal ...".
- Preview jumlah data per jenis sebelum eksekusi.
- Konfirmasi eksplisit.
- Arsip dapat dibatalkan/dipulihkan.
- Default list tidak menampilkan arsip.
- Search advanced dapat memilih "termasuk arsip".

Arsip adalah rekomendasi untuk merapikan tampilan, bukan kewajiban retensi.

### Hapus permanen

Hapus permanen sebaiknya tersedia, tetapi tidak otomatis dan tidak menjadi
solusi default untuk performa.

Persyaratan:

- Wajib preview jumlah dan jenis data yang terdampak.
- Wajib backup/export sebelum penghapusan massal.
- Wajib konfirmasi kedua, misalnya mengetik `HAPUS PERMANEN`.
- Jelaskan relasi yang ikut terdampak, seperti item transaksi, checkpoint,
  attachment, dan relasi aktivitas.
- Jangan menghapus data hanya dari UI tanpa executor dan verification.
- Catat audit event penghapusan tanpa menyimpan isi sensitif yang tidak perlu.
- Setelah penghapusan, baca ulang database untuk memastikan data benar-benar
  hilang dan relasi tidak rusak.

Rekomendasi kebijakan awal:

- Transaksi: arsip manual atau tidak terbatas; hapus permanen hanya manual.
- Aktivitas/catatan: arsip manual atau berdasarkan tanggal yang dipilih user.
- Tidak ada job background yang otomatis menghapus data dua tahun lalu.

## Tahapan Implementasi

### Phase 0: Kontrak dan inventaris

- Dokumentasikan entity, archive flag, delete flag, dan relasi tiap sumber.
- Satukan definisi periode dan end-exclusive.
- Tetapkan apakah `Catatan Aktivitas` dan `Catatan Harian` tampil bersama atau
  hanya melalui tab sumber.
- Tambahkan regression tests untuk perilaku lama.

### Phase 1: Query layer dan migration

- Tambahkan query paginated transaksi.
- Lengkapi `ActivityQueryLayer` untuk sessions, entries, dan daily notes.
- Tambahkan query count/hasMore.
- Tambahkan index melalui migration Drift.
- Uji household isolation, archive exclusion, date boundaries, sorting, dan
  pagination.

### Phase 2: Shared period service

- Implementasikan parser periode tunggal.
- Tambahkan unit test untuk semua preset, leap year, timezone/local date, dan
  batas akhir hari.
- Gunakan parser yang sama di UI, query tools, dan Assistant.

### Phase 3: Halaman Transaksi

- Tambahkan preset dan label periode.
- Implementasikan pagination/infinite scroll.
- Tambahkan grouping bulanan dan total hasil.
- Pastikan transfer dan search mengikuti query yang sama.

### Phase 4: Halaman Aktivitas/Catatan

- Tambahkan filter range/preset.
- Hubungkan UI ke query layer.
- Tampilkan source badge dan grouping bulanan.
- Tambahkan pagination serta filter termasuk arsip.
- Pastikan Catatan Harian dapat ditemukan tanpa harus mengetahui tanggal tepat.

### Phase 5: Assistant integration

- Tambahkan query periodik untuk semua entity yang relevan.
- Tambahkan deep link halaman dengan filter periode.
- Pastikan response tetap deterministic dan grounded.
- Tambahkan Gemini bounded-read tests dengan rentang eksplisit.

### Phase 6: Arsip dan hapus permanen

- Buat preview archive/delete.
- Buat confirmation policy dan capability executor.
- Buat verification dan audit log.
- Tambahkan restore archive.
- Tambahkan backup/export gate untuk bulk permanent delete.

### Phase 7: Performance dan release validation

- Uji database dengan 1.000, 10.000, dan 100.000 records.
- Ukur waktu query halaman pertama, search, filter, dan scroll berikutnya.
- Pastikan penggunaan memory tidak tumbuh sebanding dengan seluruh riwayat.
- Jalankan:

```bash
flutter analyze lib test
flutter test
flutter build apk --target-platform android-arm64 --release
```

## Definition of Done

- User dapat mencari data dari tanggal berapa pun yang masih tersimpan.
- Hasil lebih dari 100 item dapat dimuat sampai selesai melalui pagination.
- Tidak ada batas waktu tersembunyi pada query default atau Assistant.
- Transaksi, Aktivitas, Catatan Aktivitas, dan Catatan Harian memiliki filter
  periode yang konsisten.
- Data archived/deleted tidak bocor ke tampilan default.
- Tidak ada auto-delete dua tahun.
- Arsip dapat dipulihkan.
- Hapus permanen membutuhkan preview, konfirmasi, backup/export, executor,
  audit, dan verification.
- Perhitungan ringkasan tetap dilakukan deterministic oleh aplikasi.
- Gemini hanya menerima context bounded dan tidak menjadi sumber kebenaran
  finansial.
- Analyzer, full test suite, dan Android ARM64 release build lulus.
