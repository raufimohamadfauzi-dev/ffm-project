# Spesifikasi Pembaruan Toko/Tempat — Agent FFM

## Tujuan

Agent FFM dapat mengubah **nama** atau **keterangan** satu Toko/Tempat aktif yang cocok secara unik, serta mengarsipkannya secara lunak. Toko/Tempat adalah metadata transaksi; transaksi historis tetap menyimpan referensi id yang sama dan tidak boleh dimodifikasi oleh milestone ini.

## Boundary Persistence

`MerchantRepository` menjadi jalur persistence resmi untuk baca aktif, create, update metadata, dan archive. Halaman Data Utama pada tab Toko/Tempat serta executor Agent memakai repository tersebut. Repository melakukan sanitasi input, validasi nama unik untuk data aktif, dan audit lokal.

## Alur Agent

Setiap perintah berjalan melalui **draft → preview/edit → konfirmasi eksplisit → executor allowlisted → MerchantRepository → audit lokal → readback**. Target harus tepat satu; hasil nol atau lebih dari satu hanya menghasilkan klarifikasi tanpa write. Satu Action Plan membawa paling banyak satu mutasi.

## Batas Mutasi

| Operasi | Diizinkan | Dilarang |
|---|---|---|
| Update | Nama atau keterangan Toko/Tempat aktif | Ubah id, household id, merchant id pada transaksi, atau transaksi historis |
| Arsip | `isActive=false` melalui repository | Hapus permanen, pindah/gabung histori, atau ubah transaksi baru maupun lama |
| Penyimpanan | Repository resmi dan audit/readback | SQL atau CRUD langsung dari model Agent |

## Larangan Lintas-Domain

Milestone ini tidak mengubah Rekening, Kategori, Tag, Sumber Pemasukan, Profil keluarga, saldo, anggaran, transaksi, transfer, aset, hutang, piutang, maupun jadwal. Tidak ada cloud, notifikasi, otomasi, APK/AAB, atau bump versi.

## Regresi Wajib

Regresi membuktikan draft tidak melakukan write, target ambigu meminta klarifikasi, update nama/keterangan memakai verifier readback, archive bersifat lunak, audit tercatat, dan tidak ada transaksi yang dibuat atau diubah.
