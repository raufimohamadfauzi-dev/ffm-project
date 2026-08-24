import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/chat/ffm_assistant_message_card.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/chat/ffm_assistant_message_toolbar.dart';

/// Helper untuk membungkus widget dalam MaterialApp tanpa dependensi GetIt.
Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
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
}
