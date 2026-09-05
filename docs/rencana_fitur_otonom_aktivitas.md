# Rencana Fitur Baru Otonom (Halaman Aktivitas)

Dokumen ini difokuskan secara eksklusif untuk merencanakan dan mengelola fitur-fitur baru yang otonom untuk Halaman Aktivitas. Konteks tidak ditambah maupun dikurangi dari batas aktivitas harian dan asisten otonom aktivitas.

## 1. Analisis Otonom Durasi Aktivitas
Asisten mampu mengevaluasi durasi waktu yang dihabiskan pada setiap kategori (misalnya 'Perjalanan' atau 'Kerja'). 
- Jika asisten mendeteksi durasi kerja melebihi batas wajar, ia dapat menawarkan opsi istirahat secara mandiri tanpa harus diminta.
- Menyediakan "Daily Activity Summary" yang digenerate oleh AI berdasarkan catatan pengguna (Voice/Timer/Notes).

## 2. Pengelolaan Multi-Tasking Otomatis
- **Mendeteksi Irregularitas Sesi:** Asisten otonom akan memberi peringatan jika pengguna memulai aktivitas timer baru saat ada timer dari sesi sebelumnya yang belum di-stop (atau belum di-update) dalam waktu yang terlalu lama (misalnya lebih dari 8 jam).
- **Penutupan Sesi Cerdas:** Memberikan rekomendasi otonom untuk menutup aktivitas "Perjalanan" apabila terdeteksi bahwa pengguna baru saja mencatat "Kerja" di lokasi (bisa diidentifikasi melalui riwayat aktivitas atau voice note).

## 3. Asisten Pembuat Checkpoint Proaktif
Saat aktivitas prioritas berjalan, agen otonom dapat mengirimkan reminder terstruktur di chat (jika user sedang berada di halaman aktivitas) untuk menanyakan, *"Kamu masih mengerjakan {nama_aktivitas}? Perlu tambah update checkpoint baru?"*

## 4. Kategorisasi Suara (Auto-Categorization) Lanjutan
Meskipun saat ini asisten sudah bisa menangkap intent suara dan menaruhnya dalam format form/draft:
- Mengonfirmasi pencatatan aktivitas rutin berulang. Jika pengguna tiap pagi mencatat aktivitas yang sama, asisten akan menyimpan pattern tersebut, dan di waktu selanjutnya bisa memunculkan rekomendasi satu-klik dari FAB.

## 5. Ringkasan "Smart Empty State"
Ketika pengguna belum melakukan aktivitas apapun hari ini, *Empty State* pada halaman aktivitas tidak lagi hanya statis, melainkan agen AI akan memberikan sapaan proaktif dan memberikan shortcut *"Mulai jadwal rutin yang biasa kamu lakukan pagi ini?"*

---
*(Hanya untuk fitur otonom halaman aktivitas)*
