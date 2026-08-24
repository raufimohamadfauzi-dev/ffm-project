import 'package:ffm_manager/features/assistant/data/ffm_assistant_slm_follow_up_contract.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_slm_follow_up_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGenerator implements FfmAssistantSlmFollowUpGenerator {
  _FakeGenerator(this.response, {this.error});

  final List<String> response;
  final Object? error;
  List<String> receivedTopics = const <String>[];

  @override
  Future<List<String>> generateFollowUpSuggestions({
    required List<String> conversationTopics,
  }) async {
    receivedTopics = conversationTopics;
    if (error != null) throw error!;
    return response;
  }
}

void main() {
  test(
    'tanpa SLM atau saat SLM error tidak menghasilkan rekomendasi fallback',
    () async {
      final unavailable = FfmAssistantSlmFollowUpService(
        _FakeGenerator(const <String>[]),
      );
      final errored = FfmAssistantSlmFollowUpService(
        _FakeGenerator(const <String>[], error: StateError('model sibuk')),
      );
      const entries = [
        FfmAssistantChatEntry(isUser: true, text: 'Cek anggaran'),
      ];

      expect(await unavailable.generateForConversation(entries), isEmpty);
      expect(await errored.generateForConversation(entries), isEmpty);
    },
  );

  test(
    'hanya meneruskan tepat tiga pertanyaan SLM yang aman dan unik',
    () async {
      final generator = _FakeGenerator(const <String>[
        'Bagaimana status anggaran saat ini?',
        'Kategori mana yang ingin diperiksa?',
        'Periode apa yang ingin dilihat?',
      ]);
      final service = FfmAssistantSlmFollowUpService(generator);
      const entries = [
        FfmAssistantChatEntry(isUser: true, text: 'Pengeluaran saya Rp 125000'),
        FfmAssistantChatEntry(
          isUser: false,
          text: 'Aku dapat memeriksa data lokal.',
        ),
      ];

      final suggestions = await service.generateForConversation(entries);

      expect(suggestions, hasLength(3));
      expect(generator.receivedTopics.join(' '), isNot(contains('125000')));
      expect(
        generator.receivedTopics.join(' '),
        contains('[angka disembunyikan]'),
      );
    },
  );

  test(
    'output salah, URL, duplikat, atau kurang dari tiga tidak digunakan',
    () {
      expect(
        FfmAssistantSlmFollowUpContract.parseJsonResponse(
          '{"suggestions":["Cek anggaran?","Cek anggaran?","Lihat lagi?"]}',
        ),
        isEmpty,
      );
      expect(
        FfmAssistantSlmFollowUpContract.validateStrings(const <String>[
          'Buka https://contoh.test?',
          'Apa kategori utama?',
          'Bagaimana periode ini?',
        ]),
        isEmpty,
      );
      expect(
        FfmAssistantSlmFollowUpContract.validateStrings(const <String>[
          'Apa yang perlu diperiksa?',
          'Bagaimana status data utama?',
        ]),
        isEmpty,
      );
    },
  );
}
