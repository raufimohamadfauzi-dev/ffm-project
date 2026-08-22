import 'dart:convert';

import '../domain/ffm_assistant_models.dart';
import 'ffm_assistant_local_model_gateway.dart';

/// Kontrak paket classifier intent ringan yang dibuat di komputer pengembang.
/// Paket ini hanya mengenali arah perintah, bukan menyimpan atau mengeksekusi
/// transaksi. Parser deterministik FFM tetap menetapkan hasil akhir.
class FfmAssistantIntentClassifierManifest {
  const FfmAssistantIntentClassifierManifest({
    required this.formatVersion,
    required this.modelFile,
    required this.sha256,
    required this.labels,
    required this.minimumConfidence,
  });

  static const format = 'ffm-assistant-intent-classifier-v1';

  final String formatVersion;
  final String modelFile;
  final String sha256;
  final List<String> labels;
  final double minimumConfidence;

  bool get isCompatible {
    if (formatVersion != format ||
        modelFile.trim().isEmpty ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256.toLowerCase()) ||
        minimumConfidence < .85 ||
        minimumConfidence > 1) {
      return false;
    }
    final allowed = FfmAssistantIntentType.values
        .map((intent) => intent.name)
        .toSet();
    return labels.isNotEmpty && labels.every(allowed.contains);
  }

  factory FfmAssistantIntentClassifierManifest.fromJsonText(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException(
        'Manifest classifier harus berupa objek JSON.',
      );
    }
    final map = decoded.map((key, value) => MapEntry('$key', value));
    final labels = (map['labels'] as List? ?? const [])
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final confidence = map['minimumConfidence'];
    final manifest = FfmAssistantIntentClassifierManifest(
      formatVersion: '${map['formatVersion'] ?? ''}',
      modelFile: '${map['modelFile'] ?? ''}',
      sha256: '${map['sha256'] ?? ''}',
      labels: labels,
      minimumConfidence: confidence is num
          ? confidence.toDouble()
          : double.tryParse('$confidence') ?? 0,
    );
    if (!manifest.isCompatible) {
      throw const FormatException(
        'Manifest classifier tidak kompatibel atau belum aman dipakai.',
      );
    }
    return manifest;
  }

  Map<String, dynamic> toJson() => {
    'formatVersion': formatVersion,
    'modelFile': modelFile,
    'sha256': sha256,
    'labels': labels,
    'minimumConfidence': minimumConfidence,
  };
}

/// Menjaga proposal model tetap di jalur aman. Proposal yang tidak tercantum
/// pada manifest, tidak cocok hash-nya, atau kurang yakin selalu dibuang.
abstract final class FfmAssistantIntentClassifierSafety {
  static FfmAssistantModelProposal? acceptProposal({
    required FfmAssistantIntentClassifierManifest manifest,
    required String installedSha256,
    required String intentLabel,
    required double confidence,
    List<String> missingFields = const [],
    String? notes,
  }) {
    if (!manifest.isCompatible ||
        installedSha256.toLowerCase() != manifest.sha256.toLowerCase() ||
        confidence < manifest.minimumConfidence ||
        !manifest.labels.contains(intentLabel)) {
      return null;
    }
    FfmAssistantIntentType? intent;
    for (final candidate in FfmAssistantIntentType.values) {
      if (candidate.name == intentLabel) {
        intent = candidate;
        break;
      }
    }
    if (intent == null) return null;
    return FfmAssistantModelProposal(
      intent: intent,
      confidence: confidence,
      missingFields: missingFields,
      notes: notes,
    );
  }
}
