import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/chat/ffm_assistant_message_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'detail JSON tidak tampil otomatis dan tersedia dari menu eksplisit',
    (tester) async {
      final intent = FfmAssistantIntent(
        rawText: 'apa fungsi tag?',
        normalizedText: 'apa fungsi tag',
        type: FfmAssistantIntentType.featureHelp,
        response: 'Tag adalah penanda tambahan transaksi.',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FfmAssistantMessageCard(
              entry: FfmAssistantChatEntry(
                isUser: false,
                text: intent.response!,
                intent: intent,
              ),
              isSpeaking: false,
              teachingSaved: false,
              activityConfirmed: false,
              onShowTechnical: () {},
            ),
          ),
        ),
      );

      expect(find.textContaining('responseMode'), findsNothing);
      expect(find.text('Lihat detail teknis'), findsNothing);

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();

      expect(find.text('Lihat detail teknis'), findsOneWidget);
    },
  );
}
