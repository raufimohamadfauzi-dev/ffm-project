import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_task_execution_host.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantAutonomyRepository repository;
  late FfmAssistantAutonomyTaskExecutionHost host;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = FfmAssistantAutonomyRepository(database);
    host = FfmAssistantAutonomyTaskExecutionHost(
      database: database,
      repository: repository,
      adapters: FfmAssistantCapabilityAdapterRegistry(
        database: database,
        householdId: FfmAssistantAutonomyRepository.householdId,
      ),
    );
  });

  tearDown(() => database.close());

  test('host mengeksekusi read-only melalui adapter registry', () async {
    final result = await host.execute(
      FfmAssistantActionPlan(
        id: 'host-read-plan',
        summary: 'Baca ringkasan',
        createdAt: DateTime(2026, 9, 1),
        steps: const [
          FfmAssistantActionStep(id: 'read-step', capabilityId: 'read.summary'),
        ],
      ),
    );

    expect(result?.status, FfmAssistantActionPlanStatus.completed);
  });

  test('host memblokir mutation yang belum memiliki verification', () async {
    final result = await host.execute(
      FfmAssistantActionPlan(
        id: 'host-mutation-plan',
        summary: 'Mutation tanpa approval',
        createdAt: DateTime(2026, 9, 1),
        requiresConfirmation: true,
        steps: const [
          FfmAssistantActionStep(
            id: 'mutation-step',
            capabilityId: 'mutate.save_draft',
          ),
        ],
      ),
    );

    expect(result?.status, FfmAssistantActionPlanStatus.blocked);
  });
}
