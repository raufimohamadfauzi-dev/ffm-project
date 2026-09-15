import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_goal_evidence_evaluator.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_knowledge_index.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_learning_candidate_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_memory_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_monitoring_job_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_monitoring_job.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantAutonomyRepository autonomyRepo;
  late FfmAssistantMonitoringJobService monitoringService;
  late FfmAssistantGoalEvidenceEvaluator goalEvaluator;
  late FfmAssistantLearningCandidateService candidateService;
  late FfmAssistantCapabilityAdapterRegistry adapters;
  late FfmAssistantInterpreter interpreter;

  final fixedClock = DateTime(2026, 9, 12, 10, 0);

  setUp(() {
    database = createInMemoryDatabaseForTests();
    autonomyRepo = FfmAssistantAutonomyRepository(
      database,
      now: () => fixedClock,
    );
    monitoringService = FfmAssistantMonitoringJobService(
      database: database,
      autonomyRepository: autonomyRepo,
      clock: () => fixedClock,
    );
    goalEvaluator = FfmAssistantGoalEvidenceEvaluator(
      database: database,
      clock: () => fixedClock,
    );
    final memoryRepo = FfmAssistantMemoryRepository(database);
    candidateService = FfmAssistantLearningCandidateService(memoryRepo);
    adapters = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: AppContext.householdId,
      clock: () => fixedClock,
    );
    interpreter = FfmAssistantInterpreter(database, clock: () => fixedClock);
  });

  tearDown(() async {
    await database.close();
  });

  group('F7.1 Hermes End-to-End Acceptance: Multi-Phase Integrated Workflow', () {
    test('Complete flow: Natural language job creation -> execution -> goal check -> approved replay', () async {
      // 1. User minta penjadwalan evaluasi mingguan via chat bahasa alami
      final createJobIntent = await interpreter.interpret(
        'Jadwalkan evaluasi mingguan setiap Minggu jam 9 pagi',
      );
      expect(createJobIntent.type, FfmAssistantIntentType.createMonitoringJob);
      expect(createJobIntent.draft, isNotNull);
      expect(createJobIntent.draft!.kind, FfmAssistantDraftKind.monitoringJob);

      // 2. Draft disimpan ke basis data melalui capability handler
      final saveResult = await adapters.handlers['mutate.monitoring_job_save']!(
        FfmAssistantActionStep(
          id: 'step-save-1',
          capabilityId: 'mutate.monitoring_job_save',
          parameters: createJobIntent.draft!.formValues,
        ),
      );
      expect(saveResult.isSuccess, isTrue);

      // Verifikasi job persisten di database
      final jobs = await monitoringService.listJobs(AppContext.householdId);
      expect(jobs.length, 1);
      final job = jobs.first;
      expect(job.preset, FfmAssistantMonitoringPreset.weeklyEvaluation);
      expect(job.status, FfmAssistantJobStatus.active);

      // 3. Masukkan data keuangan untuk diuji
      await database
          .into(database.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'tx-salary',
              householdId: AppContext.householdId,
              type: 'income',
              amount: 10000000,
              date: fixedClock.subtract(const Duration(days: 3)),
              recordedAt: fixedClock,
              createdAt: fixedClock,
            ),
          );
      await database
          .into(database.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'tx-groceries',
              householdId: AppContext.householdId,
              type: 'expense',
              amount: -3000000,
              date: fixedClock.subtract(const Duration(days: 1)),
              note: const Value('Belanja Mingguan'),
              recordedAt: fixedClock,
              createdAt: fixedClock,
            ),
          );

      // Jalankan evaluasi monitoring
      final report = await monitoringService.runJobNow(job.id);
      expect(report.title, 'Laporan Evaluasi Mingguan');
      expect(report.content, contains('Pemasukan: Rp10.000.000'));
      expect(report.content, contains('Pengeluaran: Rp3.000.000'));
      expect(
        report.content,
        contains('Arus Kas Bersih: Rp7.000.000 (Surplus)'),
      );

      // 4. Buat target tabungan dan evaluasi dengan bukti riil arus kas
      await database
          .into(database.goals)
          .insert(
            GoalsCompanion.insert(
              id: 'goal-emergency',
              householdId: AppContext.householdId,
              name: 'Dana Darurat',
              targetAmount: 20000000,
              currentAmount: const Value(8000000),
              targetDate: Value(DateTime(2027, 3, 1)),
              isActive: const Value(true),
              createdAt: fixedClock,
            ),
          );

      final goalProgressIntent = await interpreter.interpret(
        'Bagaimana progres target tabungan saya?',
      );
      expect(
        goalProgressIntent.type,
        FfmAssistantIntentType.evaluateGoalProgress,
      );
      expect(goalProgressIntent.response, contains('Dana Darurat'));
      expect(goalProgressIntent.response, contains('40.0%'));
      expect(goalProgressIntent.response, contains('Rp8.000.000'));
      expect(goalProgressIntent.response, contains('Rp12.000.000'));

      final directReport = await goalEvaluator.evaluateGoal('goal-emergency');
      expect(directReport, isNotNull);
      expect(directReport!.progressPercent, 40.0);
      expect(directReport.currentAmount, 8000000);

      // 5. Reusable workflow candidate: pembuatan, persetujuan, dan resolusi rencana
      final candidate = await candidateService.proposeWorkflow(
        trigger: 'analisis arus kas bulanan',
        steps: [
          {
            'capabilityId': 'read.summary',
            'parameters': {'period': 'month'},
          },
        ],
      );
      expect(candidate.isPending, isTrue);

      final approved = await candidateService.approve(candidate);
      expect(approved.isApproved, isTrue);

      final plan = candidateService.resolveApprovedPlan(approved);
      expect(plan, isNotNull);
      expect(plan!.requiresConfirmation, isFalse);
      expect(plan.steps.first.capabilityId, 'read.summary');

      // 6. Verifikasi kepatuhan boundary read-only: Saldo transaksi tetap utuh
      final allTxs = await database.select(database.transactions).get();
      expect(
        allTxs.length,
        2,
      ); // Hanya 2 transaksi awal yang dimasukkan secara sah
    });

    test(
      'Workflow with mutation capabilities strictly requires user confirmation',
      () async {
        final candidate = await candidateService.proposeWorkflow(
          trigger: 'catat pengeluaran rutin',
          steps: [
            {
              'capabilityId': 'read.summary',
              'parameters': {'period': 'month'},
            },
            {
              'capabilityId': 'mutate.save_draft',
              'parameters': {
                'type': 'expense',
                'amount': 50000,
                'category': 'makanan',
              },
            },
          ],
        );
        final approved = await candidateService.approve(candidate);
        final plan = candidateService.resolveApprovedPlan(approved);

        expect(plan, isNotNull);
        expect(plan!.requiresConfirmation, isTrue);
        expect(plan.steps.length, 2);
        expect(plan.steps[1].capabilityId, 'mutate.save_draft');
      },
    );

    test(
      'Knowledge index chat history planning for past conversations (F5)',
      () {
        final plan = FfmAssistantKnowledgeIndex.planForRequest(
          'Apa yang pernah kita bicarakan tentang target tabungan?',
        );
        expect(plan.sourceIds, contains('chat_history'));
        expect(plan.sourceIds, contains('goals'));
      },
    );
  });
}
