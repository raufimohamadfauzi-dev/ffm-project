import 'dart:convert';

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

  test('ekspor hanya memuat feedback yang sudah disetujui', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = FfmAssistantResponseFeedbackRepository(database);
    final approved = await repository.record(
      questionText: 'Apa fungsi anggaran?',
      responseText: 'Jawaban belum cukup jelas.',
      kind: FfmAssistantResponseFeedbackKind.incomplete,
    );
    await repository.record(
      questionText: 'Apa fungsi target?',
      responseText: 'Jawaban keliru.',
      kind: FfmAssistantResponseFeedbackKind.incorrect,
    );
    await repository.setReviewStatus(
      approved!.id,
      FfmAssistantResponseFeedbackReviewStatus.approved,
    );

    final exported = jsonDecode(
      await repository.exportApprovedForExternalReview(),
    ) as Map<String, dynamic>;

    expect(exported['formatVersion'], 'ffm-assistant-response-feedback-v1');
    expect(exported['feedback'], hasLength(1));
    expect(
      (exported['feedback'] as List).single['question'],
      'Apa fungsi anggaran?',
    );
  });
}
