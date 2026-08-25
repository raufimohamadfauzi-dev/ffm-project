# Spesifikasi Pembaruan Rekening — Agent FFM

## Status dan Ruang Lingkup

Spesifikasi ini berasal dari audit read-only yang telah **disetujui pengguna** dan diterapkan tanpa perubahan schema Drift. Implementasi menyediakan `AccountRepository`, refactor UI Data Utama, parser lokal, capability allowlist, executor serial, audit lokal, readback, dan regresi khusus. Tidak ada APK, migrasi schema, cloud, sinkronisasi, atau perubahan formula keuangan dalam milestone ini.

## Temuan Teknis

Rekening menyimpan `id`, `householdId`, `name`, `type`, `openingBalance`, `isActive`, `isArchived`, dan `createdAt`. Saldo buku tidak tersimpan sebagai nilai terpisah; saldo dihitung dari saldo awal, seluruh transaksi aktif pada rekening, serta transfer masuk dan keluar.

> **Saldo buku = `openingBalance` + jumlah transaksi aktif − transfer keluar + transfer masuk.**

Referensi Rekening juga digunakan oleh transaksi berkala untuk membuat transaksi atau menghitung peringatan saldo, serta oleh log rekonsiliasi untuk menyimpan catatan pemeriksaan saldo. Mengubah saldo awal, tipe, atau memindahkan referensi rekening dapat mengubah saldo tampilan dan histori secara tidak aman.

| Elemen | Dampak | Risiko mutasi Agent |
|---|---|---|
| `name` | Label tampilan Rekening | Rendah bila id dan seluruh referensi dipertahankan |
| `type` | Semantik jenis tunai/bank/e-wallet dan tampilan | Tinggi; tidak boleh diubah Agent |
| `openingBalance` | Komponen langsung saldo buku | Kritis; tidak boleh diubah Agent |
| `isActive` / `isArchived` | Ketersediaan Rekening untuk input dan laporan | Tinggi; arsip hanya boleh pada rekening tidak pernah dipakai |
| `transactions.accountId` | Saldo dan histori transaksi | Kritis; tidak boleh disentuh |
| `transfers.fromAccountId` / `toAccountId` | Saldo antar-Rekening | Kritis; tidak boleh disentuh |
| `recurring_transactions.accountId` | Aturan transaksi otomatis dan saldo | Kritis; tidak boleh disentuh |
| `account_reconciliation_logs.accountId` | Jejak rekonsiliasi saldo | Kritis; tidak boleh disentuh |

## Kontrak yang Disetujui

### Tujuan Sangat Terbatas

Membuat repository resmi Rekening dan mengizinkan Agent menargetkan **satu Rekening aktif yang cocok secara unik** untuk:

1. Mengubah **nama** Rekening saja; atau
2. Mengarsipkan secara lunak **hanya bila Rekening belum pernah dipakai oleh referensi apa pun**.

### Alur Wajib

Setiap mutasi wajib memakai **draft → preview/edit → konfirmasi eksplisit → executor allowlisted → repository resmi → audit lokal → readback**. Satu Action Plan maksimal memuat satu mutasi. Target kosong atau ambigu harus berhenti pada klarifikasi tanpa write.

### Field yang Dipertahankan

Update nama wajib mempertahankan `id`, `householdId`, `type`, `openingBalance`, `isActive`, `isArchived`, dan `createdAt`. Agent tidak boleh menawarkan perubahan saldo awal atau tipe. Arsip hanya boleh mengubah `isArchived` pada target yang lolos seluruh guard.

### Guard Arsip Wajib

Arsip ditolak jika Rekening memiliki **satu saja** referensi pada transaksi, transfer masuk/keluar, transaksi berkala, atau log rekonsiliasi—terlepas dari status histori. Ini adalah batas konservatif agar tidak ada Rekening bersaldo atau memiliki jejak keuangan yang hilang dari tampilan aktif.

### Larangan Keras

Agent dilarang mengubah `openingBalance`, `type`, `isActive`, `transactions.accountId`, `transfers.fromAccountId`, `transfers.toAccountId`, `recurring_transactions.accountId`, atau `account_reconciliation_logs.accountId`. Agent juga dilarang membuat transaksi, transfer, penyesuaian rekonsiliasi, transaksi berkala, perubahan saldo, penggabungan Rekening, hapus permanen, mass update, dan SQL/CRUD langsung.

### Semantik Arsip

Arsip hanya ditujukan untuk Rekening kosong dan belum pernah digunakan. Untuk Rekening yang sudah dipakai, Agent wajib menjelaskan guard yang memblokir arsip dan meminta pengguna menyelesaikan perpindahan atau penanganan histori melalui kontrak masa depan yang terpisah.

### Regresi yang Diterapkan

Regresi `ffm_assistant_account_mutation_test.dart` membuktikan draft tidak menulis, target ambigu dan target terlalu pendek meminta klarifikasi, update nama menjaga seluruh field terlindungi serta saldo buku, dan arsip hanya berhasil pada Rekening tanpa referensi. Guard diuji terpisah untuk transaksi, Rekening asal transfer, Rekening tujuan transfer, transaksi berkala, dan log rekonsiliasi. Regresi juga memastikan mutasi Agent tidak membuat transaksi atau transfer baru serta mencatat audit lokal dan hasil readback.

## Implementasi dan Batas Readback

`AccountRepository.updateName` hanya dapat mengubah `name`. `AccountRepository.archive` melakukan pengecekan referensi ulang tepat sebelum menulis `isArchived = true`; `isActive` tetap dipertahankan. Executor Agent memeriksa guard pada fase preview dan sekali lagi sebelum write. Setelah write, verifier membaca kembali `id`, `householdId`, `type`, `openingBalance`, `isActive`, `isArchived`, dan `createdAt`.

UI **Data Utama → Rekening** juga memakai repository yang sama untuk tambah, ubah manual, dan arsip. Jika arsip Rekening ditolak karena jejak data, UI menampilkan alasan guard dan tidak mengubah data. Pengubahan saldo awal atau tipe melalui UI manual tetap berada di luar capability Agent dan tidak dibuka oleh bahasa perintah.
