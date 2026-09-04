import 'package:intl/intl.dart';

/// Formatter pesan ramah berbahasa Indonesia dalam format HTML untuk Telegram Bot.
class TelegramMessageFormatter {
  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  /// Format rupiah yang rapi (contoh: Rp 1.250.000)
  static String formatRupiah(num amount) => _currencyFormat.format(amount);

  /// Membentuk laporan mingguan berkala untuk keluarga
  static String formatWeeklyReport({
    String? familyName,
    String? husbandName,
    String? wifeName,
    required num totalExpense,
    required num totalIncome,
    String? topExpenseCategory,
    num? topExpenseAmount,
    required num cashBalance,
    int? healthScore,
    String? headline,
  }) {
    final buffer = StringBuffer();

    // Header keluarga
    final titleFamily = familyName != null && familyName.trim().isNotEmpty
        ? 'Keluarga <b>${familyName.trim()}</b>'
        : 'Keluarga Anda';
    buffer.writeln('🌿 <b>Laporan Keuangan Mingguan — $titleFamily</b>');

    // Sapaan hangat
    final greeting = _buildGreeting(husbandName, wifeName);
    if (greeting.isNotEmpty) {
      buffer.writeln('<i>$greeting</i>');
    }
    buffer.writeln('');

    // Rincian Arus Kas
    buffer.writeln('📉 <b>Pengeluaran Pekan Ini:</b> ${formatRupiah(totalExpense)}');
    if (totalIncome > 0) {
      buffer.writeln('📈 <b>Pemasukan Pekan Ini:</b> ${formatRupiah(totalIncome)}');
    }

    if (topExpenseCategory != null &&
        topExpenseCategory.trim().isNotEmpty &&
        topExpenseAmount != null &&
        topExpenseAmount > 0) {
      buffer.writeln(
        '🛒 <b>Pos Terbesar:</b> ${topExpenseCategory.trim()} (${formatRupiah(topExpenseAmount)})',
      );
    }

    buffer.writeln('💰 <b>Sisa Kas & Rekening:</b> ${formatRupiah(cashBalance)}');

    // Skor kesehatan finansial jika ada
    if (healthScore != null) {
      buffer.writeln('🛡️ <b>Skor Kesehatan Finansial:</b> $healthScore/100');
    }

    // Headline / saran penutup
    if (headline != null && headline.trim().isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('💡 <i>"${headline.trim()}"</i>');
    }

    return buffer.toString().trim();
  }

  /// Membentuk pesan peringatan mendesak (*Radar Alert*)
  static String formatAlertMessage({
    required String title,
    required String summary,
    String? recommendation,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('⚠️ <b>Peringatan Radar Asisten FFM</b>\n');
    buffer.writeln('📌 <b>$title</b>');
    buffer.writeln(summary.trim());

    if (recommendation != null && recommendation.trim().isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('💡 <i>Saran: ${recommendation.trim()}</i>');
    }

    return buffer.toString().trim();
  }

  /// Membentuk notifikasi instan saat ada transaksi baru dicatat di aplikasi
  static String formatNewTransactionMessage({
    required String type,
    required num amount,
    required String categoryOrDescription,
    String? categoryName,
    String? accountName,
    String? recordedBy,
    DateTime? transactionDate,
  }) {
    final buffer = StringBuffer();
    final isExpense = type == 'expense';
    final isIncome = type == 'income';

    if (isExpense) {
      buffer.writeln('🛒 <b>Catatan Pengeluaran Baru</b>\n');
      buffer.writeln('📉 <b>Nominal:</b> ${formatRupiah(amount)}');
    } else if (isIncome) {
      buffer.writeln('💰 <b>Pemasukan Baru Masuk</b>\n');
      buffer.writeln('📈 <b>Nominal:</b> ${formatRupiah(amount)}');
    } else {
      buffer.writeln('🔄 <b>Mutasi Transaksi Baru</b>\n');
      buffer.writeln('💵 <b>Nominal:</b> ${formatRupiah(amount)}');
    }

    if (categoryName != null && categoryName.trim().isNotEmpty) {
      buffer.writeln('🏷️ <b>Kategori:</b> ${categoryName.trim()}');
    }

    if (categoryOrDescription.trim().isNotEmpty &&
        categoryOrDescription.trim() != categoryName?.trim()) {
      buffer.writeln('📝 <b>Keterangan:</b> ${categoryOrDescription.trim()}');
    }

    if (accountName != null && accountName.trim().isNotEmpty) {
      buffer.writeln('💳 <b>Sumber Dana:</b> ${accountName.trim()}');
    }

    if (recordedBy != null && recordedBy.trim().isNotEmpty) {
      buffer.writeln('👤 <b>Dicatat oleh:</b> ${recordedBy.trim()}');
    }

    if (transactionDate != null) {
      try {
        final dateStr =
            DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(transactionDate);
        buffer.writeln('📅 <b>Waktu:</b> $dateStr WIB');
      } catch (_) {
        buffer.writeln('📅 <b>Waktu:</b> ${transactionDate.toIso8601String()}');
      }
    }

    return buffer.toString().trim();
  }

  static String _buildGreeting(String? husband, String? wife) {
    final h = husband?.trim();
    final w = wife?.trim();

    if (h != null && h.isNotEmpty && w != null && w.isNotEmpty) {
      return 'Halo Bapak $h & Ibu $w, berikut catatan radar pekan ini:';
    } else if (h != null && h.isNotEmpty) {
      return 'Halo Bapak $h, berikut catatan radar pekan ini:';
    } else if (w != null && w.isNotEmpty) {
      return 'Halo Ibu $w, berikut catatan radar pekan ini:';
    }
    return 'Halo, berikut ringkasan radar keuangan keluarga pekan ini:';
  }
}
