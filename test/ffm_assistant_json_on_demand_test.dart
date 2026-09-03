import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/chat/ffm_assistant_message_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('JSON Data Utama tag menghasilkan draft dengan field yang relevan', () {
    final result = FfmAssistantProposalJsonService.parse(
      '{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"master_data","target":"tag","name":"Keluarga","fields":{},"note":"Pengeluaran keluarga"}}',
      createdAt: DateTime(2026, 8, 31),
    );

    expect(result.error, isNull);
    expect(result.draft?.kind, FfmAssistantDraftKind.masterData);
    expect(result.draft?.categoryName, 'tag');
    expect(result.draft?.title, 'Keluarga');
    expect(result.draft?.formValues, isEmpty);
  });

  test('JSON Data Utama tag tanpa nama meminta data wajib', () {
    final result = FfmAssistantProposalJsonService.parse(
      '{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"master_data","target":"tag","fields":{}}}',
      createdAt: DateTime(2026, 8, 31),
    );

    expect(result.draft, isNull);
    expect(result.error, contains('nama wajib'));
  });

  test('JSON transaksi membawa toko dan tag ke draft', () {
    final result = FfmAssistantProposalJsonService.parse(
      '{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"transaction","kind":"expense","amount":25000,"title":"Belanja pupuk","fromAccount":"Tunai","category":"Pertanian","merchant":"Toko Tani","tags":"cabai, pupuk"}}',
      createdAt: DateTime(2026, 8, 31),
    );

    expect(result.error, isNull);
    expect(result.draft?.kind, FfmAssistantDraftKind.expense);
    expect(result.draft?.merchantName, 'Toko Tani');
    expect(result.draft?.formValues['tags'], 'cabai,pupuk');
  });

  test('JSON transaksi menolak nominal desimal yang ambigu', () {
    final result = FfmAssistantProposalJsonService.parse(
      '{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"transaction","kind":"expense","amount":1.5,"fromAccount":"Tunai"}}',
      createdAt: DateTime(2026, 8, 31),
    );

    expect(result.draft, isNull);
    expect(result.error, contains('nominal'));
  });

  test('JSON proposal tetap terbaca saat LLM menambahkan teks pembuka', () {
    final result = FfmAssistantProposalJsonService.parse(
      'Berikut data transaksi:\n{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"transaction","kind":"expense","amount":25000}}\nSilakan cek kembali.',
      createdAt: DateTime(2026, 8, 31),
    );

    expect(result.error, isNull);
    expect(result.draft?.amount, 25000);
  });

  test('JSON transaksi membawa Data Utama baru ke preview yang sama', () {
    final result = FfmAssistantProposalJsonService.parse(
      '{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"transaction","kind":"expense","amount":25000,"fromAccount":"Tunai","merchant":"Toko Tani Baru","newMerchant":"Toko Tani Baru","tags":"pupuk","newTags":"pupuk"}}',
      createdAt: DateTime(2026, 8, 31),
    );

    expect(result.error, isNull);
    expect(result.draft?.merchantName, 'Toko Tani Baru');
    expect(
      result.draft?.formValues,
      containsPair('newMerchant', 'Toko Tani Baru'),
    );
    expect(result.draft?.formValues, containsPair('newTags', 'pupuk'));
  });

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
              onToggleTechnicalDetails: () {},
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
