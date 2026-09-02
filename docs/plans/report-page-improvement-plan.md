# Rencana Peningkatan Halaman Laporan

## Tujuan

Menjadikan halaman Laporan sebagai pusat ringkasan periode yang jelas, dengan rincian yang dapat dibuka dari modul keuangan dan aktivitas. Tahap ini hanya mencakup halaman laporan, data lokal, dan ekspor laporan. Orchestrator/LLM tidak diubah dalam rencana ini.

## Prinsip

- Semua nominal, total, perbandingan, dan persentase dihitung secara deterministik dari data lokal.
- Ringkasan tampil lebih dulu; rincian dibuka hanya saat diperlukan agar halaman tetap ringan.
- Periode laporan berlaku konsisten untuk semua bagian yang mendukung filter tanggal.
- Piutang, aset, hutang, dan target diberi label yang jelas agar tidak tercampur dengan kas.
- Tidak ada data fiktif bila suatu modul belum memiliki data pada periode terpilih.

## Tahap 1 - Audit Kontrak Laporan

- [ ] Inventarisasi data yang saat ini sudah dibaca `MonthlyReportPage`.
- [ ] Petakan sumber data untuk transaksi, kategori, tag, toko, rekening, anggaran, target, hutang, piutang, aset, aktivitas, dan panen.
- [ ] Tetapkan definisi periode laporan: bulan yang dipilih, pembanding bulan sebelumnya, dan aturan transaksi lintas periode.
- [ ] Tetapkan arti arus kas, pemasukan, pengeluaran, piutang, hutang, aset, dan saldo target agar tidak tumpang tindih.
- [ ] Identifikasi bagian yang belum bisa dihitung dari data lokal secara andal.

## Tahap 2 - Ringkasan Utama

- [ ] Pertahankan kartu pemasukan, pengeluaran, dan arus kas bersih.
- [ ] Tampilkan jumlah transaksi pada periode terpilih.
- [ ] Tampilkan perubahan pemasukan serta pengeluaran dibanding periode sebelumnya.
- [ ] Tampilkan status kesehatan keuangan dengan penjelasan singkat yang berbasis angka.
- [ ] Tambahkan state kosong yang menjelaskan bahwa belum ada transaksi pada periode tersebut.
- [ ] Pastikan seluruh nominal memakai formatter Rupiah yang konsisten.

## Tahap 3 - Rincian Transaksi

- [ ] Tambahkan bagian kategori pemasukan dan pengeluaran terbesar.
- [ ] Tambahkan tombol untuk membuka daftar transaksi periode terpilih.
- [ ] Tambahkan rincian transaksi terbesar tanpa mencampurkan transfer sebagai pemasukan/pengeluaran.
- [ ] Tambahkan rincian tag teratas bila transaksi memiliki tag.
- [ ] Tambahkan rincian toko/merchant teratas bila transaksi memiliki toko.
- [ ] Tambahkan state kosong untuk kategori, tag, atau toko yang belum memiliki data.

## Tahap 4 - Kondisi Keuangan Keluarga

- [ ] Tambahkan ringkasan progres target keuangan aktif.
- [ ] Tambahkan ringkasan hutang aktif dan total cicilan bulanan.
- [ ] Tambahkan ringkasan piutang terutang dengan label "bukan kas".
- [ ] Tambahkan ringkasan aset secara terpisah dari arus kas periode.
- [ ] Tambahkan tautan ke halaman sumber untuk melihat detail tiap modul.
- [ ] Pastikan tidak ada total ganda antara target, aset, piutang, dan saldo kas.

## Tahap 5 - Anggaran, Aktivitas, dan Panen

- [ ] Tambahkan ringkasan anggaran versus realisasi bila data anggaran tersedia.
- [ ] Tambahkan aktivitas penting yang selesai atau aktif pada periode laporan.
- [ ] Tambahkan ringkasan panen/hasil usaha bila ada data yang relevan pada periode tersebut.
- [ ] Pisahkan fakta aktivitas dari dampak keuangan yang benar-benar tercatat.
- [ ] Tampilkan penjelasan keterbatasan bila aktivitas/panen belum terhubung ke transaksi.

## Tahap 6 - Penjelasan Laporan

- [ ] Tambahkan narasi deterministik singkat di bawah ringkasan utama.
- [ ] Jelaskan perubahan terbesar berdasarkan kategori dan perbandingan periode.
- [ ] Tampilkan maksimal beberapa penyebab utama, lalu sediakan "Lihat rincian".
- [ ] Gunakan bahasa Indonesia yang ringkas dan tidak menyalahkan user.
- [ ] Jangan membuat saran atau klaim penyebab jika data pendukung tidak cukup.

## Tahap 7 - Navigasi dan Ekspor

- [ ] Pastikan setiap bagian laporan dapat membuka halaman sumber dengan filter periode yang sesuai bila didukung.
- [ ] Perluas PDF agar mengikuti ringkasan dan rincian yang tampil di aplikasi.
- [ ] Pastikan ekspor menyatakan periode, waktu pembuatan, dan keterbatasan data.
- [ ] Pertahankan riwayat laporan tanpa menyimpan ulang data transaksi mentah.
- [ ] Uji PDF pada data kosong, data sedikit, dan data dengan banyak kategori.

## Tahap 8 - UX dan Aksesibilitas

- [ ] Pastikan ringkasan utama terbaca tanpa perlu scroll panjang.
- [ ] Gunakan section yang dapat dibuka/tutup untuk rincian panjang.
- [ ] Pastikan label, warna positif/negatif, dan ikon tidak menjadi satu-satunya penanda arti.
- [ ] Pastikan state loading, error, dan data kosong jelas.
- [ ] Uji tampilan layar kecil Android serta ukuran font besar.

## Tahap 9 - Test dan Validasi

- [ ] Unit test total pemasukan, pengeluaran, arus kas, dan perbandingan periode.
- [ ] Unit test transfer tidak dihitung sebagai pemasukan atau pengeluaran.
- [ ] Unit test kategori, tag, toko, target, hutang, piutang, aset, dan anggaran.
- [ ] Widget test state kosong, loading, rincian terbuka, dan pemilihan bulan.
- [ ] Integration test navigasi dari laporan ke halaman sumber.
- [ ] Test ekspor PDF dengan angka dan periode yang konsisten.
- [ ] Jalankan `flutter analyze lib test`.

## Di Luar Scope Saat Ini

- [ ] Tidak mengubah Gemini, orchestrator, capability agent, atau prompt LLM.
- [ ] Tidak membuat LLM sebagai sumber perhitungan keuangan.
- [ ] Tidak mengubah skema database tanpa kebutuhan yang terverifikasi saat implementasi.
