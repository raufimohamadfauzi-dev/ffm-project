# Spesifikasi Pembaruan Tag — Agent FFM

## Tujuan

Agent FFM dapat mengubah nama atau mengarsipkan secara lunak **satu Tag aktif** yang cocok secara unik. Tag hanya merupakan metadata penanda; perubahan ini tidak membuat, menghapus, atau mengubah relasi Tag pada transaksi.

## Boundary Persistence

`TagRepository` menjadi jalur persistence resmi untuk baca Tag aktif, create, update nama, dan arsip lunak. Tab Tag pada halaman Data Utama serta executor Agent memakai repository ini. Repository memvalidasi nama, menolak duplikasi nama aktif, mencatat audit lokal, dan tidak pernah menulis tabel `transaction_tags`.

## Alur Agent

Semua perintah berjalan melalui **draft → preview/edit → konfirmasi eksplisit → executor allowlisted → TagRepository → audit lokal → readback**. Target harus tepat satu; hasil nol atau lebih dari satu hanya menghasilkan klarifikasi tanpa write. Satu Action Plan berisi maksimal satu mutasi.

## Batas Mutasi

| Operasi | Diizinkan | Dilarang |
|---|---|---|
| Update | Nama satu Tag aktif | Tambah, hapus, pindah, atau ubah relasi `transaction_tags` |
| Arsip | `isArchived=true` melalui repository | Hapus permanen Tag atau mass update transaksi |
| Readback | Membaca nama dan status arsip Tag | Membaca/menulis nominal, saldo, kategori, rekening, maupun anggaran |

## Dampak Historis

Mengganti nama Tag dapat menampilkan nama baru pada transaksi yang sebelumnya sudah memiliki relasi ke Tag tersebut. Namun, id Tag dan setiap pasangan `transactionId`–`tagId` tetap sama. Mengarsipkan Tag hanya menyembunyikannya dari pilihan Tag baru; histori tetap utuh.

## Regresi Wajib

Regresi membuktikan draft tidak menulis metadata atau relasi, target ambigu meminta klarifikasi, update dan arsip memakai repository/audit/readback, serta relasi Tag historis tidak berubah.
