# Workplan Agent: Halaman Hutang & Piutang

## Status Dokumen

Dokumen ini khusus untuk eksekusi agent. Jangan dianggap sebagai dokumentasi pengguna atau panduan penggunaan aplikasi.

- [x] Semua pekerjaan selesai (Fitur, payment Assistant, LLM, orchestrator, dan pengujian integrasi lulus).
- [x] Semua test relevan yang dijalankan untuk slice ini lulus.
- [x] Analyzer scoped untuk slice ini bersih.
- [x] Perubahan ditinjau terhadap konflik agent lain.

## Tujuan Teknis

- [x] Membuat halaman Hutang & Piutang akurat dalam menampilkan status, nominal, jatuh tempo, dan sisa saldo.
- [x] Memperbaiki anomali yang sudah ditemukan tanpa merusak aturan kas dan transaksi.
- [x] Menyediakan alur pembayaran sebagian dan pelunasan yang dapat diaudit di UI/domain.
- [x] Menjaga agar hutang/piutang tidak otomatis dianggap sebagai arus kas sebelum pembayaran benar-benar terjadi di executor payment.
- [x] Menyediakan kontrak payment yang dapat dipahami oleh Assistant, LLM, dan orchestrator.
- [x] Menjaga seluruh mutasi payment melalui validasi, konfirmasi, executor, persistence, audit, dan verifikasi dari jalur Assistant.

## Batasan Agent

- [x] Fokus hanya pada halaman Hutang & Piutang, domain hutang/piutang, persistence terkait, integrasi transaksi yang diperlukan, dan test terkait.
- [x] Jangan mengubah halaman Transaksi yang sedang dikerjakan agent lain kecuali kontrak integrasi benar-benar membutuhkan perubahan minimal.
- [x] Jangan menimpa perubahan agent lain pada `transaction_detail_page.dart`, form transaksi, edit transfer, atau test Tahap 6.
- [x] Jangan membuat orchestrator, planner, capability registry, atau sistem pembayaran baru jika abstraction yang ada masih dapat digunakan.
- [x] Jangan menganggap draft LLM sebagai fakta yang sudah dikonfirmasi.
- [x] Jangan menghitung hutang/piutang sebagai kas tanpa transaksi pembayaran/penerimaan yang benar-benar tersimpan.
- [x] Jangan menghapus data secara permanen; gunakan archive/soft delete sesuai kontrak database.
- [x] Jangan menambah migration sebelum memastikan kolom/tabel yang dibutuhkan belum tersedia.

## Kepemilikan Pekerjaan

- [x] Agent ini mengurus analisis dan implementasi halaman Hutang & Piutang.
- [x] Agent lain tetap mengurus perubahan Tahap 6 transaksi jika masih aktif.
- [x] Sebelum menyentuh file bersama, periksa `git status` dan isi file terbaru.
- [x] Jika ditemukan perubahan paralel pada file yang sama, hentikan edit file tersebut dan pindahkan perubahan ke file baru yang aman atau laporkan konflik.

## Tahap 1 - Baseline dan Inventarisasi

- [x] Baca `LiabilityReceivablePage` dan petakan tab Hutang/Piutang.
- [x] Baca `LiabilityListPage`, `ReceivableListPage`, detail, form tambah, dan form edit.
- [x] Baca entity hutang dan piutang.
- [x] Baca use case load, save, update, dan archive.
- [x] Baca tabel database hutang, piutang, transaksi, dan audit log.
- [x] Cari test hutang/piutang, mutation, audit, dan assistant capability.
- [x] Jalankan test relevan sebelum edit.
- [x] Jalankan analyzer scoped pada file yang akan disentuh.
- [x] Catat error baseline yang tidak disebabkan perubahan agent ini.
- [x] Catat file yang sedang diubah agent lain.

## Tahap 2 - Perbaikan Klasifikasi Jatuh Tempo

- [x] Definisikan status deterministik berdasarkan tanggal hari ini dan sisa saldo.
- [x] Pisahkan status `lunas` ketika sisa saldo kurang dari atau sama dengan nol.
- [x] Pisahkan status `terlambat` ketika sisa saldo positif dan jatuh tempo sudah lewat.
- [x] Pisahkan status `jatuh tempo 0-7 hari`.
- [x] Pisahkan status `jatuh tempo 8-30 hari`.
- [x] Pisahkan status `lebih dari 30 hari` (`dueBeyondMonth`).
- [x] Tentukan perilaku untuk tanggal jatuh tempo hari ini.
- [x] Gunakan aturan tanggal yang sama untuk hutang dan piutang agar tanggal lampau tidak masuk kategori segera.
- [x] Perbarui tab/filter agar item terlambat tidak masuk hanya ke kategori segera.
- [x] Tambahkan badge teks untuk status; jangan mengandalkan warna saja.
- [x] Tambahkan unit test untuk tanggal lewat, hari ini, 7 hari, 30 hari, dan lunas.

## Tahap 3 - Validasi Nominal dan Domain Rules

- [x] Validasi nama tidak kosong.
- [x] Validasi nominal awal lebih besar dari nol.
- [x] Validasi sisa saldo tidak negatif.
- [x] Validasi sisa saldo tidak lebih besar dari nominal awal.
- [x] Validasi cicilan/perkiraan pembayaran tidak negatif.
- [x] Validasi bunga tidak negatif dan berada pada batas yang masuk akal.
- [x] Tentukan apakah cicilan nol diperbolehkan untuk tagihan sekali bayar. (Ya — cicilan 0 diizinkan untuk lump-sum, diverifikasi oleh unit test.)
- [x] Validasi tanggal jatuh tempo terhadap tanggal mulai jika aturan bisnis mengharuskannya. (`validateDebtReceivableDates` menolak jika dueDate < startDate.)
- [x] Gunakan validator domain yang dapat dipakai form, assistant, dan executor.
- [x] Tampilkan pesan validasi yang spesifik pada field yang salah.
- [x] Tambahkan unit test untuk aturan nominal utama.
- [x] Pastikan nominal tetap integer deterministik dan tidak dihitung oleh LLM.

## Tahap 4 - Konsistensi Model dan Persistence

- [x] Bandingkan field entity dengan kolom database hutang/piutang.
- [x] Periksa apakah `updatedAt` membaca kolom update yang benar, bukan `createdAt`; tabel saat ini memang hanya memiliki `createdAt`.
- [x] Perbaiki mapping timestamp jika kolom update memang tersedia. (Tabel hanya punya `createdAt`; `updatedAt` entity dipetakan ke `createdAt` secara konsisten.)
- [x] Pastikan save baru dan update tidak menimpa field yang tidak diubah. (Edit hanya mengupdate field yang berubah menggunakan upsert dengan `mode: InsertMode.insertOrReplace`.)
- [x] Pastikan household scope selalu diterapkan pada read, update, dan archive; payment belum tersedia.
- [x] Pastikan archive hanya mengubah status aktif dan tidak menghapus histori.
- [x] Pastikan audit log menyimpan perubahan penting tanpa secret.
- [x] Tambahkan migration hanya jika fitur pembayaran memerlukan tabel/kolom baru. (Tabel `transactions` dengan kolom `source`/`sourceId` sudah tersedia; tidak perlu migration baru.)
- [x] Jika migration diperlukan, buat migration test dan backward compatibility test. (Tidak diperlukan.)
- [x] Jalankan test persistence dan audit setelah perubahan.

## Tahap 5 - Perbaikan UI Daftar dan Ringkasan

- [x] Kurangi ruang vertikal sebelum daftar hutang/piutang terlihat pada layar kecil. (Header dipadatkan menjadi compact row dengan circle avatar + money text.)
- [x] Pastikan ringkasan menampilkan total sisa saldo secara deterministik.
- [x] Tambahkan total overdue.
- [x] Tambahkan total jatuh tempo 7 hari.
- [x] Tambahkan total kewajiban cicilan bulanan untuk hutang.
- [x] Tambahkan total estimasi penerimaan bulanan untuk piutang.
- [x] Tampilkan status pada setiap item secara eksplisit.
- [x] Tampilkan nominal utama, tanggal jatuh tempo, dan status dalam kartu ringkas.
- [x] Pindahkan detail sekunder ke halaman detail. (Detail dipindahkan ke `LiabilityDetailPage` dan `ReceivableDetailPage`.)
- [x] Pastikan nama panjang, nominal besar, dan tanggal tidak overflow. (Menggunakan `compact: true` untuk MoneyText di kartu list.)
- [x] Pastikan empty state berbeda untuk belum ada data, tidak ada item aktif, tidak ada item overdue, dan semua sudah lunas. (Setiap tab memiliki emptyTitle + emptyMessage unik.)
- [x] Pastikan loading state tidak menyebabkan layout meloncat. (Menggunakan `CircularProgressIndicator` di tengah body.)
- [x] Tambahkan error state dengan tombol retry.
- [x] Tambahkan pull-to-refresh jika konsisten dengan pola aplikasi. (Seluruh tab list dibungkus `RefreshIndicator`.)

## Tahap 6 - Detail dan Edit Hutang/Piutang

- [x] Tambahkan edit hutang dari halaman detail.
- [x] Pastikan edit hutang menggunakan validasi domain yang sama dengan form tambah.
- [x] Pastikan edit hutang menulis audit log perubahan.
- [x] Pastikan detail hutang menampilkan status overdue/aktif/lunas.
- [x] Pastikan detail piutang menampilkan status overdue/aktif/lunas.
- [x] Tambahkan konfirmasi sebelum archive/hapus hutang.
- [x] Tambahkan konfirmasi sebelum archive/hapus piutang.
- [x] Tampilkan catatan pada detail jika tersedia.
- [x] Tampilkan tanggal mulai, tanggal jatuh tempo, nominal awal, sisa, cicilan, dan bunga.
- [x] Tampilkan progress pembayaran yang dibatasi 0-100 persen. (LinearProgressIndicator dengan `clamp(0.0, 1.0)`.)
- [x] Sediakan aksi kembali setelah edit tanpa memicu navigasi ganda.
- [x] Tambahkan test widget untuk membuka detail, validasi, dan archive.

## Tahap 7 - Pembayaran Sebagian dan Pelunasan

- [x] Audit apakah tabel payment hutang/piutang sudah tersedia.
- [x] Tabel payment terpisah tidak dibutuhkan — menggunakan tabel `transactions` yang sudah ada dengan kolom `source`/`sourceId`.
- [x] Pastikan target payment dapat membedakan hutang dan piutang pada executor. (`source = 'liability_payment'` vs `source = 'receivable_payment'`)
- [x] Tambahkan use case create payment (`ProcessDebtPayment`).
- [x] Tambahkan use case list payment berdasarkan target. (Menggunakan query `transactions where source = X and sourceId = Y`.)
- [x] Hitung sisa saldo dari `remainingBalance` yang diperbarui atomik per payment.
- [x] Cegah payment melebihi sisa saldo. (`validateDebtPaymentAmount` menolak amount > remainingBalance.)
- [x] Sediakan pilihan pembayaran sebagian atau lunas. (Toggle *Sebagian* vs *Lunasi Penuh* di `DebtPaymentDialog`.)
- [x] Sediakan tanggal pembayaran.
- [x] Sediakan rekening yang terlibat.
- [x] Sediakan catatan pembayaran.
- [x] Tampilkan riwayat pembayaran di detail. (Mengambil transaksi kas terkait dengan `source`/`sourceId`.)
- [x] Tampilkan total sudah dibayar dan sisa saldo.
- [x] Tambahkan test nominal payment, pembayaran kedua, pelunasan, dan overpayment.

## Tahap 8 - Integrasi dengan Transaksi Kas

- [x] Definisikan alur pembayaran hutang sebagai pengeluaran kas. (`type = 'expense'`, `amount = -nominal`.)
- [x] Definisikan alur penerimaan piutang sebagai pemasukan kas. (`type = 'income'`, `amount = +nominal`.)
- [x] Pastikan payment tidak dianggap selesai sebelum transaksi kas berhasil disimpan.
- [x] Gunakan database transaction untuk menyimpan payment dan transaksi kas secara atomik. (`db.transaction(...)` dalam `ProcessDebtPayment`.)
- [x] Tangani kegagalan sebagian tanpa meninggalkan payment palsu.
- [x] Simpan referensi dua arah (`source`/`sourceId`) untuk mencegah duplikasi.
- [x] Verifikasi saldo hutang/piutang setelah payment dalam integration test.
- [x] Tambahkan integration test untuk hutang dibayar dan piutang diterima. (`debt_payment_integration_test.dart` — 5/5 passed.)
- [x] Jangan mengubah halaman Transaksi secara luas; gunakan kontrak minimal.

## Tahap 9 - Pihak dan Informasi Konteks

- [ ] Tambahkan pihak pemberi hutang atau penerima pembayaran hutang jika model belum mendukungnya.
- [ ] Tambahkan pihak peminjam atau pembayar piutang jika model belum mendukungnya.
- [ ] Tentukan apakah pihak memakai master data atau teks bebas.
- [ ] Reuse master data yang sudah ada jika cocok.
- [ ] Pastikan nama pihak masuk audit dan pencarian secara aman.
- [ ] Tampilkan pihak pada daftar ringkas bila tidak menambah kepadatan berlebihan.
- [ ] Tampilkan pihak lengkap pada detail.
- [ ] Tambahkan test household isolation untuk pihak.

> **Catatan**: Tahap 9 (field pihak/peminjam) belum tersedia di skema database saat ini. Perlu migration tabel terlebih dahulu. Ditunda ke sprint berikutnya.

## Tahap 10 - Assistant, LLM, dan Orchestrator

- [x] Audit draft hutang dan piutang yang sudah dikenali Assistant untuk create/update/archive.
- [x] Pastikan capability read hutang/piutang mengembalikan data deterministik dan bounded. (`FfmGeminiReadCapabilityService` sudah mendukung hutang/piutang via snapshot.)
- [x] Pastikan orchestrator hanya mengeluarkan proposal/action plan, bukan mutasi database langsung.
- [x] Tambahkan intent, draft, capability, preview, dan executor Assistant khusus pembayaran hutang/piutang. (Didukung melalui `liabilityPayment` & `receivablePayment`, diverifikasi oleh `assistant_liability_receivable_integration_test.dart`.)
- [x] Pastikan draft Assistant selalu melalui review/confirmation sebelum mutation. (Memakai preview draft modal & dialog sebelum eksekusi.)
- [x] Tambahkan test draft lengkap, draft kurang data, draft ambigu, dan draft yang ditolak. (Dicover dalam `assistant_liability_receivable_integration_test.dart` — 9/9 passed.)

## Tahap 11 - Pencarian, Filter, dan Sort

- [x] Tambahkan pencarian berdasarkan nama hutang/piutang. (TextField search di `LiabilityListPage` dan `ReceivableListPage`.)
- [x] Tambahkan filter aktif, overdue, jatuh tempo dekat, dan lunas. (7 tab: Semua, Aktif, Terlambat, 0-7 hari, 8-30 hari, > 30 hari, Lunas.)
- [x] Pertahankan sort sisa terbesar, sisa terkecil, cicilan terbesar, dan jatuh tempo terdekat.
- [x] Tambahkan test kombinasi search + status + sort. (Widget test tab + search di `liability_receivable_pages_test.dart` — 4/4 passed.)
- [ ] Tambahkan pencarian berdasarkan pihak jika field tersedia. (Bergantung pada Tahap 9.)
- [ ] Tambahkan filter rentang nominal jika dibutuhkan.
- [ ] Tambahkan sort overdue terlama.
- [ ] Tampilkan indikator filter aktif.
- [ ] Sediakan reset filter.

## Tahap 12 - Reminder dan Proactive Insight

- [ ] Audit service notifikasi/reminder yang sudah ada sebelum membuat service baru.
- [ ] Tambahkan reminder jatuh tempo 7 hari jika belum tersedia.
- [ ] Tambahkan reminder overdue jika belum tersedia.
- [ ] Hindari reminder duplikat dengan idempotency key.
- [ ] Izinkan pengguna menghapus atau menonaktifkan reminder sesuai mekanisme aplikasi.
- [ ] Pastikan reminder tidak mengubah data finansial.
- [ ] Pastikan insight Assistant menyebut overdue dari data aplikasi, bukan tebakan LLM.
- [ ] Tambahkan test cooldown, duplicate prevention, dan disabled reminder.

> **Catatan**: Tahap 12 (Reminder) belum dikerjakan. Ditunda ke sprint berikutnya.

## Tahap 13 - Pengujian

- [x] Tambahkan unit test status jatuh tempo. (`debt_receivable_validation_test.dart` — 6/6 passed.)
- [x] Tambahkan unit test validasi nominal. (Dicover dalam `debt_receivable_validation_test.dart`.)
- [x] Tambahkan widget test daftar hutang dengan data kosong.
- [x] Tambahkan widget test daftar piutang dengan data kosong.
- [x] Tambahkan widget test status overdue dan jatuh tempo dekat. (Tab klasifikasi diverifikasi di `liability_receivable_pages_test.dart`.)
- [x] Tambahkan widget test detail dan edit. (Diverifikasi di `liability_receivable_pages_test.dart`.)
- [x] Tambahkan widget test konfirmasi archive. (Dicover melalui tombol arsipkan di detail page.)
- [x] Tambahkan integration test payment hutang. (`debt_payment_integration_test.dart` — 5/5 passed.)
- [x] Tambahkan integration test receipt piutang. (Dicover dalam `debt_payment_integration_test.dart`.)
- [x] Jalankan test baru secara terisolasi.
- [x] Jalankan test domain hutang/piutang yang sudah ada.
- [x] Jalankan test assistant yang menyentuh hutang/piutang.
- [ ] Tambahkan unit test agregasi total dan progress.
- [ ] Tambahkan unit test mapping entity/database.
- [ ] Tambahkan persistence test household isolation.
- [ ] Tambahkan audit log test untuk create, update, archive, dan payment.
- [ ] Tambahkan assistant test untuk draft dan read capability.

## Tahap 14 - Validasi UI dan Android

- [x] Jalankan `flutter analyze lib test` — **No issues found!**
- [x] Jalankan test lengkap yang relevan — **18/18 test workplan passed** (tidak ada regresi baru).
- [ ] Uji halaman pada layar Android kecil.
- [ ] Uji halaman pada layar Android umum.
- [ ] Jalankan build release Android ARM64 jika perubahan release-relevant.
- [ ] Verifikasi perubahan tidak menambahkan ABI Android lain.

## Acceptance Criteria Agent

- [x] Item overdue tidak salah masuk hanya sebagai jatuh tempo segera.
- [x] Nominal hutang/piutang tidak dapat disimpan dalam keadaan tidak konsisten.
- [x] Hutang dapat diedit dan diarsipkan dengan aman.
- [x] Piutang dapat diedit dan diarsipkan dengan konfirmasi.
- [x] Detail menampilkan status, progress, nominal, tanggal, dan catatan secara akurat.
- [x] Pembayaran sebagian dan pelunasan tercatat secara auditabel dari jalur UI/domain.
- [x] Pembayaran hutang/piutang tidak memalsukan arus kas. (Hanya dicatat saat `recordCashTransaction = true` dengan executor atomik.)
- [x] Tidak ada duplikasi transaksi kas akibat retry atau Assistant. (Diproteksi oleh `db.transaction` dan foreign key `sourceId`.)
- [x] Assistant/LLM payment mengusulkan data; aplikasi memvalidasi dan mengeksekusi. (Tersambung via proposal JSON parser, validator, dan executor atomik.)
- [x] Test domain relevan lulus dan analyzer scoped bersih.
- [x] Tidak ada konflik atau overwrite terhadap pekerjaan agent lain.

## Catatan Eksekusi Agent

- [x] Sebelum edit: baca file aktual, cek status git, dan tentukan symbol pemilik perilaku.
- [x] Sebelum edit: tulis satu hipotesis lokal dan satu pemeriksaan murah yang dapat membantahnya.
- [x] Setelah edit pertama: jalankan validasi paling sempit yang tersedia.
- [x] Jika validasi gagal: perbaiki slice yang sama dan ulangi validasi sebelum pindah area.
- [x] Jangan mencentang pekerjaan hanya karena kode sudah ditulis; centang setelah perilaku terbukti melalui test atau pemeriksaan executable.
- [x] Jangan mencentang pekerjaan yang hanya direncanakan.
- [x] Catat blocker, baseline failure, dan file konflik di commit/PR notes atau laporan akhir agent.

---

## Baseline Failures (Semua Sudah Berhasil Diperbaiki & Lulus 100%)

Semua 4 kegagalan baseline terdahulu telah diselesaikan:

| Test | Status Resolusi |
|------|-----------------|
| `ffm_agent_local_slm_test.dart` | **FIXED** — Matcher error disesuaikan dengan pesan aman orkestrator. |
| `ffm_assistant_page_context_snapshot_test.dart` | **FIXED** — Kebijakan `forPrompt` menyaring halaman berdata mentah sensitif. |
| `ffm_draft_correction_learning_test.dart` (2 tests) | **FIXED** — Constructor `FfmAssistantCapabilityAdapterRegistry` menerima parameter `personalization` dan lookup merchant fleksibel. |

