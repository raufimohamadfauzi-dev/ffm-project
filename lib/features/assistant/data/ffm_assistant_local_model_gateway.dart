import '../domain/ffm_assistant_models.dart';

/// Gaya v54: model bahasa hanya boleh memberi proposal pemahaman, bukan
/// melakukan aksi atau menyimpan data. Parser FFM tetap sumber keputusan aman.
class FfmAssistantModelProposal {
  const FfmAssistantModelProposal({
    required this.intent,
    required this.confidence,
    this.draft,
    this.missingFields = const [],
    this.extractedFields = const <String, String>{},
    this.suggestedCapabilities = const <String>[],
    this.clarification,
    this.reasoning,
    this.actionTarget,
    this.queryId,
    this.notes,
    this.needsReviewBadge = false,
  });

  final FfmAssistantIntentType intent;
  final double confidence;
  final FfmAssistantDraft? draft;
  final List<String> missingFields;
  final Map<String, String> extractedFields;
  final List<String> suggestedCapabilities;
  final String? clarification;
  final String? reasoning;

  /// Opaque allow-listed target, never interpreted as a route without local validation.
  final String? actionTarget;

  /// Stable query identifier; query execution remains deterministic and local.
  final String? queryId;
  final String? notes;
  final bool needsReviewBadge;

  bool get isUsable => confidence >= 0.78;
}

abstract class FfmAssistantLocalModelGateway {
  /// Mengembalikan null bila model belum diinstal, tidak kompatibel, atau
  /// proposal tidak dapat dipercaya. Pemanggil wajib memakai parser lokal.
  Future<FfmAssistantModelProposal?> propose({required String input});

  /// Versi ber-konteks untuk planner. Implementasi lama tetap aman karena
  /// default-nya meneruskan input ke kontrak proposal yang sudah diaudit.
  Future<FfmAssistantModelProposal?> proposeWithContext({
    required String input,
    String? pageContext,
    String? conversationHistory,
    List<String> capabilityIds = const <String>[],
    List<String> activeAccountNames = const <String>[],
    List<String> activeCategoryNames = const <String>[],
  }) => propose(input: input);
}

/// Implementasi aman sebelum runtime SLM benar-benar dipilih dan diaudit.
/// Keberadaan file model bukan izin untuk memproses data finansial secara
/// otomatis; proposal model tetap harus divalidasi oleh interpreter FFM.
class FfmAssistantDisabledLocalModelGateway
    implements FfmAssistantLocalModelGateway {
  const FfmAssistantDisabledLocalModelGateway();

  @override
  Future<FfmAssistantModelProposal?> propose({required String input}) async {
    // Sengaja tidak menjalankan atau membuka file model: runtime SLM dipasang
    // pada rilis terpisah setelah format model dan evaluasi FFM ditetapkan.
    return null;
  }

  @override
  Future<FfmAssistantModelProposal?> proposeWithContext({
    required String input,
    String? pageContext,
    String? conversationHistory,
    List<String> capabilityIds = const <String>[],
    List<String> activeAccountNames = const <String>[],
    List<String> activeCategoryNames = const <String>[],
  }) => propose(input: input);
}
