enum TaskStatus { open, completed }

class TaskEntity {
  const TaskEntity({
    required this.id,
    required this.householdId,
    required this.title,
    required this.status,
    required this.isArchived,
    required this.createdAt,
    this.note,
    this.dueDate,
    this.completedAt,
    this.updatedAt,
  });

  final String id;
  final String householdId;
  final String title;
  final String? note;
  final DateTime? dueDate;
  final TaskStatus status;
  final DateTime? completedAt;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get isCompleted => status == TaskStatus.completed;
}
