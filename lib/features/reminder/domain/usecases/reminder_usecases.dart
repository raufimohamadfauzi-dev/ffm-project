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

class ReminderHistoryStatusUpdater {
  const ReminderHistoryStatusUpdater();

  bool canUndo(ReminderHistoryStatus status) =>
      status == ReminderHistoryStatus.completed;

  bool canComplete(ReminderHistoryStatus status) =>
      status == ReminderHistoryStatus.pending ||
      status == ReminderHistoryStatus.snoozed;
}
