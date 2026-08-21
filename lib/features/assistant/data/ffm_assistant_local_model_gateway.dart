import '../domain/ffm_assistant_models.dart';

/// Gaya v54: model bahasa hanya boleh memberi proposal pemahaman, bukan
/// melakukan aksi atau menyimpan data. Parser FFM tetap sumber keputusan aman.
class FfmAssistantModelProposal {
  const FfmAssistantModelProposal({
    required this.intent,
    required this.confidence,
    this.missingFields = const [],
    this.notes,
  });

  final FfmAssistantIntentType intent;
  final double confidence;
  final List<String> missingFields;
  final String? notes;

  bool get isUsable => confidence >= 0.85;
}

abstract class FfmAssistantLocalModelGateway {
  /// Mengembalikan null bila model belum diinstal, tidak kompatibel, atau
  /// proposal tidak dapat dipercaya. Pemanggil wajib memakai parser lokal.
  Future<FfmAssistantModelProposal?> propose({
    required String input,
    required List<String> knownAccountNames,
  });
}

/// Implementasi aman sebelum runtime SLM benar-benar dipilih dan diaudit.
/// Keberadaan file model bukan izin untuk memproses data finansial secara
/// otomatis; proposal model tetap harus divalidasi oleh interpreter FFM.
class FfmAssistantDisabledLocalModelGateway
    implements FfmAssistantLocalModelGateway {
  const FfmAssistantDisabledLocalModelGateway();

  @override
  Future<FfmAssistantModelProposal?> propose({
    required String input,
    required List<String> knownAccountNames,
  }) async {
    // Sengaja tidak menjalankan atau membuka file model: runtime SLM dipasang
    // pada rilis terpisah setelah format model dan evaluasi FFM ditetapkan.
    return null;
  }
}
