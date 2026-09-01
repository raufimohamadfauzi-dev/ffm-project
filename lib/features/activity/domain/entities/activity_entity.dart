enum ActivitySessionStatus {
  active,
  completed,
  cancelled;

  String get value => name;

  static ActivitySessionStatus fromValue(String? value) => values.firstWhere(
    (item) => item.name == value,
    orElse: () => ActivitySessionStatus.active,
  );
}

enum ActivityKind {
  timer,
  task,
  note,
  event;

  String get value => name;

  static ActivityKind fromValue(String? value) => values.firstWhere(
    (item) => item.name == value,
    orElse: () => ActivityKind.timer,
  );
}

/// Mode aktivitas utama untuk membedakan time tracking vs catatan/riwayat
enum ActivityMode {
  /// Time tracking: aktivitas dengan durasi yang dihitung
  /// (timer, task yang sedang berjalan)
  timeTracking,

  /// Catatan/riwayat: kejadian satu kali atau log singkat
  /// (note, event, task yang sudah selesai tanpa durasi penting)
  history;

  String get value => name;

  String get label => switch (this) {
    ActivityMode.timeTracking => 'Pakai timer',
    ActivityMode.history => 'Catat saja',
  };

  ActivityKind get activityKind => switch (this) {
    ActivityMode.timeTracking => ActivityKind.timer,
    ActivityMode.history => ActivityKind.note,
  };

  static ActivityMode? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    return switch (normalized) {
      'timetracking' ||
      'time_tracking' ||
      'time-tracking' ||
      'timer' ||
      'timed' => ActivityMode.timeTracking,
      'history' ||
      'record' ||
      'riwayat' ||
      'note' ||
      'catatan' => ActivityMode.history,
      _ => null,
    };
  }

  static ActivityMode fromValue(String? value) =>
      tryParse(value) ?? ActivityMode.timeTracking;

  /// Mendapatkan mode default untuk ActivityKind tertentu
  static ActivityMode defaultForKind(ActivityKind kind) {
    switch (kind) {
      case ActivityKind.timer:
        return ActivityMode.timeTracking;
      case ActivityKind.task:
        return ActivityMode
            .timeTracking; // Task default ke time tracking, bisa berubah
      case ActivityKind.note:
        return ActivityMode.history;
      case ActivityKind.event:
        return ActivityMode.history;
    }
  }

  /// Mendapatkan ActivityKind yang direkomendasikan untuk mode
  static List<ActivityKind> recommendedKindsForMode(ActivityMode mode) {
    switch (mode) {
      case ActivityMode.timeTracking:
        return [ActivityKind.timer, ActivityKind.task];
      case ActivityMode.history:
        return [ActivityKind.note, ActivityKind.event];
    }
  }
}

extension ActivityKindMode on ActivityKind {
  ActivityMode get activityMode => ActivityMode.defaultForKind(this);
}

class ActivitySessionEntity {
  const ActivitySessionEntity({
    required this.id,
    required this.householdId,
    required this.title,
    required this.category,
    this.categoryId,
    this.kind = ActivityKind.timer,
    this.parentSessionId,
    required this.startedAt,
    required this.status,
    required this.createdAt,
    this.endedAt,
    this.scheduledAt,
    this.dueDate,
    this.isAllDay = false,
    this.isCompleted = false,
    this.priority = 0,
    this.notes,
    this.isArchived = false,
    this.updatedAt,
    // Activity Intelligence Upgrade fields
    this.activityGroupId,
    this.subjectType,
    this.subjectId,
  });

  final String id;
  final String householdId;
  final String title;
  final String category;

  /// ID Categories bertipe activity; nullable untuk data legacy.
  final String? categoryId;
  final ActivityKind kind;
  final String? parentSessionId;

  /// Activity Intelligence Upgrade - Grouping & Subject Linking
  /// activityGroupId: Mengelompokkan aktivitas dalam satu rangkaian/proses
  /// subjectType: Jenis entitas yang sedang dikerjakan (crop, asset, dll)
  /// subjectId: ID spesifik entitas yang sedang dikerjakan
  final String? activityGroupId;
  final String? subjectType;
  final String? subjectId;

  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime? scheduledAt;
  final DateTime? dueDate;
  final bool isAllDay;
  final bool isCompleted;
  final int priority;
  final ActivitySessionStatus status;
  final String? notes;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Mendapatkan mode aktual (hitung dari kind/status)
  ActivityMode get effectiveMode {
    return ActivityMode.defaultForKind(kind);
  }

  /// Apakah ini mode time tracking?
  bool get isTimeTracking => effectiveMode == ActivityMode.timeTracking;

  /// Apakah ini mode catatan/riwayat?
  bool get isHistory => effectiveMode == ActivityMode.history;

  ActivitySessionEntity copyWith({
    String? title,
    String? category,
    String? categoryId,
    ActivityKind? kind,
    DateTime? endedAt,
    DateTime? scheduledAt,
    DateTime? dueDate,
    bool? isAllDay,
    bool? isCompleted,
    int? priority,
    ActivitySessionStatus? status,
    String? notes,
    bool? isArchived,
    DateTime? updatedAt,
    // Activity Intelligence Upgrade fields
    String? activityGroupId,
    String? subjectType,
    String? subjectId,
  }) => ActivitySessionEntity(
    id: id,
    householdId: householdId,
    title: title ?? this.title,
    category: category ?? this.category,
    categoryId: categoryId ?? this.categoryId,
    kind: kind ?? this.kind,
    parentSessionId: parentSessionId,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    dueDate: dueDate ?? this.dueDate,
    isAllDay: isAllDay ?? this.isAllDay,
    isCompleted: isCompleted ?? this.isCompleted,
    priority: priority ?? this.priority,
    status: status ?? this.status,
    notes: notes ?? this.notes,
    isArchived: isArchived ?? this.isArchived,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    activityGroupId: activityGroupId ?? this.activityGroupId,
    subjectType: subjectType ?? this.subjectType,
    subjectId: subjectId ?? this.subjectId,
  );

  Duration durationAt([DateTime? now]) {
    final end = endedAt ?? now ?? DateTime.now();
    final duration = end.difference(startedAt);
    return duration.isNegative ? Duration.zero : duration;
  }
}

class ActivityCheckpointEntity {
  const ActivityCheckpointEntity({
    required this.id,
    required this.sessionId,
    required this.label,
    required this.occurredAt,
    required this.sequence,
    required this.createdAt,
    this.place,
    this.note,
  });

  final String id;
  final String sessionId;
  final String label;
  final String? place;
  final DateTime occurredAt;
  final int sequence;
  final String? note;
  final DateTime createdAt;
}

class ActivityJournalEntryEntity {
  const ActivityJournalEntryEntity({
    required this.id,
    required this.householdId,
    required this.activityType,
    required this.title,
    required this.startedAt,
    required this.createdAt,
    this.sessionId,
    this.participants,
    this.topic,
    this.place,
    this.endedAt,
    this.notes,
    this.followUp,
    this.isArchived = false,
    this.updatedAt,
  });

  final String id;
  final String? sessionId;
  final String householdId;
  final String activityType;
  final String title;
  final String? participants;
  final String? topic;
  final String? place;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? notes;
  final String? followUp;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Duration durationAt([DateTime? now]) {
    final end = endedAt ?? now ?? DateTime.now();
    final duration = end.difference(startedAt);
    return duration.isNegative ? Duration.zero : duration;
  }
}

enum ActivityEntrySource {
  manual,
  voice,
  assistant,
  system;

  String get value => name;

  static ActivityEntrySource fromValue(String? value) => values.firstWhere(
    (item) => item.name == value,
    orElse: () => ActivityEntrySource.manual,
  );
}

class ActivityNoteEntity {
  const ActivityNoteEntity({
    required this.id,
    required this.householdId,
    required this.text,
    required this.category,
    this.numericValue,
    this.unit,
    this.latitude,
    this.longitude,
    required this.createdAt,
    this.linkedSessionId,
    this.source = ActivityEntrySource.manual,
    this.isArchived = false,
    this.updatedAt,
  });

  final String id;
  final String householdId;
  final String text;
  final String category;
  final double? numericValue;
  final String? unit;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;
  final String? linkedSessionId;
  final ActivityEntrySource source;
  final bool isArchived;
  final DateTime? updatedAt;
}

class ActivityLiveSnapshot {
  ActivityLiveSnapshot({
    required this.activeSessions,
    this.checkpoints = const {},
    this.notes = const [],
    this.revision = 0,
    DateTime? lastUpdatedAt,
  }) : lastUpdatedAt = lastUpdatedAt ?? DateTime.now();

  final List<ActivitySessionEntity> activeSessions;
  final Map<String, List<ActivityCheckpointEntity>> checkpoints;
  final List<ActivityNoteEntity> notes;
  final int revision;
  final DateTime lastUpdatedAt;

  bool get hasActiveSessions => activeSessions.isNotEmpty;

  ActivitySessionEntity? get rootSession {
    for (final session in activeSessions) {
      if (session.parentSessionId == null) return session;
    }
    return activeSessions.firstOrNull;
  }

  List<ActivitySessionEntity> get childSessions => activeSessions
      .where((s) => s.parentSessionId != null)
      .toList(growable: false);

  List<ActivitySessionEntity> childrenOf(String parentId) => activeSessions
      .where((s) => s.parentSessionId == parentId)
      .toList(growable: false);

  ActivityCheckpointEntity? lastCheckpointFor(String sessionId) {
    final list = checkpoints[sessionId];
    if (list == null || list.isEmpty) return null;
    return list.last;
  }
}

class ActivityDurationCalculator {
  const ActivityDurationCalculator();

  Duration between(DateTime start, DateTime end) {
    final duration = end.difference(start);
    return duration.isNegative ? Duration.zero : duration;
  }

  String format(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}j';
    return '${hours}j ${minutes}m';
  }
}
