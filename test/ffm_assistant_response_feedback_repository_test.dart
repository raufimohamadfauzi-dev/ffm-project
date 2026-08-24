import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_response_feedback_repository.dart';

void main() {
  test(
    'feedback jawaban disanitasi dan masuk antrean review tanpa auto-approve',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      final repository = FfmAssistantResponseFeedbackRepository(
        database,
        clock: () => DateTime(2026, 8, 24, 10),
      );

      final feedback = await repository.record(
        questionText: 'catat belanja Rafi Rp 120.000',
        responseText: 'Saya belum bisa memproses Rp 120.000 untuk Rafi',
        kind: FfmAssistantResponseFeedbackKind.incorrect,
        note: 'Jawaban seharusnya meminta klarifikasi kategori.',
        pageContext: 'transactions',
        protectedTerms: const ['Rafi'],
      );

      expect(feedback, isNotNull);
      expect(feedback!.questionText, contains('<ENTITAS>'));
      expect(feedback.questionText, contains('<NOMINAL>'));
      expect(
        feedback.reviewStatus,
        FfmAssistantResponseFeedbackReviewStatus.pending,
      );
      expect((await repository.readPending()).single.id, feedback.id);

      await repository.setReviewStatus(
        feedback.id,
        FfmAssistantResponseFeedbackReviewStatus.approved,
      );

      expect(await repository.readPending(), isEmpty);
    },
  );

  test('feedback kosong atau terlalu panjang ditolak tanpa write', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = FfmAssistantResponseFeedbackRepository(database);

    final feedback = await repository.record(
      questionText: '',
      responseText: 'jawaban',
      kind: FfmAssistantResponseFeedbackKind.unhelpful,
    );

    expect(feedback, isNull);
    expect(
      await database.select(database.assistantResponseFeedbacks).get(),
      isEmpty,
    );
  });
}
