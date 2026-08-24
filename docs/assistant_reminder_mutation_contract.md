# Kontrak Mutasi Pengingat oleh Agent

Dokumen ini mengunci aturan sebelum Agent memperoleh capability perubahan pengingat. Pengingat bukan data tabel biasa: setiap perubahan dapat mengubah alarm Android, riwayat kejadian, aksi latar belakang, dan deep link ke halaman Pengingat.

## Aturan yang tidak boleh dilanggar

| Operasi Agent | Urutan wajib | Kondisi gagal aman |
|---|---|---|
| Ubah pengingat | Temukan satu pengingat aktif → tampilkan draft berisi judul/waktu saat ini dan usulan → konfirmasi eksplisit → cek izin → cancel jadwal lama → simpan melalui `ReminderRepository` → hitung kejadian baru → simpan history → schedule ulang → readback. | Bila izin/jadwal tidak tersedia, tidak ada perubahan database. |
| Arsip pengingat | Temukan satu pengingat aktif → preview dampak → konfirmasi → cancel kejadian berikut dan ID dasar → `setActive(false)` melalui repository → readback. | Data dan history tidak dihapus; pengingat tetap dapat dibuka kembali dari halaman Pengingat. |
| Hapus permanen | Tidak menjadi capability Agent pada fase ini. | Penghapusan dari chat ditolak dan diarahkan ke halaman Pengingat agar user melihat dampak history. |

## Dependency yang wajib diinjeksi

Adapter Agent tidak boleh menulis langsung ke tabel `reminders` untuk mutasi. Implementasi harus menerima `ReminderRepository`, `ReminderNotificationGateway`, dan `ReminderOccurrenceCalculator` dari dependency injection yang sama dengan `ReminderBloc`. Test harus memakai gateway palsu yang mencatat operasi `cancel`/`schedule`; tidak boleh menganggap penyimpanan DB saja sebagai sukses.

## Bukti verifikasi minimal

Setiap test integrasi pengingat harus membuktikan bahwa target ambigu tidak dipilih diam-diam, mutasi belum berjalan sebelum konfirmasi, jadwal lama dibatalkan, jadwal baru dibuat bila aktif, status/history dibaca kembali, serta error izin tidak meninggalkan perubahan database parsial.
