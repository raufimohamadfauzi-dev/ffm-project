import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_learning_candidate_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_memory_repository.dart';

void main() {
  test('workflow candidate tetap pending sampai disetujui user', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final service = FfmAssistantLearningCandidateService(
      FfmAssistantMemoryRepository(database),
    );

    final candidate = await service.proposeWorkflow(
      trigger: 'catat makan kantor',
      steps: const [
        {'capability': 'draft.expense', 'category': 'Makan'},
        {'capability': 'mutate.save_draft'},
      ],
    );

    expect(candidate.isPending, isTrue);
    expect(await service.readApproved(), isEmpty);
    expect((await service.readPending()).single.trigger, 'catat makan kantor');

    final approved = await service.approve(candidate);
    expect(approved.isApproved, isTrue);
    expect((await service.readApproved()).single.workflowJson['version'], 1);
    expect(await service.readPending(), isEmpty);
  });

  test('workflow candidate dapat ditolak tanpa menjadi aktif', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final service = FfmAssistantLearningCandidateService(
      FfmAssistantMemoryRepository(database),
    );

    final candidate = await service.proposeWorkflow(
      trigger: 'hapus semua data',
      steps: const [
        {'capability': 'sensitive.delete'},
      ],
    );
    await service.reject(candidate);

    expect(await service.readPending(), isEmpty);
    expect(await service.readApproved(), isEmpty);
  });
}
