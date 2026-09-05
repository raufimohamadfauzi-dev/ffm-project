import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/chat/ffm_assistant_message_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets(
    'metadata waktu dan model tersembunyi dan muncul saat bubble ditekan',
    (tester) async {
      final entry = FfmAssistantChatEntry(
        isUser: false,
        text: 'Jawaban asisten.',
        sentAt: DateTime(2026, 9, 5, 9, 12, 5),
        receivedAt: DateTime(2026, 9, 5, 9, 12, 9),
        modelUsed: 'gemini-cloud',
      );

      await tester.pumpWidget(
        _wrap(
          FfmAssistantMessageCard(
            entry: entry,
            isSpeaking: false,
            teachingSaved: false,
            activityConfirmed: false
          ),
        ),
      );

      expect(find.textContaining('Kirim 09:12:05'), findsNothing);
      expect(find.textContaining('Terima 09:12:09'), findsNothing);
      expect(find.textContaining('gemini-cloud'), findsNothing);

await tester.tap(find.text('Jawaban asisten.'));
      await tester.pump();

      expect(find.textContaining('Kirim 09:12:05'), findsOneWidget);
      expect(find.textContaining('Terima 09:12:09'), findsOneWidget);
      expect(find.textContaining('gemini-cloud'), findsOneWidget);
    },
  );

  testWidgets(
    'metadata bubble user menampilkan waktu kirim tanpa waktu terima',
    (tester) async {
      final entry = FfmAssistantChatEntry(
        isUser: true,
        text: 'Cek saldo',
        sentAt: DateTime(2026, 9, 5, 9, 12, 5),
        modelUsed: 'user',
      );

      await tester.pumpWidget(
        _wrap(
          FfmAssistantMessageCard(
            entry: entry,
            isSpeaking: false,
            teachingSaved: false,
            activityConfirmed: false
          ),
        ),
      );

await tester.tap(find.text('Cek saldo'));
      await tester.pump();

      expect(find.textContaining('Kirim 09:12:05'), findsOneWidget);
      expect(find.textContaining('Terima'), findsNothing);
      expect(find.textContaining('user'), findsOneWidget);
    },
  );
}
