import 'package:intl/intl.dart';

/// Format tanggal aman tanpa risiko crash LocaleDataException.
///
/// intl membutuhkan data locale (date symbols) dimuat via
/// [initializeDateFormatting] sebelum [DateFormat] dengan argumen locale
/// dipakai. Kelas ini tetap aman seandainya data belum siap.
class SafeDateFormat {
  const SafeDateFormat._();

  static String format(
    DateTime? date, {
    String pattern = 'dd MMM yyyy',
    String locale = 'id_ID',
    String fallbackText = '-',
  }) {
    if (date == null) return fallbackText;

    try {
      // 1. Coba format sesuai locale target (misal: 'id_ID')
      return DateFormat(pattern, locale).format(date);
    } catch (_) {
      try {
        // 2. Fallback: Format tanpa argumen locale (menggunakan default intl)
        return DateFormat(pattern).format(date);
      } catch (_) {
        // 3. Ultimate Fallback: String formatting standar Dart (YYYY-MM-DD)
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      }
    }
  }
}

/// Ekstensi praktis agar DateTime bisa diformat aman dari mana saja.
extension SafeDateTimeFormatter on DateTime {
  String toSafeString({String pattern = 'dd MMMM yyyy', String locale = 'id_ID'}) {
    try {
      return DateFormat(pattern, locale).format(this);
    } catch (_) {
      // Fallback aman jika locale belum siap
      return DateFormat(pattern).format(this);
    }
  }
}
