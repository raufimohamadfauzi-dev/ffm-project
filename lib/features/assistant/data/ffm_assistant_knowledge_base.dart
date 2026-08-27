/// Basis pengetahuan panduan penggunaan 15 fitur FFM untuk Asisten Lokal.
///
/// Berkas ini menyediakan jawaban panduan langkah-demi-langkah yang
/// deterministik — tidak bergantung pada SLM atau database. Semua jawaban
/// bersifat read-only dan tidak pernah membuat draft atau menulis data.
library;

class FfmKnowledgeEntry {
  const FfmKnowledgeEntry({
    required this.triggers,
    required this.title,
    required this.answer,
  });

  final List<String> triggers;
  final String title;
  final String answer;

  bool matches(String normalized) =>
      triggers.any((t) => normalized.contains(t));
}

class FfmAssistantKnowledgeBase {
  const FfmAssistantKnowledgeBase();

  static const _entries = <FfmKnowledgeEntry>[
    // ─── TRANSAKSI ────────────────────────────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'cara catat transaksi',
        'cara catat pengeluaran',
        'cara catat pemasukan',
        'cara tambah transaksi',
        'tambah pengeluaran',
        'tambah pemasukan',
        'cara mencatat',
      ],
      title: '📒 Cara Mencatat Transaksi',
      answer: '''Untuk mencatat transaksi kamu bisa:
- **Via Chat**: Ketik *"Catat [jenis] [nominal] di [rekening]"* — misalnya *"Catat pengeluaran 50rb di BCA untuk makan"*. Aku akan menyiapkan draft untuk kamu cek dan konfirmasi.
- **Via Formulir Manual**: Buka menu **Transaksi** → tekan tombol **+** di pojok kanan bawah → isi detail transaksi.
- **Via Impor JSON**: Tempel hasil JSON nota di menu impor transaksi untuk ditinjau sebagai draft.

Ingat: draft belum tersimpan sampai kamu tekan **Simpan** di formulir.''',
    ),

    // ─── TRANSFER ────────────────────────────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'cara transfer',
        'cara pindah saldo',
        'transfer antar rekening',
        'pindahkan uang',
        'cara transfer rekening',
      ],
      title: '🔄 Cara Transfer Antar-Rekening',
      answer: '''Transfer adalah pemindahan dana antar-rekening milikmu di dalam FFM (bukan transfer ke rekening bank lain).
- **Via Chat**: Ketik *"Transfer 200rb dari BCA ke Gopay"* — aku siapkan draft untuk kamu konfirmasi.
- **Via Formulir**: Buka **Transaksi** → tekan **+** → pilih jenis **Transfer** → isi rekening asal, tujuan, dan nominal.

Catatan penting: transfer **tidak mengubah** total kekayaan bersihmu, hanya memindahkan saldo antar-dompet.''',
    ),

    // ─── ANGGARAN / BUDGET ───────────────────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'cara buat anggaran',
        'cara atur budget',
        'cara atur anggaran',
        'cara bikin budget',
        'anggaran itu apa',
        'fungsi anggaran',
        'budget itu apa',
      ],
      title: '📊 Cara Mengatur Anggaran (Budget)',
      answer: '''Anggaran adalah batas pengeluaran per kategori dalam satu periode (mingguan atau bulanan).
**Cara membuat anggaran:**
1. Buka menu **Anggaran** (dari menu Lainnya atau langsung dari asisten: *"Buka halaman anggaran"*).
2. Tekan **+ Tambah Anggaran** → pilih kategori → tentukan batas nominal → pilih periode.
3. Simpan.

**Cara memantau:** FFM akan menampilkan persentase penggunaan secara otomatis di halaman Anggaran dan mengirim peringatan saat mendekati batas.

**Via Chat:** Ketik *"Atur budget makan 1,5 juta bulan ini"* — aku akan siapkan draft penyesuaian untuk kamu konfirmasi.''',
    ),

    // ─── TARGET TABUNGAN / GOALS ─────────────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'cara buat tabungan',
        'cara buat target',
        'cara nabung',
        'target tabungan',
        'goal itu apa',
        'fitur tabungan',
        'cara menabung',
      ],
      title: '🎯 Cara Membuat Target Tabungan (Goals)',
      answer: '''Target Tabungan adalah pos dana yang kamu sisihkan secara bertahap untuk tujuan tertentu (liburan, DP rumah, pendidikan anak, dll).
**Cara membuat:**
1. Buka menu **Tabungan** → tekan **+ Tambah Target**.
2. Isi nama target, nominal tujuan akhir, dan target tanggal tercapai.
3. Pilih rekening sumber dana (opsional).
4. Simpan.

**Cara mengisi tabungan:** Catat setoran ke target sebagai pengeluaran berkategori nama target tabunganmu.

**Via Chat:** Ketik *"Buat tabungan Liburan target 5 juta"* — aku siapkan draftnya.''',
    ),

    // ─── HUTANG / PIUTANG ────────────────────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'cara catat hutang',
        'cara catat pinjaman',
        'cara catat cicilan',
        'hutang itu apa',
        'fitur hutang',
        'cara bayar hutang',
        'cara lunas hutang',
      ],
      title: '💳 Cara Mencatat Hutang & Cicilan',
      answer: '''Hutang adalah kewajiban finansial yang kamu miliki kepada orang atau lembaga lain.
**Cara mencatat hutang baru:**
1. Buka **Hutang & Cicilan** → tekan **+ Tambah Hutang**.
2. Isi nama pemberi pinjaman, nominal pokok, bunga (jika ada), dan tanggal jatuh tempo.
3. Simpan.

**Cara mencatat pembayaran cicilan:**
- Buka hutang yang bersangkutan → tekan **Bayar** → isi nominal dan rekening sumber.

**Via Chat:** Ketik *"Catat hutang ke Budi 500rb jatuh tempo akhir bulan"*.

Untuk **piutang** (uang yang dipinjam orang lain kepadamu), gunakan menu **Piutang** dengan cara yang sama.''',
    ),

    // ─── PENGINGAT ───────────────────────────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'cara buat pengingat',
        'cara bikin alarm',
        'cara atur notifikasi',
        'cara ingatkan',
        'fitur pengingat',
        'cara pasang reminder',
      ],
      title: '⏰ Cara Membuat Pengingat Tagihan',
      answer: '''Pengingat adalah alarm finansial berkala untuk membantu kamu tidak lupa bayar tagihan rutin.
**Cara membuat:**
1. Buka **Pengingat** (menu Lainnya) → tekan **+ Tambah Pengingat**.
2. Isi nama tagihan, nominal perkiraan, tanggal jatuh tempo, dan frekuensi (sekali/bulanan/tahunan).
3. Simpan.

**Via Chat:** Ketik *"Ingatkan bayar internet tanggal 20 setiap bulan"* — aku siapkan draftnya.

Notifikasi pengingat muncul di notifikasi HP pada tanggal yang kamu tentukan.''',
    ),

    // ─── TRANSAKSI BERULANG ──────────────────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'transaksi rutin',
        'transaksi berulang',
        'cara buat tagihan rutin',
        'cara otomatis catat',
        'cara catat langganan',
        'subscription',
      ],
      title: '🔁 Cara Mengatur Transaksi Berulang',
      answer: '''Transaksi Berulang adalah pengeluaran atau pemasukan yang terjadi secara rutin (gaji bulanan, bayar kos, langganan Netflix, premi asuransi, dll).
**Cara membuat:**
1. Buka **Transaksi Berulang** (menu Lainnya) → tekan **+**.
2. Isi kategori, nominal, rekening, dan jadwal frekuensi.
3. Simpan.

Pada tanggal yang ditentukan, FFM akan mengingatkan kamu untuk mengeksekusi transaksi tersebut (tidak otomatis tersimpan — kamu tetap harus konfirmasi).''',
    ),

    // ─── ASET ────────────────────────────────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'cara catat aset',
        'cara tambah aset',
        'aset itu apa',
        'fitur aset',
        'cara catat investasi',
        'cara catat emas',
        'cara catat properti',
      ],
      title: '🏠 Cara Mencatat Aset & Kekayaan',
      answer: '''Aset adalah kekayaan berwujud yang kamu miliki di luar rekening kas (emas, properti, kendaraan, investasi reksa dana/saham, dll).
**Cara mencatat:**
1. Buka **Aset** (menu Lainnya) → tekan **+ Tambah Aset**.
2. Isi nama aset, jenis, dan nilai pasar saat ini.
3. Simpan.

**Cara memperbarui nilai:** Buka aset → tekan **Edit** → ubah nilai pasar sesuai harga terkini.

Total nilai asetmu otomatis dimasukkan dalam perhitungan **Kekayaan Bersih (Net Worth)** di halaman Ikhtisar.''',
    ),

    // ─── BACKUP & EKSPOR ─────────────────────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'cara backup',
        'cara ekspor data',
        'cara simpan data',
        'cara pindah data',
        'cara ganti hp',
        'cara restore',
        'cara impor data',
      ],
      title: '💾 Cara Backup & Pindah Data ke HP Baru',
      answer: '''Semua data FFM tersimpan secara lokal di perangkat. Agar aman saat ganti HP, lakukan backup rutin:
**Cara Backup:**
1. Buka **Ekspor & Cadangan** (menu Lainnya) → tekan **Buat Cadangan**.
2. Pilih format **JSON Lengkap (ffm-v23-full)**.
3. Pilih lokasi penyimpanan (Google Drive, folder Downloads, atau share ke aplikasi lain).

**Cara Restore di HP Baru:**
1. Install aplikasi FFM di HP baru.
2. Buka **Ekspor & Cadangan** → tekan **Muat Cadangan** → pilih file backup.
3. Konfirmasi untuk menggantikan data saat ini.

**Catatan:** Backup tidak menyertakan riwayat percakapan chat — hanya data finansial, memori asisten, dan pengaturan.''',
    ),

    // ─── REKONSILIASI SALDO ──────────────────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'rekonsiliasi',
        'saldo tidak cocok',
        'saldo berbeda',
        'selisih saldo',
        'cara cek selisih',
        'audit saldo',
      ],
      title: '🔍 Cara Rekonsiliasi Saldo (Saldo Tidak Cocok)',
      answer: '''Rekonsiliasi adalah pencocokan antara saldo di FFM dengan saldo rekening bank yang sebenarnya.
**Cara melakukan rekonsiliasi:**
1. Buka **Aktivitas** atau **Rekonsiliasi** (menu Lainnya).
2. Masukkan saldo aktual dari buku tabungan/mobile banking.
3. FFM akan menampilkan selisih dan daftar transaksi yang mungkin terlewat.

**Selisih saldo biasanya disebabkan oleh:**
- Ada transaksi yang belum tercatat (biaya admin bank, bunga, dll).
- Transaksi tercatat ganda.
- Saldo awal rekening yang salah.

Catat transaksi koreksi untuk menyeimbangkan saldo.''',
    ),

    // ─── ZAKAT ───────────────────────────────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'zakat',
        'zakat mal',
        'zakat fitrah',
        'hitung zakat',
        'berapa zakat',
        'nisab zakat',
        'kewajiban zakat',
      ],
      title: '🌙 Simulasi Kewajiban Zakat',
      answer: '''FFM memiliki fitur kalender Hijriah dan simulasi zakat.
**Zakat Mal (Harta):**
- Nisab: setara 85 gram emas (harga emas harian berubah — cek harga terkini).
- Kadar: **2,5%** dari total harta yang sudah mencapai haul (dimiliki 1 tahun Hijriah).
- Harta yang dihitung: tabungan/kas + investasi + aset likuid (dikurangi hutang yang jatuh tempo).

**Cara simulasi di FFM:**
1. Buka **Kalender Hijriah** (menu Lainnya).
2. Tekan **Hitung Zakat Mal** — FFM menggunakan data aset dan rekening yang sudah kamu catat sebagai dasar simulasi.
3. Hasilnya adalah estimasi — konsultasikan dengan amil atau ulama untuk keputusan akhir.

**Zakat Fitrah:**
- Nominal ditetapkan oleh baznas/pemerintah setempat tiap tahun (biasanya ekuivalen 2,5–3,5 kg beras).
- Wajib dibayar sebelum shalat Idul Fitri.''',
    ),

    // ─── ADVISOR / KESEHATAN FINANSIAL ───────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'kesehatan keuangan',
        'skor finansial',
        'rasio keuangan',
        'penilaian keuangan',
        'fitur advisor',
        'analisis keuangan',
        'cek kesehatan keuangan',
      ],
      title: '💡 Cara Cek Kesehatan Finansial',
      answer: '''FFM memiliki fitur **Advisor Finansial** yang menganalisis rasio kesehatan keuanganmu secara lokal.
**Rasio yang dihitung:**
- **Rasio Tabungan**: persentase pemasukan yang disisihkan (ideal: ≥20%).
- **Rasio Cicilan/Hutang**: total cicilan bulanan ÷ pemasukan bersih (aman: <35%).
- **Rasio Likuiditas**: kas dan tabungan ÷ pengeluaran bulanan (aman: ≥3 bulan).
- **Net Worth Trend**: tren pertumbuhan kekayaan bersih.

**Cara melihat:**
Buka **Penasihat** atau ketik *"Cek kesehatan keuanganku"* di chat — aku langsung tampilkan ringkasannya.''',
    ),

    // ─── WIDGET HOME SCREEN ──────────────────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'widget',
        'widget home screen',
        'shortcut hp',
        'cara pasang widget',
        'widget ringkasan',
      ],
      title: '📱 Cara Pasang Widget di Home Screen Android',
      answer: '''FFM mendukung widget ringkasan keuangan yang bisa dipasang di layar utama HP Android.
**Cara memasang:**
1. Tekan lama (long-press) di area kosong layar utama HP.
2. Pilih **Widget** → cari **FFM** atau **Family Finance Manager**.
3. Pilih ukuran widget → tekan dan seret ke posisi yang diinginkan.

**Jenis Widget yang tersedia:**
- **Ringkasan**: Saldo total + pengeluaran bulan ini.
- **Shortcut Asisten**: Langsung buka chat asisten.
- **Shortcut Tambah Transaksi**: Langsung ke formulir transaksi.''',
    ),

    // ─── LAPORAN BULANAN ──────────────────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'cara melihat laporan',
        'laporan bulanan',
        'bandingkan bulan',
        'lihat laporan',
        'grafik pengeluaran',
        'analisa bulanan',
      ],
      title: '📊 Cara Melihat Laporan Bulanan',
      answer: '''Laporan bulanan membandingkan arus kas, pemasukan, dan pengeluaran per bulan.
**Cara melihat:**
1. Buka **Ringkasan Bulanan** dari menu Lainnya atau dari chat: *"Buka laporan bulanan"*.
2. Pilih periode yang ingin dibandingkan.
3. FFM akan menampilkan grafik perbandingan arus kas, kategori pengeluaran terbesar, dan tren.

**Via Chat:** Ketik *"Bagaimana laporan bulan ini?"* atau *"Bandingkan bulan ini sama bulan lalu"* — aku akan tampilkan ringkasannya.''',
    ),

    // ─── PROGRES TABUNGAN ─────────────────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'cara cek progres tabungan',
        'progres target',
        'cek target tabungan',
        'seberapa dekat target',
        'tabungan terkumpul',
      ],
      title: '🎯 Cara Cek Progres Tabungan',
      answer: '''Progres tabungan menunjukkan seberapa dekat kamu dengan target keuangan.
**Cara melihat:**
1. Buka **Target Keuangan** (Goals) dari menu Lainnya.
2. Pilih target yang ingin dilihat — FFM akan menampilkan saldo terkumpul, persentase, dan sisa yang dibutuhkan.

**Via Chat:** Ketik *"Berapa progres tabungan liburan?"* atau *"Target mana yang paling dekat tercapai?"* — aku bantu cek datanya.''',
    ),

    // ─── KELOLA HUTANG ────────────────────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'cara kelola hutang',
        'strategi lunasi hutang',
        'bayar cicilan',
        'hutang banyak',
        'cara hilangkan utang',
      ],
      title: '💳 Cara Mengelola Hutang & Cicilan',
      answer: '''Mengelola hutang membutuhkan strategi yang jelas.
**Langkah awal:**
1. Buka **Hutang & Piutang** untuk melihat semua kewajiban aktif beserta saldo, bunga, dan jatuh tempo.
2. Prioritaskan hutang dengan bunga tertinggi (avalanche method) atau saldo terkecil (snowball method).
3. Catat setiap pembayaran cicilan agar saldo selalu terbarui.

**Via Chat:** Ketik *"Tolong bantu strategi lunasi hutang"* atau *"Hutang mana yang harus dibayar duluan?"* — aku bantu analisis dari data yang ada.''',
    ),

    // ─── GRAFIK PENGELUARAN ───────────────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'lihat grafik',
        'grafik uang',
        'pie chart',
        'visual pengeluaran',
        'pengeluaran terbesar',
      ],
      title: '📈 Cara Melihat Grafik Pengeluaran',
      answer: '''FFM menampilkan grafik pengeluaran untuk membantu kamu memahami pola belanja.
**Cara melihat:**
1. Buka **Ringkasan** (halaman utama) — grafik pie chart pengeluaran per kategori sudah ditampilkan.
2. Untuk analisis lebih detail, buka **Analisa** dari menu Lainnya.
3. Gunakan filter periode untuk melihat tren mingguan atau bulanan.

**Via Chat:** Ketik *"Kategori pengeluaran terbesar bulan ini apa?"* atau *"Tren pengeluaran 3 bulan terakhir"* — aku bantu baca grafiknya.''',
    ),

    // ─── PENGINGAT RUTIN ──────────────────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'cara atur pengingat rutin',
        'pengingat bulanan',
        'reminder otomatis',
        'tagihan rutin',
        'pengingat cicilan',
      ],
      title: '⏰ Cara Mengatur Pengingat Rutin',
      answer: '''Pengingat rutin membantu kamu tidak lupa tagihan atau komitmen berulang.
**Cara membuat:**
1. Buka **Pengingat** → tekan **+ Tambah Pengingat**.
2. Isi nama tagihan, nominal, tanggal jatuh tempo, dan frekuensi (harian/mingguan/bulanan/tahunan).
3. Simpan — notifikasi akan muncul sesuai jadwal.

**Tips:** Untuk tagihan yang nominalnya berubah (misal listrik), buat pengingat dengan nominal perkiraan dan catatan agar bisa disesuaikan saat tagihan datang.

**Via Chat:** Ketik *"Ingatkan bayar listrik tanggal 15 setiap bulan"* — aku siapkan draftnya.''',
    ),

    // ─── DANA DARURAT ─────────────────────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'dana darurat',
        'uang darurat',
        'cadangan keuangan',
        'siaga keuangan',
        'tabungan darurat',
        'emergency fund',
      ],
      title: '🛡️ Cara Membangun Dana Darurat',
      answer: '''Dana darurat adalah cadangan keuangan untuk situasi tak terduga (sakit, kehilangan pekerjaan, perbaikan mendesak).
**Target ideal:** 3-6x pengeluaran bulanan.
**Cara membangun di FFM:**
1. Buka **Target Keuangan** → tekan **+ Tambah Target**.
2. Buat target bernama "Dana Darurat" dengan nominal 3-6x pengeluaran bulananmu.
3. Tentukan tenggat (misal 12-24 bulan) agar ada komitmen.
4. Catat setiap setoran sebagai transaksi pengeluaran berkategori tabungan.

**Prioritas:** Dana darurat harus dibangun SEBELUM menabung untuk tujuan konsumtif (liburan, gadget, dll).''',
    ),

    // ─── ANALISIS KEUANGAN PERSONAL ───────────────────────────────────────
    FfmKnowledgeEntry(
      triggers: [
        'analisis keuangan saya',
        'kondisi keuangan saya',
        'bagaimana keuangan saya',
        'cek kesehatan finansial saya',
        'evaluasi keuangan',
      ],
      title: '🔍 Cara Melihat Analisis Keuangan Personal',
      answer: '''FFM bisa menganalisis kondisi keuanganmu berdasarkan data yang sudah tercatat.
**Yang bisa dianalisis:**
- **Savings Rate**: persentase pemasukan yang ditabung (ideal: ≥20%).
- **Debt-to-Income Ratio**: total cicilan dibanding pemasukan (aman: <35%).
- **Burn Rate**: laju pengeluaran dibanding pemasukan.
- **Kategori pengeluaran terbesar**: pos mana yang paling banyak makan uang.

**Cara melihat:**
- Buka **Analisa** dari menu Lainnya.
- Atau ketik di chat: *"Analisis keuanganku"* atau *"Bagaimana kondisi keuangan saya?"* — aku bantu baca datanya.''',
    ),
  ];

  /// Cari jawaban panduan yang cocok berdasarkan teks yang dinormalisasi.
  /// Mengembalikan `null` jika tidak ada entri yang cocok.
  FfmKnowledgeEntry? findAnswer(String normalizedText) {
    for (final entry in _entries) {
      if (entry.matches(normalizedText)) return entry;
    }
    return null;
  }
}
