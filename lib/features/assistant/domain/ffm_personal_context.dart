import 'ffm_memory_candidate.dart';

/// Personal context yang dikompilasi oleh Personal Context Engine.
///
/// Ini adalah structured output yang akan diteruskan ke reasoning/response layer.
/// Context Engine hanya menghasilkan structured context, bukan prompt final.
class FfmPersonalContext {
  const FfmPersonalContext({
    required this.query,
    required this.normalizedQuery,
    required this.detectedTopic,
    required this.detectedEntities,
    required this.detectedIntent,
    required this.workingContext,
    required this.personalFacts,
    required this.preferences,
    required this.goals,
    required this.behaviorPatterns,
    required this.episodes,
    required this.corrections,
    required this.dataContext,
    required this.responsePreferences,
    required this.capturedAt,
    this.processingMetadata = const {},
  });

  final String query;
  final String normalizedQuery;
  final String? detectedTopic;
  final Map<String, String> detectedEntities;
  final String? detectedIntent;
  
  final List<FfmMemoryCandidate> workingContext;
  final List<FfmMemoryCandidate> personalFacts;
  final List<FfmMemoryCandidate> preferences;
  final List<FfmMemoryCandidate> goals;
  final List<FfmMemoryCandidate> behaviorPatterns;
  final List<FfmMemoryCandidate> episodes;
  final List<FfmMemoryCandidate> corrections;
  
  final FfmDataContext dataContext;
  final FfmResponsePreferences responsePreferences;
  
  final DateTime capturedAt;
  final Map<String, dynamic> processingMetadata;

  FfmPersonalContext copyWith({
    String? query,
    String? normalizedQuery,
    String? detectedTopic,
    Map<String, String>? detectedEntities,
    String? detectedIntent,
    List<FfmMemoryCandidate>? workingContext,
    List<FfmMemoryCandidate>? personalFacts,
    List<FfmMemoryCandidate>? preferences,
    List<FfmMemoryCandidate>? goals,
    List<FfmMemoryCandidate>? behaviorPatterns,
    List<FfmMemoryCandidate>? episodes,
    List<FfmMemoryCandidate>? corrections,
    FfmDataContext? dataContext,
    FfmResponsePreferences? responsePreferences,
    DateTime? capturedAt,
    Map<String, dynamic>? processingMetadata,
  }) => FfmPersonalContext(
    query: query ?? this.query,
    normalizedQuery: normalizedQuery ?? this.normalizedQuery,
    detectedTopic: detectedTopic ?? this.detectedTopic,
    detectedEntities: detectedEntities ?? this.detectedEntities,
    detectedIntent: detectedIntent ?? this.detectedIntent,
    workingContext: workingContext ?? this.workingContext,
    personalFacts: personalFacts ?? this.personalFacts,
    preferences: preferences ?? this.preferences,
    goals: goals ?? this.goals,
    behaviorPatterns: behaviorPatterns ?? this.behaviorPatterns,
    episodes: episodes ?? this.episodes,
    corrections: corrections ?? this.corrections,
    dataContext: dataContext ?? this.dataContext,
    responsePreferences: responsePreferences ?? this.responsePreferences,
    capturedAt: capturedAt ?? this.capturedAt,
    processingMetadata: processingMetadata ?? this.processingMetadata,
  );

  /// Total jumlah memory dalam context
  int get totalMemoryCount => 
    workingContext.length +
    personalFacts.length +
    preferences.length +
    goals.length +
    behaviorPatterns.length +
    episodes.length +
    corrections.length;

  /// Cek apakah context kosong
  bool get isEmpty => totalMemoryCount == 0;
}

/// Context data dari FFM yang diperlukan untuk menjawab query
class FfmDataContext {
  const FfmDataContext({
    this.period,
    this.requiresFinancialSummary = false,
    this.requiresMasterData = false,
    this.requiresRecentTransactions = false,
    this.customRequests = const [],
  });

  final String? period; // e.g., "current_month", "previous_week"
  final bool requiresFinancialSummary;
  final bool requiresMasterData;
  final bool requiresRecentTransactions;
  final List<String> customRequests;

  FfmDataContext copyWith({
    String? period,
    bool? requiresFinancialSummary,
    bool? requiresMasterData,
    bool? requiresRecentTransactions,
    List<String>? customRequests,
  }) => FfmDataContext(
    period: period ?? this.period,
    requiresFinancialSummary: requiresFinancialSummary ?? this.requiresFinancialSummary,
    requiresMasterData: requiresMasterData ?? this.requiresMasterData,
    requiresRecentTransactions: requiresRecentTransactions ?? this.requiresRecentTransactions,
    customRequests: customRequests ?? this.customRequests,
  );
}

/// Response preferences yang diekstrak dari memory pengguna
class FfmResponsePreferences {
  const FfmResponsePreferences({
    this.concise = false,
    this.useIndonesian = true,
    this.showRupiah = true,
    this.clarificationStyle = FfmClarificationStyle.standard,
    this.customStyle = const {},
  });

  final bool concise;
  final bool useIndonesian;
  final bool showRupiah;
  final FfmClarificationStyle clarificationStyle;
  final Map<String, dynamic> customStyle;

  FfmResponsePreferences copyWith({
    bool? concise,
    bool? useIndonesian,
    bool? showRupiah,
    FfmClarificationStyle? clarificationStyle,
    Map<String, dynamic>? customStyle,
  }) => FfmResponsePreferences(
    concise: concise ?? this.concise,
    useIndonesian: useIndonesian ?? this.useIndonesian,
    showRupiah: showRupiah ?? this.showRupiah,
    clarificationStyle: clarificationStyle ?? this.clarificationStyle,
    customStyle: customStyle ?? this.customStyle,
  );
}

enum FfmClarificationStyle {
  standard,
  minimal,
  detailed,
}

/// Working context untuk tracking percakapan aktif.
///
/// Bisa di-serialize ke/dari JSON untuk persistensi lintas sesi.
class FfmWorkingContext {
  const FfmWorkingContext({
    this.lastUserIntent,
    this.lastReferencedEntity,
    this.currentTopic,
    this.currentPeriod,
    this.currentGoal,
    this.lastActivityId,
    this.lastActivityTitle,
    this.pendingClarification,
    this.lastActionResult,
    this.lastUpdatedAt,
  });

  final String? lastUserIntent;
  final String? lastReferencedEntity;
  final String? currentTopic;
  final String? currentPeriod;
  final String? currentGoal;
  final String? lastActivityId;
  final String? lastActivityTitle;
  final String? pendingClarification;
  final String? lastActionResult;
  final DateTime? lastUpdatedAt;

  FfmWorkingContext copyWith({
    String? lastUserIntent,
    String? lastReferencedEntity,
    String? currentTopic,
    String? currentPeriod,
    String? currentGoal,
    String? lastActivityId,
    String? lastActivityTitle,
    String? pendingClarification,
    String? lastActionResult,
    DateTime? lastUpdatedAt,
  }) => FfmWorkingContext(
    lastUserIntent: lastUserIntent ?? this.lastUserIntent,
    lastReferencedEntity: lastReferencedEntity ?? this.lastReferencedEntity,
    currentTopic: currentTopic ?? this.currentTopic,
    currentPeriod: currentPeriod ?? this.currentPeriod,
    currentGoal: currentGoal ?? this.currentGoal,
    lastActivityId: lastActivityId ?? this.lastActivityId,
    lastActivityTitle: lastActivityTitle ?? this.lastActivityTitle,
    pendingClarification: pendingClarification ?? this.pendingClarification,
    lastActionResult: lastActionResult ?? this.lastActionResult,
    lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
  );

  FfmWorkingContext clear() => const FfmWorkingContext();

  Map<String, dynamic> toJson() => {
    if (lastUserIntent != null) 'lastUserIntent': lastUserIntent,
    if (lastReferencedEntity != null) 'lastReferencedEntity': lastReferencedEntity,
    if (currentTopic != null) 'currentTopic': currentTopic,
    if (currentPeriod != null) 'currentPeriod': currentPeriod,
    if (currentGoal != null) 'currentGoal': currentGoal,
    if (lastActivityId != null) 'lastActivityId': lastActivityId,
    if (lastActivityTitle != null) 'lastActivityTitle': lastActivityTitle,
    if (pendingClarification != null) 'pendingClarification': pendingClarification,
    if (lastActionResult != null) 'lastActionResult': lastActionResult,
    if (lastUpdatedAt != null) 'lastUpdatedAt': lastUpdatedAt!.toIso8601String(),
  };

  factory FfmWorkingContext.fromJson(Map<String, dynamic> json) {
    return FfmWorkingContext(
      lastUserIntent: json['lastUserIntent'] as String?,
      lastReferencedEntity: json['lastReferencedEntity'] as String?,
      currentTopic: json['currentTopic'] as String?,
      currentPeriod: json['currentPeriod'] as String?,
      currentGoal: json['currentGoal'] as String?,
      lastActivityId: json['lastActivityId'] as String?,
      lastActivityTitle: json['lastActivityTitle'] as String?,
      pendingClarification: json['pendingClarification'] as String?,
      lastActionResult: json['lastActionResult'] as String?,
      lastUpdatedAt: json['lastUpdatedAt'] is String
          ? DateTime.tryParse(json['lastUpdatedAt'] as String)
          : null,
    );
  }

  /// Apakah context ini masih relevan (tidak lebih dari 24 jam)?
  bool get isExpired {
    if (lastUpdatedAt == null) return true;
    return DateTime.now().difference(lastUpdatedAt!).inHours > 24;
  }
}
