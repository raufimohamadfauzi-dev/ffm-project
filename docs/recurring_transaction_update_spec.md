# Spesifikasi Pembaruan Transaksi Berkala — Agent FFM

## Tujuan

Agent FFM dapat menyiapkan perubahan terbatas untuk **satu** aturan Transaksi Berkala aktif yang cocok secara unik. Perubahan hanya meliputi nama atau catatan; Agent juga dapat menonaktifkan satu aturan melalui arsip lunak.

## Alur Keamanan

Semua permintaan melewati **draft → preview/edit → konfirmasi eksplisit → executor allowlisted → usecase resmi → audit lokal → readback**. Satu Action Plan membawa maksimal satu mutasi dan tidak boleh membuat write sebelum pengguna mengonfirmasi.

## Batas Mutasi

| Operasi | Diizinkan | Dipertahankan / Dilarang |
|---|---|---|
| Update | Nama atau catatan satu aturan | `id`, `householdId`, nominal, jenis, rekening, kategori, sumber, periode, tanggal mulai/akhir, mode kalkulasi, dan persentase tetap sama |
| Arsip | `isActive=false` melalui `ArchiveRecurringTransaction` | Tidak menghapus permanen aturan, riwayat, transaksi, atau run historis |
| Target | Resolver deterministik atas aturan aktif dengan hasil tepat satu | Hasil nol atau lebih dari satu hanya meminta klarifikasi; tidak ada mass update |

## Larangan Keras

Agent tidak boleh memanggil `ProcessRecurringTransactions`, membuat transaksi, membuat atau mengubah `recurring_transaction_runs`, mengejar jadwal jatuh tempo, mengubah saldo, maupun mengaktifkan notifikasi atau otomasi baru. Model hanya menghasilkan intent/draft; tidak memiliki akses SQL atau CRUD langsung.

## Executor dan Verifikasi

Executor hanya memakai `GetRecurringTransactions`, `UpdateRecurringTransaction`, dan `ArchiveRecurringTransaction`. Saat update, seluruh field terlindungi disalin kembali dari aturan lama dan hanya metadata yang diizinkan diubah. Setelah update, readback memeriksa nama/catatan dan status aktif. Setelah arsip, readback memeriksa bahwa aturan menjadi tidak aktif. Audit lokal dicatat oleh usecase resmi.

## Regresi Wajib

Test harus membuktikan draft tidak menulis data, target ambigu meminta klarifikasi, update nama/catatan menjaga seluruh field terlindungi, arsip bersifat lunak, Action Plan memakai draft/mutate/verify yang benar, dan tidak ada transaksi atau run baru terbentuk.
