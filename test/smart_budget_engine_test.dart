import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/advisor/domain/services/smart_budget_engine.dart';
import 'package:ffm_manager/features/advisor/domain/services/smart_envelope_rebalance.dart';
import 'package:ffm_manager/features/transaction/domain/usecases/transaction_crud_usecases.dart';

void main() {
  group('SmartBudgetEngine - Dynamic Category Baseline', () {
    const engine = SmartBudgetEngine();
    final now = DateTime(2026, 9, 15);

    test('3-Month Moving Average kalkulasi rata-rata per kategori', () {
      final txs = [
        // Bulan Agustus (Month -1)
        TransactionEntity(
          id: '1',
          householdId: 'local',
          owner: 'Pengguna',
          categoryId: 'Makanan & Minuman',
          amount: 3000000,
          date: DateTime(2026, 8, 10),
          recordedAt: DateTime(2026, 8, 10),
          source: 'expense',
        ),
        TransactionEntity(
          id: '2',
          householdId: 'local',
          owner: 'Pengguna',
          categoryId: 'Transportasi',
          amount: 1000000,
          date: DateTime(2026, 8, 12),
          recordedAt: DateTime(2026, 8, 12),
          source: 'expense',
        ),

        // Bulan Juli (Month -2)
        TransactionEntity(
          id: '3',
          householdId: 'local',
          owner: 'Pengguna',
          categoryId: 'Makanan & Minuman',
          amount: 2000000,
          date: DateTime(2026, 7, 20),
          recordedAt: DateTime(2026, 7, 20),
          source: 'expense',
        ),
        TransactionEntity(
          id: '4',
          householdId: 'local',
          owner: 'Pengguna',
          categoryId: 'Transportasi',
          amount: 800000,
          date: DateTime(2026, 7, 22),
          recordedAt: DateTime(2026, 7, 22),
          source: 'expense',
        ),

        // Bulan Juni (Month -3)
        TransactionEntity(
          id: '5',
          householdId: 'local',
          owner: 'Pengguna',
          categoryId: 'Makanan & Minuman',
          amount: 2500000,
          date: DateTime(2026, 6, 15),
          recordedAt: DateTime(2026, 6, 15),
          source: 'expense',
        ),
      ];

      final baselines = engine.calculateDynamicBaselines(transactions: txs, now: now);

      expect(baselines.length, equals(2));

      final foodBaseline = baselines.firstWhere((b) => b.categoryName == 'Makanan & Minuman');
      // Rata-rata Makanan: (3.000.000 + 2.000.000 + 2.500.000) / 3 bulan = 2.500.000
      expect(foodBaseline.averageMonthlyAmount, equals(2500000.0));
      expect(foodBaseline.dataPointMonths, equals(3));

      final transportBaseline = baselines.firstWhere((b) => b.categoryName == 'Transportasi');
      // Rata-rata Transportasi: (1.000.000 + 800.000) / 2 bulan = 900.000
      expect(transportBaseline.averageMonthlyAmount, equals(900000.0));
      expect(transportBaseline.dataPointMonths, equals(2));
    });

    test('Burn Rate Velocity & Batas Belanja Harian Aman', () {
      final currentMonthExpenses = [
        TransactionEntity(
          id: '1',
          householdId: 'local',
          owner: 'Pengguna',
          categoryId: 'Makanan & Minuman',
          amount: 1500000,
          date: DateTime(2026, 9, 5),
          recordedAt: DateTime(2026, 9, 5),
          source: 'expense',
        ),
        TransactionEntity(
          id: '2',
          householdId: 'local',
          owner: 'Pengguna',
          categoryId: 'Belanja',
          amount: 1000000,
          date: DateTime(2026, 9, 10),
          recordedAt: DateTime(2026, 9, 10),
          source: 'expense',
        ),
      ];

      // Total spent = 2.500.000 di hari ke-15 dari 30 hari
      final analysis = engine.calculateBurnRate(
        currentMonthExpenses: currentMonthExpenses,
        monthlyBudgetLimit: 3000000, // Budget 3 juta
        now: now,
      );

      expect(analysis.totalExpenseSoFar, equals(2500000.0));
      expect(analysis.daysElapsed, equals(15));
      expect(analysis.remainingDays, equals(15));
      expect(analysis.dailyAverageExpense, equals(2500000 / 15)); // ~166.666/hari
      expect(analysis.projectedMonthlyExpense, equals(5000000.0)); // Proyeksi 5 juta (Jebol)
      expect(analysis.isOnTrack, isFalse);

      // Sisa anggaran = 3.000.000 - 2.500.000 = 500.000 untuk 15 hari
      expect(analysis.safeDailySpendingLimit, equals(5000000 / 150)); // ~33.333/hari
    });
  });

  group('SmartEnvelopeRebalance', () {
    const rebalancer = SmartEnvelopeRebalance();

    test('deteksi peluang rebalance dari pos melimpah ke pos menipis', () {
      const statuses = [
        CategoryBudgetStatus(
          categoryName: 'Makanan & Minuman',
          budgetLimit: 2000000,
          spentAmount: 1800000, // 90% terpakai (Menipis)
        ),
        CategoryBudgetStatus(
          categoryName: 'Hiburan',
          budgetLimit: 1000000,
          spentAmount: 200000, // 20% terpakai (Melimpah, sisa 800.000)
        ),
        CategoryBudgetStatus(
          categoryName: 'Transportasi',
          budgetLimit: 800000,
          spentAmount: 400000, // 50% terpakai (Normal)
        ),
      ];

      final proposals = rebalancer.analyzeRebalanceOpportunities(
        categoryStatuses: statuses,
      );

      expect(proposals.length, equals(1));
      final proposal = proposals.first;

      expect(proposal.targetCategory, equals('Makanan & Minuman'));
      expect(proposal.sourceCategory, equals('Hiburan'));
      expect(proposal.suggestedAmount, greaterThan(0));
    });
  });
}
