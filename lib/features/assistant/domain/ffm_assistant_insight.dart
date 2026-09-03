import 'dart:convert';
import 'ffm_assistant_models.dart';

enum FfmAssistantInsightType {
  runwayRisk,
  envelopeRebalance,
  anomalySpike,
  microExpenseLeak,
  debtServiceRatio,
  goalProgressRisk,
  budgetAlert,
}

enum FfmAssistantInsightSeverity {
  info,
  caution,
  warning,
  critical,
}

enum FfmAssistantInsightStatus {
  newInsight,
  seen,
  dismissed,
  snoozed,
  acted,
  expired,
}

class FfmAssistantInsight {
  const FfmAssistantInsight({
    required this.id,
    required this.householdId,
    required this.type,
    required this.severity,
    required this.priority,
    required this.confidence,
    required this.title,
    required this.summary,
    required this.evidence,
    this.geminiExplanation,
    this.suggestedAction,
    this.destination,
    this.actionPayload,
    required this.createdAt,
    this.expiresAt,
    this.snoozedUntil,
    required this.dedupeKey,
    this.cooldownKey,
    this.status = FfmAssistantInsightStatus.newInsight,
    this.updatedAt,
  });

  final String id;
  final String householdId;
  final FfmAssistantInsightType type;
  final FfmAssistantInsightSeverity severity;
  final int priority; // 1 (lowest) to 100 (highest)
  final double confidence; // 0.0 to 1.0
  final String title;
  final String summary;
  final Map<String, dynamic> evidence;
  final String? geminiExplanation;
  final String? suggestedAction;
  final FfmAssistantDestination? destination;
  final Map<String, dynamic>? actionPayload;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? snoozedUntil;
  final String dedupeKey;
  final String? cooldownKey;
  final FfmAssistantInsightStatus status;
  final DateTime? updatedAt;

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  bool get isSnoozed {
    if (status != FfmAssistantInsightStatus.snoozed || snoozedUntil == null) {
      return false;
    }
    return DateTime.now().isBefore(snoozedUntil!);
  }

  bool get isActive {
    if (status == FfmAssistantInsightStatus.dismissed ||
        status == FfmAssistantInsightStatus.acted ||
        isExpired) {
      return false;
    }
    if (isSnoozed) return false;
    return true;
  }

  FfmAssistantInsight copyWith({
    String? id,
    String? householdId,
    FfmAssistantInsightType? type,
    FfmAssistantInsightSeverity? severity,
    int? priority,
    double? confidence,
    String? title,
    String? summary,
    Map<String, dynamic>? evidence,
    String? geminiExplanation,
    String? suggestedAction,
    FfmAssistantDestination? destination,
    Map<String, dynamic>? actionPayload,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? snoozedUntil,
    String? dedupeKey,
    String? cooldownKey,
    FfmAssistantInsightStatus? status,
    DateTime? updatedAt,
  }) {
    return FfmAssistantInsight(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      type: type ?? this.type,
      severity: severity ?? this.severity,
      priority: priority ?? this.priority,
      confidence: confidence ?? this.confidence,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      evidence: evidence ?? this.evidence,
      geminiExplanation: geminiExplanation ?? this.geminiExplanation,
      suggestedAction: suggestedAction ?? this.suggestedAction,
      destination: destination ?? this.destination,
      actionPayload: actionPayload ?? this.actionPayload,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      snoozedUntil: snoozedUntil ?? this.snoozedUntil,
      dedupeKey: dedupeKey ?? this.dedupeKey,
      cooldownKey: cooldownKey ?? this.cooldownKey,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'household_id': householdId,
      'type': type.name,
      'severity': severity.name,
      'priority': priority,
      'confidence': confidence,
      'title': title,
      'summary': summary,
      'evidence_json': jsonEncode(evidence),
      'gemini_explanation': geminiExplanation,
      'suggested_action': suggestedAction,
      'destination': destination?.name,
      'action_payload': actionPayload != null ? jsonEncode(actionPayload) : null,
      'created_at': createdAt.millisecondsSinceEpoch,
      'expires_at': expiresAt?.millisecondsSinceEpoch,
      'snoozed_until': snoozedUntil?.millisecondsSinceEpoch,
      'dedupe_key': dedupeKey,
      'cooldown_key': cooldownKey,
      'status': status.name,
      'updated_at': (updatedAt ?? createdAt).millisecondsSinceEpoch,
    };
  }

  factory FfmAssistantInsight.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> parsedEvidence = const {};
    try {
      final rawEvidence = map['evidence_json']?.toString();
      if (rawEvidence != null && rawEvidence.isNotEmpty) {
        final decoded = jsonDecode(rawEvidence);
        if (decoded is Map) {
          parsedEvidence = Map<String, dynamic>.from(decoded);
        }
      }
    } catch (_) {}

    Map<String, dynamic>? parsedPayload;
    try {
      final rawPayload = map['action_payload']?.toString();
      if (rawPayload != null && rawPayload.isNotEmpty) {
        final decoded = jsonDecode(rawPayload);
        if (decoded is Map) {
          parsedPayload = Map<String, dynamic>.from(decoded);
        }
      }
    } catch (_) {}

    final typeName = map['type']?.toString();
    final type = FfmAssistantInsightType.values.where((v) => v.name == typeName).firstOrNull ??
        FfmAssistantInsightType.budgetAlert;

    final severityName = map['severity']?.toString();
    final severity = FfmAssistantInsightSeverity.values.where((v) => v.name == severityName).firstOrNull ??
        FfmAssistantInsightSeverity.info;

    final statusName = map['status']?.toString();
    final status = FfmAssistantInsightStatus.values.where((v) => v.name == statusName).firstOrNull ??
        FfmAssistantInsightStatus.newInsight;

    final destName = map['destination']?.toString();
    final destination = destName != null
        ? FfmAssistantDestination.values.where((v) => v.name == destName).firstOrNull
        : null;

    final createdAtMs = int.tryParse(map['created_at']?.toString() ?? '') ?? 0;
    final expiresAtMs = int.tryParse(map['expires_at']?.toString() ?? '');
    final snoozedUntilMs = int.tryParse(map['snoozed_until']?.toString() ?? '');
    final updatedAtMs = int.tryParse(map['updated_at']?.toString() ?? '');

    return FfmAssistantInsight(
      id: map['id']?.toString() ?? '',
      householdId: map['household_id']?.toString() ?? '',
      type: type,
      severity: severity,
      priority: int.tryParse(map['priority']?.toString() ?? '50') ?? 50,
      confidence: double.tryParse(map['confidence']?.toString() ?? '1.0') ?? 1.0,
      title: map['title']?.toString() ?? '',
      summary: map['summary']?.toString() ?? '',
      evidence: parsedEvidence,
      geminiExplanation: map['gemini_explanation']?.toString(),
      suggestedAction: map['suggested_action']?.toString(),
      destination: destination,
      actionPayload: parsedPayload,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      expiresAt: expiresAtMs != null ? DateTime.fromMillisecondsSinceEpoch(expiresAtMs) : null,
      snoozedUntil: snoozedUntilMs != null ? DateTime.fromMillisecondsSinceEpoch(snoozedUntilMs) : null,
      dedupeKey: map['dedupe_key']?.toString() ?? '',
      cooldownKey: map['cooldown_key']?.toString(),
      status: status,
      updatedAt: updatedAtMs != null ? DateTime.fromMillisecondsSinceEpoch(updatedAtMs) : null,
    );
  }
}
