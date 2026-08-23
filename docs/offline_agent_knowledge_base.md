# Pengetahuan Dasar FFM dan Kontrak Orchestrator

## 1. Identitas Aplikasi

**Nama:** Family Finance Manager (FFM)
**Tujuan:** Membantu pengguna mencatat keuangan pribadi dan keluarga, memantau saldo, mengatur anggaran, melacak aktivitas, dan menganalisis pengeluaran.
**Prinsip Utama:** Privasi penuh (data disimpan secara lokal), kontrol pengguna (tindakan permanen membutuhkan konfirmasi), dan fungsionalitas offline (termasuk asisten lokal).

## 2. Pemahaman Konteks Halaman (Page Context)

Orchestrator bekerja dengan membaca konteks halaman yang sedang aktif. Setiap halaman dalam FFM memiliki:
- **Destination ID:** Pengenal unik halaman (misal: `summary`, `transactions`, `masterData`).
- **Data Penting:** Informasi yang sedang ditampilkan (misal: daftar transaksi bulan ini, sisa anggaran).
- **Aksi yang Tersedia:** Tombol atau fungsi yang dapat dipanggil (misal: tambah transaksi, edit kategori).
- **Status Filter:** Filter yang sedang aktif (misal: hanya melihat rekening tertentu).

SLM harus menggunakan informasi ini untuk memahami pertanyaan kontekstual seperti "Berapa total pengeluaran di halaman ini?".

## 3. Registri Kemampuan (Capability Registry)

Orchestrator memiliki akses ke berbagai kemampuan (capability) yang dikelompokkan berdasarkan tingkat risikonya:

### A. Kemampuan Baca (Read-Only) - Risiko Rendah
- Membaca saldo rekening.
- Mencari transaksi berdasarkan tanggal, kategori, atau jumlah.
- Membaca riwayat aktivitas.
- Melihat daftar kategori atau tag.
*Aturan:* Dapat dieksekusi langsung tanpa konfirmasi.

### B. Kemampuan Navigasi - Risiko Rendah
- Berpindah antar halaman (misal: buka halaman Anggaran).
- Membuka form dengan data awal (draft).
*Aturan:* Dapat dieksekusi langsung tanpa konfirmasi.

### C. Kemampuan Persiapan (Drafting) - Risiko Menengah
- Mengisi form transaksi (pemasukan, pengeluaran, transfer).
- Menyiapkan form aset atau hutang.
*Aturan:* Menghasilkan status "Draft". Wajib menampilkan preview kepada pengguna sebelum eksekusi final.

### D. Kemampuan Eksekusi Final - Risiko Tinggi
- Menyimpan transaksi ke database.
- Menghapus data.
- Mengubah pengaturan keamanan (PIN).
*Aturan:* Wajib melalui tahap konfirmasi akhir (Final Confirmation). Tidak boleh dieksekusi secara otonom.

## 4. Alur Kerja (Workflow) Orchestrator

Setiap permintaan pengguna akan diproses melalui alur berikut:

1. **Interpretasi (SLM):** Menganalisis niat pengguna (intent), mengekstrak parameter (jumlah, tanggal, kategori), dan menentukan capability yang dibutuhkan.
2. **Validasi (Orchestrator):** Memeriksa apakah parameter sudah lengkap. Jika kurang, orchestrator akan bertanya kembali (Clarification).
3. **Perencanaan (Orchestrator):** Menyusun rencana langkah (Action Plan). Jika ada aksi berisiko menengah/tinggi, buat Draft.
4. **Preview (UI):** Menampilkan rencana atau draf kepada pengguna dalam format yang mudah dibaca.
5. **Konfirmasi (Pengguna):** Pengguna menyetujui, membatalkan, atau meminta perubahan.
6. **Eksekusi (Orchestrator):** Menjalankan capability sesuai rencana yang disetujui.
7. **Laporan (UI):** Memberitahukan hasil eksekusi kepada pengguna.

## 5. Aturan Penanganan Error dan Ambiguitas

- Jika SLM tidak yakin dengan kategori transaksi, pilih "Lain-lain" atau biarkan kosong dan minta pengguna melengkapi.
- Jika pengguna meminta aksi yang tidak didukung (misal: "Beli saham"), orchestrator harus dengan jelas menyatakan bahwa fitur tersebut tidak tersedia.
- Jika terjadi error saat eksekusi (misal: saldo tidak cukup untuk transfer), orchestrator harus membatalkan aksi dan melaporkan alasan kegagalan.

## 6. Pembelajaran Terkontrol (Controlled Learning)

- Orchestrator dapat mengenali pola (misal: "Beli kopi selalu masuk kategori Makanan & Minuman").
- Pola ini tidak langsung diterapkan. Orchestrator harus mengusulkan: "Apakah Anda ingin saya selalu memasukkan 'beli kopi' ke kategori Makanan & Minuman?"
- Jika disetujui, pola ini disimpan di database lokal (SQLite) sebagai **Memori Asisten**, terpisah dari data transaksi.
- Memori ini akan diekspor saat backup JSON dan dapat dipulihkan di perangkat lain.
