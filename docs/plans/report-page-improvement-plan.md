# Rencana Peningkatan Halaman Laporan (Report Page Improvement Plan)

## Executive Summary & Tujuan

Menjadikan halaman Laporan (`MonthlyReportPage`) sebagai **Pusat Laporan Periode Keluarga (Financial & Operational Executive Hub)** yang komprehensif, jujur, dan 100% fungsional. Laporan ini mengonsolidasikan seluruh data keuangan (arus kas, transaksi, kategori, tag, toko, anggaran, target, hutang, piutang, aset) **DAN** data aktivitas/operasional (catatan aktivitas, jurnal harian, tugas, rutinitas, serta hasil panen/usaha).

Seluruh angka, persentase, perbandingan, dan narasi dihasilkan secara **deterministik dari database lokal (Drift/SQLite)** tanpa bergantung pada halusinasi LLM. Tampilan aplikasi (UI) dan hasil ekspor cetak (PDF) diselaraskan sepenuhnya.

---

## Prinsip Utama

1. **Akurat & Deterministik**: Semua nominal, agregasi, perbandingan MoM (Month-over-Month), dan indikator dihitung langsung dari data lokal.
2. **Cakupan Data Menyeluruh (Comprehensive Coverage)**: Jika data ada di database (keuangan maupun aktivitas operasional), data tersebut disajikan dalam laporan periode terpilih.
3. **Pemisahan Kas & Non-Kas**: Arus kas bersih (pemasukan/pengeluaran riil) tidak boleh dicampur dengan transfer antar rekening, sisa piutang, nilai aset non-kas, atau potensi hasil panen yang belum cair.
4. **Ringkasan Berjenjang (Progressive Disclosure)**: Ringkasan eksekutif tampil di bagian atas; detail mendalam disediakan dalam card/section yang dapat diperluas (expandable) atau dibuka melalui drill-down ke halaman sumber.
5. **Dukungan State Kosong (Empty State)**: Menampilkan pesan informatif yang jelas jika pada periode terpilih belum ada transaksi atau aktivitas tertentu.
6. **Konsistensi UI & PDF Export**: Setiap informasi utama yang tampil di aplikasi wajib tersedia pada dokumen ekspor PDF.

---

## Inventarisasi Sumber Data Laporan

| Modul / Domain | Tabel / Sumber Data | Parameter & Metrik Laporan |
| :--- | :--- | :--- |
| **Arus Kas & Transaksi** | `TransactionsTable`, `TransactionItemsTable`, `TransfersTable` | Total Pemasukan, Total Pengeluaran, Arus Kas Bersih (Net Cashflow), Perubahan MoM (%), Jumlah Transaksi, Pengabaian Transfer Internal. |
| **Analisis Kategori & Tag** | `CategoriesTable`, `TransactionTagsTable`, `TagsTable` | Top 5 Kategori Pemasukan, Top 5 Kategori Pengeluaran, Top Tag Pengeluaran/Pemasukan. |
| **Merchant & Merchant/Toko** | `MerchantsTable` | Top 5 Toko/Merchant tempat transaksi terbanyak & nominal terbesar. |
| **Rekening & Mutasi** | `AccountsTable`, `TransfersTable` | Saldo Kas/Bank Likuid, Ringkasan Mutasi/Transfer Antar Rekening periode ini. |
| **Anggaran (Envelope Budget)**| `EnvelopeBudgetsTable`, `EnvelopeTransfersTable` | Total Anggaran vs Realisasi Pengeluaran, Sisa Alokasi, Indikator Over-budget. |
| **Target Keuangan (Goals)** | `GoalsTable` | Target Aktif, Progres Capaian, Penambahan Tabungan Bulan Ini, Batas Waktu. |
| **Hutang (Liabilities)** | `LiabilitiesTable` | Sisa Hutang, Total Cicilan Bulanan, Status Jatuh Tempo Periode Ini. |
| **Piutang (Receivables)** | `ReceivablesTable` | Sisa Piutang (Label "Bukan Kas"), Piutang Baru Periode Ini, Piutang Jatuh Tempo Bulan Ini. |
| **Aset & Kekayaan Bersih** | `AssetsTable` | Portofolio Aset (Kas, Investasi, Properti, Vehikel, Alat Usaha), Total Estimasi Aset, Calculated Net Worth (Aset + Kas - Hutang). |
| **Catatan Aktivitas (Activities)** | `ActivityEntriesTable`, `ActivitySessionsTable` | Jumlah Sesi & Kegiatan Selesai, Sesi Berdurasi Panjang, Lokasi/Topik Utama, Entitas Aktivitas Penting. |
| **Jurnal & Refleksi Harian** | `DailyNotesTable` | Jumlah Catatan Harian yang ditulis pada periode laporan & ringkasan topik. |
| **Tugas & Rutinitas** | `TasksTable`, `DailyRoutinesTable`, `DailyRoutineCompletionsTable` | Tugas Selesai vs Pending, Tingkat Penyelesaian Rutinitas Harian (Completion Rate %). |
| **Hasil Panen / Usaha** | `HarvestEventsTable` | Komoditas Dipanen, Total Volume/Bobot (kg/unit), Total Nominal Pendapatan Panen, Pembeli/Pengepul, Status Pencatatan Transaksi Kas. |
| **Riwayat Laporan** | `OfflineToolHistoryService` | Log pembuatan laporan sebelumnya untuk pembanding cepat. |

---

## Rencana Tahapan Implementasi

### Tahap 1 — Refactoring Data Loader & Agregator Deterministik
- [ ] Buat data model agregat `_MonthlyReportData` yang memuat seluruh domain data (Keuangan, Aktivitas, Anggaran, Panen, Aset, Hutang/Piutang).
- [ ] Implementasikan query agregasi yang efisien di `_MonthlyReportPageState._load(DateTime month)`:
  - Query transaksi bulan terpilih & bulan sebelumnya (hitung MoM).
  - Filter pengeluaran/pemasukan murni (abaikan transfer internal).
  - Agregasi pengeluaran & pemasukan per kategori, per tag, dan per merchant.
  - Query pos anggaran aktif & hitung realisasi pengeluaran yang sesuai kategori anggaran.
  - Query status target keuangan (goals), hutang (liabilities), piutang (receivables), dan aset (assets).
  - Query catatan aktivitas (`ActivityEntries` & `ActivitySessions`) pada bulan terpilih.
  - Query jurnal harian (`DailyNotes`), tugas (`Tasks`), dan rutinitas (`DailyRoutineCompletions`).
  - Query fakta hasil panen (`HarvestEvents`) pada bulan terpilih.
  - Hitung Kekayaan Bersih (Net Worth) & Skor Kesehatan Keuangan (`FinancialHealthCalculator`).

### Tahap 2 — Ringkasan Utama & Kesehatan Keuangan (Overview Section)
- [ ] **Kartu Header Periode**: Tampilkan label bulan/tahun, tombol "Ganti Bulan", dan shortcut navigasi cepat (Bulan Ini / Bulan Lalu).
- [ ] **Kartu Arus Kas Utama**:
  - Pemasukan vs Pengeluaran dengan warna semantik (`positiveColor`, `negativeColor`).
  - Arus Kas Bersih (Surplus / Defisit).
  - Indikator Perubahan MoM: `+X% dibanding bulan lalu` atau `-Y% dibanding bulan lalu`.
  - Jumlah total transaksi tercatat pada periode ini.
- [ ] **Kartu Skor Kesehatan & Kekayaan Bersih**:
  - Skor Kesehatan Finansial (0-100) beserta badge status (Kondisi Sangat Kuat / Baik / Cukup / Warning).
  - Ringkasan Kekayaan Bersih (Total Aset Likuid + Non-Kas - Sisa Hutang).

### Tahap 3 — Rincian Analisis Transaksi (Categories, Tags, Merchants & Top Transactions)
- [ ] **Breakdown Kategori Pengeluaran & Pemasukan Terbesar**:
  - Top 5 kategori pengeluaran dengan persentase dari total pengeluaran dan progress bar visual.
  - Top 5 kategori pemasukan.
- [ ] **Rincian Tag & Toko/Merchant Teratas**:
  - Tag transaksi yang paling sering digunakan atau menyedot anggaran terbesar.
  - Toko/Merchant dengan total belanja terbesar pada periode laporan.
- [ ] **Daftar Transaksi Terbesar (Top Highlights)**:
  - 3-5 transaksi pengeluaran terbesar periode ini (untuk identifikasi kebocoran anggaran).
- [ ] **Aksi Drill-Down**: Tombol "Lihat Semua Transaksi Periode Ini" yang mengarahkan ke Halaman Transaksi dengan filter tanggal yang sudah terpasang.

### Tahap 4 — Anggaran vs Realisasi & Target Keuangan (Budget & Goals)
- [ ] **Ringkasan Anggaran (Envelope Budget Performance)**:
  - Tampilkan pos anggaran aktif, jumlah alokasi vs realisasi pengeluaran bulan ini.
  - Indikator visual persen terpakai (contoh: 85% terpakai) dan badge peringatan jika over-budget.
- [ ] **Ringkasan Target Keuangan (Goals)**:
  - Tampilkan progres tiap target aktif (Capaian saat ini / Target nominal).
  - Penambahan saldo target pada periode laporan ini.

### Tahap 5 — Kondisi Hutang, Piutang & Portofolio Aset
- [ ] **Ringkasan Hutang (Liabilities)**:
  - Total sisa kewajiban hutang & total kewajiban cicilan bulanan.
  - Status kewajiban jatuh tempo bulan ini.
- [ ] **Ringkasan Piutang (Receivables - Labeled NON-KAS)**:
  - Total piutang yang belum diterima.
  - Piutang baru yang terjadi di periode ini & piutang yang jatuh tempo bulan ini.
- [ ] **Ringkasan Portofolio Aset**:
  - Breakdown nilai aset berdasarkan kategori (Kas/Bank, Investasi, Properti, Kendaraan, Alat Kerja/Usaha).

### Tahap 6 — Laporan Aktivitas Operasional, Jurnal & Hasil Panen (Activity & Operational Report)
- [ ] **Section Catatan Aktivitas Periode Ini (Activity Log Report)**:
  - Total sesi & kegiatan operasional yang diselesaikan pada periode laporan.
  - Daftar entitas aktivitas penting (misal: perawatan lahan, rapat keluarga, servis kendaraan, kegiatan usaha).
  - Tampilkan lokasi, durasi, dan peserta aktivitas jika tersedia.
- [ ] **Section Jurnal Harian, Tugas & Rutinitas**:
  - Jumlah catatan refleksi harian (`DailyNotes`) yang ditulis pada bulan ini.
  - Jumlah tugas selesai (`Tasks`) vs tugas yang belum rampung.
  - Persentase tingkat penyelesaian rutinitas harian (`DailyRoutines`).
- [ ] **Section Hasil Panen / Usaha (Harvest Events Report)**:
  - Ringkasan fakta panen periode ini: Komoditas (padi, jagung, cabai, dll.), total volume/kuantitas (kg/kuintal), dan estimasi/realisasi nilai nominal panen.
  - Nama pembeli/pengepul utama.
  - Penjelasan keterbatasan & status: Apakah hasil panen sudah masuk sebagai transaksi kas di aplikasi atau belum.

### Tahap 7 — Narasi Ringkas Laporan Deterministik (Executive Summary Narrative)
- [ ] Sediakan bagian narasi yang disusun otomatis dari aturan logika deterministik:
  - Menyebutkan pendorong utama perubahan pengeluaran (misal: "Pengeluaran naik 12% didominasi oleh kategori Belanja Bulanan di Toko X").
  - Menyebutkan status anggaran dan capaian aktivitas operasional bulan ini.
  - Bahasa Indonesia yang ringkas, objektif, dan informatif bagi keluarga.

### Tahap 8 — Peningkatan Ekspor PDF & Riwayat Laporan (`PdfReportService`)
- [ ] Perluas `PdfReportService.buildMonthlyReport` untuk menyertakan:
  1. Header & Ringkasan Eksekutif (Pemasukan, Pengeluaran, Net Cashflow, Skor Kesehatan, Net Worth).
  2. Tabel Breakdown Kategori & Toko Teratas.
  3. Tabel Perbandingan Anggaran vs Realisasi.
  4. Tabel Target Keuangan, Hutang, Piutang, dan Aset.
  5. **Section Laporan Aktivitas & Jurnal Operasional** (Daftar kegiatan penting & catatan harian periode ini).
  6. **Section Laporan Hasil Panen/Usaha** (Ringkasan komoditas, volume, nominal, & pembeli).
  7. Tabel Rincian Transaksi Utama.
- [ ] Perbarui pencatatan riwayat laporan di `OfflineToolHistoryService` agar menyimpan metadata lengkap.

### Tahap 9 — Pengujian & Validasi Sensitif
- [ ] **Unit Tests**:
  - Verifikasi perhitungan Pemasukan, Pengeluaran, Net Cashflow, dan MoM %.
  - Verifikasi pengabaian transaksi transfer internal.
  - Verifikasi agregasi Kategori, Tag, Merchant, Anggaran, Goals, Hutang, Piutang, Aset, Aktivitas, dan Panen.
- [ ] **Widget Tests**:
  - Verifikasi `MonthlyReportPage` dapat merender seluruh section dengan data lengkap.
  - Verifikasi state kosong (empty state) jika periode terpilih belum memiliki transaksi/aktivitas.
  - Verifikasi dialog pemilih bulan & ekspor PDF.
- [ ] **Integration Tests**:
  - Verifikasi pembuatan dokumen PDF tanpa error dan pencatatan riwayat ke `OfflineToolHistoryService`.
- [ ] **Analisis Kode**:
  - Jalankan `flutter analyze lib test` hingga tidak ada error/warning.

---

## Rencana Verifikasi

1. **Uji Jalur Analisis Data**:
   - Menjalankan unit test untuk memastikan seluruh fungsi kalkulasi deterministik lulus 100%.
2. **Uji Antarmuka Aplikasi (UI Test)**:
   - Memastikan seluruh section (Keuangan, Anggaran, Aset/Hutang/Piutang, Catatan Aktivitas, Hasil Panen) dapat ditampilkan dengan rapi, responsif, dan mudah dibaca di layar Android.
3. **Uji Ekspor PDF**:
   - Menguji pembuatan dokumen PDF dan memastikan file PDF berisi laporan keuangan dan aktivitas operasional yang lengkap serta konsisten dengan tampilan UI.
4. **Validasi Kepatuhan**:
   - Mengubah kode menggunakan tool edit bawaan IDE (`write_file`, `replace_file_content`).
   - Menjalankan `flutter analyze lib test` dan memastikan target release Android ARM64 tetap terjaga.
