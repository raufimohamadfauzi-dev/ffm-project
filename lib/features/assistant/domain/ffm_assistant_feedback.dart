/// Feedback Model untuk Assistant Responses
/// 
/// Model ini menyimpan feedback user terhadap response assistant
/// untuk analisis dan improvement di masa depan.
library;

enum FfmAssistantFeedbackType {
  /// User likes the response
  thumbsUp,
  
  /// User dislikes the response
  thumbsDown,
  
  /// User marked response as incorrect
  incorrect,
  
  /// User reported an issue with the response
  issue,
  
  /// User provided a correction suggestion
  correction,
}

enum FfmAssistantFeedbackCategory {
  /// Response was factually incorrect
  factual,
  
  /// Response was confusing or unclear
  confusing,
  
  /// Response was helpful
  helpful,
  
  /// Response had hallucination
  hallucination,
  
  /// Response missed context
  missingContext,
  
  /// Response had other issues
  other,
}

class FfmAssistantFeedback {
  const FfmAssistantFeedback({
    required this.id,
    required this.householdId,
    required this.userQuery,
    required this.assistantResponse,
    required this.type,
    required this.category,
    required this.createdAt,
    this.correction,
    this.note,
    this.verifiedFacts,
    this.analysisResults,
    this.intentType,
  });

  final String id;
  final String householdId;
  final String userQuery;
  final String assistantResponse;
  final FfmAssistantFeedbackType type;
  final FfmAssistantFeedbackCategory category;
  final DateTime createdAt;
  
  /// User's correction suggestion (for correction type)
  final String? correction;
  
  /// Additional note from user
  final String? note;
  
  /// Verified facts that were used (for context)
  final String? verifiedFacts;
  
  /// Analysis results that were used (for context)
  final String? analysisResults;
  
  /// Intent type that was classified
  final String? intentType;

  FfmAssistantFeedback copyWith({
    String? id,
    String? householdId,
    String? userQuery,
    String? assistantResponse,
    FfmAssistantFeedbackType? type,
    FfmAssistantFeedbackCategory? category,
    DateTime? createdAt,
    String? correction,
    String? note,
    String? verifiedFacts,
    String? analysisResults,
    String? intentType,
  }) {
    return FfmAssistantFeedback(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      userQuery: userQuery ?? this.userQuery,
      assistantResponse: assistantResponse ?? this.assistantResponse,
      type: type ?? this.type,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      correction: correction ?? this.correction,
      note: note ?? this.note,
      verifiedFacts: verifiedFacts ?? this.verifiedFacts,
      analysisResults: analysisResults ?? this.analysisResults,
      intentType: intentType ?? this.intentType,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'householdId': householdId,
      'userQuery': userQuery,
      'assistantResponse': assistantResponse,
      'type': type.name,
      'category': category.name,
      'createdAt': createdAt.toIso8601String(),
      'correction': correction,
      'note': note,
      'verifiedFacts': verifiedFacts,
      'analysisResults': analysisResults,
      'intentType': intentType,
    };
  }

  static FfmAssistantFeedback fromJson(Map<String, dynamic> json) {
    return FfmAssistantFeedback(
      id: json['id'] as String,
      householdId: json['householdId'] as String,
      userQuery: json['userQuery'] as String,
      assistantResponse: json['assistantResponse'] as String,
      type: FfmAssistantFeedbackType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => FfmAssistantFeedbackType.issue,
      ),
      category: FfmAssistantFeedbackCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => FfmAssistantFeedbackCategory.other,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      correction: json['correction'] as String?,
      note: json['note'] as String?,
      verifiedFacts: json['verifiedFacts'] as String?,
      analysisResults: json['analysisResults'] as String?,
      intentType: json['intentType'] as String?,
    );
  }
}
