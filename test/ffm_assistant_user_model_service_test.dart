import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_memory_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_user_model_service.dart';

void main() {
  test(
    'user model menyimpan preferensi approved dan membangun context lokal',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      final service = FfmAssistantUserModelService(
        FfmAssistantMemoryRepository(database),
      );

      final saved = await service.saveApproved(
        kind: 'preference',
        key: 'gaya ringkasan',
        value: 'singkat',
        confidence: .9,
      );

      expect(saved.approved, isTrue);
      expect(saved.confidence, .9);
      expect(
        await service.buildContext(query: 'ringkasan'),
        contains('singkat'),
      );

      await service.forget(saved.id);
      expect(await service.buildContext(), isEmpty);
    },
  );
}
