/// Definisi kebiasaan berulang yang terpisah dari Tugas, Catatan Harian,
/// Aktivitas bertimer, dan Jadwal kalender.
class RoutineEntity {
  const RoutineEntity({
    required this.id,
    required this.householdId,
    required this.title,
    required this.weekdays,
    required this.isActive,
    required this.isArchived,
    required this.createdAt,
    this.note,
    this.updatedAt,
  });

  final String id;
  final String householdId;
  final String title;
  final String? note;
  final List<int> weekdays;
  final bool isActive;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool runsOn(DateTime day) =>
      weekdays.isEmpty || weekdays.contains(day.weekday);
}

/// Bukti pelaksanaan satu [RoutineEntity] pada satu tanggal lokal.
class RoutineCompletionEntity {
  const RoutineCompletionEntity({
    required this.id,
    required this.routineId,
    required this.householdId,
    required this.routineDate,
    required this.completedAt,
    required this.createdAt,
    this.note,
  });

  final String id;
  final String routineId;
  final String householdId;
  final DateTime routineDate;
  final DateTime completedAt;
  final String? note;
  final DateTime createdAt;
}
