# Rencana Migrasi Kendaraan, BBM, dan Listrik

Dokumen handoff khusus untuk implementasi database, migrasi, UI, dan integrasi
Assistant/LLM kendaraan, pembelian BBM, meter listrik, dan token PLN.

Dokumen induk: `docs/assistant_draft_database_ui_audit_plan.md`

## Status Pengerjaan

**Ditunda sampai seluruh checklist dokumen induk selesai.** Jangan mulai
implementasi tabel, migrasi, token listrik, BBM, kendaraan, atau meter listrik
dari dokumen ini sebelum dokumen induk dinyatakan selesai.

## Status

- [x] Audit awal selesai.
- [x] Ditemukan master kendaraan dan meter listrik masih disimpan sebagai JSON
  di `SharedPreferences`.
- [x] Ditemukan pembelian token sebagian masuk ke `utilityTokenPurchases`.
- [ ] Migrasi master kendaraan ke tabel Drift.
- [ ] Migrasi master meter listrik ke tabel Drift.
- [ ] Migrasi riwayat BBM ke tabel Drift.
- [ ] Perkuat riwayat pembelian token.
- [ ] Adaptasi repository.
- [ ] Adaptasi draft/parser/orchestrator LLM.
- [ ] Tambahkan resolver plat dan nomor meter.
- [ ] Tambahkan grafik dan analisis deterministik.
- [ ] Seluruh acceptance test lulus.

## Kondisi Saat Ini

### Kendaraan

UI dan model sudah memiliki:

- nama/panggilan kendaraan;
- plat nomor;
- merek/model;
- tipe kendaraan;
- jenis BBM;
- kapasitas tangki;
- odometer;
- catatan;
- liter, nominal, harga per liter, jenis BBM, SPBU, dan tanggal log BBM.

Namun data disimpan sebagai JSON di `SharedPreferences`, termasuk riwayat BBM.

### Listrik

UI dan model sudah memiliki:

- nama properti/meter;
- nomor meter atau IDPEL;
- nama pelanggan;
- daya/tarif;
- lokasi;
- catatan;
- token terakhir;
- nominal dan tanggal pembelian terakhir.

Namun master meter masih disimpan sebagai JSON di `SharedPreferences`. Tabel
`utilityTokenPurchases` sudah ada, tetapi belum menjadi satu-satunya sumber
riwayat yang lengkap.

## Target Tabel

### `vehicles`

- `id`, `householdId`
- `name`
- `plateNumber`, `normalizedPlateNumber`
- `brandModel`, `vehicleType`, `fuelType`
- `tankCapacity`, `lastOdometer`, `notes`
- `isArchived`, `createdAt`, `updatedAt`
- Index household + normalized plate

### `fuelLogs`

- `id`, `householdId`, `vehicleId`
- `transactionId`
- `date`, `liters`, `totalAmount`, `pricePerLiter`
- `odometerKm`, `fuelType`, `spbuLocation`, `notes`
- `createdAt`, `updatedAt`
- Index household + vehicle + date

### `utilityMeters`

- `id`, `householdId`
- `name`
- `meterNumber`, `normalizedMeterNumber`
- `customerName`, `tariffPower`, `location`, `notes`
- `isArchived`, `createdAt`, `updatedAt`
- Unique/index household + normalized meter number

### `utilityTokenPurchases`

Pastikan field berikut konsisten:

- `id`, `householdId`, `meterId`, `meterNumber`
- `tokenCode`, `amount`, `purchasedAt`
- `transactionId`
- Tambahkan `createdAt`/`updatedAt` bila diperlukan.

## Aturan Bisnis

- Satu pembelian listrik/BBM menghasilkan satu transaksi pengeluaran.
- Pembelian tersebut juga menghasilkan satu row riwayat domain.
- Row riwayat menyimpan `transactionId` yang sama.
- Tidak boleh membuat dua transaksi keuangan untuk satu pembelian.
- Semua operasi transaksi + riwayat harus atomik dan dapat rollback.
- Nominal, total tahunan, tren boros, dan biaya per kilometer dihitung dari DB,
  bukan dari perhitungan LLM.

## Resolver

### Listrik

- Normalisasi nomor meter dengan menghapus karakter non-digit.
- Exact match berdasarkan `householdId + normalizedMeterNumber`.
- Jika satu hasil: update meter tersebut.
- Jika tidak ada: buat draft meter baru dan tunggu konfirmasi.
- Jika lebih dari satu: minta klarifikasi, jangan pilih hasil pertama.

### Kendaraan

- Normalisasi plat dengan menghapus non-alfanumerik dan uppercase.
- Exact match berdasarkan `householdId + normalizedPlateNumber`.
- Jika satu hasil: update kendaraan tersebut.
- Jika tidak ada: buat draft kendaraan baru dan tunggu konfirmasi.
- Jika lebih dari satu: minta klarifikasi.

## Routing Assistant dan LLM

- Gambar token listrik diarahkan ke alur meter listrik, bukan transaksi umum.
- OCR membaca nomor meter, token, nominal, dan tanggal.
- Gambar struk BBM diarahkan ke alur kendaraan.
- OCR membaca plat, liter, nominal, jenis BBM, odometer, SPBU, dan tanggal.
- Gemini tidak boleh menebak entity ID.
- Orchestrator membaca data household terlebih dahulu.
- Resolver lokal menentukan `resolved`, `missing`, atau `ambiguous`.
- `missing` menghasilkan draft create entity terpisah dan membutuhkan konfirmasi.
- `ambiguous` tidak boleh disimpan.

## Migrasi Data Lama

- Baca `ffm_vehicles_<householdId>`.
- Insert master kendaraan ke Drift.
- Pindahkan semua log BBM tanpa duplikasi ID.
- Baca `ffm_utility_meters_<householdId>`.
- Insert master meter ke Drift.
- Ubah data token/nominal terakhir menjadi history purchase bila tersedia.
- Verifikasi jumlah row, identifier, nominal, dan tanggal.
- Jangan hapus JSON lama sebelum verifikasi berhasil.
- Setelah migrasi, repository memakai Drift sebagai sumber kebenaran.

## Checklist Implementasi

- [ ] Tambah tabel Drift dan index.
- [ ] Tambah schema migration.
- [ ] Tambah repository Drift kendaraan.
- [ ] Tambah repository Drift meter listrik.
- [ ] Tambah repository Drift fuel logs.
- [ ] Migrasikan data lama secara idempotent.
- [ ] Ubah UI kendaraan membaca/menulis Drift.
- [ ] Ubah UI listrik membaca/menulis Drift.
- [ ] Hubungkan transaksi dan riwayat dengan `transactionId`.
- [ ] Tambah adapter `vehicle_fuel`.
- [ ] Tambah adapter `utility_meter`.
- [ ] Tambah parser proposal single/multi.
- [ ] Tambah schema Gemini.
- [ ] Tambah read capabilities bounded.
- [ ] Tambah resolver entity.
- [ ] Tambah verifier khusus.
- [ ] Tambah grafik listrik bulanan/tahunan.
- [ ] Tambah grafik BBM bulanan/tahunan dan biaya per kilometer.

## Acceptance Test

- [ ] Rumah A dan Rumah B tidak tertukar.
- [ ] Motor A dan Motor B tidak tertukar.
- [ ] Identifier ambigu menghasilkan klarifikasi.
- [ ] Entity baru membutuhkan konfirmasi.
- [ ] Pembelian existing meng-update entity yang benar.
- [ ] Satu pembelian menghasilkan satu transaksi dan satu history row.
- [ ] Retry tidak menggandakan data.
- [ ] Mismatch nominal/tanggal/entity ditolak verifier.
- [ ] Migrasi mempertahankan data lama.
- [ ] Grafik membaca angka langsung dari database.
- [ ] `flutter analyze lib test` lulus.
- [ ] `flutter test` penuh lulus.
