import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_agent_task_plan_resolver.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_monitoring_job_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_agent_work.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_monitoring_job.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantAutonomyRepository autonomyRepo;
  late FfmAssistantMonitoringJobService service;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    autonomyRepo = FfmAssistantAutonomyRepository(database);
    service = FfmAssistantMonitoringJobService(
      database: database,
      autonomyRepository: autonomyRepo,
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('F3.1 Schema & Versioned Monitoring Job', () {
    test('Job serializes and deserializes correctly', () {
      final now = DateTime(2026, 9, 12, 10, 0);
      final job = FfmAssistantMonitoringJob.create(
        householdId: AppContext.householdId,
        preset: FfmAssistantMonitoringPreset.weeklyEvaluation,
        cadence: FfmAssistantJobCadence.weekly,
        targetTimeMinutes: 540, // 09:00
        targetDay: DateTime.sunday,
        now: now,
      );

      final json = job.toJson();
      final restored = FfmAssistantMonitoringJob.fromJson(json);

      expect(restored, isNotNull);
      expect(restored!.id, job.id);
      expect(restored.preset, FfmAssistantMonitoringPreset.weeklyEvaluation);
      expect(restored.cadence, FfmAssistantJobCadence.weekly);
      expect(restored.targetTimeMinutes, 540);
      expect(restored.targetDay, DateTime.sunday);
      expect(restored.status, FfmAssistantJobStatus.active);
    });

    test('calculateNextRun calculates correct future time', () {
      final now = DateTime(2026, 9, 12, 10, 0); // Sabtu
      final job = FfmAssistantMonitoringJob.create(
        householdId: AppContext.householdId,
        preset: FfmAssistantMonitoringPreset.weeklyEvaluation,
        cadence: FfmAssistantJobCadence.weekly,
        targetTimeMinutes: 540, // 09:00
        targetDay: DateTime.sunday,
        now: now,
      );

      final nextRun = job.calculateNextRun(now);
      // Besoknya (Minggu 13 September 2026 jam 09:00)
      expect(nextRun.year, 2026);
      expect(nextRun.month, 9);
      expect(nextRun.day, 13);
      expect(nextRun.hour, 9);
      expect(nextRun.minute, 0);
    });

    test('Maps to and from AssistantAgentGoal without loss', () {
      final now = DateTime(2026, 9, 12, 10, 0);
      final job = FfmAssistantMonitoringJob.create(
        householdId: AppContext.householdId,
        preset: FfmAssistantMonitoringPreset.budgetMonitor,
        categoryFilter: 'Makan',
        cadence: FfmAssistantJobCadence.daily,
        targetTimeMinutes: 480, // 08:00
        now: now,
      );

      final agentGoal = job.toAgentGoal();
      expect(agentGoal.domain, 'monitoring_job');
      expect(agentGoal.status, FfmAssistantAgentGoalStatus.active);

      // Simulasikan row dari Drift
      final restored = FfmAssistantMonitoringJob.fromAgentGoal(
        AssistantAgentGoal(
          id: agentGoal.id,
          householdId: agentGoal.householdId,
          domain: agentGoal.domain,
          title: agentGoal.title,
          objective: agentGoal.objective,
          status: agentGoal.status.name,
          priority: 5,
          createdAt: agentGoal.createdAt,
          updatedAt: agentGoal.updatedAt,
          completionCondition: agentGoal.completionCondition,
        ),
      );

      expect(restored, isNotNull);
      expect(restored!.preset, FfmAssistantMonitoringPreset.budgetMonitor);
      expect(restored.categoryFilter, 'Makan');
      expect(restored.cadence, FfmAssistantJobCadence.daily);
      expect(restored.targetTimeMinutes, 480);
    });
  });

  group('F3.2 Lifecycle & Deterministic Evaluation Service', () {
    test('createJob saves durable goal and pending task', () async {
      final now = DateTime(2026, 9, 12, 10, 0);
      final job = FfmAssistantMonitoringJob.create(
        householdId: AppContext.householdId,
        preset: FfmAssistantMonitoringPreset.weeklyEvaluation,
        now: now,
      );

      final saved = await service.createJob(job);
      expect(saved, isNotNull);

      final list = await service.listJobs(AppContext.householdId);
      expect(list.length, 1);
      expect(list.first.title, contains('Evaluasi Mingguan'));

      // Verifikasi task juga terbuat
      final events = await autonomyRepo.enqueueDueTaskEvents(limit: 10);
      expect(events, 0); // Belum due karena next run di masa depan
    });

    test('pauseJob, resumeJob, and cancelJob update status correctly',
        () async {
      final now = DateTime(2026, 9, 12, 10, 0);
      final job = FfmAssistantMonitoringJob.create(
        householdId: AppContext.householdId,
        preset: FfmAssistantMonitoringPreset.dueCheck,
        now: now,
      );
      await service.createJob(job);

      // Pause
      final paused = await service.pauseJob(job.id);
      expect(paused, isTrue);
      var current = await service.jobById(job.id);
      expect(current!.status, FfmAssistantJobStatus.paused);

      // Resume
      final resumed = await service.resumeJob(job.id);
      expect(resumed, isTrue);
      current = await service.jobById(job.id);
      expect(current!.status, FfmAssistantJobStatus.active);

      // Cancel
      final cancelled = await service.cancelJob(job.id);
      expect(cancelled, isTrue);
      current = await service.jobById(job.id);
      expect(current!.status, FfmAssistantJobStatus.cancelled);
    });

    test('Weekly evaluation produces structured report without hallucination',
        () async {
      final now = DateTime(2026, 9, 15);
      // Pemasukan 5jt
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-inc',
              householdId: AppContext.householdId,
              type: 'income',
              amount: 5000000,
              date: now.subtract(const Duration(days: 2)),
              recordedAt: now,
              createdAt: now,
            ),
          );
      // Pengeluaran 1jt
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-exp-1',
              householdId: AppContext.householdId,
              type: 'expense',
              amount: -1000000,
              date: now.subtract(const Duration(days: 1)),
              note: const Value('Belanja Mingguan'),
              recordedAt: now,
              createdAt: now,
            ),
          );

      final job = FfmAssistantMonitoringJob.create(
        householdId: AppContext.householdId,
        preset: FfmAssistantMonitoringPreset.weeklyEvaluation,
        now: now,
      );
      await service.createJob(job);

      final report = await service.runJobNow(job.id);
      expect(report.title, 'Laporan Evaluasi Mingguan');
      expect(report.content, contains('Total Pemasukan: Rp5.000.000'));
      expect(report.content, contains('Total Pengeluaran: Rp1.000.000'));
      expect(report.content, contains('Arus Kas Bersih: Rp4.000.000 (Surplus)'));
      expect(report.content, contains('Belanja Mingguan'));
      expect(report.isActionRequired, isFalse);
    });

    test('Due check evaluation reports near due liabilities', () async {
      final now = DateTime(2026, 9, 15);
      // Cicilan jatuh tempo 3 hari lagi (18 Sep 2026)
      await database.into(database.liabilities).insert(
            LiabilitiesCompanion.insert(
              id: 'liab-due',
              householdId: AppContext.householdId,
              name: 'Tagihan Listrik & WiFi',
              originalAmount: 800000,
              remainingBalance: 800000,
              monthlyInstallment: const Value(800000),
              dueDate: Value(DateTime(2026, 9, 18)),
              startDate: DateTime(2026, 1, 1),
              createdAt: now,
            ),
          );

      final job = FfmAssistantMonitoringJob.create(
        householdId: AppContext.householdId,
        preset: FfmAssistantMonitoringPreset.dueCheck,
        now: now,
      );
      await service.createJob(job);

      final report = await service.runJobNow(job.id);
      expect(report.title, 'Pemeriksaan Tagihan & Target');
      expect(report.content, contains('Tagihan Listrik & WiFi'));
      expect(report.content, contains('SEGERA'));
      expect(report.isActionRequired, isTrue);
    });
  });

  group('F3.3 & F3.4 Natural Language & Capability Integration', () {
    test('Interpreter creates monitoring job draft from Indonesian query',
        () async {
      final now = DateTime(2026, 9, 12, 10, 0);
      final interpreter = FfmAssistantInterpreter(database, clock: () => now);

      final intent = await interpreter.interpret(
        'Jadwalkan evaluasi mingguan setiap Minggu jam 9 pagi',
      );

      expect(intent.type, FfmAssistantIntentType.createMonitoringJob);
      expect(intent.draft, isNotNull);
      expect(intent.draft!.kind, FfmAssistantDraftKind.monitoringJob);
      expect(
        intent.draft!.formValues['preset'],
        'weeklyEvaluation',
      );
      expect(intent.draft!.formValues['cadence'], 'weekly');
      expect(intent.draft!.formValues['targetTimeMinutes'], 540);
      expect(intent.draft!.formValues['targetDay'], DateTime.sunday);
      expect(intent.response, contains('Evaluasi Mingguan'));
      expect(intent.response, contains('pukul 9:00'));
    });

    test('Interpreter handles list, pause, and cancel requests', () async {
      final now = DateTime(2026, 9, 12, 10, 0);
      final job = FfmAssistantMonitoringJob.create(
        householdId: AppContext.householdId,
        preset: FfmAssistantMonitoringPreset.weeklyEvaluation,
        now: now,
      );
      await service.createJob(job);

      final interpreter = FfmAssistantInterpreter(database, clock: () => now);

      // List
      final listIntent =
          await interpreter.interpret('lihat daftar jadwal monitoring');
      expect(listIntent.type, FfmAssistantIntentType.listMonitoringJobs);
      expect(listIntent.response, contains('Evaluasi Mingguan'));

      // Pause
      final pauseIntent = await interpreter.interpret('jeda monitoring');
      expect(pauseIntent.type, FfmAssistantIntentType.manageMonitoringJob);
      expect(pauseIntent.response, contains('berhasil dijeda'));

      // Resume
      final resumeIntent = await interpreter.interpret('lanjutkan monitoring');
      expect(resumeIntent.type, FfmAssistantIntentType.manageMonitoringJob);
      expect(resumeIntent.response, contains('berhasil diaktifkan kembali'));

      // Cancel
      final cancelIntent = await interpreter.interpret('batalkan monitoring');
      expect(cancelIntent.type, FfmAssistantIntentType.manageMonitoringJob);
      expect(cancelIntent.response, contains('telah dibatalkan'));
    });

    test('Capability adapter saves monitoring job and executes evaluation',
        () async {
      final now = DateTime(2026, 9, 12, 10, 0);
      final adapters = FfmAssistantCapabilityAdapterRegistry(
        database: database,
        householdId: AppContext.householdId,
        clock: () => now,
      );

      // Save capability
      final saveResult = await adapters.handlers['mutate.monitoring_job_save']!(
        const FfmAssistantActionStep(
          id: 'step-1',
          capabilityId: 'mutate.monitoring_job_save',
          parameters: {
            'preset': 'budgetMonitor',
            'cadence': 'daily',
            'targetTimeMinutes': 540,
            'categoryFilter': 'Makan',
            'title': 'Pantau Anggaran Makan Harian',
          },
        ),
      );
      expect(saveResult.isSuccess, isTrue);
      expect(saveResult.message, contains('berhasil disimpan'));

      // Read jobs capability
      final readResult = await adapters.handlers['read.monitoring_jobs']!(
        const FfmAssistantActionStep(
          id: 'step-2',
          capabilityId: 'read.monitoring_jobs',
          parameters: {},
        ),
      );
      expect(readResult.isSuccess, isTrue);
      expect(readResult.message, contains('Pantau Anggaran Makan Harian'));

      // Evaluate capability
      final evalResult =
          await adapters.handlers['read.monitoring_evaluation']!(
        const FfmAssistantActionStep(
          id: 'step-3',
          capabilityId: 'read.monitoring_evaluation',
          parameters: {},
        ),
      );
      expect(evalResult.isSuccess, isTrue);
      expect(evalResult.message, contains('Laporan Evaluasi Mingguan'));
    });

    test('F3.6: Task plan resolver resolves read.monitoring_evaluation safely',
        () async {
      final now = DateTime(2026, 9, 12, 10, 0);
      final job = FfmAssistantMonitoringJob.create(
        householdId: AppContext.householdId,
        preset: FfmAssistantMonitoringPreset.weeklyEvaluation,
        now: now,
      );
      await service.createJob(job);

      final tasks = await autonomyRepo.tasksForGoal(job.id);
      expect(tasks, isNotEmpty);
      final task = tasks.first;

      final resolver =
          FfmAssistantAgentTaskPlanResolver(autonomyRepo, now: () => now);
      final event = FfmAssistantAutonomyEvent(
        id: 'event-1',
        type: 'agent.task.due',
        occurredAt: now,
        entityId: job.id,
        payload: {'taskId': task.id, 'goalId': job.id},
      );

      final plan = await resolver.resolve(event);
      expect(plan, isNotNull);
      expect(plan!.requiresConfirmation, isFalse);
      expect(plan.steps.first.capabilityId, 'read.monitoring_evaluation');
    });
  });
}
