# Spesifikasi Catatan Harian — Aktivitas & Jurnal

## Batas Produk

Catatan Harian adalah teks bebas lokal yang tampil sebagai section di halaman **Aktivitas & Jurnal**. Catatan bukan sesi bertimer, tidak memakai tabel `activity_*`, tidak menambah item navbar, dan tidak mengubah data finansial.

## Data Minimum

Setiap catatan menyimpan ID lokal, household ID lokal, tanggal catatan, judul opsional, isi, timestamp dibuat/diubah, serta status arsip. Isi dibatasi dan disanitasi sebelum disimpan atau diekspor. Hapus permanen tidak akan menjadi capability Agent.

## Alur Pengguna

Pengguna dapat menambah, mengubah, mengarsipkan, dan membaca catatan dari section Catatan pada halaman Aktivitas & Jurnal. Aktivitas bertimer, checkpoint, suara, dan filter aktivitas tetap berjalan seperti sebelumnya.

## Batas Agent

Agent hanya boleh menyiapkan draft Catatan Harian, menampilkan preview, lalu menyimpan setelah konfirmasi eksplisit. Setelah simpan, repository membaca ulang catatan yang tersimpan. Kunci idempotensi yang sama dengan isi sama tidak boleh membuat catatan ganda; isi berbeda dengan kunci yang sama wajib ditolak. Agent tidak boleh menulis otomatis, menghapus permanen, atau mencampur catatan dengan transaksi.

## Pengujian Wajib

Migrasi Drift harus mempertahankan data lama. Regresi harus mencakup sanitasi, draft → konfirmasi → simpan → readback, arsip, dan isolasi dari tabel `activity_*`.
