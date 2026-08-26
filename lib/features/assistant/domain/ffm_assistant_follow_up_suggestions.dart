import 'ffm_assistant_models.dart';

/// Penghasil 3 rekomendasi pertanyaan lanjutan cerdas (Follow-up suggestions)
/// yang relevan dengan respons Asisten terakhir.
class FfmAssistantFollowUpSuggestions {
  const FfmAssistantFollowUpSuggestions._();

  static List<String> generate({
    required FfmAssistantIntent? intent,
    required String? lastResponseText,
    String? userQuestion,
  }) {
    final lowerUser = (userQuestion ?? '').toLowerCase();
    final lowerResponse = (lastResponseText ?? '').toLowerCase();

    // 1. Topik Kalender & Waktu
    if (intent?.type == FfmAssistantIntentType.calendarQuery ||
        lowerUser.contains('kalender') ||
        lowerUser.contains('hijri') ||
        lowerResponse.contains('hijriah') ||
        lowerResponse.contains('masehi')) {
      return const [
        'Kapan tanggal 1 Ramadan tahun ini?',
        'Berapa hari lagi sampai akhir bulan?',
        'Jadwalkan pengingat bayar tagihan',
      ];
    }

    // 3. Jika sedang ada draft aktif yang disiapkan
    if (intent?.draft != null) {
      final kind = intent!.draft!.kind;
      if (kind == FfmAssistantDraftKind.expense ||
          kind == FfmAssistantDraftKind.income ||
          kind == FfmAssistantDraftKind.transfer) {
        return const [
          'Konfirmasi dan simpan draf ini',
          'Ganti nominal draf transaksi ini',
          'Batalkan draf transaksi ini',
        ];
      }
      return const [
        'Lanjutkan proses simpan',
        'Ubah rincian draf ini',
        'Batal',
      ];
    }

    // 4. Analisis Keuangan & Statistik Transaksi
    if (intent?.type == FfmAssistantIntentType.transactionStats ||
        intent?.type == FfmAssistantIntentType.weeklyAnalysis ||
        intent?.type == FfmAssistantIntentType.queryData ||
        lowerUser.contains('pengeluaran') ||
        lowerUser.contains('saldo') ||
        lowerUser.contains('transaksi')) {
      return const [
        'Berapa sisa anggaran belanja bulan ini?',
        'Tampilkan ringkasan pengeluaran minggu ini',
        'Berapa total saldo seluruh rekening?',
      ];
    }

    // 5. Anggaran & Peringatan Keuangan
    if (intent?.type == FfmAssistantIntentType.financialWarnings ||
        intent?.type == FfmAssistantIntentType.createBudget ||
        lowerUser.contains('anggaran') ||
        lowerUser.contains('budget')) {
      return const [
        'Apakah ada anggaran yang hampir habis?',
        'Bagaimana cara mengatur limit belanja?',
        'Catat pengeluaran bensin 25 ribu',
      ];
    }

    // 6. Setup Data Utama / Akun / Profil
    if (intent?.type == FfmAssistantIntentType.setupGuide ||
        intent?.type == FfmAssistantIntentType.createMasterData ||
        intent?.type == FfmAssistantIntentType.createProfile ||
        lowerUser.contains('setup') ||
        lowerUser.contains('rekening') ||
        lowerUser.contains('kategori')) {
      return const [
        'Buat rekening BCA saldo 1 juta',
        'Tambah kategori Makanan dan Minuman',
        'Bagaimana cara atur profil keuangan?',
      ];
    }

    // 7. Bantuan Fitur & Identitas Asisten
    if (intent?.type == FfmAssistantIntentType.assistantIdentity ||
        intent?.type == FfmAssistantIntentType.help ||
        intent?.type == FfmAssistantIntentType.listPages ||
        lowerUser.contains('bisa apa') ||
        lowerUser.contains('bantuan')) {
      return const [
        'Cara mencatat pengeluaran harian?',
        'Berapa sisa anggaran bulan ini?',
        'Tampilkan daftar halaman aplikasi',
      ];
    }

    // 8. Default / Rekomendasi Umum yang Berguna
    return const [
      'Catat pengeluaran makan siang 35 ribu',
      'Berapa pengeluaran saya minggu ini?',
      'Kalender perangkat ada apa saja?',
    ];
  }
}
