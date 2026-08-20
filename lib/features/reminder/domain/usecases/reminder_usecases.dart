import '../entities/reminder_entity.dart';

class ReminderOccurrenceCalculator {
  const ReminderOccurrenceCalculator();

  ReminderOccurrence? nextOccurrence(ReminderEntity reminder, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final base = reminder.scheduledAt.toLocal();
    final candidate = switch (reminder.recurrenceType) {
      ReminderRecurrenceType.once => _nextOnce(base, current),
      ReminderRecurrenceType.daily => _nextDaily(base, current),
      ReminderRecurrenceType.weekly => _nextWeekly(
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

  String occurrenceKey(DateTime dateTime) {
    final value = dateTime.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}-'
        '${two(value.hour)}${two(value.minute)}';
  }

  DateTime? _nextOnce(DateTime base, DateTime now) {
    return base.isAfter(now) ? base : null;
  }

  DateTime _nextDaily(DateTime base, DateTime now) {
    var candidate = DateTime(
      now.year,
      now.month,
      now.day,
      base.hour,
      base.minute,
      base.second,
    );
    if (candidate.isBefore(now) || candidate.isBefore(base)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  DateTime _nextWeekly(
    DateTime base,
    DateTime now,
    List<int> configuredWeekdays,
  ) {
    final weekdays =
        configuredWeekdays.isEmpty
              ? <int>[base.weekday]
              : configuredWeekdays
                    .toSet()
                    .where((day) => day >= 1 && day <= 7)
                    .toList()
          ..sort();
    for (var offset = 0; offset <= 7; offset++) {
      final day = now.add(Duration(days: offset));
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
    return DateTime(
      now.year,
      now.month,
      now.day + 7,
      base.hour,
      base.minute,
      base.second,
    );
  }
}

int stableReminderNotificationId(String reminderId, String occurrenceKey) {
  var hash = 2166136261;
  for (final codeUnit in '$reminderId:$occurrenceKey'.codeUnits) {
    hash = (hash ^ codeUnit) * 16777619;
    hash &= 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}

class ReminderHistoryStatusUpdater {
  const ReminderHistoryStatusUpdater();

  bool canUndo(ReminderHistoryStatus status) =>
      status == ReminderHistoryStatus.completed;

  bool canComplete(ReminderHistoryStatus status) =>
      status == ReminderHistoryStatus.pending ||
      status == ReminderHistoryStatus.snoozed;
}
