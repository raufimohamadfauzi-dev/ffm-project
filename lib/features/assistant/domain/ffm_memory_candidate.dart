import 'ffm_memory_type.dart';

/// Kandidat memory yang diambil dari berbagai sumber untuk dinilai relevansinya.
///
/// Setiap kandidat akan melalui proses scoring, filtering, dan deduplication
/// sebelum dimasukkan ke Context Pack.
class FfmMemoryCandidate {
  FfmMemoryCandidate({
    required this.id,
    required this.type,
    required this.key,
    required this.value,
    required this.evidence,
    this.status = FfmMemoryStatus.active,
    this.importance = 0.5,
    this.metadata = const {},
    this.relevanceScore = 0.0,
    this.recencyScore = 0.0,
    this.finalScore = 0.0,
  });

  final String id;
  final FfmMemoryType type;
  final String key; // Canonical key untuk deduplication
  final String value;
  final FfmMemoryEvidence evidence;
  final FfmMemoryStatus status;
  final double importance; // 0.0 - 1.0, beda dari confidence
  final Map<String, dynamic> metadata;

  /// Scoring fields yang akan diisi oleh retrieval engine
  double relevanceScore;
  double recencyScore;
  double finalScore;

  FfmMemoryCandidate copyWith({
    String? id,
    FfmMemoryType? type,
    String? key,
    String? value,
    FfmMemoryEvidence? evidence,
    FfmMemoryStatus? status,
    double? importance,
    Map<String, dynamic>? metadata,
    double? relevanceScore,
    double? recencyScore,
    double? finalScore,
  }) => FfmMemoryCandidate(
    id: id ?? this.id,
    type: type ?? this.type,
    key: key ?? this.key,
    value: value ?? this.value,
    evidence: evidence ?? this.evidence,
    status: status ?? this.status,
    importance: importance ?? this.importance,
    metadata: metadata ?? this.metadata,
    relevanceScore: relevanceScore ?? this.relevanceScore,
    recencyScore: recencyScore ?? this.recencyScore,
    finalScore: finalScore ?? this.finalScore,
  );

  FfmMemoryCandidate withScores({
    required double relevance,
    required double recency,
    required double finalVal,
  }) => FfmMemoryCandidate(
    id: id,
    type: type,
    key: key,
    value: value,
    evidence: evidence,
    status: status,
    importance: importance,
    metadata: metadata,
    relevanceScore: relevance,
    recencyScore: recency,
    finalScore: finalVal,
  );

  /// Cek apakah kandidat ini valid untuk dimasukkan ke context
  bool get isValid {
    if (status == FfmMemoryStatus.archived || 
        status == FfmMemoryStatus.superseded) {
      return false;
    }
    if (evidence.confidence < 0.3) {
      return false;
    }
    return true;
  }

  /// Cek apakah kandidat ini conflict dengan kandidat lain
  bool conflictsWith(FfmMemoryCandidate other) {
    return type == other.type && 
           key == other.key && 
           value != other.value;
  }

  /// Cek apakah kandidat ini adalah duplikat dari kandidat lain
  bool isDuplicateOf(FfmMemoryCandidate other) {
    return type == other.type && 
           key == other.key && 
           value == other.value;
  }
}

/// Candidate memory yang diusulkan untuk dipromosikan menjadi persistent memory.
///
/// Dihasilkan oleh SLM atau pattern extraction, tetapi harus melalui
/// validasi dan approval sebelum menjadi persistent memory.
class FfmMemoryPromotionCandidate {
  const FfmMemoryPromotionCandidate({
    required this.type,
    required this.key,
    required this.value,
    required this.confidence,
    this.reason,
    this.sourceId,
    this.requiresApproval = true,
  });

  final FfmMemoryType type;
  final String key;
  final String value;
  final double confidence;
  final String? reason;
  final String? sourceId;
  final bool requiresApproval;

  FfmMemoryPromotionCandidate copyWith({
    FfmMemoryType? type,
    String? key,
    String? value,
    double? confidence,
    String? reason,
    String? sourceId,
    bool? requiresApproval,
  }) => FfmMemoryPromotionCandidate(
    type: type ?? this.type,
    key: key ?? this.key,
    value: value ?? this.value,
    confidence: confidence ?? this.confidence,
    reason: reason ?? this.reason,
    sourceId: sourceId ?? this.sourceId,
    requiresApproval: requiresApproval ?? this.requiresApproval,
  );

  /// Validasi dasar untuk candidate
  bool get isValid {
    if (confidence < 0.0 || confidence > 1.0) return false;
    final cleanKey = key.trim().toLowerCase();
    final cleanVal = value.trim().toLowerCase();
    if (cleanKey.isEmpty || cleanVal.isEmpty) return false;
    if (cleanVal == 'unknown' ||
        cleanVal == 'null' ||
        cleanVal == 'undefined' ||
        cleanKey == 'unknown') {
      return false;
    }
    return true;
  }

  /// Cek apakah candidate ini berisi data sensitif
  bool get isSensitive {
    final sensitiveKeys = [
      'password', 'pin', 'otp', 'token', 'secret', 'key',
      'nomor_ktp', 'nik', 'nomor_kartu', 'credit_card',
      'cvv', 'expiry', 'security_answer',
    ];
    final lowerKey = key.toLowerCase();
    final lowerValue = value.toLowerCase();
    
    return sensitiveKeys.any((pattern) => 
      lowerKey.contains(pattern) || lowerValue.contains(pattern)
    );
  }
}
