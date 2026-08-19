import 'financial_health_calculator.dart';

enum SuggestionPlacement { dashboard, transaction, analysis }

class AdvisorSuggestionInput {
  const AdvisorSuggestionInput({
    required this.healthScore,
    required this.transactionCount,
    required this.hasIncome,
    required this.hasExpense,
  });

  final FinancialHealthScore healthScore;
  final int transactionCount;
  final bool hasIncome;
  final bool hasExpense;
}

class AdvisorSuggestion {
  const AdvisorSuggestion({
    required this.title,
    required this.message,
    required this.placement,
  });

  final String title;
  final String message;
  final SuggestionPlacement placement;
}

class AdvisorSuggestionGenerator {
  const AdvisorSuggestionGenerator();

  List<AdvisorSuggestion> generate(AdvisorSuggestionInput input) {
    final suggestions = <AdvisorSuggestion>[];
    if (!input.hasIncome && !input.hasExpense) {
      suggestions.add(
        const AdvisorSuggestion(
          title: 'Mulai dari satu transaksi',
          message: 'Catat pemasukan atau pengeluaran pertama supaya pola keuangan keluarga mulai terbaca.',
          placement: SuggestionPlacement.dashboard,
        ),
      );
    } else if (!input.hasIncome) {
      suggestions.add(
        const AdvisorSuggestion(
          title: 'Pemasukan belum tercatat',
          message: 'Coba catat pemasukan yang sudah diterima supaya arus kas keluarga lebih utuh.',
          placement: SuggestionPlacement.dashboard,
        ),
      );
    } else if (!input.hasExpense) {
      suggestions.add(
        const AdvisorSuggestion(
          title: 'Pengeluaran belum tercatat',
          message: 'Catat pengeluaran harian apa adanya. Nanti ringkasan akan membantu melihat polanya.',
          placement: SuggestionPlacement.dashboard,
        ),
      );
    } else if (input.healthScore.cashflow < 0) {
      suggestions.add(
        const AdvisorSuggestion(
          title: 'Arus kas sedang minus',
          message: 'Yuk cek kategori pengeluaran terbesar dan cari pos yang masih bisa dirapikan.',
          placement: SuggestionPlacement.dashboard,
        ),
      );
    } else {
      suggestions.add(
        const AdvisorSuggestion(
          title: 'Ritme keuangan sudah mulai kebaca',
          message: 'Pertahankan pencatatan rutin supaya perbandingan antarbulan makin berguna.',
          placement: SuggestionPlacement.dashboard,
        ),
      );
    }
    suggestions.add(
      const AdvisorSuggestion(
        title: 'Catat serinci yang kamu butuhkan',
        message: 'Gunakan kategori, toko, tag, dan Dipakai oleh untuk melihat rincian tanpa memisahkan saldo keluarga.',
        placement: SuggestionPlacement.analysis,
      ),
    );
    return suggestions;
  }
}
