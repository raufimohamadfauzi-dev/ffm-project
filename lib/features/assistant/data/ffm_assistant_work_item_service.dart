/// Service untuk mengubah hasil interpretasi menjadi work item yang terstruktur.
library;

import '../domain/ffm_assistant_models.dart';
import '../domain/ffm_assistant_work_item.dart';
import '../domain/ffm_assistant_draft_validator.dart';

/// Service untuk mengonversi intent menjadi work item dengan informasi field.
/// Semua hasil LLM (Agent dan Gemini) melewati parser/validator yang sama.
class FfmAssistantWorkItemService {
  const FfmAssistantWorkItemService();

  /// Mengubah daftar intent menjadi hasil pemahaman dengan work item.
  /// Hasil LLM selalu melewati parser/validator sebelum menjadi work item.
  FfmAssistantUnderstandingResult intentsToWorkItems(
    List<FfmAssistantIntent> intents,
    String rawText,
    String normalizedText, {
    FfmAssistantDestination? currentDestination,
    List<FfmAssistantDestination>? supportedForms,
  }) {
    final workItems = <FfmAssistantWorkItem>[];
    var index = 0;

    for (final intent in intents) {
      final workItem = _intentToWorkItem(
        intent,
        index,
        currentDestination: currentDestination,
        supportedForms: supportedForms,
      );
      if (workItem != null) {
        workItems.add(workItem);
        index++;
      }
    }

    return FfmAssistantUnderstandingResult(
      workItems: workItems,
      intents: intents,
      rawText: rawText,
      normalizedText: normalizedText,
    );
  }

  FfmAssistantWorkItem? _intentToWorkItem(
    FfmAssistantIntent intent,
    int index, {
    FfmAssistantDestination? currentDestination,
    List<FfmAssistantDestination>? supportedForms,
  }) {
    // Skip intents that don't represent actionable work
    if (intent.type == FfmAssistantIntentType.unknown ||
        intent.type == FfmAssistantIntentType.help ||
        intent.type == FfmAssistantIntentType.outOfDomain) {
      return null;
    }

    final id = 'work_${DateTime.now().millisecondsSinceEpoch}_$index';
    final targetDestination = intent.destination ?? FfmAssistantDestination.summary;

    // Extract field information from draft if available
    final knownFields = <FfmAssistantFieldInfo>[];
    final unknownFields = <String>[];
    final ambiguousFields = <FfmAssistantFieldInfo>[];

    if (intent.draft != null) {
      // Validator draft sudah mengetahui field wajib per jenis draft.
      // Jangan menebak satu daftar field universal di sini: transfer, anggaran,
      // aset, dan target memiliki kebutuhan yang berbeda.
      final issues = FfmAssistantDraftValidator.validate(intent.draft!);

      _extractKnownFieldsFromDraft(intent.draft!, knownFields);

      for (final issue in issues) {
        final field = issue.field ?? issue.code;
        if (issue.severity == FfmAssistantDraftIssueSeverity.conflict) {
          ambiguousFields.add(FfmAssistantFieldInfo(
            name: field,
            status: FfmAssistantFieldStatus.ambiguous,
            ambiguityReason: issue.message,
          ));
        } else if (issue.blocksContinuation &&
            !unknownFields.contains(field)) {
          unknownFields.add(field);
        }
      }
    }

    // Hanya validator FFM yang boleh menyatakan field wajib telah lengkap.
    final needsClarification =
        intent.clarification != null ||
        unknownFields.isNotEmpty ||
        ambiguousFields.isNotEmpty;
    final clarification = intent.clarification ??
        (needsClarification
            ? 'Aku masih perlu ${[
                ...unknownFields,
                ...ambiguousFields.map((field) => field.name),
              ].join(', ')} supaya draft-nya tidak salah.'
            : null);
    final confidence = needsClarification
        ? FfmAssistantWorkItemConfidence.low
        : (intent.draft != null
            ? FfmAssistantWorkItemConfidence.high
            : FfmAssistantWorkItemConfidence.medium);

    return FfmAssistantWorkItem(
      id: id,
      intent: intent.type,
      sourceIntent: intent,
      targetDestination: targetDestination,
      confidence: confidence,
      knownFields: knownFields,
      unknownFields: unknownFields,
      ambiguousFields: ambiguousFields,
      clarificationQuestion: clarification,
      currentDestination: currentDestination,
      supportedForms: supportedForms,
    );
  }

  void _extractKnownFieldsFromDraft(
    FfmAssistantDraft draft,
    List<FfmAssistantFieldInfo> knownFields,
  ) {
    final values = <String, String?>{
      'amount': draft.amount?.toString(),
      'title': draft.title,
      'fromAccountName': draft.fromAccountName,
      'toAccountName': draft.toAccountName,
      'categoryName': draft.categoryName,
      'goalName': draft.goalName,
      'partyName': draft.partyName,
      'date': draft.date?.toIso8601String().substring(0, 10),
      'note': draft.note,
    };
    for (final entry in values.entries) {
      if (entry.value?.trim().isNotEmpty != true) continue;
      knownFields.add(
        FfmAssistantFieldInfo(
          name: entry.key,
          status: FfmAssistantFieldStatus.known,
          value: entry.value,
        ),
      );
    }
  }
}
