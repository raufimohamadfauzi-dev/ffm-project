class GoalEntity {
  const GoalEntity({
    required this.id,
    required this.householdId,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    required this.targetDate,
    this.categoryId,
    this.note,
    this.isActive = true,
    this.createdAt,
  });

  final String id;
  final String householdId;
  final String name;
  final int targetAmount;
  final int currentAmount;
  final DateTime targetDate;
  final String? categoryId;
  final String? note;
  final bool isActive;
  final DateTime? createdAt;
}
