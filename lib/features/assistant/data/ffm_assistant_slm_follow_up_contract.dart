import 'dart:convert';

abstract interface class FfmAssistantSlmFollowUpGenerator {
  Future<List<String>> generateFollowUpSuggestions({
    required List<String> conversationTopics,
  });
}

class FfmAssistantSlmFollowUpContract {
  const FfmAssistantSlmFollowUpContract._();

  static List<String> parseJsonResponse(String response) {
    try {
      final decoded = jsonDecode(response);
      if (decoded is! Map<String, dynamic>) return const <String>[];
      return validateStrings(decoded['suggestions']);
    } on FormatException {
      return const <String>[];
    }
  }

  static List<String> validateStrings(Object? raw) {
    if (raw is! List || raw.length != 3) return const <String>[];
    final values = raw
        .whereType<String>()
        .map((value) => value.trim())
        .toList(growable: false);
    if (values.length != 3) return const <String>[];
    final canonical = values.map((value) => value.toLowerCase()).toSet();
    if (canonical.length != 3 ||
        values.any((value) => !_isSafeQuestion(value))) {
      return const <String>[];
    }
    return values;
  }

  static bool _isSafeQuestion(String value) {
    if (value.length < 6 || value.length > 140 || !value.endsWith('?')) {
      return false;
    }
    final lower = value.toLowerCase();
    return !RegExp(
          r'(https?://|www\.|javascript:|data:|file:|\b(rp|idr)\s*\d|\d{5,})',
        ).hasMatch(lower) &&
        !lower.contains('hapus semua') &&
        !lower.contains('simpan otomatis') &&
        !lower.contains('langsung simpan');
  }
}
