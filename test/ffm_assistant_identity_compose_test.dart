import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_answer_composer.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_self_description.dart';

class _FakeComposer implements FfmAssistantAnswerComposer {
  _FakeComposer({this.result, this.error});

  final String? result;
  final Object? error;
  int callCount = 0;

  @override
  Future<String?> composeGroundedAnswer({
    required String question,
    required String facts,
  }) async {
    callCount++;
    final failure = error;
    if (failure != null) throw failure;
    return result;
  }
}

void main() {
  AppDatabase freshDb() => createInMemoryDatabaseForTests();

  test(
    'identitas aplikasi dijawab dari deskripsi resmi tanpa composer lokal',
    () async {
      final db = freshDb();
      addTearDown(db.close);
      final composer = _FakeComposer(
        result: 'Pembuat FFM adalah Rafi Sinkkat. Dia juga aktif di YouTube.',
      );
      final interpreter = FfmAssistantInterpreter(
        db,
        slmReadyCheck: () async => true,
        answerComposer: composer,
      );

      final intent = await interpreter.interpret('siapa pembuat aplikasi');

      expect(composer.callCount, 0);
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
    'composer lokal tidak dipakai dan deskripsi resmi tetap tersedia',
    () async {
      final db = freshDb();
      addTearDown(db.close);
      final composer = _FakeComposer(result: null);
      final interpreter = FfmAssistantInterpreter(
        db,
        slmReadyCheck: () async => true,
        answerComposer: composer,
      );

      final intent = await interpreter.interpret('siapa developer fmm');

      expect(composer.callCount, 0);
      expect(intent.responseMode, FfmAssistantResponseMode.localRules);
      expect(
        intent.response,
        contains(FfmAssistantSelfDescriptionService.creatorName),
      );
    },
  );

  test('exception composer lokal tidak memengaruhi deskripsi resmi', () async {
    final db = freshDb();
    addTearDown(db.close);
    final composer = _FakeComposer(error: Exception('native crash'));
    final interpreter = FfmAssistantInterpreter(
      db,
      slmReadyCheck: () async => true,
      answerComposer: composer,
    );

    final intent = await interpreter.interpret('kamu bisa apa');

    expect(composer.callCount, 0);
    expect(intent.responseMode, FfmAssistantResponseMode.localRules);
    expect(intent.response, contains('catat transaksi'));
  });

  test('provider lokal tidak dipakai untuk identitas aplikasi', () async {
    final db = freshDb();
    addTearDown(db.close);
    final composer = _FakeComposer(result: 'jawaban seharusnya tidak dipakai');
    final interpreter = FfmAssistantInterpreter(
      db,
      slmReadyCheck: () async => false,
      answerComposer: composer,
    );

    final intent = await interpreter.interpret('aplikasi apa ini');

    expect(composer.callCount, 0);
    expect(intent.responseMode, FfmAssistantResponseMode.localRules);
    expect(intent.confidence, 1);
  });

  test(
    'rangkuman tanpa link dilengkapi otomatis untuk pertanyaan pembuat',
    () async {
      final db = freshDb();
      addTearDown(db.close);
      final composer = _FakeComposer(
        result: 'Pembuat aplikasi ini adalah Rafi Sinkkat.',
      );
      final interpreter = FfmAssistantInterpreter(
        db,
        slmReadyCheck: () async => true,
        answerComposer: composer,
      );

      final intent = await interpreter.interpret('siapa pembuat aplikasi');

      expect(
        intent.response,
        contains(FfmAssistantSelfDescriptionService.creatorYouTube),
      );
      expect(
        intent.response,
        contains(FfmAssistantSelfDescriptionService.creatorTikTok),
      );
      expect(
        intent.response,
        contains('](${FfmAssistantSelfDescriptionService.creatorYouTube})'),
      );
    },
  );

  test('pertanyaan kemampuan tidak disisipi link pembuat', () async {
    final db = freshDb();
    addTearDown(db.close);
    final composer = _FakeComposer(result: 'Aku bisa bantu catat transaksi.');
    final interpreter = FfmAssistantInterpreter(
      db,
      slmReadyCheck: () async => true,
      answerComposer: composer,
    );

    final intent = await interpreter.interpret('asisten bisa apa saja');

    expect(
      intent.response,
      isNot(contains(FfmAssistantSelfDescriptionService.creatorYouTube)),
    );
    expect(intent.response, contains('catat transaksi'));
  });

  group('FfmAssistantComposedAnswerContract.sanitize', () {
    test('menerima teks normal dan memangkas newline berlebih', () {
      final out = FfmAssistantComposedAnswerContract.sanitize(
        'Jawaban pertama.\n\n\n\nParagraf kedua.',
      );
      expect(out, 'Jawaban pertama.\n\nParagraf kedua.');
    });

    test('menolak output terlalu pendek', () {
      expect(FfmAssistantComposedAnswerContract.sanitize('oke'), isNull);
    });

    test('menolak output JSON meski instruksi melarang', () {
      expect(
        FfmAssistantComposedAnswerContract.sanitize(
          '{"answer":"Pembuatnya Rafi"}',
        ),
        isNull,
      );
    });

    test('menolak output lebih panjang dari batas aman', () {
      final rambling = 'a' * 1300;
      expect(FfmAssistantComposedAnswerContract.sanitize(rambling), isNull);
    });

    test('membungkus tanda kutip dan code fence dibersihkan', () {
      expect(
        FfmAssistantComposedAnswerContract.sanitize('"Jawaban rapi."'),
        'Jawaban rapi.',
      );
      expect(
        FfmAssistantComposedAnswerContract.sanitize(
          '```\nJawaban tanpa fence.\n```',
        ),
        'Jawaban tanpa fence.',
      );
    });
  });
}
