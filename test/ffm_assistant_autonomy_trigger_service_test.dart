import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_trigger_service.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantAutonomyRepository repository;
  late FfmAssistantAutonomyTriggerService service;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = FfmAssistantAutonomyRepository(database);
    service = FfmAssistantAutonomyTriggerService(repository);
  });

  tearDown(() => database.close());

  test('trigger memakai household dan ID deduplikasi yang stabil', () async {
    final occurredAt = DateTime(2026, 9, 1, 12);
    final first = await service.emit(
      triggerId: 'reminder-1',
      type: 'reminder.due',
      householdId: 'household-b',
      occurredAt: occurredAt,
      payload: const {'reminderId': 'r-1'},
    );
    final duplicate = await service.emit(
      triggerId: 'reminder-1',
      type: 'reminder.due',
      householdId: 'household-b',
      occurredAt: occurredAt,
    );

    expect(first, isTrue);
    expect(duplicate, isFalse);
    final events = await repository.pendingEvents(householdId: 'household-b');
    expect(events, hasLength(1));
    expect(events.single.householdId, 'household-b');
    expect(events.single.payload['reminderId'], 'r-1');
  });

  test(
    'trigger membuang field sensitif dan membatasi metadata payload',
    () async {
      final accepted = await service.emit(
        triggerId: 'safe-1',
        type: 'database.changed',
        householdId: 'household-a',
        occurredAt: DateTime(2026, 9, 1),
        payload: {
          'entityId': 'asset-1',
          'prompt': 'jangan simpan',
          'accessToken': 'jangan simpan',
          'count': 2,
          'nested': {'secret': 'jangan simpan'},
        },
      );

      final event = (await repository.pendingEvents(householdId: 'household-a'))
          .single;
      expect(accepted, isTrue);
      expect(event.payload, {'entityId': 'asset-1', 'count': 2});
    },
  );
}
