import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_worker.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_learning_candidate_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_memory_repository.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_agent_work.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantAutonomyRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = FfmAssistantAutonomyRepository(
      database,
      now: () => DateTime(2026, 9, 1, 12),
    );
  });

  tearDown(() => database.close());

  test(
    'worker memproses event pending dan tidak mengambil event completed',
    () async {
      final event = FfmAssistantAutonomyEvent(
        id: 'worker-event-1',
        type: 'reminder.due',
        occurredAt: DateTime(2026, 9, 1, 11),
      );
      await repository.enqueueEvent(event);
      var calls = 0;
      final worker = FfmAssistantAutonomyWorker(repository: repository);

      final first = await worker.runOnce((_) async => calls++);
      final second = await worker.runOnce((_) async => calls++);

      expect(first.attempted, 1);
      expect(first.processed, 1);
      expect(second.attempted, 0);
      expect(calls, 1);
    },
  );

  test('worker retry gagal dibatasi oleh maxAttempts', () async {
    final event = FfmAssistantAutonomyEvent(
      id: 'worker-event-failed',
      type: 'transaction.created',
      occurredAt: DateTime(2026, 9, 1, 11),
    );
    await repository.enqueueEvent(event);
    final worker = FfmAssistantAutonomyWorker(
      repository: repository,
      maxAttempts: 2,
    );

    final first = await worker.runOnce((_) async {
      throw StateError('sementara gagal');
    });
    final second = await worker.runOnce((_) async {
      throw StateError('masih gagal');
    });
    final third = await worker.runOnce((_) async {});

    expect(first.failed, 1);
    expect(second.failed, 1);
    expect(third.attempted, 0);
    expect((await repository.eventById(event.id))?.attemptCount, 2);
  });

  test(
    'worker mengantrekan task yang sudah jatuh tempo menjadi event durable',
    () async {
      final goal = FfmAssistantAgentGoal(
        id: 'worker-goal',
        householdId: FfmAssistantAutonomyRepository.householdId,
        domain: 'finance',
        title: 'Goal worker',
        objective: 'Menjalankan task terjadwal.',
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );
      final task = FfmAssistantAgentTask(
        id: 'worker-task',
        goalId: goal.id,
        householdId: goal.householdId,
        title: 'Task jatuh tempo',
        nextRunAt: DateTime(2026, 9, 1, 11),
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );
      await repository.createGoal(goal);
      await repository.createTask(task);
      final worker = FfmAssistantAutonomyWorker(repository: repository);
      FfmAssistantAutonomyEvent? received;

      final result = await worker.runOnce((event) async => received = event);

      expect(result.enqueued, 1);
      expect(result.processed, 1);
      expect(received?.type, 'agent.task.due');
      expect(received?.payload['taskId'], task.id);
    },
  );

  test(
    'konsolidasi memori mengusulkan workflow untuk pola merchant berulang',
    () async {
      final householdId = 'house-memory';
      final merchantId = 'merchant-coffee';
      final categoryId = 'category-drinks';
      final now = DateTime.now();
      await database.into(database.merchants).insert(
            MerchantsCompanion.insert(
              id: merchantId,
              householdId: householdId,
              name: 'Kopi Pagi',
              createdAt: now,
            ),
          );
      await database.into(database.categories).insert(
            CategoriesCompanion.insert(
              id: categoryId,
              householdId: householdId,
              name: 'Minuman',
              type: 'expense',
              createdAt: now,
            ),
          );

      for (var index = 0; index < 3; index++) {
        await database.into(database.transactions).insert(
              TransactionsCompanion.insert(
                id: 'memory-tx-$index',
                householdId: householdId,
                type: 'expense',
                amount: -25000,
                categoryId: drift.Value(categoryId),
                merchantId: drift.Value(merchantId),
                date: now.subtract(Duration(days: index)),
                recordedAt: now,
                createdAt: now,
              ),
            );
      }

      final candidateService = FfmAssistantLearningCandidateService(
        FfmAssistantMemoryRepository(database),
      );
      final worker = FfmAssistantAutonomyWorker(
        repository: repository,
        database: database,
        candidateService: candidateService,
      );

      await worker.consolidateMemory(householdId: householdId);
      await worker.consolidateMemory(householdId: householdId);

      final pending = await candidateService.readPending();
      expect(pending, hasLength(1));
      expect(pending.single.trigger, 'otonom.kategori.kopi pagi');
      expect(pending.single.source, 'background-autonomy-memory');
      expect(
        pending.single.workflowJson['steps'],
        contains(
          containsPair('capabilityId', 'system.set_merchant_category'),
        ),
      );
    },
  );
}
