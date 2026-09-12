import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_goal_evidence_evaluator.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_agent_work.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantGoalEvidenceEvaluator evaluator;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    evaluator = FfmAssistantGoalEvidenceEvaluator(
      database: database,
      clock: () => DateTime(2026, 9, 12, 10, 0),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('F4.1 - F4.5 Goal Evidence Evaluator (Deterministic & Grounded)', () {
    test('Reports targetReached when current amount satisfies target', () async {
      final now = DateTime(2026, 9, 12);
      await database.into(database.goals).insert(
            GoalsCompanion.insert(
              id: 'goal-1',
              householdId: AppContext.householdId,
              name: 'Dana Darurat',
              targetAmount: 10000000,
              currentAmount: const Value(10000000),
              isActive: const Value(true),
              createdAt: now,
            ),
          );

      final report = await evaluator.evaluateGoal('goal-1', now: now);
      expect(report, isNotNull);
      expect(report!.status, FfmAssistantGoalProgressStatus.targetReached);
      expect(report.progressPercent, 100.0);
      expect(report.isAchievableWithCurrentCashflow, isTrue);
      expect(report.recommendation, contains('Target telah tercapai'));
    });

    test('Evaluates onTrack when cashflow comfortably covers monthly allocation',
        () async {
      final now = DateTime(2026, 9, 12);
      // Target: sisa 6jt butuh 6 bulan (1jt/bln). Deadline 12 Maret 2027 (~181 hari)
      await database.into(database.goals).insert(
            GoalsCompanion.insert(
              id: 'goal-motor',
              householdId: AppContext.householdId,
              name: 'Beli Motor',
              targetAmount: 12000000,
              currentAmount: const Value(6000000),
              targetDate: Value(DateTime(2027, 3, 12)),
              isActive: const Value(true),
              createdAt: now,
            ),
          );

      // Transaksi 90 hari: pemasukan 5jt/bln, pengeluaran 3jt/bln -> surplus 2jt/bln (melebihi 1jt/bln)
      for (var i = 1; i <= 3; i++) {
        final txDate = now.subtract(Duration(days: i * 25));
        await database.into(database.transactions).insert(
              TransactionsCompanion.insert(
                id: 'tx-inc-$i',
                householdId: AppContext.householdId,
                type: 'income',
                amount: 5000000,
                date: txDate,
                recordedAt: txDate,
                createdAt: txDate,
              ),
            );
        await database.into(database.transactions).insert(
              TransactionsCompanion.insert(
                id: 'tx-exp-$i',
                householdId: AppContext.householdId,
                type: 'expense',
                amount: -3000000,
                date: txDate,
                recordedAt: txDate,
                createdAt: txDate,
              ),
            );
      }

      final report = await evaluator.evaluateGoal('goal-motor', now: now);
      expect(report, isNotNull);
      expect(report!.status, anyOf(
        FfmAssistantGoalProgressStatus.onTrack,
        FfmAssistantGoalProgressStatus.aheadOfSchedule,
      ));
      expect(report.isAchievableWithCurrentCashflow, isTrue);
      expect(report.remainingAmount, 6000000);
      expect(report.averageMonthlyCashflow, 2000000);
      expect(report.requiredMonthlySaving, lessThanOrEqualTo(2000000));
    });

    test('Evaluates behindSchedule when required monthly saving exceeds surplus',
        () async {
      final now = DateTime(2026, 9, 12);
      // Target butuh 5jt dalam 2 bulan (2.5jt/bln).
      await database.into(database.goals).insert(
            GoalsCompanion.insert(
              id: 'goal-laptop',
              householdId: AppContext.householdId,
              name: 'Laptop Kerja',
              targetAmount: 10000000,
              currentAmount: const Value(5000000),
              targetDate: Value(DateTime(2026, 11, 12)),
              isActive: const Value(true),
              createdAt: now,
            ),
          );

      // Surplus hanya 500rb/bulan
      final txDate = now.subtract(const Duration(days: 15));
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-inc-1',
              householdId: AppContext.householdId,
              type: 'income',
              amount: 3500000,
              date: txDate,
              recordedAt: txDate,
              createdAt: txDate,
            ),
          );
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-exp-1',
              householdId: AppContext.householdId,
              type: 'expense',
              amount: -2000000,
              date: txDate,
              recordedAt: txDate,
              createdAt: txDate,
            ),
          );

      final report = await evaluator.evaluateGoal('goal-laptop', now: now);
      expect(report, isNotNull);
      expect(report!.status, FfmAssistantGoalProgressStatus.behindSchedule);
      expect(report.isAchievableWithCurrentCashflow, isFalse);
      expect(report.recommendation, contains('melebihi surplus kas'));
    });

    test('Completion evaluator recognizes not_blocked condition', () {
      const evaluator = FfmAssistantAgentCompletionEvaluator();
      final statusesWithBlocked = [
        FfmAssistantAgentTaskStatus.completed,
        FfmAssistantAgentTaskStatus.blocked,
      ];
      final statusesWithoutBlocked = [
        FfmAssistantAgentTaskStatus.completed,
        FfmAssistantAgentTaskStatus.waitingForTime,
      ];

      expect(
        evaluator.isSatisfied('not_blocked', statusesWithBlocked),
        isFalse,
      );
      expect(
        evaluator.isSatisfied('not_blocked', statusesWithoutBlocked),
        isTrue,
      );
    });
  });

  group('F4 Integration: Interpreter & Capability Registry', () {
    test('Interpreter answers goal progress query with grounded evaluation',
        () async {
      final now = DateTime(2026, 9, 12, 10, 0);
      await database.into(database.goals).insert(
            GoalsCompanion.insert(
              id: 'goal-darurat',
              householdId: AppContext.householdId,
              name: 'Dana Darurat',
              targetAmount: 5000000,
              currentAmount: const Value(2500000),
              targetDate: Value(DateTime(2027, 1, 1)),
              isActive: const Value(true),
              createdAt: now,
            ),
          );

      final interpreter = FfmAssistantInterpreter(database, clock: () => now);

      final intent =
          await interpreter.interpret('Bagaimana progres target tabungan saya?');
      expect(intent.type, FfmAssistantIntentType.evaluateGoalProgress);
      expect(intent.response, contains('Dana Darurat'));
      expect(intent.response, contains('50.0%'));
      expect(intent.response, contains('Rp2.500.000'));
    });

    test('Capability adapter read.goal_evidence_evaluation returns evaluation',
        () async {
      final now = DateTime(2026, 9, 12, 10, 0);
      await database.into(database.goals).insert(
            GoalsCompanion.insert(
              id: 'goal-darurat',
              householdId: AppContext.householdId,
              name: 'Tabungan Nikah',
              targetAmount: 20000000,
              currentAmount: const Value(15000000),
              targetDate: Value(DateTime(2027, 6, 1)),
              isActive: const Value(true),
              createdAt: now,
            ),
          );

      final adapters = FfmAssistantCapabilityAdapterRegistry(
        database: database,
        householdId: AppContext.householdId,
        clock: () => now,
      );

      final result =
          await adapters.handlers['read.goal_evidence_evaluation']!(
        const FfmAssistantActionStep(
          id: 'step-goal-1',
          capabilityId: 'read.goal_evidence_evaluation',
          parameters: {'goalId': 'goal-darurat'},
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.message, contains('Tabungan Nikah'));
      expect(result.message, contains('75.0%'));
      expect(result.message, contains('Terkumpul: Rp15.000.000'));
    });
  });
}
