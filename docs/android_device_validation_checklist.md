# Checklist Validasi Android Nyata — FFM

Dokumen ini digunakan **setelah source telah lolos analyzer dan regresi** untuk memeriksa integrasi yang memang membutuhkan perangkat Android. Setiap pengujian memakai data uji, tidak memerlukan cloud, dan tidak boleh mem-bypass PIN maupun konfirmasi mutasi Agent.

| Area | Langkah uji di perangkat | Hasil yang diharapkan |
|---|---|---|
| Notifikasi Pengingat | Buat satu pengingat uji untuk waktu dekat, tunggu notifikasi, lalu ketuk notifikasi dan aksi selesai bila tersedia. | Aplikasi membuka tujuan Pengingat yang tepat; ketukan tidak menghapus data; aksi selesai hanya mengubah history melalui jalur resmi. |
| Deep link | Ketuk notifikasi yang sama kembali atau buka aplikasi dari status bar sesudah aplikasi ditutup. | Tujuan tidak terbuka berulang atau menghasilkan history duplikat; navigasi tetap memiliki jalan kembali. |
| Suara dan mikrofon | Mulai, jeda, lanjutkan, lalu hentikan pembacaan jawaban; coba input suara jika izin diberikan. | Ikon selalu sesuai status playback; tidak ada pemutaran ganda; penolakan izin menampilkan pesan yang jelas tanpa crash. |
| PIN dan privasi | Ubah PIN memakai empat digit, ulangi verifikasi, tutup aplikasi, lalu buka kembali. | Kolom verifikasi kosong saat pengulangan; PIN salah tidak membuka data; data PIN tidak pernah ditampilkan di chat. |
| Model lokal | Buka Model Asisten Lokal, refresh status, pasang atau impor model uji bila tersedia, kemudian tutup dan buka kembali halaman. | Spinner tidak tanpa batas; status jelas; model yang sudah ada tidak diunduh ulang; gagal impor memberi tindakan pemulihan. |
| Asisten dan saran | Buka chat baru pada Transaksi atau Anggaran, tutup, lalu buka kembali dalam kurang dari 30 menit. Kirim satu pesan pengguna. | Saran proaktif yang sama tidak berulang dalam cooldown pada halaman sama; setelah pesan pengguna, kartu saran hilang; tidak ada mutasi otomatis. |
| Berbagi dan impor | Ekspor cadangan atau JSON uji, bagikan ke aplikasi file, lalu impor kembali hanya pada data uji. | Intent berbagi terbuka; validasi file menolak format salah; preview dan konfirmasi tetap muncul sebelum write. |
| Gambar/nota bila tersedia | Pilih gambar kecil atau foto uji dari kamera/galeri dan batalkan sekali. | Izin dan pembatalan ditangani tanpa crash; gambar tidak mengubah transaksi tanpa draft, preview, dan konfirmasi. |

> Bila satu langkah gagal, catat perangkat, versi Android, langkah reproduksi, screenshot atau video singkat, dan **Salin detail teknis** dari aplikasi bila tersedia. Jangan mengirim database keluarga, PIN, model besar, atau file cadangan nyata ke chat.

## Batas Validasi Sandbox

Sandbox tidak memiliki `adb`, Android SDK, emulator, atau perangkat Android terhubung. Karena itu, analyzer serta regresi Flutter membuktikan perilaku source yang dapat diuji lokal, sedangkan izin perangkat, intent sistem, status bar, audio, kamera, file picker, dan deep link tetap harus diperiksa melalui checklist ini pada perangkat nyata.
