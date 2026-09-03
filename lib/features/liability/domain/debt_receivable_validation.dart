enum DebtReceivableDueStatus {
  paid,
  overdue,
  dueWithinWeek,
  dueWithinMonth,
  dueBeyondMonth,
  active,
}

DebtReceivableDueStatus classifyDebtReceivableDue({
  required int remainingBalance,
  required DateTime dueDate,
  required DateTime today,
}) {
  if (remainingBalance <= 0) return DebtReceivableDueStatus.paid;
  final day = DateTime(today.year, today.month, today.day);
  final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
  if (dueDay.isBefore(day)) return DebtReceivableDueStatus.overdue;
  final daysUntilDue = dueDay.difference(day).inDays;
  if (daysUntilDue <= 7) return DebtReceivableDueStatus.dueWithinWeek;
  if (daysUntilDue <= 30) return DebtReceivableDueStatus.dueWithinMonth;
  return DebtReceivableDueStatus.dueBeyondMonth;
}

String debtReceivableDueStatusLabel(DebtReceivableDueStatus status) {
  return switch (status) {
    DebtReceivableDueStatus.paid => 'Lunas',
    DebtReceivableDueStatus.overdue => 'Terlambat',
    DebtReceivableDueStatus.dueWithinWeek => 'Jatuh tempo 0-7 hari',
    DebtReceivableDueStatus.dueWithinMonth => 'Jatuh tempo 8-30 hari',
    DebtReceivableDueStatus.dueBeyondMonth => 'Lebih dari 30 hari',
    DebtReceivableDueStatus.active => 'Aktif',
  };
}

String? validateDebtReceivableAmounts({
  required int originalAmount,
  required int remainingBalance,
  required int monthlyInstallment,
  double? interestRate,
}) {
  if (originalAmount <= 0) return 'Nominal awal harus lebih besar dari nol.';
  if (remainingBalance < 0) return 'Sisa saldo tidak boleh negatif.';
  if (remainingBalance > originalAmount) {
    return 'Sisa saldo tidak boleh melebihi nominal awal.';
  }
  // Cicilan nol diperbolehkan untuk hutang/piutang sekali bayar (lump-sum)
  if (monthlyInstallment < 0) {
    return 'Nominal pembayaran tidak boleh negatif.';
  }
  if (interestRate != null && interestRate < 0) {
    return 'Bunga tidak boleh negatif.';
  }
  return null;
}

String? validateDebtReceivableDates({
  required DateTime startDate,
  required DateTime dueDate,
}) {
  final startDay = DateTime(startDate.year, startDate.month, startDate.day);
  final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
  if (dueDay.isBefore(startDay)) {
    return 'Tanggal jatuh tempo tidak boleh sebelum tanggal mulai.';
  }
  return null;
}

String? validateDebtPaymentAmount({
  required int paymentAmount,
  required int remainingBalance,
}) {
  if (paymentAmount <= 0) {
    return 'Nominal pembayaran harus lebih besar dari nol.';
  }
  if (paymentAmount > remainingBalance) {
    return 'Nominal pembayaran tidak boleh melebihi sisa saldo ($remainingBalance).';
  }
  return null;
}
