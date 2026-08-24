enum ReminderRecurrenceType { once, daily, weekly }

extension ReminderRecurrenceTypeX on ReminderRecurrenceType {
  String get storageValue => switch (this) {
    ReminderRecurrenceType.once => 'once',
    ReminderRecurrenceType.daily => 'daily',
    ReminderRecurrenceType.weekly => 'weekly',
  };

  String get label => switch (this) {
    ReminderRecurrenceType.once => 'Sekali',
    ReminderRecurrenceType.daily => 'Setiap hari',
    ReminderRecurrenceType.weekly => 'Hari tertentu',
  };

  static ReminderRecurrenceType fromStorage(String value) => switch (value) {
    'daily' => ReminderRecurrenceType.daily,
    'weekly' => ReminderRecurrenceType.weekly,
    _ => ReminderRecurrenceType.once,
  };
}

enum ReminderHistoryStatus { pending, completed, missed, snoozed, cancelled }

extension ReminderHistoryStatusX on ReminderHistoryStatus {
  String get storageValue => switch (this) {
    ReminderHistoryStatus.pending => 'pending',
    ReminderHistoryStatus.completed => 'completed',
    ReminderHistoryStatus.missed => 'missed',
    ReminderHistoryStatus.snoozed => 'snoozed',
    ReminderHistoryStatus.cancelled => 'cancelled',
  };

  String get label => switch (this) {
    ReminderHistoryStatus.pending => 'Belum dilakukan',
    ReminderHistoryStatus.completed => 'Sudah dilakukan',
    ReminderHistoryStatus.missed => 'Terlewat',
    ReminderHistoryStatus.snoozed => 'Ditunda',
    ReminderHistoryStatus.cancelled => 'Dibatalkan',
  };

  static ReminderHistoryStatus fromStorage(String value) => switch (value) {
    'completed' => ReminderHistoryStatus.completed,
    'missed' => ReminderHistoryStatus.missed,
    'snoozed' => ReminderHistoryStatus.snoozed,
    'cancelled' => ReminderHistoryStatus.cancelled,
    _ => ReminderHistoryStatus.pending,
  };
}

class ReminderEntity {
  const ReminderEntity({
    required this.id,
    required this.householdId,
    required this.title,
    required this.scheduledAt,
    required this.recurrenceType,
    required this.weekdays,
    required this.notificationId,
    this.note,
    this.isActive = true,
    this.soundUri,
    this.soundName,
    this.defaultSnoozeMinutes = 10,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String householdId;
  final String title;
  final String? note;
  final DateTime scheduledAt;
  final ReminderRecurrenceType recurrenceType;
  final List<int> weekdays;
  final bool isActive;
  final String? soundUri;
  final String? soundName;
  final int defaultSnoozeMinutes;
  final int notificationId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class ReminderHistoryEntity {
  const ReminderHistoryEntity({
    required this.id,
    required this.reminderId,
    required this.householdId,
    required this.title,
    required this.occurrenceKey,
    required this.scheduledAt,
    required this.status,
    required this.notificationId,
    required this.createdAt,
    this.triggeredAt,
    this.completedAt,
    this.snoozedUntil,
    this.updatedAt,
  });

  final String id;
  final String reminderId;
  final String householdId;
  final String title;
  final String occurrenceKey;
  final DateTime scheduledAt;
  final DateTime? triggeredAt;
  final ReminderHistoryStatus status;
  final DateTime? completedAt;
  final DateTime? snoozedUntil;
  final int notificationId;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

class ReminderOccurrence {
  const ReminderOccurrence({
    required this.key,
    required this.scheduledAt,
    required this.notificationId,
  });

  final String key;
  final DateTime scheduledAt;
  final int notificationId;
}

int stableReminderNotificationId(String reminderId, String occurrenceKey) {
  var hash = 0x811c9dc5;
  for (final codeUnit in '$reminderId:$occurrenceKey'.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}
