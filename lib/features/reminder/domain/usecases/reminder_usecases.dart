import 'package:hijri_plus/hijri_plus.dart';
import '../entities/reminder_entity.dart';

class ReminderOccurrenceCalculator {
  const ReminderOccurrenceCalculator();

  static const replenishmentHorizon = Duration(days: 14);
  static const maxQueuedOccurrences = 32;

  ReminderOccurrence? nextOccurrence(ReminderEntity reminder, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final base = reminder.scheduledAt.toLocal();
    final candidate = switch (reminder.recurrenceType) {
      ReminderRecurrenceType.once => _nextOnce(base, current),
      ReminderRecurrenceType.daily => nextDailyOccurrenceAt(base, current),
      ReminderRecurrenceType.weekly => nextWeeklyOccurrenceAt(
        base,
        current,
        reminder.weekdays,
      ),
      ReminderRecurrenceType.monthly => nextMonthlyOccurrenceAt(base, current),
      ReminderRecurrenceType.yearly => nextYearlyOccurrenceAt(base, current),
      ReminderRecurrenceType.hijriMonthly =>
          nextHijriMonthlyOccurrenceAt(base, current),
    };
    if (candidate == null) return null;
    return ReminderOccurrence(
      key: occurrenceKey(candidate),
      scheduledAt: candidate,
      notificationId: stableReminderNotificationId(
        reminder.id,
        occurrenceKey(candidate),
      ),
    );
  }

  List<ReminderOccurrence> upcomingOccurrences(
    ReminderEntity reminder, {
    DateTime? now,
    Duration horizon = replenishmentHorizon,
    int limit = maxQueuedOccurrences,
  }) {
    if (!reminder.isActive || limit < 1) return const [];
    final current = now ?? DateTime.now();
    final end = current.add(horizon);
    final occurrences = <ReminderOccurrence>[];
    var cursor = current;
    while (occurrences.length < limit) {
      final occurrence = nextOccurrence(reminder, now: cursor);
      if (occurrence == null) break;
      if (occurrence.scheduledAt.isAfter(end) && occurrences.isNotEmpty) break;
      occurrences.add(occurrence);
      if (reminder.recurrenceType == ReminderRecurrenceType.once ||
          occurrence.scheduledAt.isAfter(end)) {
        break;
      }
      cursor = occurrence.scheduledAt.add(const Duration(seconds: 1));
    }
    return occurrences;
  }

  String occurrenceKey(DateTime dateTime) {
    final value = dateTime.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}-'
        '${two(value.hour)}${two(value.minute)}';
  }

  DateTime? _nextOnce(DateTime base, DateTime now) {
    return base.isAfter(now) ? base : null;
  }
}

/// Occurrence harian berikutnya (hari ini atau besok) pada jam-menit sama
/// dengan [base]. Dipakai juga oleh penjadwal background agar satu sumber
/// kebenaran untuk logika pengulangan.
DateTime nextDailyOccurrenceAt(DateTime base, DateTime now) {
  final boundary = now.isAfter(base) ? now : base;
  var candidate = DateTime(
    boundary.year,
    boundary.month,
    boundary.day,
    base.hour,
    base.minute,
    base.second,
  );
  if (candidate.isBefore(now) || candidate.isBefore(base)) {
    candidate = DateTime(
      candidate.year,
      candidate.month,
      candidate.day + 1,
      base.hour,
      base.minute,
      base.second,
    );
  }
  return candidate;
}

/// Occurrence mingguan berikutnya pada salah satu [configuredWeekdays]
/// dengan jam-menit sama seperti [base].
DateTime nextWeeklyOccurrenceAt(
  DateTime base,
  DateTime now,
  List<int> configuredWeekdays,
) {
  final validWeekdays =
      configuredWeekdays.toSet().where((day) => day >= 1 && day <= 7).toList()
        ..sort();
  final weekdays = validWeekdays.isEmpty ? <int>[base.weekday] : validWeekdays;
  final boundary = now.isAfter(base) ? now : base;
  for (var offset = 0; offset <= 14; offset++) {
    final day = DateTime(boundary.year, boundary.month, boundary.day + offset);
    final candidate = DateTime(
      day.year,
      day.month,
      day.day,
      base.hour,
      base.minute,
      base.second,
    );
    if (weekdays.contains(candidate.weekday) &&
        !candidate.isBefore(now) &&
        !candidate.isBefore(base)) {
      return candidate;
    }
  }
  throw StateError('Tidak dapat menghitung occurrence mingguan yang valid.');
}

/// Occurrence bulanan berikutnya pada tanggal yang sama dengan [base]
/// (menyesuaikan batas akhir bulan jika bulan memiliki jumlah hari lebih sedikit)
/// dengan jam-menit sama seperti [base].
DateTime nextMonthlyOccurrenceAt(DateTime base, DateTime now) {
  final boundary = now.isAfter(base) ? now : base;
  var targetYear = boundary.year;
  var targetMonth = boundary.month;

  for (var offset = 0; offset <= 36; offset++) {
    var m = targetMonth + offset;
    var y = targetYear + (m - 1) ~/ 12;
    m = ((m - 1) % 12) + 1;

    final daysInMonth = DateTime(y, m + 1, 0).day;
    final clampedDay = base.day > daysInMonth ? daysInMonth : base.day;

    final candidate = DateTime(
      y,
      m,
      clampedDay,
      base.hour,
      base.minute,
      base.second,
    );

    if (!candidate.isBefore(now) && !candidate.isBefore(base)) {
      return candidate;
    }
  }
  throw StateError('Tidak dapat menghitung occurrence bulanan yang valid.');
}

/// Occurrence tahunan berikutnya pada bulan dan tanggal yang sama dengan [base]
/// (menyesuaikan 29 Februari ke 28 Februari pada tahun non-kabisat)
/// dengan jam-menit sama seperti [base].
DateTime nextYearlyOccurrenceAt(DateTime base, DateTime now) {
  final boundary = now.isAfter(base) ? now : base;
  var targetYear = boundary.year;

  for (var offset = 0; offset <= 10; offset++) {
    final y = targetYear + offset;
    final daysInMonth = DateTime(y, base.month + 1, 0).day;
    final clampedDay = base.day > daysInMonth ? daysInMonth : base.day;

    final candidate = DateTime(
      y,
      base.month,
      clampedDay,
      base.hour,
      base.minute,
      base.second,
    );

    if (!candidate.isBefore(now) && !candidate.isBefore(base)) {
      return candidate;
    }
  }
  throw StateError('Tidak dapat menghitung occurrence tahunan yang valid.');
}

/// Occurrence bulanan Hijriah berikutnya pada tanggal Hijriah yang sama dengan
/// [base] (tanggal Hijriah dihitung dari base menggunakan Umm Al-Qura default).
/// Jika tanggal Hijriah tidak ada pada bulan target (misal bulan pendek 29 hari),
/// digunakan hari terakhir bulan Hijriah tersebut.
DateTime nextHijriMonthlyOccurrenceAt(DateTime base, DateTime now) {
  // Gunakan UmmAlQuraCalendar default (tanpa overrides) untuk kalkulasi
  // deterministik. Kustomisasi pengguna (dayAdjustment, override) tidak
  // diperlukan di sini karena ini hanya untuk penjadwalan occurrence.
  final calendar = UmmAlQuraCalendar();

  // Konversi base ke Hijriah untuk mendapat tanggal Hijriah target
  final baseGreg = GregorianDate.fromDateTime(base);
  final baseHijri = calendar.toHijri(baseGreg).date;
  final targetHijriDay = baseHijri.day;

  final boundary = now.isAfter(base) ? now : base;

  // Cari bulan Hijriah dari boundary
  final boundaryGreg = GregorianDate.fromDateTime(boundary);
  final boundaryHijri = calendar.toHijri(boundaryGreg).date;

  // Iterasi hingga 36 bulan Hijriah ke depan
  for (var offset = 0; offset <= 36; offset++) {
    // Hitung bulan dan tahun Hijriah target
    var targetHijriMonth = boundaryHijri.month + offset;
    var targetHijriYear = boundaryHijri.year;
    while (targetHijriMonth > 12) {
      targetHijriMonth -= 12;
      targetHijriYear++;
    }

    // Clamp hari ke hari terakhir bulan Hijriah ini menggunakan daysInMonth
    final daysInHijriMonth = calendar.daysInMonth(
      targetHijriYear,
      targetHijriMonth,
    );
    final clampedDay =
        targetHijriDay > daysInHijriMonth ? daysInHijriMonth : targetHijriDay;

    // Konversi kembali ke Gregorian
    final targetHijri = HijriDate(targetHijriYear, targetHijriMonth, clampedDay);
    final targetGreg = calendar.toGregorian(targetHijri).date;

    final candidate = DateTime(
      targetGreg.year,
      targetGreg.month,
      targetGreg.day,
      base.hour,
      base.minute,
      base.second,
    );

    if (!candidate.isBefore(now) && !candidate.isBefore(base)) {
      return candidate;
    }
  }
  throw StateError(
    'Tidak dapat menghitung occurrence bulanan Hijriah yang valid.',
  );
}

class ReminderHistoryStatusUpdater {
  const ReminderHistoryStatusUpdater();

  bool canUndo(ReminderHistoryStatus status) =>
      status == ReminderHistoryStatus.completed;

  bool canComplete(ReminderHistoryStatus status) =>
      status == ReminderHistoryStatus.pending ||
      status == ReminderHistoryStatus.snoozed;
}
