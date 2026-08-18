enum FinancialHealthStatus { excellent, good, fair, warning, critical }

class FinancialHealthInput {
  const FinancialHealthInput({
    required this.totalIncome,
    required this.totalExpenses,
    required this.totalMonthlyInstallments,
    required this.emergencyFundAmount,
    required this.averageMonthlyExpenses,
  });

  final int totalIncome;
  final int totalExpenses;
  final int totalMonthlyInstallments;
  final int emergencyFundAmount;
  final int averageMonthlyExpenses;
}

class FinancialHealthScore {
  const FinancialHealthScore({
    required this.totalScore,
    required this.status,
    required this.cashflow,
    required this.expenseRatio,
  });

  final int totalScore;
  final FinancialHealthStatus status;
  final int cashflow;
  final double expenseRatio;
}

class FinancialHealthCalculator {
  const FinancialHealthCalculator();

  FinancialHealthScore calculate(FinancialHealthInput input) {
    final cashflow = input.totalIncome - input.totalExpenses;
    final expenseRatio = input.totalIncome <= 0
        ? (input.totalExpenses > 0 ? 1.0 : 0.0)
        : input.totalExpenses / input.totalIncome;
    var score = 50;
    if (input.totalIncome > 0) {
      score += cashflow >= 0 ? 20 : -25;
      if (expenseRatio <= .7) score += 15;
      if (expenseRatio > .95) score -= 15;
    }
    if (input.totalMonthlyInstallments > 0 && input.totalIncome > 0) {
      final installmentRatio = input.totalMonthlyInstallments / input.totalIncome;
      if (installmentRatio <= .3) score += 10;
      if (installmentRatio > .5) score -= 15;
    }
    if (input.averageMonthlyExpenses > 0 && input.emergencyFundAmount >= input.averageMonthlyExpenses * 3) {
      score += 10;
    } else if (input.averageMonthlyExpenses > 0 && input.emergencyFundAmount < input.averageMonthlyExpenses) {
      score -= 5;
    }
    score = score.clamp(0, 100).toInt();
    final status = switch (score) {
      >= 80 => FinancialHealthStatus.excellent,
      >= 65 => FinancialHealthStatus.good,
      >= 50 => FinancialHealthStatus.fair,
      >= 30 => FinancialHealthStatus.warning,
      _ => FinancialHealthStatus.critical,
    };
    return FinancialHealthScore(
      totalScore: score,
      status: status,
      cashflow: cashflow,
      expenseRatio: expenseRatio,
    );
  }
}
