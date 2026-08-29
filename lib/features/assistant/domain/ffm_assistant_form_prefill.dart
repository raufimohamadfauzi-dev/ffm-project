import 'ffm_assistant_draft_validator.dart';
import 'ffm_assistant_models.dart';

/// Payload prefill yang aman untuk form resmi. Nilai ini bukan controller UI,
/// tidak membawa rahasia, dan tidak mengandung instruksi simpan.
class FfmAssistantFormPrefill {
  const FfmAssistantFormPrefill({
    required this.target,
    required this.values,
    required this.check,
  });

  final FfmAssistantDestination target;
  final Map<String, String> values;
  final FfmAssistantFormCheck check;

  List<String> get missingFields => check.missingFields;
  List<String> get warnings => check.warnings;
  bool get isReady => check.canContinue;
}

/// Hasil pemeriksaan setelah draft dipetakan. Form menggunakan hasil ini untuk
/// menandai kekurangan atau konflik sebelum pengguna menyimpan.
class FfmAssistantFormCheck {
  const FfmAssistantFormCheck({
    required this.missingFields,
    required this.warnings,
  });

  final List<String> missingFields;
  final List<String> warnings;

  bool get canContinue => missingFields.isEmpty;
}

/// Mapper deterministik draft → prefill. Form tetap memutuskan bagaimana
/// menerapkan nilai dan pengguna tetap menekan simpan secara manual.
abstract final class FfmAssistantFormPrefillMapper {
  static FfmAssistantFormPrefill fromDraft(FfmAssistantDraft draft) {
    final values = <String, String>{
      'kind': draft.kind.name,
      if (draft.amount != null) 'amount': draft.amount.toString(),
      if (draft.title?.trim().isNotEmpty ?? false) 'title': draft.title!.trim(),
      if (draft.fromAccountName?.trim().isNotEmpty ?? false)
        'fromAccountName': draft.fromAccountName!.trim(),
      if (draft.toAccountName?.trim().isNotEmpty ?? false)
        'toAccountName': draft.toAccountName!.trim(),
      if (draft.categoryName?.trim().isNotEmpty ?? false)
        'categoryName': draft.categoryName!.trim(),
      if (draft.note?.trim().isNotEmpty ?? false) 'note': draft.note!.trim(),
      if (draft.date != null) 'date': _date(draft.date!),
      if (draft.adminFee != null) 'adminFee': draft.adminFee.toString(),
      if (draft.goalName?.trim().isNotEmpty ?? false)
        'goalName': draft.goalName!.trim(),
    };
    final issues = FfmAssistantDraftValidator.validate(draft);
    return FfmAssistantFormPrefill(
      target: _targetFor(draft.kind),
      values: Map.unmodifiable(values),
      check: FfmAssistantFormCheck(
        missingFields: List.unmodifiable(
          issues
              .where(
                (issue) =>
                    issue.severity == FfmAssistantDraftIssueSeverity.required,
              )
              .map((issue) => issue.field ?? issue.code),
        ),
        warnings: List.unmodifiable(
          issues
              .where(
                (issue) =>
                    issue.severity != FfmAssistantDraftIssueSeverity.required,
              )
              .map((issue) => issue.message),
        ),
      ),
    );
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static FfmAssistantDestination _targetFor(
    FfmAssistantDraftKind kind,
  ) => switch (kind) {
    FfmAssistantDraftKind.income ||
    FfmAssistantDraftKind.expense ||
    FfmAssistantDraftKind.transfer ||
    FfmAssistantDraftKind.goalDeposit ||
    FfmAssistantDraftKind.goalUsage => FfmAssistantDestination.transactions,
    FfmAssistantDraftKind.budget ||
    FfmAssistantDraftKind.budgetUpdate ||
    FfmAssistantDraftKind.budgetArchive => FfmAssistantDestination.budget,
    FfmAssistantDraftKind.goal ||
    FfmAssistantDraftKind.goalUpdate ||
    FfmAssistantDraftKind.goalArchive => FfmAssistantDestination.goals,
    FfmAssistantDraftKind.asset ||
    FfmAssistantDraftKind.assetUpdate ||
    FfmAssistantDraftKind.assetArchive => FfmAssistantDestination.assets,
    FfmAssistantDraftKind.liability ||
    FfmAssistantDraftKind.liabilityUpdate ||
    FfmAssistantDraftKind.liabilityArchive ||
    FfmAssistantDraftKind.receivable ||
    FfmAssistantDraftKind.receivableUpdate ||
    FfmAssistantDraftKind.receivableArchive =>
      FfmAssistantDestination.liabilities,
    FfmAssistantDraftKind.reminder ||
    FfmAssistantDraftKind.reminderUpdate ||
    FfmAssistantDraftKind.reminderArchive => FfmAssistantDestination.reminders,
    FfmAssistantDraftKind.activity ||
    FfmAssistantDraftKind.activityArchive ||
    FfmAssistantDraftKind.activityDelete ||
    FfmAssistantDraftKind.activityFinish ||
    FfmAssistantDraftKind.activityUpdate ||
    FfmAssistantDraftKind.activityEdit => FfmAssistantDestination.activity,
    _ => FfmAssistantDestination.masterData,
  };
}
