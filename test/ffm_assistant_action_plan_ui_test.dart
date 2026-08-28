import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_work_item.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/chat/ffm_assistant_message_card.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/chat/ffm_assistant_message_toolbar.dart';

/// Helper untuk membungkus widget dalam MaterialApp tanpa dependensi GetIt.
Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('error Gemini menyediakan aksi coba lagi', (tester) async {
    const intent = FfmAssistantIntent(
      rawText: 'cek ringkasan',
      normalizedText: 'cek ringkasan',
      type: FfmAssistantIntentType.unknown,
      responseOrigin: FfmAssistantResponseOrigin.cloudError,
    );
    var retried = false;

    await tester.pumpWidget(
      _wrap(
        FfmAssistantMessageCard(
          entry: const FfmAssistantChatEntry(
            isUser: false,
            text: 'Gemini tidak tersedia.',
            intent: intent,
          ),
          isSpeaking: false,
          teachingSaved: false,
          activityConfirmed: false,
          primaryActionLabel: 'Coba lagi',
          onIntent: () => retried = true,
        ),
      ),
    );

    await tester.tap(find.text('Coba lagi'));
    expect(retried, isTrue);
  });

  testWidgets(
    'FfmAssistantMessageCard menampilkan tombol Buka dengan ikon open_in_new untuk intent dengan draft',
    (tester) async {
      final intent = FfmAssistantIntent(
        rawText: 'catat gaji',
        normalizedText: 'catat gaji',
        type: FfmAssistantIntentType.createIncome,
        destination: FfmAssistantDestination.transactions,
        draft: FfmAssistantDraft(
          kind: FfmAssistantDraftKind.income,
          amount: 5000000,
          createdAt: DateTime(2026, 8, 23),
        ),
      );

      final review = FfmAssistantDraftReview(
        draft: intent.draft!,
        version: 1,
        issues: const [],
      );

      final entry = FfmAssistantChatEntry(
        isUser: false,
        text: 'Ini draft gaji.',
        intent: intent,
        review: review,
      );

      var handled = false;

      await tester.pumpWidget(
        _wrap(
          FfmAssistantMessageCard(
            entry: entry,
            isSpeaking: false,
            onIntent: () {
              handled = true;
            },
            primaryActionLabel: 'Konfirmasi',
            review: review,
            teachingSaved: false,
            activityConfirmed: false,
            onCopyText: () {},
          ),
        ),
      );

      // Tombol Buka (open_in_new) harus ada dan aktif
      final openButton = find.byIcon(Icons.open_in_new);
      expect(openButton, findsOneWidget);

      final buttonWidget = tester.widget<FilledButton>(
        find.ancestor(of: openButton, matching: find.byType(FilledButton)),
      );
      expect(buttonWidget.onPressed, isNotNull);

      // Menjalankan callback langsung
      buttonWidget.onPressed?.call();
      await tester.pump();

      expect(handled, isTrue);
    },
  );

  testWidgets('aksi Buka lintas halaman tersedia tanpa draft', (tester) async {
    final intent = FfmAssistantIntent(
      rawText: 'buka anggaran',
      normalizedText: 'buka anggaran',
      type: FfmAssistantIntentType.openPage,
      destination: FfmAssistantDestination.budget,
    );

    final entry = FfmAssistantChatEntry(
      isUser: false,
      text: 'Aku bisa membuka Anggaran.',
      intent: intent,
    );

    var handled = false;

    await tester.pumpWidget(
      _wrap(
        FfmAssistantMessageCard(
          entry: entry,
          isSpeaking: false,
          onIntent: () {
            handled = true;
          },
          primaryActionLabel: 'Buka',
          teachingSaved: false,
          activityConfirmed: false,
          onCopyText: () {},
        ),
      ),
    );

    expect(find.text('Buka'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Buka'), matching: find.byType(FilledButton)),
    );
    expect(button.onPressed, isNotNull);
    button.onPressed?.call();
    await tester.pump();
    expect(handled, isTrue);
  });

  testWidgets(
    'halaman aktif memakai aksi Cek halaman, bukan menghilangkan tombol',
    (tester) async {
      final intent = FfmAssistantIntent(
        rawText: 'cek anggaran',
        normalizedText: 'cek anggaran',
        type: FfmAssistantIntentType.financialWarnings,
        destination: FfmAssistantDestination.budget,
      );

      final entry = FfmAssistantChatEntry(
        isUser: false,
        text: 'Kamu sudah di Anggaran.',
        intent: intent,
      );

      await tester.pumpWidget(
        _wrap(
          FfmAssistantMessageCard(
            entry: entry,
            isSpeaking: false,
            onIntent: () {},
            primaryActionLabel: 'Cek halaman',
            teachingSaved: false,
            activityConfirmed: false,
            onCopyText: () {},
          ),
        ),
      );

      expect(find.text('Cek halaman'), findsOneWidget);
    },
  );

  testWidgets(
    'FfmAssistantMessageToolbar tidak menampilkan tombol Buka saat hasPrimaryAction false',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FfmAssistantMessageToolbar(
            isUser: false,
            hasPrimaryAction: false,
            primaryActionLabel: 'Buka',
            activityConfirmed: false,
            isSpeaking: false,
            teachingSaved: false,
            foregroundColor: Colors.black,
          ),
        ),
      );

      expect(find.text('Buka'), findsNothing);
      expect(find.byIcon(Icons.open_in_new), findsNothing);
    },
  );

  testWidgets('ringkasan pemahaman menampilkan jumlah draft yang benar',
      (tester) async {
    final workItems = [
      FfmAssistantWorkItem(
        id: 'work_1',
        intent: FfmAssistantIntentType.createExpense,
        targetDestination: FfmAssistantDestination.transactions,
        confidence: FfmAssistantWorkItemConfidence.high,
        knownFields: const [],
        unknownFields: const [],
        ambiguousFields: const [],
      ),
      FfmAssistantWorkItem(
        id: 'work_2',
        intent: FfmAssistantIntentType.createBudget,
        targetDestination: FfmAssistantDestination.budget,
        confidence: FfmAssistantWorkItemConfidence.low,
        knownFields: const [],
        unknownFields: const ['amount'],
        ambiguousFields: const [],
        clarificationQuestion: 'Berapa nominal anggaran?',
      ),
    ];

    final result = FfmAssistantUnderstandingResult(
      workItems: workItems,
      intents: const [],
      rawText: 'catat makan lalu buat anggaran',
      normalizedText: 'catat makan lalu buat anggaran',
    );

    expect(result.summary, contains('2 pekerjaan'));
    expect(result.hasReadyItems, isTrue);
    expect(result.needsClarification, isTrue);
  });

  testWidgets('ringkasan pemahaman kosong saat tidak ada work item',
      (tester) async {
    final result = const FfmAssistantUnderstandingResult(
      workItems: [],
      intents: [],
      rawText: 'pesan tidak valid',
      normalizedText: 'pesan tidak valid',
    );

    expect(result.summary, contains('Tidak ada pekerjaan'));
    expect(result.hasReadyItems, isFalse);
    expect(result.needsClarification, isFalse);
  });

  testWidgets('loading state ditampilkan saat streaming aktif', (tester) async {
    final intent = FfmAssistantIntent(
      rawText: 'cek ringkasan',
      normalizedText: 'cek ringkasan',
      type: FfmAssistantIntentType.queryData,
      response: 'Memproses...',
      responseOrigin: FfmAssistantResponseOrigin.agentOrchestrator,
    );

    await tester.pumpWidget(
      _wrap(
        FfmAssistantMessageCard(
          entry: FfmAssistantChatEntry(
            isUser: false,
            text: 'Memproses...',
            intent: intent,
          ),
          visibleText: 'Memproses...',
          isStreaming: true,
          isSpeaking: false,
          teachingSaved: false,
          activityConfirmed: false,
          onCopyText: () {},
        ),
      ),
    );

    // Streaming state is indicated by isStreaming flag
    // The widget should render without error
    expect(find.text('Memproses...'), findsOneWidget);
  });

  testWidgets('error provider menampilkan pesan dan tombol coba lagi',
      (tester) async {
    const intent = FfmAssistantIntent(
      rawText: 'cek ringkasan',
      normalizedText: 'cek ringkasan',
      type: FfmAssistantIntentType.unknown,
      response: 'Gemini tidak tersedia saat ini.',
      responseOrigin: FfmAssistantResponseOrigin.cloudError,
    );

    var retried = false;

    await tester.pumpWidget(
      _wrap(
        FfmAssistantMessageCard(
          entry: const FfmAssistantChatEntry(
            isUser: false,
            text: 'Gemini tidak tersedia saat ini.',
            intent: intent,
          ),
          isSpeaking: false,
          teachingSaved: false,
          activityConfirmed: false,
          primaryActionLabel: 'Coba lagi',
          onIntent: () => retried = true,
          onRetryGemini: () => retried = true,
          onCopyText: () {},
        ),
      ),
    );

    expect(find.text('Gemini tidak tersedia saat ini.'), findsOneWidget);
    expect(find.text('Coba lagi'), findsOneWidget);

    await tester.tap(find.text('Coba lagi'));
    expect(retried, isTrue);
  });
}
