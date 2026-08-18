class LiabilityEntity {
  const LiabilityEntity({
    required this.id,
    required this.householdId,
    required this.name,
    required this.originalAmount,
    required this.remainingBalance,
    required this.monthlyInstallment,
    this.interestRate,
    required this.startDate,
    required this.dueDate,
    required this.updatedAt,
    this.note,
  });

  final String id;
  final String householdId;
  final String name;
  final int originalAmount;
  final int remainingBalance;
  final int monthlyInstallment;
  final double? interestRate;
  final DateTime startDate;
  final DateTime dueDate;
  final DateTime updatedAt;
  final String? note;
}
