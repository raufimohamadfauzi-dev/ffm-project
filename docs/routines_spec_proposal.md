# Spesifikasi Rutinitas — Personal Life Manager

## Batas Produk

Rutinitas adalah kebiasaan atau tindakan berulang yang ingin ditandai pengguna, bukan daftar Tugas satu kali, bukan sesi Aktivitas bertimer, bukan Catatan Harian, dan bukan Jadwal kalender. Implementasi pertama berada sebagai section di halaman **Aktivitas & Jurnal** tanpa navbar baru. Rutinitas tidak boleh membuat transaksi, saldo, notifikasi, atau tindakan otomatis.

## Data Minimum

Setiap Rutinitas menyimpan ID lokal, household ID, judul wajib, catatan opsional, pola hari mingguan opsional, status aktif, arsip lunak, serta timestamp dibuat/diubah. Setiap penandaan pelaksanaan disimpan pada tabel riwayat terpisah dengan tanggal lokal, waktu penandaan, dan catatan opsional agar satu Rutinitas dapat ditandai beberapa hari tanpa mengubah definisinya.

## Alur Pengguna

Pengguna dapat menambah, membaca, menyunting, mengaktifkan atau menonaktifkan, mengarsipkan, serta menandai Rutinitas selesai untuk hari tertentu. Penandaan untuk hari yang sama bersifat idempoten: pengulangan tidak membuat riwayat ganda. Membatalkan penandaan hanya menghapus status pelaksanaan untuk hari itu lewat aksi eksplisit pengguna, bukan menghapus Rutinitas atau riwayat lain.

## Batas Agent

Agent hanya boleh membuat draft tambah/ubah/tandai selesai/batalkan tanda/aktifkan/nonaktifkan/arsip, kemudian preview dan konfirmasi eksplisit sebelum executor allowlisted memakai repository resmi, audit lokal, dan readback verification. Resolusi target wajib tunggal. Tidak ada hapus permanen, penandaan otomatis, notifikasi otomatis, atau tindakan proaktif yang langsung mengubah Rutinitas.

## Kriteria Validasi

Migrasi Drift harus mempertahankan data lama serta tidak mengubah tabel `activity_*`, `daily_notes`, atau `tasks`. Test mencakup batas teks, pola hari, idempotensi pelaksanaan per hari, pembatalan eksplisit, soft-archive, isolasi domain, draft tanpa write, konfirmasi wajib, audit, readback, dan target ambigu.

## Di Luar Scope Tahap Rutinitas

Jadwal kalender dengan waktu mulai/akhir, pengingat atau notifikasi Rutinitas, delegasi anggota keluarga, recurring transaction, sinkronisasi cloud, serta otomatisasi berbasis saran akan dikerjakan pada domain berikutnya atau hanya setelah izin eksplisit pengguna.
