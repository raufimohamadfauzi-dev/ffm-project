/// Mesin pembuat saran pertanyaan lanjutan adaptif (Adaptive Follow-up Suggestions).
///
/// Menghasilkan 3 pertanyaan kontekstual yang cerdas dan relevan berdasarkan
/// topik percakapan terakhir (seperti Grok / Manus AI), agar pengguna dapat
/// langsung memilih dan mengirimnya kembali ke Asisten dengan 1 ketukan.
class FfmFollowUpSuggestionEngine {
  const FfmFollowUpSuggestionEngine();

  /// Menghasilkan 3 pertanyaan lanjutan berdasarkan isi pesan pengguna dan respons asisten.
  List<String> generateSuggestions({
    required String userText,
    required String assistantResponse,
    String? categoryName,
  }) {
    final combined = '${userText.toLowerCase()} ${assistantResponse.toLowerCase()} ${categoryName?.toLowerCase() ?? ''}';

    // 1. Topik Pertanian, Kebun, Panen, dan Siklus Kas
    if (combined.contains('panen') ||
        combined.contains('pupuk') ||
        combined.contains('sawah') ||
        combined.contains('kebun') ||
        combined.contains('tani') ||
        combined.contains('bibit') ||
        combined.contains('komoditas') ||
        combined.contains('musiman')) {
      return const [
        'Berapa sisa runway kas saya sampai masa panen?',
        'Kapan perkiraan tanggal panen berikutnya?',
        'Bagaimana cara menekan biaya pupuk dan operasional kebun?',
      ];
    }

    // 2. Topik Kendaraan, Bensin, dan Log BBM
    if (combined.contains('bbm') ||
        combined.contains('bensin') ||
        combined.contains('pertalite') ||
        combined.contains('pertamax') ||
        combined.contains('solar') ||
        combined.contains('spbu') ||
        combined.contains('odometer') ||
        combined.contains('motor') ||
        combined.contains('mobil') ||
        combined.contains('kendaraan')) {
      return const [
        'Berapa rata-rata efisiensi BBM (KM/L) kendaraan saya?',
        'Berapa total biaya pengeluaran bensin bulan ini?',
        'Berapa liter bensin yang sudah diisi bulan ini?',
      ];
    }

    // 3. Topik Listrik, Pulsa Listrik, Meteran, dan Token PLN
    if (combined.contains('token') ||
        combined.contains('listrik') ||
        combined.contains('pln') ||
        combined.contains('meteran') ||
        combined.contains('idpel') ||
        combined.contains('kwh') ||
        combined.contains('stroom')) {
      return const [
        'Kapan perkiraan token listrik ini akan habis?',
        'Berapa total pembelian token listrik bulan ini?',
        'Tampilkan nomor meteran properti saya yang lain',
      ];
    }

    // 4. Topik Anggaran, Amplop, dan Defisit (Rebalance)
    if (combined.contains('anggaran') ||
        combined.contains('budget') ||
        combined.contains('amplop') ||
        combined.contains('rebalance') ||
        combined.contains('defisit') ||
        combined.contains('surplus') ||
        combined.contains('pagu')) {
      return const [
        'Pos anggaran mana saja yang sedang defisit?',
        'Berapa batas belanja harian yang aman untuk minggu ini?',
        'Berapa surplus anggaran yang aman dialihkan?',
      ];
    }

    // 5. Topik Hutang, Piutang, dan Cicilan Bulanan
    if (combined.contains('hutang') ||
        combined.contains('utang') ||
        combined.contains('cicilan') ||
        combined.contains('piutang') ||
        combined.contains('bunga') ||
        combined.contains('dsr') ||
        combined.contains('tempo')) {
      return const [
        'Berapa sisa pokok hutang dan total cicilan bulanan saya?',
        'Bagaimana strategi melunasi hutang dengan bunga tertinggi lebih cepat?',
        'Apakah rasio cicilan hutang saya saat ini masih aman?',
      ];
    }

    // 6. Topik Tabungan, Target, dan Goal Keuangan
    if (combined.contains('target') ||
        combined.contains('goal') ||
        combined.contains('tabungan') ||
        combined.contains('menabung') ||
        combined.contains('investasi')) {
      return const [
        'Berapa progres pencapaian target tabungan saya saat ini?',
        'Berapa nominal yang harus ditabung setiap bulan agar tercapai?',
        'Apakah sisa kas bulan ini cukup untuk menambah tabungan?',
      ];
    }

    // 7. Topik Makanan, Dapur, dan Belanja Harian
    if (combined.contains('makan') ||
        combined.contains('dapur') ||
        combined.contains('sembako') ||
        combined.contains('belanja') ||
        combined.contains('pasar') ||
        combined.contains('warung')) {
      return const [
        'Berapa rata-rata pengeluaran belanja dapur harian saya?',
        'Apakah belanja makanan bulan ini lebih hemat dari bulan lalu?',
        'Berapa sisa jatah uang makan sampai akhir bulan?',
      ];
    }

    // 8. Topik Laporan & Ringkasan Umum Keuangan (Fallback Dinamis Cerdas)
    return const [
      'Tampilkan ringkasan arus kas masuk dan keluar minggu ini',
      'Kategori pengeluaran apa yang paling besar bulan ini?',
      'Berapa total saldo kas likuid saya yang tersedia saat ini?',
    ];
  }
}
