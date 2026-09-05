import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_chat_history_repository.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  group('FfmAssistantChatHistoryRepository suggestedQuestions', () {
    late FfmAssistantChatHistoryRepository repository;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repository = FfmAssistantChatHistoryRepository();
    });

    test('serializes and deserializes suggestedQuestions correctly', () async {
      final entries = [
        const FfmAssistantChatEntry(
          isUser: true,
          text: 'Berapa sisa panen jagung?',
        ),
        const FfmAssistantChatEntry(
          isUser: false,
          text: 'Sisa panen sekitar 20 hari lagi.',
          suggestedQuestions: [
            'Berapa sisa runway kas sampai panen?',
            'Kapan perkiraan tanggal panen berikutnya?',
            'Bagaimana cara menekan biaya pupuk?',
          ],
        ),
      ];

      await repository.save(entries);
      final loaded = await repository.load();

      expect(loaded.length, equals(2));
      expect(loaded[0].isUser, isTrue);
      expect(loaded[0].suggestedQuestions, isEmpty);

      expect(loaded[1].isUser, isFalse);
      expect(loaded[1].suggestedQuestions.length, equals(3));
      expect(loaded[1].suggestedQuestions[0], contains('runway'));
      expect(loaded[1].suggestedQuestions[1], contains('panen'));
      expect(loaded[1].suggestedQuestions[2], contains('pupuk'));
    });

    test('handles legacy entries without suggestedQuestions gracefully', () async {
      final legacyJson = '''
      [
        {"isUser": false, "text": "Jawaban lama tanpa saran pertanyaan"}
      ]
      ''';
      SharedPreferences.setMockInitialValues({
        'ffm_assistant_chat_history_v1': legacyJson,
      });

      final loaded = await repository.load();
      expect(loaded.length, equals(1));
      expect(loaded[0].text, equals('Jawaban lama tanpa saran pertanyaan'));
      expect(loaded[0].suggestedQuestions, isEmpty);
    });
  });
}
