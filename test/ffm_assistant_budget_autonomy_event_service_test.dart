import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_worker.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_budget_autonomy_event_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_budget_autonomy_repository.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_budget_autonomy_service.dart';
import 'package:ffm_manager/features/budget/data/budget_repository.dart';

void main() {
  const householdId = 'household-budget-autonomy';
  final now = DateTime(2026, 9, 17, 9);
  late AppDatabase database;
  late FfmAssistantAutonomyRepository eventRepository;
  late FfmAssistantBudgetAutonomyRepository delegationRepository;
  late FfmAssistantBudgetAutonomyEventService eventService;
  late FfmAssistantAutonomyWorker worker;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    eventRepository = FfmAssistantAutonomyRepository(database, now: () => now);
    delegationRepository = FfmAssistantBudgetAutonomyRepository(database);
    final budgetRepository = BudgetRepository(
      database,
      AuditLogger(database),
      clock: () => now,
    );
    eventService = FfmAssistantBudgetAutonomyEventService(
      eventRepository: eventRepository,
      delegationRepository: delegationRepository,
      budgetRepository: budgetRepository,
      budgetAutonomyService: FfmAssistantBudgetAutonomyService(
        database,
        budgetRepository,
        delegationRepository,
        clock: () => now,
      ),
      clock: () => now,
    );
    worker = FfmAssistantAutonomyWorker(
      repository: eventRepository,
      database: database,
      budgetAutonomyEventService: eventService,
    );
    await database
        .into(database.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'food',
            householdId: householdId,
            name: 'Makan',
            type: 'expense',
            createdAt: now,
          ),
        );
    await database
        .into(database.envelopeBudgets)
        .insert(
          EnvelopeBudgetsCompanion.insert(
            id: 'budget-food',
            householdId: householdId,
            categoryId: const Value('food'),
            categoryIdsJson: const Value('["food"]'),
            name: 'Makan',
            allocated: const Value(100000),
            alertPercent: const Value(80),
            periodType: const Value('monthly'),
            startDate: DateTime(2026, 9, 1),
            endDate: DateTime(2026, 9, 30),
            createdAt: now,
          ),
        );
    await database
        .into(database.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: 'food-spend',
            householdId: householdId,
            type: 'expense',
            amount: -90000,
            categoryId: const Value('food'),
            date: now,
            recordedAt: now,
            createdAt: now,
          ),
        );
  });

  tearDown(() => database.close());

  Future<void> delegate({int maxAdjustmentAmount = 30000}) =>
      delegationRepository.saveDelegation(
        id: 'food-delegation',
        householdId: householdId,
        budgetId: 'budget-food',
        status: FfmAssistantBudgetDelegationStatus.active.name,
        maxAdjustmentAmount: maxAdjustmentAmount,
        maxAllocatedAmount: 150000,
        maxExecutions: 2,
        createdAt: now,
        updatedAt: now,
      );

  Future<int> allocated() async => (await (database.select(
    database.envelopeBudgets,
  )..where((row) => row.id.equals('budget-food'))).getSingle()).allocated;

  test('no delegation or ineligible candidate does not write', () async {
    await worker.runOnce((_) async {
      fail('Budget events must not reach the generic autonomy handler.');
    }, householdId: householdId);
    expect(await allocated(), 100000);
    expect(
      await database.select(database.budgetAutonomyExecutionLedgers).get(),
      isEmpty,
    );

    await delegate(maxAdjustmentAmount: 5000);
    await worker.runOnce((_) async {
      fail('No ineligible budget event should be dispatched.');
    }, householdId: householdId);
    expect(await allocated(), 100000);
    expect(
      await database.select(database.budgetAutonomyExecutionLedgers).get(),
      isEmpty,
    );
  });

  test(
    'valid delegated alert candidate writes once through the event worker',
    () async {
      await delegate();
      var genericCalls = 0;

      final first = await worker.runOnce(
        (_) async => genericCalls++,
        householdId: householdId,
      );
      final second = await worker.runOnce(
        (_) async => genericCalls++,
        householdId: householdId,
      );

      final ledger = await database
          .select(database.budgetAutonomyExecutionLedgers)
          .get();
      expect(first.enqueued, 1);
      expect(first.processed, 1);
      expect(second.enqueued, 0);
      expect(await allocated(), 112500);
      expect(ledger, hasLength(1));
      expect(
        ledger.single.idempotencyKey,
        'budget-autonomy:alert-threshold:food-delegation:budget-food:r0',
      );
      expect(genericCalls, 0);
    },
  );

  test(
    'retrying a delegated event is idempotent and generic events are unchanged',
    () async {
      await delegate();
      await eventService.enqueueCandidates(householdId: householdId);
      final event = (await eventRepository.pendingEvents(
        householdId: householdId,
      )).single;

      await eventRepository.processEvent(event, eventService.handle);
      final retry = await eventRepository.processEvent(
        event,
        eventService.handle,
      );
      var genericCalls = 0;
      final genericEvent = FfmAssistantAutonomyEvent(
        id: 'ordinary-read-only-event',
        type: 'reminder.due',
        occurredAt: now,
        householdId: householdId,
      );
      await eventRepository.enqueueEvent(genericEvent);
      await worker.runOnce((event) async {
        if (event.id == genericEvent.id) genericCalls++;
      }, householdId: householdId);

      expect(retry, FfmAssistantAutonomyEventProcessResult.duplicate);
      expect(await allocated(), 112500);
      expect(
        await database.select(database.budgetAutonomyExecutionLedgers).get(),
        hasLength(1),
      );
      expect(genericCalls, 1);
    },
  );
}
