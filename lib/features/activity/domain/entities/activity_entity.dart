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

class ActivitySessionEntity {
  const ActivitySessionEntity({
    required this.id,
    required this.householdId,
    required this.title,
    required this.category,
    this.parentSessionId,
    required this.startedAt,
    required this.status,
    required this.createdAt,
    this.endedAt,
    this.notes,
    this.isArchived = false,
    this.updatedAt,
  });

  final String id;
  final String householdId;
  final String title;
  final String category;
  final String? parentSessionId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final ActivitySessionStatus status;
  final String? notes;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime? updatedAt;

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
