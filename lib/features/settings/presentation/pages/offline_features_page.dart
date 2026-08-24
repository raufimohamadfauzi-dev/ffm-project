import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../../backup/presentation/pages/backup_page.dart';
import '../../../backup/presentation/pages/monthly_report_page.dart';
import '../../../budget/presentation/pages/budget_page.dart';
import '../../../reminder/presentation/pages/reminder_page.dart';
import '../../../transaction/presentation/pages/transaction_pages.dart';
import 'database_structure_page.dart';
import 'master_data_page.dart';
import 'pin_security_page.dart';
import 'offline_advanced_page.dart';
import 'privacy_center_page.dart';

class OfflineFeaturesPage extends StatelessWidget {
  const OfflineFeaturesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final features = <_OfflineFeature>[
      _OfflineFeature(
        icon: Icons.receipt_long_outlined,
        title: 'Pencatatan pemasukan dan pengeluaran',
        summary: 'Catat uang masuk dan uang keluar keluarga, lalu lihat hitungannya otomatis.',
        where: 'Tab Transaksi > Tambah transaksi.',
        how: 'Setiap catatan disimpan ke database lokal dengan tanggal, nominal Rupiah, kategori, sumber saldo, rincian pemakaian, toko, catatan, dan lampiran bila diperlukan.',
        steps: const [
          'Buka tab Transaksi.',
          'Pilih Uang masuk atau Uang keluar.',
          'Isi nominal dan rincian yang diperlukan.',
          'Periksa kembali, lalu tekan Simpan.',
        ],
        actionLabel: 'Buka Transaksi',
        onOpen: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TransactionListPage())),
      ),
      _OfflineFeature(
        icon: Icons.account_balance_outlined,
        title: 'Aset, hutang, target, dan dana tujuan',
        summary: 'Pantau harta, kewajiban, target keuangan, dan dana yang disiapkan untuk kebutuhan tertentu.',
        where: 'Menu lainnya dan halaman Analisa keuangan.',
        how: 'Data aset, hutang, target, dan dana tujuan disimpan lokal lalu dipakai untuk menghitung kekayaan bersih, kemajuan target, dan kesehatan keuangan.',
        steps: const [
          'Buka Menu lainnya.',
          'Pilih bagian data yang mau diisi.',
          'Masukkan data nyata milik keluarga, tanpa nominal contoh.',
          'Lihat perkembangannya di Analisa keuangan atau Ringkasan bulanan.',
        ],
        actionLabel: 'Buka Analisa keuangan',
        onOpen: (context) => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const MonthlyReportPage())),
      ),
      _OfflineFeature(
        icon: Icons.tune_outlined,
        title: 'Rincian transaksi dan data utama',
        summary: 'Atur kategori, induk kategori, toko/tempat, tag, rekening, dompet, dan penanda pemakaian transaksi.',
        where: 'Menu lainnya > Data Utama.',
        how: 'Semua pilihan dropdown transaksi bersumber dari Data Utama. Induk kategori bisa diketik saat membuat kategori baru, toko/tempat bisa diberi rincian, dan tag bisa diberi keterangan fungsi. Penanda Dipakai oleh seperti Keluarga, Istri, atau Anak cuma menjelaskan penggunaan transaksi; saldo tetap satu kesatuan Keuangan Keluarga.',
        steps: const [
          'Buka Menu lainnya > Data Utama.',
          'Ketik induk kategori baru atau pilih saran yang sudah ada.',
          'Tambahkan toko/tempat beserta rincian supaya pilihan transaksi tidak membingungkan.',
          'Beri keterangan pada tag agar fungsi jangka panjangnya jelas saat menyaring riwayat.',
          'Pakai pilihan tersebut saat mencatat transaksi agar riwayatnya lebih jelas.',
        ],
        actionLabel: 'Buka Data Utama',
        onOpen: (context) => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const MasterDataPage())),
      ),
      _OfflineFeature(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Rekening, dompet, dan rekonsiliasi saldo',
        summary: 'Pisahkan sumber saldo untuk pencocokan, tanpa memisahkan keuangan keluarga.',
        where: 'Menu lainnya > Alat offline lanjutan > Rekonsiliasi saldo.',
        how: 'Saldo buku dihitung dari transaksi yang ditandai ke rekening atau dompet. Selisih dengan saldo asli dapat dibuat sebagai transaksi penyesuaian dan riwayatnya disimpan per sumber.',
        steps: const [
          'Buat sumber saldo seperti Tunai, Rekening, atau E-wallet.',
          'Pilih sumber saldo saat menyimpan transaksi.',
          'Masukkan saldo asli ketika melakukan rekonsiliasi.',
          'Simpan penyesuaian bila ada selisih.',
        ],
        actionLabel: 'Buka Rekonsiliasi',
        onOpen: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OfflineAdvancedPage())),
      ),
      _OfflineFeature(
        icon: Icons.file_upload_outlined,
        title: 'Impor CSV atau Excel',
        summary: 'Masukkan riwayat transaksi dari berkas dengan pemetaan kolom dan pemeriksaan duplikat.',
        where: 'Menu lainnya > Alat offline lanjutan > Impor transaksi.',
        how: 'Berkas dibaca di perangkat. Kolom tanggal, nominal, jenis, kategori, catatan, dan sumber saldo bisa dipetakan manual. Baris ganda dilewati dan batch gagal dapat dibatalkan.',
        steps: const [
          'Pilih berkas CSV atau Excel dari perangkat.',
          'Cocokkan kolom berkas dengan kolom transaksi.',
          'Periksa pratinjau dan jumlah duplikat.',
          'Konfirmasi impor, lalu buka riwayat hasilnya.',
        ],
        actionLabel: 'Buka Alat Impor',
        onOpen: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OfflineAdvancedPage())),
      ),
      _OfflineFeature(
        icon: Icons.repeat_outlined,
        title: 'Deteksi pola transaksi berulang',
        summary: 'Temukan tagihan atau pengeluaran yang sering muncul dan ubah menjadi jadwal rutin.',
        where: 'Menu lainnya > Alat offline lanjutan > Pola transaksi.',
        how: 'Pola dihitung dari transaksi yang sudah tersimpan. Tindakan Buat jadwal membuka formulir yang sudah terisi dan jadwal yang sama tidak dibuat dua kali.',
        steps: const [
          'Catat beberapa transaksi yang memang berulang.',
          'Buka pemeriksaan pola transaksi.',
          'Periksa nominal, kategori, dan frekuensinya.',
          'Tekan Buat jadwal bila polanya benar.',
        ],
        actionLabel: 'Buka Deteksi Pola',
        onOpen: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OfflineAdvancedPage())),
      ),
      _OfflineFeature(
        icon: Icons.warning_amber_outlined,
        title: 'Peringatan pengeluaran tidak biasa',
        summary: 'Dapatkan peringatan lokal saat pengeluaran kategori tertentu melonjak.',
        where: 'Menu lainnya > Alat offline lanjutan > Peringatan pengeluaran.',
        how: 'Pemeriksaan otomatis berjalan setelah transaksi disimpan, membandingkan pengeluaran dengan pola lokal sebelumnya, dan bisa dinyalakan atau dimatikan per kategori.',
        steps: const [
          'Buka pengaturan peringatan pengeluaran.',
          'Atur ambang batas dan kategori yang dipantau.',
          'Simpan transaksi seperti biasa.',
          'Baca peringatan di aplikasi atau notifikasi lokal perangkat.',
        ],
        actionLabel: 'Buka Peringatan',
        onOpen: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OfflineAdvancedPage())),
      ),
      _OfflineFeature(
        icon: Icons.cloud_upload_outlined,
        title: 'Cadangan otomatis lokal',
        summary: 'Cadangan dibuat di perangkat, diverifikasi, dan bisa dipulihkan dari daftar.',
        where: 'Menu lainnya > Alat offline lanjutan > Cadangan otomatis.',
        how: 'Saat aplikasi dibuka, cadangan otomatis berjalan sesuai jadwal lokal. Setiap berkas memiliki checksum dan dapat diperiksa sebelum dipulihkan.',
        steps: const [
          'Nyalakan cadangan otomatis.',
          'Buka daftar cadangan untuk melihat waktu, ukuran, dan integritasnya.',
          'Pilih berkas cadangan bila ingin memulihkan data.',
          'Periksa pratinjau sebelum menyetujui pemulihan.',
        ],
        actionLabel: 'Buka Cadangan',
        onOpen: (context) =>
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const BackupPage())),
      ),
      _OfflineFeature(
        icon: Icons.insights_outlined,
        title: 'Laporan dan paket analisa terfilter',
        summary: 'Buat laporan mingguan, JSON, CSV, atau HTML dari periode dan kategori yang kamu pilih.',
        where: 'Menu lainnya > Ekspor & Cadangan.',
        how: 'Pilih tanggal, jenis transaksi, dan kategori. Laporan PDF mingguan, JSON, CSV, serta HTML dibuat dari data lokal. Tombol Salin prompt dan Salin JSON membantu kamu memberikan data terpilih ke AI pilihanmu secara manual. FFM tidak mengirim data ke internet dan tidak menyimpan API key.',
        steps: const [
          'Buka Menu lainnya > Ekspor & Cadangan.',
          'Pilih periode, jenis transaksi, dan kategori.',
          'Atur apakah rincian item, catatan, dan detail toko boleh ikut.',
          'Salin prompt lalu salin atau ekspor JSON jika mau meminta analisa AI manual.',
          'Pakai CSV untuk spreadsheet atau HTML untuk dibuka di peramban.',
          'Periksa isi berkas sebelum membagikannya ke layanan AI.',
        ],
        actionLabel: 'Buka Ekspor & Cadangan',
        onOpen: (context) =>
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const BackupPage())),
      ),
      _OfflineFeature(
        icon: Icons.health_and_safety_outlined,
        title: 'Pusat kesehatan data',
        summary: 'Periksa data yang janggal di seluruh tabel dan tandai masalah yang sudah ditinjau.',
        where: 'Menu lainnya > Alat offline lanjutan > Pemeriksaan kesehatan data.',
        how: 'Pemeriksaan mencakup transaksi, aset, hutang, target, anggaran, transaksi rutin, rekening, dan pos anggaran. Hasil diberi tingkat Kritis, Peringatan, atau Info.',
        steps: const [
          'Jalankan pemeriksaan kesehatan data.',
          'Baca tingkat dan penjelasan setiap masalah.',
          'Tandai masalah satu per satu atau sekaligus setelah ditinjau.',
          'Buka riwayat pemeriksaan bila perlu.',
        ],
        actionLabel: 'Buka Pusat Kesehatan',
        onOpen: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OfflineAdvancedPage())),
      ),
      _OfflineFeature(
        icon: Icons.lock_outline,
        title: 'Database lokal terenkripsi',
        summary: 'Data keuangan disimpan di perangkat dan dikunci otomatis.',
        where: 'Berjalan otomatis sejak aplikasi dibuka. Pengaturan akses ada di Menu lainnya > Kunci aplikasi.',
        how: 'FFM memakai SQLite dengan lapisan enkripsi SQLCipher. Kunci database dibuat dan disimpan aman di perangkat, jadi data tidak perlu dikirim ke internet.',
        steps: const [
          'Buka Menu lainnya.',
          'Pilih Kunci aplikasi untuk menyalakan PIN atau biometrik.',
          'Gunakan aplikasi seperti biasa; enkripsi database berjalan otomatis di belakang layar.',
        ],
        actionLabel: 'Buka Kunci aplikasi',
        onOpen: (context) => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const PinSecurityPage())),
      ),
      _OfflineFeature(
        icon: Icons.data_object_outlined,
        title: 'Impor transaksi dari JSON',
        summary: 'Tempel atau pilih file JSON hasil dari LLM, lalu cek semua transaksi sebelum dipakai.',
        where: 'Transaksi > Impor JSON di pojok kanan atas.',
        how: 'FFM membaca struktur JSON yang kamu pilih atau tempel. Data hanya menjadi preview transaksi; tidak ada data yang disimpan sebelum kamu memeriksa, memperbaiki, lalu mengonfirmasi sendiri.',
        steps: const [
          'Buka halaman Transaksi.',
          'Tekan Impor JSON, lalu pilih file atau tempel hasil JSON yang sudah kamu dapatkan.',
          'Periksa setiap tanggal, nominal, kategori, rekening, dan rincian yang tampil.',
          'Perbaiki bagian yang keliru atau batalkan jika belum yakin.',
          'Tekan Pakai hasil ini, lengkapi sumber saldo bila perlu, lalu simpan transaksi sendiri.',
        ],
        actionLabel: 'Buka Transaksi',
        onOpen: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TransactionListPage())),
      ),
      _OfflineFeature(
        icon: Icons.mic_none_outlined,
        title: 'Input suara Bahasa Indonesia',
        summary: 'Ngomong pakai kalimat sederhana; hasilnya mengisi form dulu dan tidak langsung disimpan.',
        where: 'Transaksi > Tambah transaksi > ikon mikrofon di kartu Uang masuk atau Uang keluar.',
        how: 'Pengenalan suara memproses Bahasa Indonesia langsung di perangkat tanpa internet. Jalur utama yang sudah siap memakai pengenalan suara lokal dari sistem; parser lokal mencoba membaca arah, nominal, kategori, dan rincian. Adapter Whisper.cpp offline disiapkan sebagai engine lanjutan berbasis model lokal yang bisa diimpor, tetapi aplikasi tidak mengunduh model otomatis. Setelah selesai, hasilnya hanya menjadi isian form sehingga kamu masih bisa mengoreksi sebelum disimpan. V1 tidak mengirim rekaman suara ke server dan tidak menyediakan pilihan pemrosesan melalui internet.',
        steps: const [
          'Buka Transaksi, tekan tambah, lalu tentukan kartu Uang keluar atau Uang masuk.',
          'Tekan ikon mikrofon dan tunggu sampai tulisan berubah menjadi sedang mendengar.',
          'Ucapkan dengan urutan: arah transaksi, keperluan, nominal, lalu rincian bila perlu.',
          'Untuk uang keluar, ucapkan: “Uang keluar, beli makan, lima puluh ribu, untuk Anak.”',
          'Untuk uang masuk, ucapkan: “Uang masuk, gaji, tiga juta, untuk Keluarga.”',
          'Boleh tambahkan konteks seperti: “Bayar listrik dua ratus ribu dari Rekening.”',
          'Setelah berhenti mendengar, cek kartu hasil suara: arah, nominal, kategori, dan rincian. Kalau keliru, ubah manual atau tekan Dengar lagi.',
          'Kalau pengenalan tanpa internet belum tersedia, cek izin mikrofon dan bahasa Indonesia di pengaturan HP.',
          'Tekan Simpan hanya setelah semua isian benar. Sebelum itu, data belum masuk ke database.',
        ],
        actionLabel: 'Coba di Transaksi',
        onOpen: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TransactionListPage())),
      ),
      _OfflineFeature(
        icon: Icons.autorenew_rounded,
        title: 'Transaksi rutin dan pengingat lokal',
        summary:
            'Tagihan dan pemasukan berulang bisa dibuat otomatis tanpa server.',
        where: 'Menu lainnya > Transaksi rutin atau Pengingat.',
        how: 'Aplikasi memeriksa jadwal saat dibuka, membuat transaksi yang sudah jatuh tempo, dan menyiapkan pengingat lokal di perangkat.',
        steps: const [
          'Buka Menu lainnya > Transaksi rutin.',
          'Buat jadwal harian, mingguan, bulanan, atau tahunan.',
          'Atur pengingat jika diperlukan.',
          'Cek Menu lainnya > Pengingat untuk melihat jadwal terdekat.',
        ],
        actionLabel: 'Buka Pengingat',
        onOpen: (context) =>
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ReminderPage())),
      ),
      _OfflineFeature(
        icon: Icons.search_outlined,
        title: 'Pencarian transaksi lokal',
        summary: 'Cari transaksi lama tanpa mengirim data ke mana-mana.',
        where: 'Transaksi > kolom pencarian di bagian atas.',
        how: 'Ketik nama toko, catatan, kategori, atau nominal. Pencarian berjalan di perangkat memakai indeks lokal dan punya cadangan pencarian biasa jika indeks belum tersedia.',
        steps: const [
          'Buka halaman Transaksi.',
          'Ketik kata kunci di kolom pencarian paling atas.',
          'Cari berdasarkan nama toko, catatan, kategori, atau nominal.',
          'Gabungkan dengan saringan tanggal bila hasilnya terlalu banyak.',
        ],
        actionLabel: 'Buka Transaksi',
        onOpen: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TransactionListPage())),
      ),
      _OfflineFeature(
        icon: Icons.flag_outlined,
        title: 'Panduan transaksi pertama',
        summary: 'Petunjuk singkat supaya kamu paham dampak pemasukan dan pengeluaran sejak awal.',
        where: 'Transaksi > Tambah transaksi, saat belum ada riwayat.',
        how: 'Kartu panduan muncul otomatis sebelum transaksi pertama disimpan. Pemasukan menambah saldo keluarga, sedangkan pengeluaran mengurangi saldo. Kalau pengeluaran memakai uang pinjaman, tersedia jalur cepat ke catatan hutang. Saldo tetap satu kesatuan Keuangan Keluarga; Keluarga, Istri, dan Anak hanya menjadi penanda Dipakai oleh pada transaksi.',
        steps: const [
          'Buka Transaksi lalu tekan tombol tambah.',
          'Pilih Uang masuk kalau mau mencatat saldo awal atau pemasukan.',
          'Pilih Uang keluar kalau mau mencatat belanja atau pembayaran.',
          'Baca penjelasan dampaknya, lengkapi isian, lalu simpan setelah semuanya benar.',
          'Kalau uang pengeluaran berasal dari pinjaman, buka Catatan hutang dari kartu panduan.',
        ],
        actionLabel: 'Buka Transaksi',
        onOpen: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TransactionListPage())),
      ),
      _OfflineFeature(
        icon: Icons.ios_share_outlined,
        title: 'Cadangan dan pulihkan data',
        summary: 'Simpan data keluarga sebagai berkas JSON dan pulihkan kembali tanpa cloud.',
        where: 'Menu lainnya > Ekspor & Cadangan.',
        how: 'Berkas cadangan diberi checksum SHA-256, bisa difilter berdasarkan tanggal, dan dipulihkan dengan pemeriksaan sebelum data lama diganti.',
        steps: const [
          'Buka Ekspor & Cadangan.',
          'Pilih ekspor penuh atau tentukan rentang tanggal.',
          'Simpan berkas di lokasi yang aman.',
          'Saat pindah perangkat, pilih pulihkan lalu cek pratinjau sebelum melanjutkan.',
        ],
        actionLabel: 'Buka Cadangan',
        onOpen: (context) =>
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const BackupPage())),
      ),
      _OfflineFeature(
        icon: Icons.insights_outlined,
        title: 'Analisa dan saran lokal',
        summary: 'Angka, grafik, ramalan, dan saran dihitung dari data di perangkat.',
        where: 'Dashboard atau Menu lainnya > Analisa keuangan.',
        how: 'Mesin aturan lokal menghitung arus kas gabungan Keuangan Keluarga, skor kesehatan, forecast tiga bulan, rincian pengeluaran berdasarkan penanda Dipakai oleh bila tersedia, serta saran berdasarkan data yang sudah dicatat.',
        steps: const [
          'Catat beberapa transaksi pemasukan dan pengeluaran.',
          'Buka Dashboard untuk melihat ringkasan cepat.',
          'Buka Analisa keuangan untuk grafik dan penjelasan lebih lengkap.',
          'Ikuti saran yang muncul setelah data cukup.',
        ],
        actionLabel: 'Buka Transaksi',
        onOpen: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TransactionListPage())),
      ),
      _OfflineFeature(
        icon: Icons.summarize_outlined,
        title: 'Ringkasan bulanan',
        summary: 'Pilih bulan, bandingkan arus kas, lihat skor kesehatan, dan bagikan PDF.',
        where: 'Menu lainnya > Ringkasan bulanan.',
        how: 'Laporan dihitung dari transaksi, aset, hutang, target, dan kategori yang tersimpan di perangkat. Bulan sebelumnya dipakai sebagai pembanding dan riwayat laporan disimpan lokal.',
        steps: const [
          'Buka Menu lainnya > Ringkasan bulanan.',
          'Pilih bulan yang mau dicek, bukan cuma bulan berjalan.',
          'Lihat pemasukan, pengeluaran, arus kas bersih, dan perbandingan bulan sebelumnya.',
          'Tekan Ekspor dan bagikan PDF kalau mau menyimpan atau mengirim berkas secara manual.',
        ],
        actionLabel: 'Buka Ringkasan bulanan',
        onOpen: (context) => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const MonthlyReportPage())),
      ),
      _OfflineFeature(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Anggaran berbasis pos',
        summary: 'Bagi uang ke pos Makan, Sekolah Anak, Tagihan, Darurat, Tabungan, dan Kebutuhan Lain.',
        where: 'Tab Anggaran atau Menu lainnya > Anggaran berbasis pos.',
        how: 'Setiap pos menyimpan alokasi bulan ini di database lokal. Sisa dihitung dari alokasi, rollover, dana masuk atau keluar antarpos, dan transaksi kategori terkait.',
        steps: const [
          'Buka tab Anggaran atau Menu lainnya > Anggaran berbasis pos.',
          'Ketuk pos yang mau diatur, lalu isi uang yang dibagi ke pos tersebut.',
          'Cek status Aman, Hampir habis, atau Melewati batas.',
          'Pakai Atur ulang pos kalau perlu menggeser alokasi antarpos. Ini tidak memindahkan saldo Tunai, Rekening, atau Dompet digital.',
        ],
        actionLabel: 'Buka Anggaran berbasis pos',
        onOpen: (context) =>
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const BudgetPage())),
      ),
      _OfflineFeature(
        icon: Icons.privacy_tip_outlined,
        title: 'Pusat Privasi',
        summary: 'Cek enkripsi, PIN, biometrik, izin perangkat, lokasi data, dan ukuran cadangan.',
        where: 'Menu lainnya > Pusat privasi.',
        how: 'Pemeriksaan dilakukan langsung di HP. Aplikasi membaca status kunci lokal, ukuran database, daftar cadangan otomatis, dan izin kamera atau mikrofon tanpa mengirim data ke server.',
        steps: const [
          'Buka Menu lainnya > Pusat privasi.',
          'Tekan Periksa privasi sekarang untuk memuat status terbaru.',
          'Atur PIN, biometrik, atau izin kamera dan mikrofon bila diperlukan.',
          'Cek lokasi database dan cadangan saat ingin memastikan data tetap lokal.',
        ],
        actionLabel: 'Buka Pusat Privasi',
        onOpen: (context) => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const PrivacyCenterPage())),
      ),
      _OfflineFeature(
        icon: Icons.offline_bolt_outlined,
        title: 'Alat offline lanjutan',
        summary: 'Cek saldo, impor CSV atau Excel, periksa data, cari pola, dan lihat peringatan lokal.',
        where: 'Menu lainnya > Alat offline lanjutan.',
        how: 'Semua alat lanjutan memproses data yang sudah tersimpan di perangkat, tanpa penyelarasan awan. Cadangan otomatis dapat dibuat paling banyak sekali sehari saat aplikasi dibuka.',
        steps: const [
          'Buka Menu lainnya.',
          'Pilih Alat offline lanjutan.',
          'Pilih alat yang dibutuhkan dan ikuti petunjuk pada layar.',
        ],
        actionLabel: 'Buka Alat lanjutan',
        onOpen: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OfflineAdvancedPage())),
      ),
      _OfflineFeature(
        icon: Icons.storage_outlined,
        title: 'Audit dan pemeriksaan data lokal',
        summary:
            'Perubahan data dicatat dan jumlah isi database bisa diperiksa.',
        where: 'Menu lainnya > Struktur Database.',
        how: 'Audit log mencatat tambah, ubah, dan hapus pada data penting. Struktur Database menampilkan tabel serta jumlah data yang tersimpan di perangkat.',
        steps: const [
          'Buka Menu lainnya.',
          'Pilih Struktur Database untuk melihat isi ringkas database.',
          'Gunakan informasi ini saat memeriksa hasil pemulihan atau mencari data yang belum lengkap.',
        ],
        actionLabel: 'Buka Struktur Database',
        onOpen: (context) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DatabaseStructurePage()),
        ),
      ),
    ];

    final scheme = Theme.of(context).colorScheme;
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.offlineFeatures,
      child: Scaffold(
        appBar: AppBar(title: const Text('Fitur tanpa internet')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const SizedBox(
                      width: 116,
                      height: 116,
                      child: Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 64,
                        semanticLabel: 'Lambang keluarga dan keuangan FFM',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const AppHelpBanner(
              title: 'Semua tetap jalan tanpa internet',
              message: 'Data keuangan, pindai nota, input suara, analisa, dan cadangan diproses di perangkat. Beberapa fitur perlu izin kamera, mikrofon, atau penyimpanan dari sistem HP.',
              icon: Icons.wifi_off_outlined,
            ),
            const SizedBox(height: 16),
            AppCard(
              color: scheme.primaryContainer,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.privacy_tip_outlined, color: scheme.primary),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Catatan privasi: aplikasi ini tidak memakai sinkronisasi awan dan tidak mengirim catatan ke server. Hasil pindai tetap perlu dicek karena pembacaan nota dan suara bisa keliru.',
                      style: TextStyle(color: scheme.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const AppSectionHeader(title: 'Sudah selesai'),
            const SizedBox(height: 8),
            ...features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _OfflineFeatureCard(feature: feature),
              ),
            ),
            const SizedBox(height: 12),
            const AppSectionHeader(title: 'Sedang dibereskan'),
            const SizedBox(height: 8),
            const AppCard(
              child: Text(
                'Tidak ada fitur target V1.1 yang tertunda. Penyelarasan awan dan wawasan AI belum diaktifkan karena memang termasuk rencana V2.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineFeature {
  const _OfflineFeature({
    required this.icon,
    required this.title,
    required this.summary,
    required this.where,
    required this.how,
    required this.steps,
    required this.actionLabel,
    required this.onOpen,
  });

  final IconData icon;
  final String title;
  final String summary;
  final String where;
  final String how;
  final List<String> steps;
  final String actionLabel;
  final void Function(BuildContext context) onOpen;
}

class _OfflineFeatureCard extends StatelessWidget {
  const _OfflineFeatureCard({required this.feature});

  final _OfflineFeature feature;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          child: Icon(feature.icon),
        ),
        title: Text(feature.title),
        subtitle: Text(feature.summary),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 14),
          _InfoBlock(title: 'Letaknya di mana?', text: feature.where),
          const SizedBox(height: 12),
          _InfoBlock(title: 'Cara kerjanya', text: feature.how),
          const SizedBox(height: 12),
          const Text('Cara pakai', style: AppTextStyles.labelCaps),
          const SizedBox(height: 6),
          ...feature.steps.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.key + 1}.',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(entry.value)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () => feature.onOpen(context),
              icon: const Icon(Icons.open_in_new),
              label: Text(feature.actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.labelCaps),
        const SizedBox(height: 4),
        Text(text),
      ],
    );
  }
}
