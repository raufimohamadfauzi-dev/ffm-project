import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/domain/detectors/anomaly_spike_detector.dart';
import 'package:ffm_manager/features/assistant/domain/detectors/debt_service_ratio_detector.dart';
import 'package:ffm_manager/features/assistant/domain/detectors/goal_progress_risk_detector.dart';
import 'package:ffm_manager/features/assistant/domain/detectors/intelligent_envelope_rebalance_detector.dart';
import 'package:ffm_manager/features/assistant/domain/detectors/micro_expense_leak_detector.dart';
import 'package:ffm_manager/features/assistant/domain/detectors/predictive_runway_detector.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_insight.dart';

void main() {
  late AppDatabase db;
  const householdId = 'house-test';
  final now = DateTime(2026, 9, 10, 10, 0);

  setUp(() {
    db = createInMemoryDatabaseForTests();
  });

  tearDown(() async {
    await db.close();
  });

  group('Financial Detectors Tests', () {
    test('PredictiveRunwayDetector triggers warning when daily burn exceeds safe spend', () async {
      // Rekening dengan saldo Rp 1.000.000
      await db.into(db.accounts).insert(
            AccountsCompanion.insert(
              id: 'acc-runway',
              householdId: householdId,
              name: 'BCA Utama',
              type: 'bank',
              openingBalance: const Value(2150000),
              isActive: const Value(true),
              isArchived: const Value(false),
              createdAt: now.subtract(const Duration(days: 30)),
            ),
          );

      // Transaksi pengeluaran 14 hari terakhir: Rp 100.000 / hari
      for (int i = 1; i <= 14; i++) {
        final txDate = now.subtract(Duration(days: i));
        await db.into(db.transactions).insert(
              TransactionsCompanion.insert(
                id: 'tx-runway-$i',
                householdId: householdId,
                type: 'expense',
                amount: -100000,
                date: txDate,
                recordedAt: txDate,
                accountId: const Value('acc-runway'),
                note: const Value('Pengeluaran harian'),
                isArchived: const Value(false),
                isDeleted: const Value(false),
                createdAt: txDate,
              ),
            );
      }

      final detector = PredictiveRunwayDetector(db);
      final insight = await detector.detect(householdId: householdId, now: now, defaultPaydayDay: 25);

      expect(insight, isNotNull);
      expect(insight!.type, FfmAssistantInsightType.runwayRisk);
      expect(insight.severity, FfmAssistantInsightSeverity.warning);
      expect(insight.evidence['daysToPayday'], 14);
      expect(insight.title, contains('Peringatan Laju Pengeluaran'));
      expect(insight.summary, contains('Laju pengeluaran Anda'));
    });

    test('IntelligentEnvelopeRebalanceDetector triggers when budget A is deficit and B is surplus', () async {
      final start = DateTime(2026, 9, 1);
      final end = DateTime(2026, 9, 30);

      // Pos A: Makan (Alokasi 500.000)
      await db.into(db.envelopeBudgets).insert(
            EnvelopeBudgetsCompanion.insert(
              id: 'env-makan',
              householdId: householdId,
              name: 'Makan',
              categoryId: const Value('cat-makan'),
              allocated: const Value(500000),
              startDate: start,
              endDate: end,
              createdAt: start,
            ),
          );

      // Pos B: Hiburan (Alokasi 1.000.000)
      await db.into(db.envelopeBudgets).insert(
            EnvelopeBudgetsCompanion.insert(
              id: 'env-hiburan',
              householdId: householdId,
              name: 'Hiburan',
              categoryId: const Value('cat-hiburan'),
              allocated: const Value(1000000),
              startDate: start,
              endDate: end,
              createdAt: start,
            ),
          );

      final dateMakan = DateTime(2026, 9, 5);
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-makan',
              householdId: householdId,
              type: 'expense',
              amount: -480000,
              date: dateMakan,
              recordedAt: dateMakan,
              categoryId: const Value('cat-makan'),
              isArchived: const Value(false),
              isDeleted: const Value(false),
              createdAt: dateMakan,
            ),
          );

      final dateHiburan = DateTime(2026, 9, 7);
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-hiburan',
              householdId: householdId,
              type: 'expense',
              amount: -100000,
              date: dateHiburan,
              recordedAt: dateHiburan,
              categoryId: const Value('cat-hiburan'),
              isArchived: const Value(false),
              isDeleted: const Value(false),
              createdAt: dateHiburan,
            ),
          );

      final detector = IntelligentEnvelopeRebalanceDetector(db);
      final insight = await detector.detect(householdId: householdId, now: now);

      expect(insight, isNotNull);
      expect(insight!.type, FfmAssistantInsightType.envelopeRebalance);
      expect(insight.evidence['fromBudget'], 'Hiburan');
      expect(insight.evidence['toBudget'], 'Makan');
      expect(insight.evidence['rebalanceAmount'], greaterThanOrEqualTo(10000));
    });

    test('AnomalySpikeDetector detects 15-minute duplicate transactions', () async {
      final txTime1 = now.subtract(const Duration(minutes: 5));
      final txTime2 = now.subtract(const Duration(minutes: 2));

      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-dup-1',
              householdId: householdId,
              type: 'expense',
              amount: -125000,
              date: txTime1,
              recordedAt: txTime1,
              accountId: const Value('acc-1'),
              note: const Value('Beli Token Listrik'),
              isArchived: const Value(false),
              isDeleted: const Value(false),
              createdAt: txTime1,
            ),
          );

      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-dup-2',
              householdId: householdId,
              type: 'expense',
              amount: -125000,
              date: txTime2,
              recordedAt: txTime2,
              accountId: const Value('acc-1'),
              note: const Value('Beli Token Listrik'),
              isArchived: const Value(false),
              isDeleted: const Value(false),
              createdAt: txTime2,
            ),
          );

      final detector = AnomalySpikeDetector(db);
      final insight = await detector.detect(householdId: householdId, now: now);

      expect(insight, isNotNull);
      expect(insight!.type, FfmAssistantInsightType.anomalySpike);
      expect(insight.title, contains('Transaksi Ganda'));
      expect(insight.evidence['diffMinutes'], 3);
    });

    test('MicroExpenseLeakDetector triggers when small expenses exceed 15% ratio', () async {
      for (int i = 1; i <= 10; i++) {
        final txDate = now.subtract(Duration(days: i));
        await db.into(db.transactions).insert(
              TransactionsCompanion.insert(
                id: 'tx-micro-$i',
                householdId: householdId,
                type: 'expense',
                amount: -20000,
                date: txDate,
                recordedAt: txDate,
                isArchived: const Value(false),
                isDeleted: const Value(false),
                createdAt: txDate,
              ),
            );
      }

      final dateMain = now.subtract(const Duration(days: 4));
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-main',
              householdId: householdId,
              type: 'expense',
              amount: -600000,
              date: dateMain,
              recordedAt: dateMain,
              isArchived: const Value(false),
              isDeleted: const Value(false),
              createdAt: dateMain,
            ),
          );

      final detector = MicroExpenseLeakDetector(db);
      final insight = await detector.detect(householdId: householdId, now: now);

      expect(insight, isNotNull);
      expect(insight!.type, FfmAssistantInsightType.microExpenseLeak);
      expect(insight.evidence['count'], 10);
      expect(insight.evidence['ratio'], 25);
    });

    test('DebtServiceRatioDetector alerts when DSR is critical (>= 40%)', () async {
      final dateInc = now.subtract(const Duration(days: 5));
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-inc-gaji',
              householdId: householdId,
              type: 'income',
              amount: 5000000,
              date: dateInc,
              recordedAt: dateInc,
              isArchived: const Value(false),
              isDeleted: const Value(false),
              createdAt: dateInc,
            ),
          );

      await db.into(db.liabilities).insert(
            LiabilitiesCompanion.insert(
              id: 'liab-1',
              householdId: householdId,
              name: 'Cicilan Motor',
              originalAmount: 20000000,
              remainingBalance: 15000000,
              monthlyInstallment: const Value(2250000),
              startDate: now.subtract(const Duration(days: 90)),
              dueDate: Value(now.add(const Duration(days: 12))),
              isActive: const Value(true),
              createdAt: now,
            ),
          );

      final detector = DebtServiceRatioDetector(db);
      final insight = await detector.detect(householdId: householdId, now: now);

      expect(insight, isNotNull);
      expect(insight!.type, FfmAssistantInsightType.debtServiceRatio);
      expect(insight.severity, FfmAssistantInsightSeverity.critical);
      expect(insight.evidence['dsrPercent'], 45);
    });

    test('GoalProgressRiskDetector triggers required monthly delta when savings rate lags', () async {
      await db.into(db.goals).insert(
            GoalsCompanion.insert(
              id: 'goal-laptop',
              householdId: householdId,
              name: 'Beli Laptop Kerja',
              targetAmount: 10000000,
              currentAmount: const Value(2000000),
              targetDate: Value(now.add(const Duration(days: 60))),
              isActive: const Value(true),
              createdAt: now.subtract(const Duration(days: 60)),
            ),
          );

      final dateGoal = now.subtract(const Duration(days: 20));
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-goal-sav',
              householdId: householdId,
              type: 'expense',
              amount: -1000000,
              goalId: const Value('goal-laptop'),
              date: dateGoal,
              recordedAt: dateGoal,
              isArchived: const Value(false),
              isDeleted: const Value(false),
              createdAt: dateGoal,
            ),
          );

      final detector = GoalProgressRiskDetector(db);
      final insight = await detector.detect(householdId: householdId, now: now);

      expect(insight, isNotNull);
      expect(insight!.type, FfmAssistantInsightType.goalProgressRisk);
      expect(insight.evidence['shortage'], 8000000);
      expect(insight.evidence['requiredMonthlyRate'], 4000000);
      expect(insight.evidence['requiredDelta'], 3500000);
    });
  });
}
