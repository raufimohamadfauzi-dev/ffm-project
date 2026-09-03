import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/advisor/domain/usecases/financial_health_calculator.dart';
import 'package:ffm_manager/features/asset/domain/entities/asset_entity.dart';
import 'package:ffm_manager/features/backup/data/pdf_report_service.dart';
import 'package:ffm_manager/features/goal/domain/entities/goal_entity.dart';
import 'package:ffm_manager/features/liability/domain/entities/liability_entity.dart';
import 'package:ffm_manager/features/receivable/domain/entities/receivable_entity.dart';
import 'package:ffm_manager/features/transaction/domain/entities/transaction_entity.dart';

void main() {
  group('PdfReportService tests', () {
    const service = PdfReportService();

    test('buildMonthlyReport menghasilkan dokumen PDF lengkap tanpa error', () async {
      final now = DateTime(2026, 9, 3);
      final score = const FinancialHealthScore(
        totalScore: 85,
        status: FinancialHealthStatus.good,
        cashflow: 5000000,
        expenseRatio: 0.5,
      );

      final dummyTx = [
        TransactionWithItems(
          transaction: Transaction(
            id: 'tx-1',
            householdId: 'house-1',
            type: 'income',
            categoryId: 'cat-inc',
            amount: 10000000,
            date: now,
            recordedAt: now,
            createdAt: now,
            isArchived: false,
            isDeleted: false,
          ),
        ),
        TransactionWithItems(
          transaction: Transaction(
            id: 'tx-2',
            householdId: 'house-1',
            type: 'expense',
            categoryId: 'cat-exp',
            amount: -3000000,
            date: now,
            recordedAt: now,
            createdAt: now,
            isArchived: false,
            isDeleted: false,
          ),
        ),
      ];

      final dummyAssets = [
        AssetEntity(
          id: 'asset-1',
          name: 'Tabungan Bank',
          assetType: 'cash',
          value: 15000000,
          placement: 'Bank Mandiri',
          createdAt: now,
          householdId: 'house-1',
        ),
      ];

      final dummyLiabilities = [
        LiabilityEntity(
          id: 'liab-1',
          name: 'KPR',
          originalAmount: 100000000,
          remainingBalance: 80000000,
          monthlyInstallment: 2000000,
          startDate: now.subtract(const Duration(days: 365)),
          dueDate: now.add(const Duration(days: 10)),
          updatedAt: now,
          householdId: 'house-1',
        ),
      ];

      final dummyReceivables = [
        ReceivableEntity(
          id: 'rec-1',
          name: 'Pinjaman Budi',
          originalAmount: 1000000,
          remainingBalance: 500000,
          monthlyInstallment: 500000,
          startDate: now,
          dueDate: now.add(const Duration(days: 5)),
          updatedAt: now,
          householdId: 'house-1',
        ),
      ];

      final dummyGoals = [
        GoalEntity(
          id: 'goal-1',
          name: 'Dana Darurat',
          targetAmount: 20000000,
          currentAmount: 10000000,
          targetDate: now.add(const Duration(days: 100)),
          householdId: 'house-1',
        ),
      ];

      final dummyBudgets = [
        EnvelopeBudget(
          id: 'budget-1',
          householdId: 'house-1',
          categoryId: 'cat-exp',
          name: 'Belanja Bulanan',
          allocated: 4000000,
          rollover: 0,
          periodType: 'monthly',
          startDate: now,
          endDate: now.add(const Duration(days: 30)),
          alertPercent: 80,
          isActive: true,
          createdAt: now,
          categoryIdsJson: '[]',
        ),
      ];

      final dummyActivities = [
        ActivityEntry(
          id: 'act-1',
          householdId: 'house-1',
          activityType: 'tani',
          title: 'Perawatan Lahan Padi',
          startedAt: now,
          notes: 'Pupuk dan pembersihan rumput',
          isArchived: false,
          createdAt: now,
        ),
      ];

      final dummyDailyNotes = [
        DailyNote(
          id: 'note-1',
          householdId: 'house-1',
          noteDate: now,
          title: 'Refleksi Panen',
          body: 'Hasil panen minggu ini cukup memuaskan.',
          isArchived: false,
          createdAt: now,
        ),
      ];

      final dummyHarvests = [
        HarvestEvent(
          id: 'harv-1',
          householdId: 'house-1',
          commodity: 'Padi GKP',
          quantity: 500.0,
          unit: 'kg',
          unitPrice: 7000,
          totalAmount: 3500000,
          buyerName: 'Pak Haji Ahmad',
          harvestedAt: now,
          isArchived: false,
          createdAt: now,
        ),
      ];

      final bytes = await service.buildMonthlyReport(
        month: DateTime(2026, 9),
        transactions: dummyTx,
        assets: dummyAssets,
        liabilities: dummyLiabilities,
        receivables: dummyReceivables,
        goals: dummyGoals,
        budgets: dummyBudgets,
        activityEntries: dummyActivities,
        dailyNotes: dummyDailyNotes,
        harvestEvents: dummyHarvests,
        categoryLabels: {'cat-inc': 'Gaji', 'cat-exp': 'Belanja'},
        score: score,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
    });

    test('buildCustomRangeReport menghasilkan dokumen PDF dengan rentang tanggal khusus', () async {
      final score = const FinancialHealthScore(
        totalScore: 80,
        status: FinancialHealthStatus.good,
        cashflow: 2000000,
        expenseRatio: 0.5,
      );

      final bytes = await service.buildCustomRangeReport(
        from: DateTime(2026, 8, 15),
        to: DateTime(2026, 9, 15),
        transactions: const [],
        assets: const [],
        liabilities: const [],
        receivables: const [],
        goals: const [],
        categoryLabels: const {},
        score: score,
      );

      expect(bytes, isNotEmpty);
    });

    test('buildWeeklyReport menghasilkan dokumen PDF tanpa error', () async {
      final bytes = await service.buildWeeklyReport(
        weekContaining: DateTime(2026, 9, 3),
        transactions: const [],
        categoryLabels: const {},
      );

      expect(bytes, isNotEmpty);
    });
  });
}
