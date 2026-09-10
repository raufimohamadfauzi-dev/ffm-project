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

  test('issue dengan sourceMessageId tidak bisa diduplikasi dan bisa dibuka lagi setelah dihapus', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = FfmAssistantResponseFeedbackRepository(database);

    final first = await repository.record(
      questionText: 'Berapa saldo kas likuid?',
      responseText: 'Jawaban belum sesuai.',
      kind: FfmAssistantResponseFeedbackKind.assistantIssue,
      sourceMessageId: 'message-1',
      issueMetadata: const {
        'responseOrigin': 'geminiCloud',
        'usedReadCapability': 'read.summary',
      },
    );
    final duplicate = await repository.record(
      questionText: 'Berapa saldo kas likuid?',
      responseText: 'Jawaban lain.',
      kind: FfmAssistantResponseFeedbackKind.assistantIssue,
      sourceMessageId: 'message-1',
      issueMetadata: const {'usedReadCapability': 'read.summary'},
    );

    expect(first, isNotNull);
    expect(duplicate!.id, first!.id);
    expect((await repository.readAllIssues()), hasLength(1));
    expect(
      (await repository.readAllIssues())
          .single
          .issueMetadata['usedReadCapability'],
      'read.summary',
    );

    await repository.delete(first.id);
    expect(await repository.readAllIssues(), isEmpty);
    final afterDelete = await repository.record(
      questionText: 'Berapa saldo kas likuid?',
      responseText: 'Jawaban sudah diperbaiki.',
      kind: FfmAssistantResponseFeedbackKind.assistantIssue,
      sourceMessageId: 'message-1',
      issueMetadata: const {'usedReadCapability': 'read.summary'},
    );
    expect(afterDelete, isNotNull);
    expect(afterDelete!.id, isNot(first.id));

    final copied = await repository.exportAllIssues();
    expect(copied, contains('Developer atau agent coding'));
    expect(copied, contains('Implementasikan perbaikan'));
    expect(copied, contains('read.summary'));

    final jsonReport = jsonDecode(
      await repository.exportAllIssuesJson(),
    ) as Map<String, dynamic>;
    expect(jsonReport['formatVersion'], 'ffm-assistant-issue-log-v1');
    expect(jsonReport['instructions'], isNotEmpty);
    expect((jsonReport['issues'] as List), hasLength(1));
  });

  test(
    'catatan issue dapat diperbarui tanpa mengubah metadata sumber',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      final repository = FfmAssistantResponseFeedbackRepository(database);

      final issue = await repository.record(
        questionText: 'Cek saldo kas',
        responseText: 'Jawaban perlu diperiksa.',
        kind: FfmAssistantResponseFeedbackKind.assistantIssue,
        sourceMessageId: 'message-note',
        issueMetadata: const {'usedReadCapability': 'read.summary'},
      );
      expect(issue, isNotNull);

      await repository.updateIssueNote(
        issue!.id,
        'Gunakan saldo transaksi aktif.',
      );

      final updated = await repository.findBySourceMessageId('message-note');
      expect(updated!.note, 'Gunakan saldo transaksi aktif.');
      expect(updated.issueMetadata['usedReadCapability'], 'read.summary');
    },
  );
}
