# Spesifikasi Tugas — Personal Life Manager

## Batas Produk

Tugas adalah daftar tindakan keluarga yang selesai atau belum selesai. Tugas merupakan domain baru yang **terpisah** dari Catatan Harian, sesi `activity_*`, Rutinitas, Pengingat, dan Jadwal. Implementasi pertama akan tampil sebagai section pada halaman **Aktivitas & Jurnal**; tidak ada item navbar baru.

## Data Minimum

Setiap tugas menyimpan ID lokal, household ID, judul wajib, catatan opsional, tanggal target opsional, status `open` atau `completed`, timestamp selesai opsional, status arsip, serta timestamp dibuat/diubah. Tidak ada transaksi, saldo, nominal, atau relasi finansial yang dibuat dari tugas.

## Alur Pengguna

Pengguna dapat menambah, membaca, menyunting, menandai selesai atau membuka kembali tugas, serta mengarsipkan tugas. Arsip adalah soft-archive; penghapusan permanen tidak menjadi capability Agent. Tugas terlambat hanya ditampilkan sebagai informasi lokal dan tidak akan membuat notifikasi atau tindakan otomatis pada tahap ini.

## Batas Agent

Agent hanya boleh membuat draft tambah/ubah/selesai/buka kembali/arsip, menampilkan preview, lalu menjalankan perubahan setelah konfirmasi eksplisit. Setiap mutasi memakai executor allowlisted, repository resmi, audit lokal, dan readback verification. Perintah ambigu harus meminta klarifikasi. Agent tidak boleh menyelesaikan, mengarsipkan, atau menjadwalkan tugas secara otomatis dari saran proaktif.

## Kriteria Validasi

Migrasi Drift wajib mempertahankan data lama dan tidak mengubah tabel `activity_*` atau `daily_notes`. Test harus mencakup sanitasi dan batas teks, perubahan status, soft-archive, isolasi domain, draft tanpa write, konfirmasi wajib, idempotensi, audit, readback, dan target ambigu.

## Di Luar Scope Tahap Tugas

Rutinitas berulang, jadwal kalender, notifikasi tugas, delegasi anggota keluarga, sinkronisasi cloud, serta penjadwalan otomatis akan dikerjakan sebagai domain terpisah setelah Tugas selesai dan tervalidasi.
