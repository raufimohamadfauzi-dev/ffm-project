enum ReminderRecurrenceType { once, daily, weekly }

enum ReminderOrigin { user, autonomous }

extension ReminderOriginX on ReminderOrigin {
  String get storageValue => switch (this) {
    ReminderOrigin.user => 'user',
    ReminderOrigin.autonomous => 'autonomous',
  };

  String get label => switch (this) {
    ReminderOrigin.user => 'Dibuat pengguna',
    ReminderOrigin.autonomous => 'Dibuat otonom',
  };

  static ReminderOrigin fromStorage(String? value) =>
      value == 'autonomous' ? ReminderOrigin.autonomous : ReminderOrigin.user;
}

/// Jenis entitas keuangan yang dapat menjadi asal sebuah pengingat.
/// Nilainya dibatasi agar pengingat tidak menyimpan nama tabel atau tipe objek
/// arbitrer dari input pengguna maupun model.
enum ReminderSourceType { liability, receivable, goal, recurringTransaction }

extension ReminderSourceTypeX on ReminderSourceType {
  String get storageValue => switch (this) {
    ReminderSourceType.liability => 'liability',
    ReminderSourceType.receivable => 'receivable',
    ReminderSourceType.goal => 'goal',
    ReminderSourceType.recurringTransaction => 'recurring_transaction',
  };

  String get label => switch (this) {
    ReminderSourceType.liability => 'hutang',
    ReminderSourceType.receivable => 'piutang',
    ReminderSourceType.goal => 'target keuangan',
    ReminderSourceType.recurringTransaction => 'jadwal transaksi rutin',
  };

  static ReminderSourceType? fromStorage(String? value) => switch (value) {
    'liability' => ReminderSourceType.liability,
    'receivable' => ReminderSourceType.receivable,
    'goal' => ReminderSourceType.goal,
    'recurring_transaction' => ReminderSourceType.recurringTransaction,
    _ => null,
  };
}

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
    this.sourceType,
    this.sourceId,
    this.origin = ReminderOrigin.user,
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

  /// Keduanya harus diisi bersamaan oleh repository agar asal pengingat dapat
  /// diverifikasi kembali sebelum asisten memberi saran tindakan.
  final ReminderSourceType? sourceType;
  final String? sourceId;
  final ReminderOrigin origin;
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

int stableSnoozeNotificationId(String reminderId, String occurrenceKey) =>
    stableReminderNotificationId(reminderId, 'snooze:$occurrenceKey');
