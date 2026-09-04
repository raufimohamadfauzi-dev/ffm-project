import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_self_description.dart';

void main() {
  AppDatabase freshDb() => createInMemoryDatabaseForTests();

  test(
    'identitas aplikasi dijawab dari deskripsi resmi',
    () async {
      final db = freshDb();
      addTearDown(db.close);
      final interpreter = FfmAssistantInterpreter(db);

      final intent = await interpreter.interpret('siapa pembuat aplikasi');

      expect(intent.type, FfmAssistantIntentType.assistantIdentity);
      expect(
        intent.response,
        contains(FfmAssistantSelfDescriptionService.creatorName),
      );
      expect(intent.responseMode, FfmAssistantResponseMode.localRules);
      expect(
        intent.responseOrigin,
        FfmAssistantResponseOrigin.agentOrchestrator,
      );
      expect(intent.draft, isNull);
    },
  );

  test(
    'deskripsi resmi tetap tersedia untuk developer fmm',
    () async {
      final db = freshDb();
      addTearDown(db.close);
      final interpreter = FfmAssistantInterpreter(db);

      final intent = await interpreter.interpret('siapa developer fmm');

      expect(intent.responseMode, FfmAssistantResponseMode.localRules);
      expect(
        intent.response,
        contains(FfmAssistantSelfDescriptionService.creatorName),
      );
    },
  );

  test('penjelasan kemampuan asisten', () async {
    final db = freshDb();
    addTearDown(db.close);
    final interpreter = FfmAssistantInterpreter(db);

    final intent = await interpreter.interpret('kamu bisa apa');

    expect(intent.responseMode, FfmAssistantResponseMode.localRules);
    expect(intent.response, contains('catat transaksi'));
  });

  test('pertanyaan identitas aplikasi', () async {
    final db = freshDb();
    addTearDown(db.close);
    final interpreter = FfmAssistantInterpreter(db);

    final intent = await interpreter.interpret('aplikasi apa ini');

    expect(intent.responseMode, FfmAssistantResponseMode.localRules);
    expect(intent.confidence, 1);
  });
}
