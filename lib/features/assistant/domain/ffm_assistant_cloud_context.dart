import 'dart:convert';

import 'ffm_assistant_models.dart';
import 'ffm_assistant_reasoning_context.dart';
import 'ffm_assistant_verified_fact_service.dart';

enum FfmAssistantCloudRequestClass {
  general,
  help,
  summary,
  financialRead,
  recentTransactions,
  accounts,
  budget,
  categories,
  goals,
  masterData,
  analysis,
  draftReview,
  mutationProposal,
}

/// Evidence capability bertipe untuk konteks cloud.
///
/// Setiap item mencatat capability yang dipakai, argumen tervalidasi, waktu
/// capture, ringkasan bounded, dan label kualitas data.
class FfmAssistantCloudCapabilityEvidence {
  const FfmAssistantCloudCapabilityEvidence({
    required this.capabilityId,
    required this.validatedArguments,
    required this.capturedAt,
    required this.boundedSummary,
    this.dataQuality = 'sufficient',
  });

  final String capabilityId;
  final Map<String, String> validatedArguments;
  final DateTime capturedAt;
  final String boundedSummary;
  final String dataQuality;

  String toBoundedPrompt({int maxCharacters = 800}) => _clip(
    'CAPABILITY EVIDENCE: id=$capabilityId; '
    'capturedAt=${capturedAt.toIso8601String()}; '
    'quality=$dataQuality; '
    'args=${jsonEncode(validatedArguments)}; '
    'summary=${_oneLine(boundedSummary, 500)}',
    maxCharacters,
  );
}

/// Field draft yang aman dan relevan untuk membantu Gemini memahami koreksi.
/// ID internal, token, dan metadata sumber tidak ikut dikirim.
class FfmAssistantCloudDraftContext {
  const FfmAssistantCloudDraftContext({
    required this.kind,
    required this.fields,
    this.reviewVersion,
    this.missingFields = const <String>[],
    this.warnings = const <String>[],
    this.status,
  });

  factory FfmAssistantCloudDraftContext.fromDraft(
    FfmAssistantDraft draft, {
    FfmAssistantDraftReview? review,
  }) {
    final fields = <String, String>{};

    void add(String key, Object? value) {
      if (value == null) return;
      final text = _oneLine('$value', 300);
      if (text.isNotEmpty) fields[key] = text;
    }

    void addDate() {
      final date = draft.date;
      if (date != null) add('date', date.toIso8601String().substring(0, 10));
    }

    void addSafeFormValues() {
      for (final entry in draft.formValues.entries) {
        final key = entry.key.trim();
        final normalized = key.toLowerCase();
        if (key.isEmpty ||
            normalized == 'source' ||
            normalized == 'id' ||
            normalized.endsWith('id') ||
            normalized.contains('token') ||
            normalized.contains('secret') ||
            normalized.contains('password')) {
          continue;
        }
        add('field.$key', entry.value);
      }
    }

    switch (draft.kind) {
      case FfmAssistantDraftKind.masterData:
        add('target', draft.categoryName);
        add('name', draft.title);
        addSafeFormValues();
        add('note', draft.note);
      case FfmAssistantDraftKind.income:
        add('amount', draft.amount);
        add('title', draft.title);
        add('party', draft.partyName);
        add('toAccount', draft.toAccountName);
        add('category', draft.categoryName);
        add('note', draft.note);
        addDate();
      case FfmAssistantDraftKind.expense:
        add('amount', draft.amount);
        add('title', draft.title);
        add('party', draft.partyName);
        add('fromAccount', draft.fromAccountName);
        add('category', draft.categoryName);
        add('note', draft.note);
        addDate();
      case FfmAssistantDraftKind.transfer:
        add('amount', draft.amount);
        add('fromAccount', draft.fromAccountName);
        add('toAccount', draft.toAccountName);
        add('adminFee', draft.adminFee);
        add('note', draft.note);
        addDate();
      case FfmAssistantDraftKind.goal:
        add('name', draft.title);
        add('targetAmount', draft.amount);
        add('targetDate', draft.date?.toIso8601String().substring(0, 10));
        add('note', draft.note);
      case FfmAssistantDraftKind.budget:
        add('name', draft.title);
        add('limit', draft.amount);
        add('category', draft.categoryName);
        addDate();
        add('note', draft.note);
      case FfmAssistantDraftKind.goalDeposit:
      case FfmAssistantDraftKind.goalUsage:
        add('goal', draft.goalName);
        add('amount', draft.amount);
        addDate();
        add('note', draft.note);
      default:
        add('title', draft.title);
        add('party', draft.partyName);
        add('amount', draft.amount);
        add('category', draft.categoryName);
        add('goal', draft.goalName);
        addDate();
        addSafeFormValues();
        add('note', draft.note);
    }

    final reviewVersion = review?.version;
    final missingFields = <String>[];
    final warnings = <String>[];
    String? status;
    if (review != null) {
      for (final issue in review.issues) {
        final label = issue.field ?? issue.code;
        final sanitized = _oneLine(label, 40);
        if (sanitized.isEmpty) continue;
        if (issue.severity == FfmAssistantDraftIssueSeverity.required ||
            issue.severity == FfmAssistantDraftIssueSeverity.conflict) {
          if (!missingFields.contains(sanitized)) missingFields.add(sanitized);
        } else if (issue.severity == FfmAssistantDraftIssueSeverity.warning) {
          final msg = _oneLine(issue.message, 120);
          final entry = msg.isEmpty ? sanitized : '$sanitized: $msg';
          if (!warnings.contains(entry)) warnings.add(entry);
        }
      }
      status = review.canContinue ? 'can_continue' : 'blocked';
    }

    return FfmAssistantCloudDraftContext(
      kind: draft.kind,
      fields: fields,
      reviewVersion: reviewVersion,
      missingFields: missingFields,
      warnings: warnings,
      status: status,
    );
  }

  final FfmAssistantDraftKind kind;
  final Map<String, String> fields;
  final int? reviewVersion;
  final List<String> missingFields;
  final List<String> warnings;
  final String? status;

  String toBoundedPrompt({int maxCharacters = 1000}) {
    final base =
        'ACTIVE DRAFT (belum tersimpan): kind=${kind.name}; '
        'fields=${jsonEncode(fields)}.';
    final reviewPart =
        reviewVersion == null &&
            missingFields.isEmpty &&
            warnings.isEmpty &&
            status == null
        ? ''
        : ' reviewVersion=${reviewVersion ?? '-'}; '
              'status=${status ?? '-'}; '
              'missing=${missingFields.isEmpty ? '-' : missingFields.join(',')}; '
              'warnings=${warnings.isEmpty ? '-' : warnings.join('; ')}.';
    return _clip(
      '$base$reviewPart Pertahankan kind dan jangan klaim sudah tersimpan.',
      maxCharacters,
    );
  }
}

/// Satu envelope context cloud yang dapat dibatasi dan diuji sebagai unit.
/// Urutan section memprioritaskan policy, draft aktif, dan fakta authoritative.
class FfmAssistantCloudContextEnvelope {
  const FfmAssistantCloudContextEnvelope({
    required this.capturedAt,
    required this.routingMode,
    required this.requestClass,
    required this.evidenceScope,
    required this.reasoningContext,
    required this.verifiedFacts,
    this.currentDestination,
    this.analysisFacts,
    this.activeDraft,
    this.personalMemoryContext = '',
    this.draftFeedback = '',
    this.conversationHistory = '',
    this.cloudMemoryContext = '',
    this.capabilityEvidences = const <FfmAssistantCloudCapabilityEvidence>[],
  });

  static const schemaVersion = 'ffm-cloud-context-v1';

  final DateTime capturedAt;
  final FfmAssistantRoutingMode routingMode;
  final FfmAssistantCloudRequestClass requestClass;
  final FfmAssistantReasoningEvidenceScope evidenceScope;
  final FfmAssistantDestination? currentDestination;
  final FfmAssistantReasoningContext reasoningContext;
  final FfmVerifiedFacts verifiedFacts;
  final FfmAnalysisFacts? analysisFacts;
  final FfmAssistantCloudDraftContext? activeDraft;
  final String personalMemoryContext;
  final String draftFeedback;
  final String conversationHistory;
  final String cloudMemoryContext;
  final List<FfmAssistantCloudCapabilityEvidence> capabilityEvidences;

  String toBoundedPrompt({int maxCharacters = 8000}) {
    final metadata = jsonEncode({
      'schemaVersion': schemaVersion,
      'capturedAt': capturedAt.toIso8601String(),
      'routingMode': routingMode.name,
      'requestClass': requestClass.name,
      'destination': currentDestination?.name,
      'evidenceScope': {
        'financialSummary': evidenceScope.includeFinancialSummary,
        'recentTransactions': evidenceScope.includeRecentTransactions,
        'masterData': evidenceScope.includeMasterData,
      },
    });
    final sections = <String>[
      'CLOUD CONTEXT METADATA:\n${_clip(metadata, 500)}',
      'AUTHORITATIVE DATA POLICY:\nAngka dan status hanya boleh berasal dari VERIFIED FACTS, ANALYSIS FACTS, atau hasil capability lokal. Memory dan riwayat hanya context. Draft belum tersimpan sampai FFM memverifikasi eksekusi.',
      if (activeDraft != null) activeDraft!.toBoundedPrompt(),
      'VERIFIED FACTS:\n${_clip(verifiedFacts.toLLMContext(), 1800)}',
      if (analysisFacts != null)
        'ANALYSIS FACTS:\n${_clip(analysisFacts!.toLLMContext(), 1400)}',
      if (capabilityEvidences.isNotEmpty)
        'CAPABILITY EVIDENCES:\n${_clip(capabilityEvidences.map((e) => e.toBoundedPrompt()).join('\n'), 1200)}',
      'REASONING CONTEXT:\n${reasoningContext.toBoundedPrompt(maxCharacters: 2600)}',
      if (personalMemoryContext.trim().isNotEmpty)
        'APPROVED PERSONAL MEMORY:\n${_clip(personalMemoryContext, 700)}',
      if (draftFeedback.trim().isNotEmpty)
        'DRAFT REVISION FEEDBACK:\n${_clip(draftFeedback, 500)}',
      if (conversationHistory.trim().isNotEmpty)
        'BOUNDED CONVERSATION HISTORY:\n${_clip(conversationHistory, 900)}',
      if (cloudMemoryContext.trim().isNotEmpty)
        'BOUNDED CLOUD MEMORY:\n${_clip(cloudMemoryContext, 500)}',
    ];
    return _clip(sections.join('\n\n'), maxCharacters);
  }
}

String _oneLine(String value, int maxCharacters) => _clip(
  value.replaceAll(RegExp(r'[\r\n\u0000]+'), ' ').trim(),
  maxCharacters,
);

String _clip(String value, int maxCharacters) {
  if (maxCharacters <= 0) return '';
  final normalized = value.replaceAll('\u0000', '').trim();
  if (normalized.length <= maxCharacters) return normalized;
  if (maxCharacters == 1) return '…';
  return '${normalized.substring(0, maxCharacters - 1)}…';
}
