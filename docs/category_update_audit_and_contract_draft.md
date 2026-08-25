# Spesifikasi Pembaruan Kategori — Agent FFM

## Status Audit

Audit ini **read-only**. Belum ada repository Kategori, handler Agent, perubahan database, maupun mutasi data yang dibuat untuk Kategori.

## Temuan Teknis

Kategori memiliki field `id`, `householdId`, `name`, `type`, `parentId`, `defaultBudgetPeriod`, `isActive`, dan `createdAt`. Satu kategori dapat dirujuk oleh transaksi melalui `transactions.categoryId`, transaksi berkala melalui `recurring_transactions.categoryId`, Target Keuangan melalui `goals.categoryId`, serta anggaran amplop melalui daftar `envelope_budgets.categoryIdsJson`.

Halaman Anggaran menghitung pengeluaran berdasarkan kategori transaksi dan juga menelusuri `parentId` untuk menganggap transaksi subkategori sebagai bagian dari amplop kategori induk. Karena itu, perubahan `type`, `parentId`, atau `defaultBudgetPeriod` dapat mengubah klasifikasi, cakupan Anggaran, saran periode, dan analisis tanpa mengubah nominal transaksi. Field-field tersebut tidak aman untuk mutasi Agent metadata umum.

| Elemen | Dampak | Risiko mutasi Agent |
|---|---|---|
| `name` | Label tampilan pada transaksi dan Anggaran | Rendah bila id tidak berubah |
| `type` | Membedakan pemasukan/pengeluaran | Tinggi; dapat mengubah klasifikasi dan analisis |
| `parentId` | Hierarki kategori/subkategori dan cakupan Anggaran | Tinggi; dapat mengubah perhitungan amplop |
| `defaultBudgetPeriod` | Saran periode konfigurasi Anggaran | Menengah–tinggi; berdampak pada perilaku setup Anggaran |
| `isActive` | Ketersediaan untuk input baru | Menengah; aman hanya sebagai arsip lunak target tunggal |
| `transactions.categoryId` | Kategori historis tiap transaksi | Kritis; tidak boleh disentuh |
| `envelopeBudgets.categoryIdsJson` | Cakupan kategori pada Anggaran | Kritis; tidak boleh disentuh |
| `goals.categoryId` | Kategori yang dikaitkan dengan Target Keuangan | Kritis; tidak boleh disentuh |

## Kontrak Mutasi yang Disetujui

### Tujuan Terbatas

Membuat repository resmi Kategori dan mengizinkan Agent menargetkan **satu kategori aktif yang cocok secara unik** untuk:

1. Mengubah **nama** kategori saja; atau
2. Mengarsipkan kategori secara lunak (`isActive=false`) saja.

### Alur Wajib

Setiap mutasi harus melalui **draft → preview/edit → konfirmasi eksplisit → executor allowlisted → repository resmi → audit lokal → readback**. Satu Action Plan maksimal memuat satu mutasi. Target kosong atau ambigu wajib berhenti pada klarifikasi tanpa write.

### Field yang Dipertahankan

Update nama wajib mempertahankan `id`, `householdId`, `type`, `parentId`, `defaultBudgetPeriod`, `isActive`, dan `createdAt`. Arsip hanya dapat mengubah `isActive` dari `true` menjadi `false` pada target tunggal.

### Larangan Keras

Agent tidak boleh mengubah atau memindahkan `transactions.categoryId`, `recurring_transactions.categoryId`, `goals.categoryId`, atau `envelope_budgets.categoryIdsJson`. Agent juga tidak boleh mengubah tipe pemasukan/pengeluaran, hierarki induk/subkategori, periode Anggaran default, nominal, saldo, rekening, Tag, transaksi, transfer, Anggaran, Target Keuangan, maupun menjalankan transaksi berkala.

### Semantik Arsip dan Batas Risiko

Arsip hanya menyembunyikan kategori dari input baru. Transaksi, transaksi berkala, dan amplop Anggaran yang sudah memiliki referensi kategori tetap tidak diubah. Nama kategori baru dapat muncul pada label histori karena id kategori dipertahankan; ini adalah perubahan tampilan metadata, bukan perpindahan transaksi.

### Guard Tambahan yang Wajib Diimplementasikan

Sebelum arsip, repository harus menolak kategori yang masih dipakai sebagai `parentId` oleh kategori aktif lain. Kontrak ini juga mengusulkan penolakan arsip bila kategori masih direferensikan oleh transaksi berkala aktif, Target Keuangan aktif, atau amplop Anggaran aktif, kecuali pengguna menyetujui kontrak lanjutan untuk menangani dependensi tersebut. Larangan ini menghindari kategori baru menjadi tidak dapat dipilih sementara aturan otomatis, Target Keuangan, atau Anggaran aktif masih merujuknya.

### Regresi Wajib

Test harus membuktikan draft tanpa write, target ambigu meminta klarifikasi, update nama menjaga seluruh field terlindungi, arsip hanya terjadi bila tidak ada dependensi aktif yang dilarang, audit/readback berjalan, dan tidak ada perubahan pada relasi kategori transaksi, transaksi berkala, Target Keuangan, atau Anggaran.
