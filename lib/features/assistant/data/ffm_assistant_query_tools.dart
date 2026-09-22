import '../../../core/database/app_database.dart';

/// Kontrak baca data Asisten. Query tool lokal dihapus agar semua pertanyaan
/// diarahkan ke Gemini Cloud dengan capability yang komprehensif.
class FfmAssistantQueryRequest {
  const FfmAssistantQueryRequest({
    required this.householdId,
    required this.normalizedText,
    required this.parameters,
    required this.now,
    this.conversationHistory = '',
  });

  final String householdId;
  final String normalizedText;
  final Map<String, Object?> parameters;
  final DateTime now;
  final String conversationHistory;
}

class FfmAssistantQueryAnswer {
  const FfmAssistantQueryAnswer({
    required this.title,
    required this.message,
    this.capabilityId,
  });

  final String title;
  final String message;
  final String? capabilityId;
}

abstract interface class FfmAssistantQueryTool {
  bool canHandle(String normalizedText);

  Future<FfmAssistantQueryAnswer?> answer(FfmAssistantQueryRequest request);
}

/// Registry tool baca lokal. Semua query tool lokal dihapus agar semua pertanyaan
/// diarahkan ke Gemini Cloud dengan capability yang komprehensif.
class FfmAssistantQueryRegistry {
  FfmAssistantQueryRegistry(
    AppDatabase database, {
    DateTime Function()? clock,
  }) {
    // Semua query tool lokal dihapus - semua pertanyaan diarahkan ke Gemini Cloud
  }

  Future<FfmAssistantQueryAnswer?> tryAnswer(
    String normalizedText, {
    required String householdId,
    String conversationHistory = '',
  }) async {
    // Semua pertanyaan diarahkan ke Gemini Cloud - return null
    // untuk memicu routing ke Gemini Cloud dengan capability yang komprehensif
    return null;
  }

  Future<FfmAssistantQueryAnswer?> answer(
    String normalizedText, {
    required String householdId,
    String conversationHistory = '',
  }) => tryAnswer(
    normalizedText,
    householdId: householdId,
    conversationHistory: conversationHistory,
  );
}
