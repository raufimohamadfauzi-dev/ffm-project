import '../domain/ffm_assistant_models.dart';
import 'ffm_assistant_slm_follow_up_contract.dart';

class FfmAssistantSlmFollowUpService {
  const FfmAssistantSlmFollowUpService(this._generator);

  final FfmAssistantSlmFollowUpGenerator _generator;

  Future<List<String>> generateForConversation(
    List<FfmAssistantChatEntry> entries,
  ) async {
    final topics = entries
        .where((entry) => entry.text.trim().isNotEmpty)
        .toList(growable: false)
        .reversed
        .take(4)
        .toList(growable: false)
        .reversed
        .map(_sanitizeTopic)
        .where((topic) => topic.isNotEmpty)
        .toList(growable: false);
    try {
      final generated = await _generator.generateFollowUpSuggestions(
        conversationTopics: topics,
      );
      return FfmAssistantSlmFollowUpContract.validateStrings(generated);
    } on Object {
      return const <String>[];
    }
  }

  String _sanitizeTopic(FfmAssistantChatEntry entry) {
    var text = entry.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    text = text.replaceAll(
      RegExp(r'\b(?:rp|idr)\s*[0-9.]+\b|\b\d{5,}\b', caseSensitive: false),
      '[angka disembunyikan]',
    );
    if (text.length > 220) text = '${text.substring(0, 220)}…';
    return '${entry.isUser ? 'Pengguna' : 'Asisten'}: $text';
  }
}
