class DailyNoteEntity {
  const DailyNoteEntity({
    required this.id,
    required this.householdId,
    required this.noteDate,
    required this.body,
    required this.isArchived,
    required this.createdAt,
    this.title,
    this.updatedAt,
  });

  final String id;
  final String householdId;
  final DateTime noteDate;
  final String? title;
  final String body;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime? updatedAt;
}
