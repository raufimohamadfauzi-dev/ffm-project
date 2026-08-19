import '../../../../core/database/app_database.dart';
import '../../../transaction/domain/entities/transaction_entity.dart';

class ForecastPoint {
  const ForecastPoint({required this.month, required this.balance});
  final DateTime month;
  final int balance;
}

class WeeklyDigest {
  const WeeklyDigest({
    required this.expense,
    required this.income,
    required this.transactionCount,
  });
  final int expense;
  final int income;
  final int transactionCount;
}

abstract final class FinancialAnalysis {
  static List<ForecastPoint> forecast(
    List<TransactionWithItems> transactions, {
    required DateTime fromMonth,
    List<RecurringTransaction> recurring = const [],
  }) {
    final monthly = <DateTime, int>{};
    for (final item in transactions) {
      final date = item.transaction.date;
      final month = DateTime(date.year, date.month);
      monthly[month] = (monthly[month] ?? 0) + item.transaction.amount;
    }
    if (monthly.isEmpty) return const [];
    final values = monthly.values.toList();
    final average =
        (values.fold<int>(0, (sum, value) => sum + value) / values.length)
            .round();
    final next = DateTime(fromMonth.year, fromMonth.month + 1);
    return [ForecastPoint(month: next, balance: average)];
  }

  static WeeklyDigest weeklyDigest(
    List<TransactionWithItems> transactions, {
    required DateTime weekContaining,
  }) {
    final start = DateTime(
      weekContaining.year,
      weekContaining.month,
      weekContaining.day,
    ).subtract(Duration(days: weekContaining.weekday - 1));
    final end = start.add(const Duration(days: 7));
    var expense = 0;
    var income = 0;
    var count = 0;
    for (final item in transactions) {
      final date = item.transaction.date;
      if (date.isBefore(start) || !date.isBefore(end)) continue;
      count++;
      if (item.transaction.amount < 0) {
        expense += item.transaction.amount.abs();
      } else {
        income += item.transaction.amount;
      }
    }
    return WeeklyDigest(
      expense: expense,
      income: income,
      transactionCount: count,
    );
  }
}
