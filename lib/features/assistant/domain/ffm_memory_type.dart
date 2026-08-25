/// Tipe-tipe memory yang dikelola oleh Personal Context Engine.
///
/// Setiap tipe memiliki lifecycle, confidence threshold, dan retrieval behavior
/// yang berbeda sesuai spesifikasi FFM Personal Memory & Context Engine.
enum FfmMemoryType {
  /// Fakta relatif stabil tentang pengguna
  /// Contoh: preferred_name, occupation, language, currency, household_role
  identity,

  /// Cara pengguna ingin Assistant bekerja
  /// Contoh: response_style, currency_format, preferred_language
  preference,

  /// Fakta yang pengguna sendiri nyatakan dan setujui
  /// Contoh: payday, monthly_food_limit, preferred_account
  explicitFact,

  /// Tujuan aktif dengan lifecycle
  /// Contoh: menabung 10 juta sebelum Desember
  goal,

  /// Kebiasaan yang disimpulkan dari pola penggunaan
  /// Contoh: user biasanya mencatat transaksi malam hari
  habit,

  /// Pola data yang teramati dari behavior
  /// Contoh: merchant "Indomaret" biasanya category = kebutuhan rumah
  behavioralPattern,

  /// Ringkasan kejadian yang mungkin relevan di masa depan
  /// Contoh: Pada 2026-08-20 pengguna meminta bantuan menurunkan pengeluaran makan
  episodic,

  /// Konteks percakapan aktif (tidak persistent)
  /// Contoh: Topik aktif, periode, target, pertanyaan sebelumnya
  working,

  /// Koreksi eksplisit pengguna dengan bobot tinggi
  /// Contoh: "Indomaret jangan masukkan ke belanja pribadi, itu biasanya kebutuhan rumah"
  correction,

  /// Rekomendasi yang pernah diberikan Assistant
  /// Contoh: Assistant pernah menyarankan user membatasi makan di luar
  assistantRecommendation,
}

/// Status lifecycle untuk memory yang memiliki lifecycle khusus (seperti goal, habit)
enum FfmMemoryStatus {
  /// Memory aktif dan dapat digunakan dalam context
  active,

  /// Memory tidak aktif sementara (untuk habit yang jarang digunakan)
  paused,

  /// Memory sudah selesai (untuk goal yang sudah tercapai)
  completed,

  /// Memory dibatalkan (untuk goal yang dibatalkan pengguna)
  cancelled,

  /// Memory sudah tidak relevan/usang
  stale,

  /// Memory diarsipkan dan tidak lagi aktif
  archived,

  /// Memory digantikan oleh memory baru yang lebih baru
  superseded,
}

/// Sumber evidence untuk memory
enum FfmMemorySource {
  /// Pengguna secara eksplisit menyatakan dan menyetujui
  userExplicit,

  /// Koreksi eksplisit dari pengguna
  userCorrection,

  /// Pattern yang sudah cukup kuat dan disetujui
  approvedPattern,

  /// Pattern yang disimpulkan dari data tetapi belum disetujui
  inferredPattern,

  /// Dari percakapan sebelumnya
  conversation,

  /// Pattern dari transaksi/behavior
  transactionPattern,

  /// Goal yang dibuat pengguna
  goal,

  /// Dari sistem (default values, dll)
  system,

  /// Rekomendasi dari Assistant
  assistantRecommendation,
}

/// Metadata evidence untuk tracking keaslian dan confidence memory
class FfmMemoryEvidence {
  const FfmMemoryEvidence({
    required this.source,
    this.sourceId,
    this.sourceType,
    required this.createdAt,
    required this.updatedAt,
    this.confidence = 0.0,
    this.approved = false,
    this.lastUsedAt,
    this.useCount = 0,
  });

  final FfmMemorySource source;
  final String? sourceId;
  final String? sourceType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double confidence; // 0.0 - 1.0
  final bool approved;
  final DateTime? lastUsedAt;
  final int useCount;

  FfmMemoryEvidence copyWith({
    FfmMemorySource? source,
    String? sourceId,
    String? sourceType,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? confidence,
    bool? approved,
    DateTime? lastUsedAt,
    int? useCount,
  }) => FfmMemoryEvidence(
    source: source ?? this.source,
    sourceId: sourceId ?? this.sourceId,
    sourceType: sourceType ?? this.sourceType,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    confidence: confidence ?? this.confidence,
    approved: approved ?? this.approved,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    useCount: useCount ?? this.useCount,
  );

  FfmMemoryEvidence markUsed() => FfmMemoryEvidence(
    source: source,
    sourceId: sourceId,
    sourceType: sourceType,
    createdAt: createdAt,
    updatedAt: updatedAt,
    confidence: confidence,
    approved: approved,
    lastUsedAt: DateTime.now(),
    useCount: useCount + 1,
  );
}
