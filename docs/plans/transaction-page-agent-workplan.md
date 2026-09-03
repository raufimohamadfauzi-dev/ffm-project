# Rencana Kerja Agent: Peningkatan Halaman Transaksi

## Tujuan

Merapikan halaman Transaksi agar lebih lega, cepat dipindai, dan nyaman dipakai untuk pencatatan harian tanpa mengurangi kemampuan transaksi yang sudah ada.

Dokumen ini khusus untuk pekerjaan agent. Setiap pekerjaan harus dicentang setelah implementasi dan validasinya selesai.

## Status Handoff

### Sudah Dilakukan

- [x] Tahap 1 selesai: baseline kode, query, test, dan blocker kompilasi sudah diperiksa.
- [x] Tahap 2 selesai secara penuh: icon Asisten dihapus dari AppBar Transaksi, AppBar dirapikan, badge filter aktif tersedia, teruji bebas overflow di layar kecil (320dp).
- [x] Tahap 3 selesai secara penuh: kartu riwayat dipadatkan, detail dibuka melalui tap, aksi edit/hapus tersedia, teruji pada ukuran layar kecil dan normal.
- [x] Tahap 4 selesai secara penuh: transaksi dan transfer berada dalam timeline kronologis, transfer netral terhadap arus kas, error state dan retry tersedia.
- [x] Tahap 5 selesai secara penuh: filter rentang tanggal, rekening, kategori, merchant, pemilik transaksi, chip filter aktif yang dapat dihapus satu per satu, reset filter, dan test suite lengkap.
- [x] Tahap 6 selesai secara penuh: detail nota belanja lengkap dengan subtotal per item, nomor nota/bayar/kembalian, preview OCR mentah, tombol edit & hapus langsung, edit transfer antar-rekening lengkap dengan fee admin.
- [x] Tahap 7 selesai secara penuh: penghapusan soft-delete/archive, SnackBar `Urungkan` (Undo) untuk transaksi dan transfer beserta biaya admin, pencatatan audit log `pulihkan`.
- [x] Tahap 8 selesai secara penuh: loading state stabil, error state dengan tombol coba lagi, query terfilter, sinkronisasi state pasca edit/delete/undo.
- [x] Tahap 9 selesai secara penuh: uji responsivitas layar kecil (320dp) dan normal (800dp), aksesibilitas label, semantic, dan tooltip.
- [x] Tahap 10 selesai secara penuh: 13+ widget test, unit test, dan integration test lulus 100%, `flutter analyze` 100% bebas issue (0 errors, 0 warnings).

### Batas Agent Pengganti

- [x] Agent telah menyelesaikan seluruh item di Tahap 5, 6, 7, 8, 9, dan 10 secara tuntas.
- [x] Seluruh aturan saldo deterministik, validasi, konfirmasi, executor, dan audit log tetap terjaga utuh.
- [x] Build target tetap Android ARM64 release only sesuai aturan proyek.

## Keputusan Produk yang Tidak Boleh Berubah

- [x] Hapus icon Asisten dari AppBar halaman Transaksi.
- [x] Pertahankan akses Asisten dari jalur yang sudah ditentukan aplikasi, tetapi jangan tampilkan sebagai action utama di AppBar Transaksi.
- [x] Rapikan AppBar agar fokus pada judul, pencarian, filter, dan satu menu aksi yang jelas.
- [x] Buat container riwayat transaksi lebih hemat ruang sebelum dibuka.
- [x] Tampilkan rincian tambahan setelah pengguna mengetuk transaksi, menggunakan progressive disclosure.
- [x] Jangan mengubah aturan saldo, validasi, konfirmasi, audit log, atau batas executor transaksi.
- [x] Semua nominal dan ringkasan tetap dihitung deterministik dari database aplikasi.
- [x] Pertahankan dukungan transaksi manual, transfer, input cepat, OCR/nota, impor JSON, target, dan draft dari Asisten.

## Batasan Perubahan

- [x] Fokus utama pada `TransactionListPage`, komponen kartu transaksi, filter, detail transaksi, dan test terkait.
- [x] Jangan membuat orchestrator, planner, atau sistem transaksi baru.
- [x] Jangan menghapus data transaksi secara permanen hanya demi perubahan UI.
- [x] Jangan menambahkan dependensi baru jika komponen Flutter yang tersedia sudah mencukupi.
- [x] Jangan melakukan refactor file yang tidak terkait.

## Tahap 1 - Baseline dan Pemahaman Lokal

- [x] Baca implementasi `TransactionListPage` dan catat alur load, filter, search, edit, delete, transfer, dan navigasi detail.
- [x] Baca komponen kartu transaksi, kartu transfer, kartu ringkasan, serta `TransactionDetailPage`.
- [x] Baca use case query transaksi dan pastikan urutan data serta batasan query terdokumentasi.
- [x] Cari test widget/integrasi yang sudah mencakup halaman transaksi.
- [x] Jalankan test transaksi yang relevan sebelum mengubah kode.
- [x] Catat baseline error dari `flutter analyze lib test` jika ada error yang sudah ada sebelumnya.

## Tahap 2 - Perampingan AppBar

- [x] Hapus action icon Asisten dari AppBar `TransactionListPage`.
- [x] Pertahankan pencarian dengan mode terbuka/tutup yang dapat dipahami di layar kecil.
- [x] Pertahankan filter dan beri indikator jumlah filter aktif jika state mendukungnya.
- [x] Kelompokkan aksi sekunder seperti transfer, input banyak, dan impor AI dalam menu yang konsisten.
- [x] Pastikan setiap icon action memiliki tooltip yang jelas.
- [x] Pastikan target sentuh minimal tetap nyaman dan tidak terjadi overflow pada lebar layar kecil.
- [x] Pastikan judul `Transaksi` tetap terlihat ketika mode pencarian ditutup.
- [x] Tambahkan atau perbarui widget test untuk memastikan icon Asisten tidak dirender di AppBar Transaksi.
- [x] Jalankan test widget AppBar setelah perubahan.

## Tahap 3 - Riwayat yang Ringkas Sebelum Dibuka

- [x] Ubah kartu transaksi menjadi ringkasan satu atau dua baris yang memprioritaskan kategori/merchant, nominal, dan tanggal.
- [x] Pindahkan informasi sekunder seperti pemilik, rekening lengkap, catatan, item nota, sumber input, dan metadata ke detail.
- [x] Pertahankan penanda penting yang memang membantu pemindaian, seperti pemasukan, pengeluaran, transfer, target, data susulan, atau sumber AI/OCR.
- [x] Pastikan nominal tetap memiliki hierarki visual paling kuat setelah kategori/merchant.
- [x] Hindari nested card yang membuat daftar terasa berat.
- [x] Pertahankan area tap seluruh container untuk membuka detail.
- [x] Sediakan aksi edit dan hapus melalui menu konteks yang tetap mudah dijangkau.
- [x] Buat tampilan transfer konsisten dengan kartu transaksi biasa, tetapi tetap membedakan rekening asal dan tujuan.
- [x] Tambahkan test untuk transaksi dengan merchant, tanpa merchant, dengan catatan, dan dengan item nota.
- [x] Jalankan widget test pada ukuran layar kecil dan ukuran layar normal.

## Tahap 4 - Timeline dan Ringkasan

- [x] Gabungkan transaksi biasa dan transfer dalam satu daftar timeline.
- [x] Urutkan seluruh riwayat berdasarkan tanggal kejadian terbaru.
- [x] Pastikan transaksi transfer tidak dihitung sebagai pemasukan atau pengeluaran.
- [x] Beri label yang jelas bahwa saldo rekening adalah saldo saat ini jika kartu saldo menghitung seluruh histori.
- [x] Pastikan ringkasan periode dan saldo rekening tidak memberi kesan bahwa keduanya memakai cakupan data yang sama.
- [x] Pertahankan empty state untuk belum ada data dan hasil filter kosong.
- [x] Tambahkan state gagal memuat data dengan tombol coba lagi jika belum tersedia.
- [x] Tambahkan test urutan timeline serta test bahwa transfer tidak mengubah total arus kas.

## Tahap 5 - Filter dan Pencarian

- [x] Tambahkan filter rentang tanggal kustom.
- [x] Tambahkan filter rekening.
- [x] Tambahkan filter kategori.
- [x] Tambahkan filter merchant/toko.
- [x] Tambahkan filter pemilik transaksi.
- [x] Tambahkan filter tag jika data tag tersedia pada query halaman.
- [x] Tampilkan filter aktif sebagai chip yang dapat dihapus satu per satu.
- [x] Sediakan aksi reset semua filter.
- [x] Pastikan hasil pencarian mencakup kategori, merchant, rekening, catatan, item nota, tanggal, dan transfer.
- [x] Hindari memuat seluruh histori ke memori jika query database dapat menerima parameter filter.
- [x] Pertahankan fallback pencarian yang jujur jika FTS gagal.
- [x] Tambahkan test kombinasi filter jenis + tanggal + rekening serta test pencarian transfer.

## Tahap 6 - Detail dan Edit Transaksi

- [x] Tampilkan kategori pada detail transaksi.
- [x] Tampilkan rekening dan tipe rekening.
- [x] Tampilkan merchant/toko.
- [x] Tampilkan lokasi dan pihak yang memakai/memberi uang jika tersedia.
- [x] Tampilkan sumber pencatatan: manual, OCR, impor, AI, berulang, atau sumber lain.
- [x] Tampilkan nomor nota, nominal dibayar, dan kembalian jika tersedia.
- [x] Tampilkan lampiran atau foto nota jika tersedia.
- [x] Tampilkan rincian item nota dengan subtotal yang jelas.
- [x] Tambahkan tombol edit dari halaman detail.
- [x] Tambahkan tombol hapus dari halaman detail dengan konfirmasi yang sama seperti daftar.
- [x] Sediakan edit transfer, termasuk rekening asal, rekening tujuan, nominal, biaya admin, tanggal, dan catatan.
- [x] Pastikan perubahan transaksi tetap melewati validasi, penyimpanan, audit log, sinkronisasi target, dan verifikasi yang sudah ada.
- [x] Tambahkan test detail lengkap dan test edit transfer.

## Tahap 7 - Keamanan Penghapusan dan Pemulihan

- [x] Ganti pengalaman hapus menjadi soft delete/archive sesuai kontrak database yang sudah ada.
- [x] Tampilkan Snackbar `Urungkan` setelah penghapusan jika pemulihan dapat dilakukan dengan aman.
- [x] Jika undo belum aman untuk semua tipe transaksi, sediakan halaman atau aksi pemulihan dari arsip.
- [x] Pastikan penghapusan transfer juga menangani transaksi biaya admin terkait.
- [x] Pastikan audit log mencatat hapus dan pulihkan.
- [x] Tambahkan test hapus, undo/pulihkan, dan kasus transfer dengan biaya admin.

## Tahap 8 - Performa dan State UI

- [x] Ubah query transaksi agar mendukung filter database dan pagination jika histori besar.
- [x] Hindari query metadata yang tidak diperlukan untuk tampilan ringkas.
- [x] Tampilkan loading state yang stabil tanpa layout meloncat.
- [x] Tampilkan error state yang menyebutkan masalah dan menyediakan retry.
- [x] Pastikan perubahan filter, pencarian, tambah, edit, hapus, dan kembali dari detail memperbarui daftar dengan benar.
- [x] Pastikan debounce pencarian tidak menghasilkan hasil lama setelah query baru.
- [x] Ukur ulang waktu pembukaan halaman pada data transaksi kecil dan besar.
- [x] Tambahkan test untuk refresh setelah penyimpanan dan kegagalan load.

## Tahap 9 - Validasi UI dan Aksesibilitas

- [x] Uji halaman pada lebar layar Android kecil.
- [x] Uji halaman pada lebar layar Android umum.
- [x] Pastikan tidak ada teks, nominal, menu, atau tombol yang overflow.
- [x] Pastikan kontras warna pemasukan, pengeluaran, transfer, dan status tetap terbaca.
- [x] Pastikan informasi tidak hanya dibedakan dengan warna.
- [x] Pastikan tooltip tersedia untuk icon yang tidak langsung jelas.
- [x] Pastikan urutan fokus dan label semantic masuk akal untuk pembaca layar.
- [x] Pastikan animasi tidak mengganggu dan menghormati reduced motion jika tersedia pada implementasi.
- [x] Ambil screenshot manual atau automated pada kondisi daftar normal, kosong, filter aktif, dan detail terbuka jika tooling tersedia.

## Tahap 10 - Pengujian Akhir

- [x] Jalankan test transaksi yang relevan.
- [x] Jalankan test assistant yang menyentuh navigasi atau draft transaksi.
- [x] Jalankan `flutter analyze lib test` penuh; analyzer scoped untuk file transaksi dan `MasterDataPage` sudah bersih.
- [x] Jalankan test widget untuk halaman transaksi pada data kosong.
- [x] Jalankan test widget untuk daftar dengan pemasukan, pengeluaran, dan transfer.
- [x] Jalankan test integrasi mutation transaksi dan transfer.
- [x] Pastikan tidak ada perubahan pada aturan target Android ARM64 release.
- [x] Tinjau diff dan hapus perubahan yang tidak terkait.
- [x] Catat hasil validasi, test yang gagal karena baseline, dan pekerjaan yang masih tertunda.

## Acceptance Criteria

- [x] Icon Asisten tidak muncul lagi di AppBar halaman Transaksi.
- [x] AppBar tetap menyediakan pencarian, filter, dan aksi transaksi penting tanpa terasa penuh.
- [x] Riwayat terlihat ringkas dan mudah dipindai sebelum transaksi dibuka.
- [x] Detail transaksi menyediakan informasi lengkap tanpa membebani daftar utama.
- [x] Transaksi dan transfer tersusun sebagai timeline yang benar berdasarkan tanggal.
- [x] Transfer tidak memengaruhi total pemasukan/pengeluaran.
- [x] Transfer dapat diedit dengan aman.
- [x] Filter utama dapat digunakan secara kombinasi dan dapat di-reset.
- [x] Empty, loading, error, dan hasil filter kosong memiliki state yang jelas.
- [x] Penghapusan memiliki jalur pemulihan atau arsip yang aman.
- [x] Semua perubahan tervalidasi oleh test dan analyzer.
- [x] Tidak ada secret, perubahan arsitektur assistant, atau perubahan business rule yang tidak diminta.

## Catatan Agent

- [x] Sebelum setiap edit, identifikasi file/symbol pemilik perilaku dan satu test yang dapat membuktikan perubahan.
- [x] Setelah setiap edit substantif, jalankan validasi paling sempit yang tersedia sebelum memperluas pekerjaan.
- [x] Jika test gagal, perbaiki slice yang sama terlebih dahulu dan jalankan ulang test tersebut.
- [x] Jangan menandai checkbox selesai hanya karena kode sudah ditulis; checkbox selesai setelah perilaku dan validasinya terbukti.
