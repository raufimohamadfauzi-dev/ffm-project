enum ReminderRecurrenceType { once, daily, weekly, monthly, yearly, hijriMonthly }

enum ReminderOrigin { user, autonomous }

enum ReminderMode { notification, alarm }

extension ReminderModeX on ReminderMode {
  String get storageValue => switch (this) {
    ReminderMode.notification => 'notification',
    ReminderMode.alarm => 'alarm',
  };

  String get label => switch (this) {
    ReminderMode.notification => 'Notifikasi Biasa',
    ReminderMode.alarm => 'Alarm Nyaring',
  };

  static ReminderMode fromStorage(String? value) =>
      value == 'alarm' ? ReminderMode.alarm : ReminderMode.notification;
}

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
enum ReminderSourceType {
  liability,
  receivable,
  goal,
  recurringTransaction,
  activity,
  task,
  familyProfile,
  telegram,
  diagnostics,
  accountSetup,
  goalSetup,
  budgetSetup,
  cashFlowProfile,
  cloudSetup,
  assistantLog,
}

extension ReminderSourceTypeX on ReminderSourceType {
  String get storageValue => switch (this) {
    ReminderSourceType.liability => 'liability',
    ReminderSourceType.receivable => 'receivable',
    ReminderSourceType.goal => 'goal',
    ReminderSourceType.recurringTransaction => 'recurring_transaction',
    ReminderSourceType.activity => 'activity',
    ReminderSourceType.task => 'task',
    ReminderSourceType.familyProfile => 'family_profile',
    ReminderSourceType.telegram => 'telegram',
    ReminderSourceType.diagnostics => 'diagnostics',
    ReminderSourceType.accountSetup => 'account_setup',
    ReminderSourceType.goalSetup => 'goal_setup',
    ReminderSourceType.budgetSetup => 'budget_setup',
    ReminderSourceType.cashFlowProfile => 'cash_flow_profile',
    ReminderSourceType.cloudSetup => 'cloud_setup',
    ReminderSourceType.assistantLog => 'assistant_log',
  };

  String get label => switch (this) {
    ReminderSourceType.liability => 'Hutang',
    ReminderSourceType.receivable => 'Piutang',
    ReminderSourceType.goal => 'Target',
    ReminderSourceType.recurringTransaction => 'Transaksi Rutin',
    ReminderSourceType.activity => 'Aktivitas',
    ReminderSourceType.task => 'Tugas',
    ReminderSourceType.familyProfile => 'Profil Keluarga',
    ReminderSourceType.telegram => 'Telegram',
    ReminderSourceType.diagnostics => 'Diagnostik',
    ReminderSourceType.accountSetup => 'Rekening',
    ReminderSourceType.goalSetup => 'Setup Target',
    ReminderSourceType.budgetSetup => 'Setup Anggaran',
    ReminderSourceType.cashFlowProfile => 'Arus Kas',
    ReminderSourceType.cloudSetup => 'Koneksi Cloud',
    ReminderSourceType.assistantLog => 'Asisten',
  };

  static ReminderSourceType? fromStorage(String? value) => switch (value) {
    'liability' => ReminderSourceType.liability,
    'receivable' => ReminderSourceType.receivable,
    'goal' => ReminderSourceType.goal,
    'recurring_transaction' => ReminderSourceType.recurringTransaction,
    'activity' => ReminderSourceType.activity,
    'task' => ReminderSourceType.task,
    'family_profile' => ReminderSourceType.familyProfile,
    'telegram' => ReminderSourceType.telegram,
    'diagnostics' => ReminderSourceType.diagnostics,
    'account_setup' => ReminderSourceType.accountSetup,
    'goal_setup' => ReminderSourceType.goalSetup,
    'budget_setup' => ReminderSourceType.budgetSetup,
    'cash_flow_profile' => ReminderSourceType.cashFlowProfile,
    'cloud_setup' => ReminderSourceType.cloudSetup,
    'assistant_log' => ReminderSourceType.assistantLog,
    _ => null,
  };
}

extension ReminderRecurrenceTypeX on ReminderRecurrenceType {
  String get storageValue => switch (this) {
    ReminderRecurrenceType.once => 'once',
    ReminderRecurrenceType.daily => 'daily',
    ReminderRecurrenceType.weekly => 'weekly',
    ReminderRecurrenceType.monthly => 'monthly',
    ReminderRecurrenceType.yearly => 'yearly',
    ReminderRecurrenceType.hijriMonthly => 'hijri_monthly',
  };

  String get label => switch (this) {
    ReminderRecurrenceType.once => 'Sekali',
    ReminderRecurrenceType.daily => 'Setiap hari',
    ReminderRecurrenceType.weekly => 'Hari tertentu',
    ReminderRecurrenceType.monthly => 'Bulanan',
    ReminderRecurrenceType.yearly => 'Tahunan',
    ReminderRecurrenceType.hijriMonthly => 'Bulanan Hijriah',
  };

  static ReminderRecurrenceType fromStorage(String value) => switch (value) {
    'daily' => ReminderRecurrenceType.daily,
    'weekly' => ReminderRecurrenceType.weekly,
    'monthly' => ReminderRecurrenceType.monthly,
    'yearly' => ReminderRecurrenceType.yearly,
    'hijri_monthly' => ReminderRecurrenceType.hijriMonthly,
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
    this.mode = ReminderMode.notification,
    this.destinationRoute,
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
  final ReminderMode mode;
  final String? destinationRoute;
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
