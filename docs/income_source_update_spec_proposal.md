# Spesifikasi Pembaruan Sumber Pemasukan — Agent FFM

## Latar Belakang

Sumber Pemasukan disimpan sebagai `transaction_parties` dengan `kind = income_source`. Transaksi dapat menyimpan referensi `sourceId` ke data tersebut. Karena itu, perubahan Agent harus bersifat metadata-only: identitas sumber dan setiap referensi transaksi yang telah ada wajib dipertahankan.

## Tujuan Terbatas yang Disetujui

Menambahkan repository resmi Sumber Pemasukan, lalu mengizinkan Agent menargetkan **satu** Sumber Pemasukan aktif secara unik untuk memperbarui nama atau keterangan, serta mengarsipkannya secara lunak.

## Alur Wajib

Semua mutasi harus memakai **draft → preview/edit → konfirmasi eksplisit → executor allowlisted → repository resmi → audit lokal → readback**. Satu Action Plan hanya dapat membawa satu mutasi. Hasil target kosong atau ambigu harus meminta klarifikasi tanpa write.

## Mutasi yang Diizinkan

| Operasi | Boleh diubah | Tetap dipertahankan |
|---|---|---|
| Update | Nama atau keterangan satu sumber aktif | `id`, `householdId`, `kind = income_source`, `role`, status aktif, dan seluruh `transactions.sourceId` |
| Arsip | Status arsip lunak satu sumber | Data sumber tetap tersimpan dan seluruh referensi transaksi historis tetap sama |

## Larangan Keras

Agent tidak boleh menambah/menghapus/memindahkan `sourceId` pada transaksi; membuat transaksi; mengubah nominal, saldo, rekening, kategori, anggaran, Tag, atau pihak keluarga; mengubah `kind`/`role`; menghapus permanen; melakukan mass update; atau menjalankan SQL/CRUD langsung.

## Semantik Arsip

Arsip membuat sumber tidak tersedia bagi input transaksi baru, tetapi tidak mengubah sumber pada transaksi yang sudah tercatat. Readback harus memeriksa status arsip atau metadata baru melalui repository resmi.

## Regresi Wajib

Regresi harus membuktikan draft tidak menulis, target ambigu meminta klarifikasi, update dan arsip memakai repository/audit/readback, `kind` dan `role` tetap sama, dan daftar `sourceId` pada transaksi historis tidak berubah.
