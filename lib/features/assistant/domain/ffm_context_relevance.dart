import 'ffm_memory_candidate.dart';

/// Model untuk relevance scoring dan context budget management.
///
/// Menggunakan multi-factor scoring sesuai spesifikasi:
/// - semanticOrLexicalMatch (30%)
/// - topicMatch (20%)
/// - entityMatch (15%)
/// - recency (10%)
/// - importance (10%)
/// - confidence (5%)
/// - goalRelevance (5%)
/// - usageFrequency (5%)

class FfmContextRelevanceScore {
  const FfmContextRelevanceScore({
    this.semanticOrLexicalMatch = 0.0,
    this.topicMatch = 0.0,
    this.entityMatch = 0.0,
    this.recency = 0.0,
    this.importance = 0.0,
    this.confidence = 0.0,
    this.goalRelevance = 0.0,
    this.usageFrequency = 0.0,
  });

  final double semanticOrLexicalMatch; // 0.0 - 1.0
  final double topicMatch; // 0.0 - 1.0
  final double entityMatch; // 0.0 - 1.0
  final double recency; // 0.0 - 1.0 (decay score)
  final double importance; // 0.0 - 1.0
  final double confidence; // 0.0 - 1.0
  final double goalRelevance; // 0.0 - 1.0
  final double usageFrequency; // 0.0 - 1.0

  /// Bobot default sesuai spesifikasi
  static const defaultWeights = FfmContextRelevanceWeights(
    semanticOrLexicalMatch: 0.30,
    topicMatch: 0.20,
    entityMatch: 0.15,
    recency: 0.10,
    importance: 0.10,
    confidence: 0.05,
    goalRelevance: 0.05,
    usageFrequency: 0.05,
  );

  /// Hitung final score dengan bobot
  double calculateFinalScore([FfmContextRelevanceWeights? weights]) {
    final w = weights ?? defaultWeights;
    return (semanticOrLexicalMatch * w.semanticOrLexicalMatch) +
           (topicMatch * w.topicMatch) +
           (entityMatch * w.entityMatch) +
           (recency * w.recency) +
           (importance * w.importance) +
           (confidence * w.confidence) +
           (goalRelevance * w.goalRelevance) +
           (usageFrequency * w.usageFrequency);
  }

  FfmContextRelevanceScore copyWith({
    double? semanticOrLexicalMatch,
    double? topicMatch,
    double? entityMatch,
    double? recency,
    double? importance,
    double? confidence,
    double? goalRelevance,
    double? usageFrequency,
  }) => FfmContextRelevanceScore(
    semanticOrLexicalMatch: semanticOrLexicalMatch ?? this.semanticOrLexicalMatch,
    topicMatch: topicMatch ?? this.topicMatch,
    entityMatch: entityMatch ?? this.entityMatch,
    recency: recency ?? this.recency,
    importance: importance ?? this.importance,
    confidence: confidence ?? this.confidence,
    goalRelevance: goalRelevance ?? this.goalRelevance,
    usageFrequency: usageFrequency ?? this.usageFrequency,
  );
}

/// Bobot untuk setiap faktor relevance
class FfmContextRelevanceWeights {
  const FfmContextRelevanceWeights({
    required this.semanticOrLexicalMatch,
    required this.topicMatch,
    required this.entityMatch,
    required this.recency,
    required this.importance,
    required this.confidence,
    required this.goalRelevance,
    required this.usageFrequency,
  });

  final double semanticOrLexicalMatch;
  final double topicMatch;
  final double entityMatch;
  final double recency;
  final double importance;
  final double confidence;
  final double goalRelevance;
  final double usageFrequency;

  FfmContextRelevanceWeights copyWith({
    double? semanticOrLexicalMatch,
    double? topicMatch,
    double? entityMatch,
    double? recency,
    double? importance,
    double? confidence,
    double? goalRelevance,
    double? usageFrequency,
  }) => FfmContextRelevanceWeights(
    semanticOrLexicalMatch: semanticOrLexicalMatch ?? this.semanticOrLexicalMatch,
    topicMatch: topicMatch ?? this.topicMatch,
    entityMatch: entityMatch ?? this.entityMatch,
    recency: recency ?? this.recency,
    importance: importance ?? this.importance,
    confidence: confidence ?? this.confidence,
    goalRelevance: goalRelevance ?? this.goalRelevance,
    usageFrequency: usageFrequency ?? this.usageFrequency,
  );
}

/// Budget untuk setiap tipe memory dalam context pack
class FfmContextBudget {
  const FfmContextBudget({
    this.workingMemoryMax = 8,
    this.personalFactsMax = 8,
    this.preferencesMax = 5,
    this.goalsMax = 5,
    this.behaviorPatternsMax = 8,
    this.episodesMax = 5,
    this.correctionsMax = 5,
    this.maxTotalItems = 50,
  });

  final int workingMemoryMax;
  final int personalFactsMax;
  final int preferencesMax;
  final int goalsMax;
  final int behaviorPatternsMax;
  final int episodesMax;
  final int correctionsMax;
  final int maxTotalItems;

  FfmContextBudget copyWith({
    int? workingMemoryMax,
    int? personalFactsMax,
    int? preferencesMax,
    int? goalsMax,
    int? behaviorPatternsMax,
    int? episodesMax,
    int? correctionsMax,
    int? maxTotalItems,
  }) => FfmContextBudget(
    workingMemoryMax: workingMemoryMax ?? this.workingMemoryMax,
    personalFactsMax: personalFactsMax ?? this.personalFactsMax,
    preferencesMax: preferencesMax ?? this.preferencesMax,
    goalsMax: goalsMax ?? this.goalsMax,
    behaviorPatternsMax: behaviorPatternsMax ?? this.behaviorPatternsMax,
    episodesMax: episodesMax ?? this.episodesMax,
    correctionsMax: correctionsMax ?? this.correctionsMax,
    maxTotalItems: maxTotalItems ?? this.maxTotalItems,
  );
}

/// Result dari conflict resolution
class FfmConflictResolution {
  const FfmConflictResolution({
    required this.resolved,
    required this.selectedCandidate,
    this.rejectedCandidates = const [],
    this.requiresClarification = false,
    this.clarificationMessage,
  });

  final bool resolved;
  final FfmMemoryCandidate? selectedCandidate;
  final List<FfmMemoryCandidate> rejectedCandidates;
  final bool requiresClarification;
  final String? clarificationMessage;

  FfmConflictResolution copyWith({
    bool? resolved,
    FfmMemoryCandidate? selectedCandidate,
    List<FfmMemoryCandidate>? rejectedCandidates,
    bool? requiresClarification,
    String? clarificationMessage,
  }) => FfmConflictResolution(
    resolved: resolved ?? this.resolved,
    selectedCandidate: selectedCandidate ?? this.selectedCandidate,
    rejectedCandidates: rejectedCandidates ?? this.rejectedCandidates,
    requiresClarification: requiresClarification ?? this.requiresClarification,
    clarificationMessage: clarificationMessage ?? this.clarificationMessage,
  );
}
