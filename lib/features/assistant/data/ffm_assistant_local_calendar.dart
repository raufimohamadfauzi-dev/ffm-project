/// Kalkulasi kalender lokal yang murni dan tidak membutuhkan internet.
/// Nilai waktu harus berasal dari perangkat agar jawaban mengikuti pengaturan HP.
abstract final class FfmAssistantLocalCalendar {
  static const _days = <String>[
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];

  static const _months = <String>[
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  static String? answer(String text, {required DateTime now}) {
    if (_contains(text, const [
      'sekarang jam berapa',
      'jam berapa sekarang',
      'waktu sekarang',
    ])) {
      final hour = now.hour.toString().padLeft(2, '0');
      final minute = now.minute.toString().padLeft(2, '0');
      return 'Sekarang pukul $hour.$minute pada ${formatDate(now)}, mengikuti waktu lokal HP kamu.';
    }
    if (_contains(text, const [
      'hari ini tanggal berapa',
      'tanggal hari ini',
      'sekarang tanggal berapa',
    ])) {
      return 'Hari ini ${formatDate(now)}, mengikuti tanggal lokal HP kamu.';
    }
    if (_contains(text, const [
      'besok hari apa',
      'besok tanggal berapa',
      'tanggal besok',
      'hari apa besok',
    ])) {
      final tomorrow = now.add(const Duration(days: 1));
      return 'Besok ${formatDate(tomorrow)}, mengikuti tanggal lokal HP kamu.';
    }

    final relative = RegExp(
      r'\b(\d+)\s+(hari|minggu|bulan)\s+(lagi|kedepan|ke depan|lalu)\b',
    ).firstMatch(text);
    if (relative != null) {
      final value = int.tryParse(relative.group(1)!);
      if (value == null || value > 36500) {
        return 'Angka waktunya belum bisa aku hitung. Tulis angka yang wajar, misalnya “90 hari lagi”.';
      }
      final unit = relative.group(2)!;
      final direction = relative.group(3)!;
      final forward = direction != 'lalu';
      final signed = forward ? value : -value;
      final target = switch (unit) {
        'hari' => now.add(Duration(days: signed)),
        'minggu' => now.add(Duration(days: signed * 7)),
        _ => _addMonths(now, signed),
      };
      final label = forward ? 'lagi' : 'lalu';
      return '$value $unit $label dari tanggal lokal HP kamu adalah ${formatDate(target)}.';
    }

    if (_contains(text, const [
      'kalender perangkat',
      'kalender ada apa',
      'kalender apa saja',
      'fitur kalender',
      'tentang kalender',
      'kalender di ffm',
      'kalender di hp',
      'ada kalender apa',
      'jenis kalender',
    ]) || (text.contains('kalender') && _contains(text, const ['apa saja', 'ada apa', 'apaan', 'jelaskan', 'fungsi', 'fitur']))) {
      return '''📅 **Kalender di FFM & Perangkat Kamu:**

1. **Kalender Masehi Lokal (Waktu HP):**
   • Hari ini: **${formatDate(now)}**
   • Jam: **${now.hour.toString().padLeft(2, '0')}.${now.minute.toString().padLeft(2, '0')}**
   • Kamu bisa tanya tanggal/hari apa saja, misalnya: *"10 hari lagi tanggal berapa"*, *"besok hari apa"*, atau *"17 Agustus 2026 hari apa"*.

2. **Kalender Hijriah (Offline / Hisab Lokal):**
   • Digunakan untuk penentuan tanggal Islam, jadwal pengingat ibadah, serta perhitungan hisab haul/nisab Zakat Maal & Fitrah secara lokal tanpa internet.
   • Coba tanyakan: *"tanggal hijriah hari ini"* atau *"besok tanggal berapa hijriah"*.

3. **Jadwal & Pengingat Keuangan:**
   • Terhubung dengan menu **Pemasukan/Pengeluaran Berkala** dan **Pengingat** untuk mencatat tagihan rutin bulanan atau tanggal jatuh tempo.''';
    }

    if (_contains(text, const ['hari apa tanggal', 'tanggal apa harinya'])) {
      final date = _parseIndonesianDate(text, fallbackYear: now.year);
      if (date == null) {
        return 'Tulis tanggal lengkapnya ya, misalnya “17 Oktober 2026 hari apa?”.';
      }
      return '${formatDate(date)}.';
    }
    return null;
  }

  static String formatDate(DateTime date) =>
      '${_days[date.weekday - 1]}, ${date.day} ${_months[date.month - 1]} ${date.year}';

  static DateTime _addMonths(DateTime date, int months) {
    final targetMonthIndex = date.year * 12 + date.month - 1 + months;
    final year = targetMonthIndex ~/ 12;
    final month = targetMonthIndex % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, date.day > lastDay ? lastDay : date.day);
  }

  static DateTime? _parseIndonesianDate(
    String text, {
    required int fallbackYear,
  }) {
    final monthPattern = _months.map((month) => month.toLowerCase()).join('|');
    final match = RegExp('(\\d{1,2})\\s+($monthPattern)(?:\\s+(\\d{4}))?')
        .firstMatch(text);
    if (match == null) return null;
    final day = int.tryParse(match.group(1)!);
    final month = _months.indexWhere(
      (item) => item.toLowerCase() == match.group(2)!.toLowerCase(),
    );
    final year = int.tryParse(match.group(3) ?? '') ?? fallbackYear;
    if (day == null || month < 0 || day < 1) return null;
    final lastDay = DateTime(year, month + 2, 0).day;
    if (day > lastDay) return null;
    return DateTime(year, month + 1, day);
  }

  static bool _contains(String text, List<String> values) =>
      values.any(text.contains);
}
