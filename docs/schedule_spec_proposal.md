# Spesifikasi Jadwal — Personal Life Manager

## Batas Produk

Jadwal adalah catatan agenda lokal pada tanggal tertentu, dengan waktu mulai dan selesai opsional. Domain ini berbeda dari **Rutinitas** yang merupakan kebiasaan berulang dengan riwayat pelaksanaan per hari, **Tugas** yang merupakan tindakan satu kali, **Catatan Harian** yang berupa refleksi teks, serta **Aktivitas** yang mencatat durasi aktual melalui timer. Jadwal juga bukan Pengingat: tahap awal tidak membuat alarm, notifikasi, atau eksekusi otomatis apa pun.

Implementasi pertama ditempatkan sebagai section pada halaman **Aktivitas & Jurnal**, tanpa navbar baru. Domain Jadwal tidak boleh mengubah transaksi, saldo, target, aset, hutang, piutang, aktivitas bertimer, Rutinitas, atau Pengingat.

## Data Minimum

Setiap item Jadwal menyimpan ID lokal, household ID, judul wajib, catatan opsional, tanggal lokal wajib, penanda sepanjang hari, waktu mulai opsional, waktu selesai opsional, arsip lunak, serta timestamp dibuat dan diubah. Bila waktu selesai diisi, ia tidak boleh lebih awal daripada waktu mulai pada tanggal yang sama. Tahap ini tidak menyimpan aturan pengulangan; kebiasaan berulang tetap berada pada domain Rutinitas.

## Alur Pengguna

Pengguna dapat menambah, membaca, menyunting, memindahkan tanggal atau waktu, serta mengarsipkan item Jadwal. Jadwal yang berlangsung sepanjang hari ditampilkan tanpa jam. Pengguna menghapus tampilan aktif melalui arsip lunak; tidak ada hapus permanen pada domain Jadwal. Status selesai, alarm, notifikasi, dan pembuatan Aktivitas tidak terjadi otomatis dari Jadwal.

## Batas Agent

Agent hanya boleh menyiapkan draft tambah, ubah, pindahkan waktu/tanggal, atau arsip satu Jadwal setelah resolver menemukan satu target unik. Setiap operasi mengikuti **draft → preview/edit → konfirmasi eksplisit → executor allowlisted → repository resmi → audit lokal → readback verification**. Agent tidak membuat Jadwal, alarm, notifikasi, Aktivitas, Rutinitas, atau perubahan finansial secara proaktif dan tidak diberi SQL atau CRUD langsung.

## Kriteria Validasi

Migrasi Drift harus mempertahankan data lama dan tidak mengubah tabel `activity_*`, `daily_notes`, `tasks`, `daily_routines`, `daily_routine_completions`, `reminders`, atau tabel transaksi berkala. Test mencakup sanitasi dan batas teks, validasi tanggal/waktu, arsip lunak, idempotensi create lewat kunci penyimpanan, isolasi domain, draft tanpa write, target ambigu, konfirmasi wajib, audit, serta readback.

## Di Luar Scope Tahap Jadwal

Pengingat atau notifikasi Jadwal, alarm presisi, kalender eksternal, sinkronisasi cloud, undangan anggota keluarga, delegasi, pembuatan Aktivitas otomatis, eksekusi transaksi berkala, serta otomatisasi berbasis saran tidak termasuk tahap ini. Semua kemampuan tersebut tetap berada pada domain atau kontrak terpisah dan hanya dapat ditambahkan melalui persetujuan eksplisit berikutnya.
