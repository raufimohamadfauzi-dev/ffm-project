enum FfmDatePeriodPreset {
  allTime,
  today,
  yesterday,
  thisWeek,
  thisMonth,
  lastMonth,
  last3Months,
  last6Months,
  lastYear,
  thisYear,
  previousYear,
}

class FfmDatePeriod {
  const FfmDatePeriod({
    required this.start,
    required this.endExclusive,
    required this.label,
  });

  final DateTime? start;
  final DateTime? endExclusive;
  final String label;

  bool get isAllTime => start == null && endExclusive == null;

  DateTime? get endInclusive => endExclusive?.subtract(const Duration(days: 1));

  DateTime get startOrEpoch => start ?? DateTime.fromMicrosecondsSinceEpoch(0);
  DateTime get endOrMax => endExclusive ?? DateTime(9999, 12, 31);

  bool contains(DateTime value) {
    if (start != null && value.isBefore(start!)) return false;
    if (endExclusive != null && !value.isBefore(endExclusive!)) return false;
    return true;
  }

  static FfmDatePeriod fromPreset(FfmDatePeriodPreset preset, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final tomorrow = today.add(const Duration(days: 1));

    switch (preset) {
      case FfmDatePeriodPreset.allTime:
        return const FfmDatePeriod(
          start: null,
          endExclusive: null,
          label: 'Semua waktu',
        );
      case FfmDatePeriodPreset.today:
        return FfmDatePeriod(
          start: today,
          endExclusive: tomorrow,
          label: 'Hari ini',
        );
      case FfmDatePeriodPreset.yesterday:
        return FfmDatePeriod(
          start: today.subtract(const Duration(days: 1)),
          endExclusive: today,
          label: 'Kemarin',
        );
      case FfmDatePeriodPreset.thisWeek:
        final start = today.subtract(Duration(days: today.weekday - 1));
        return FfmDatePeriod(
          start: start,
          endExclusive: start.add(const Duration(days: 7)),
          label: 'Minggu ini',
        );
      case FfmDatePeriodPreset.thisMonth:
        return FfmDatePeriod(
          start: DateTime(today.year, today.month),
          endExclusive: DateTime(today.year, today.month + 1),
          label: 'Bulan ini',
        );
      case FfmDatePeriodPreset.lastMonth:
        return FfmDatePeriod(
          start: DateTime(today.year, today.month - 1),
          endExclusive: DateTime(today.year, today.month),
          label: 'Bulan lalu',
        );
      case FfmDatePeriodPreset.last3Months:
        return FfmDatePeriod(
          start: DateTime(today.year, today.month - 3, today.day),
          endExclusive: tomorrow,
          label: '3 bulan terakhir',
        );
      case FfmDatePeriodPreset.last6Months:
        return FfmDatePeriod(
          start: DateTime(today.year, today.month - 6, today.day),
          endExclusive: tomorrow,
          label: '6 bulan terakhir',
        );
      case FfmDatePeriodPreset.lastYear:
        return FfmDatePeriod(
          start: DateTime(today.year - 1, today.month, today.day),
          endExclusive: tomorrow,
          label: '1 tahun terakhir',
        );
      case FfmDatePeriodPreset.thisYear:
        return FfmDatePeriod(
          start: DateTime(today.year),
          endExclusive: DateTime(today.year + 1),
          label: 'Tahun ini',
        );
      case FfmDatePeriodPreset.previousYear:
        return FfmDatePeriod(
          start: DateTime(today.year - 1),
          endExclusive: DateTime(today.year),
          label: 'Tahun lalu',
        );
    }
  }

  static FfmDatePeriod custom({
    required DateTime start,
    required DateTime end,
  }) {
    final startDate = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);
    return FfmDatePeriod(
      start: startDate,
      endExclusive: endDate.add(const Duration(days: 1)),
      label: '${_format(startDate)} - ${_format(endDate)}',
    );
  }

  static FfmDatePeriod? fromText(String text, {DateTime? now}) {
    final normalized = text.toLowerCase();
    final reference = now ?? DateTime.now();
    if (normalized.contains('hari ini')) {
      return fromPreset(FfmDatePeriodPreset.today, now: reference);
    }
    if (normalized.contains('kemarin')) {
      return fromPreset(FfmDatePeriodPreset.yesterday, now: reference);
    }
    if (normalized.contains('minggu ini') ||
        normalized.contains('seminggu')) {
      return fromPreset(FfmDatePeriodPreset.thisWeek, now: reference);
    }
    if (normalized.contains('bulan ini')) {
      return fromPreset(FfmDatePeriodPreset.thisMonth, now: reference);
    }
    if (normalized.contains('bulan lalu') ||
        normalized.contains('bulan kemarin')) {
      return fromPreset(FfmDatePeriodPreset.lastMonth, now: reference);
    }
    if (normalized.contains('6 bulan')) {
      return fromPreset(FfmDatePeriodPreset.last6Months, now: reference);
    }
    if (normalized.contains('3 bulan') ||
        normalized.contains('tiga bulan') ||
        normalized.contains('90 hari')) {
      return fromPreset(FfmDatePeriodPreset.last3Months, now: reference);
    }
    if (normalized.contains('tahun lalu')) {
      return fromPreset(FfmDatePeriodPreset.previousYear, now: reference);
    }
    if (normalized.contains('tahun ini')) {
      return fromPreset(FfmDatePeriodPreset.thisYear, now: reference);
    }
    if (normalized.contains('1 tahun') ||
        normalized.contains('satu tahun') ||
        normalized.contains('setahun') ||
        normalized.contains('12 bulan') ||
        normalized.contains('tahun terakhir')) {
      return fromPreset(FfmDatePeriodPreset.lastYear, now: reference);
    }
    final yearMatch = RegExp(r'\b(?:tahun\s+)?(19|20)\d{2}\b')
        .firstMatch(normalized);
    if (yearMatch != null) {
      final year = int.parse(yearMatch.group(0)!.replaceFirst('tahun ', ''));
      return FfmDatePeriod(
        start: DateTime(year),
        endExclusive: DateTime(year + 1),
        label: 'tahun $year',
      );
    }
    return null;
  }

  static String _format(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}
