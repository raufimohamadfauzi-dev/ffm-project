# Spesifikasi Pembaruan Aset — Agent FFM

## Tujuan dan Batas Domain

Aset tetap merupakan domain keuangan yang berdiri sendiri. Implementasi berikutnya hanya akan menambahkan kemampuan Agent untuk **memperbarui satu aset** dan **mengarsipkan satu aset secara lunak**, melalui usecase resmi `SaveAsset` dan `ArchiveAsset`. Domain ini tidak mengubah transaksi, saldo rekening, kategori, target keuangan, hutang/piutang, maupun data Aset lain.

## Data yang Boleh Diubah

| Field | Aturan update |
|---|---|
| Nama | Wajib, tidak kosong setelah sanitasi. |
| Jenis aset | Boleh diubah hanya bila disebutkan secara eksplisit. |
| Nilai | Wajib bilangan bulat tidak negatif; tidak membuat transaksi otomatis. |
| Penempatan | Boleh diubah bila disebutkan secara eksplisit. |
| Catatan | Opsional. |
| Identitas dan waktu dibuat | Selalu dipertahankan dari Aset resmi. |
| Status arsip | Hanya berubah melalui aksi arsip lunak eksplisit. |

## Alur Agent yang Dikunci

Agent hanya membaca kandidat Aset aktif secara lokal untuk mencari **tepat satu target**. Perintah update atau arsip yang tidak menemukan target, atau menemukan lebih dari satu kandidat, harus meminta klarifikasi tanpa menulis data. Setelah target tunggal didapat, Agent hanya membuat draft dan preview yang dapat diperiksa atau diedit pengguna. Mutasi baru berjalan setelah konfirmasi eksplisit, memakai usecase resmi, mencatat audit lokal, lalu membaca kembali record untuk verifikasi.

> Agent dan model lokal tidak boleh menulis SQL/CRUD langsung, tidak boleh membuat transaksi atau mutasi saldo dari pembaruan Aset, dan tidak boleh menghapus Aset permanen.

## Di Luar Scope

Tidak ada penghapusan permanen Aset oleh Agent, update massal, transaksi penyesuaian otomatis, notifikasi, cloud, atau perubahan navigasi utama. UI halaman Aset yang telah ada tetap menjadi pemilik form manual; integrasi ini hanya memperluas preview dan konfirmasi Agent.

## Kriteria Validasi

Regresi harus membuktikan bahwa resolver menolak target ambigu, interpreter tidak menulis database, draft membutuhkan konfirmasi, update menjaga `id`, `householdId`, dan `createdAt`, arsip bersifat lunak, audit tercatat, dan readback menyatakan hasil yang benar. `flutter analyze` dan seluruh suite test harus lulus sebelum checkpoint Git dibuat.
