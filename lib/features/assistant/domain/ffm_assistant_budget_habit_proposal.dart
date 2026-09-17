/// A deterministic, reviewable recommendation derived from budget habits.
library;

enum FfmAssistantBudgetHabitCadence {
  weekly,
  monthly;

  String get periodType => name;

  static FfmAssistantBudgetHabitCadence? parse(String value) =>
      switch (value.trim().toLowerCase()) {
        'weekly' => FfmAssistantBudgetHabitCadence.weekly,
        'monthly' => FfmAssistantBudgetHabitCadence.monthly,
        _ => null,
      };
}

class FfmAssistantBudgetHabitAnalysisFacts {
  FfmAssistantBudgetHabitAnalysisFacts(Map<String, Object?> values)
    : values = Map.unmodifiable(values);

  final Map<String, Object?> values;
}

class FfmAssistantBudgetHabitProposalItem {
  const FfmAssistantBudgetHabitProposalItem({
    required this.categoryId,
    required this.categoryName,
    required this.cadence,
    required this.amount,
    required this.analysisFacts,
  });

  factory FfmAssistantBudgetHabitProposalItem.fromPeriodType({
    required String categoryId,
    required String categoryName,
    required String periodType,
    required int amount,
    required FfmAssistantBudgetHabitAnalysisFacts analysisFacts,
  }) => FfmAssistantBudgetHabitProposalItem(
    categoryId: categoryId,
    categoryName: categoryName,
    cadence: FfmAssistantBudgetHabitCadence.parse(periodType),
    amount: amount,
    analysisFacts: analysisFacts,
  );

  final String categoryId;
  final String categoryName;
  final FfmAssistantBudgetHabitCadence? cadence;
  final int amount;
  final FfmAssistantBudgetHabitAnalysisFacts analysisFacts;
}

class FfmAssistantBudgetHabitProposal {
  FfmAssistantBudgetHabitProposal({
    required List<FfmAssistantBudgetHabitProposalItem> items,
  }) : items = List.unmodifiable(items);

  final List<FfmAssistantBudgetHabitProposalItem> items;

  /// Splits a valid proposal into stable, contiguous pages without omitting
  /// any category. Invalid proposals have no executable pages.
  List<FfmAssistantBudgetHabitProposalBatch> batches({
    required int maxItemsPerBatch,
  }) {
    if (maxItemsPerBatch <= 0 || !isValid) {
      return const [];
    }
    final totalBatches = (items.length / maxItemsPerBatch).ceil();
    return List.unmodifiable([
      for (
        var startIndex = 0;
        startIndex < items.length;
        startIndex += maxItemsPerBatch
      )
        FfmAssistantBudgetHabitProposalBatch(
          batchNumber: (startIndex ~/ maxItemsPerBatch) + 1,
          totalBatches: totalBatches,
          startIndex: startIndex,
          items: items.sublist(
            startIndex,
            (startIndex + maxItemsPerBatch).clamp(0, items.length),
          ),
        ),
    ]);
  }

  List<FfmAssistantBudgetHabitProposalValidationIssue> validate() {
    final issues = <FfmAssistantBudgetHabitProposalValidationIssue>[];
    final categoryCadences = <String>{};
    for (final item in items) {
      final categoryId = item.categoryId.trim();
      final categoryName = item.categoryName.trim();
      if (categoryId.isEmpty || categoryName.isEmpty) {
        issues.add(
          const FfmAssistantBudgetHabitProposalValidationIssue(
            code: 'category_required',
            message: 'Setiap item harus memiliki ID dan nama kategori kanonis.',
          ),
        );
      }
      if (item.amount <= 0) {
        issues.add(
          const FfmAssistantBudgetHabitProposalValidationIssue(
            code: 'amount_must_be_positive',
            message: 'Nominal anggaran harus lebih dari nol.',
          ),
        );
      }
      if (item.cadence == null) {
        issues.add(
          const FfmAssistantBudgetHabitProposalValidationIssue(
            code: 'invalid_cadence',
            message: 'Periode anggaran hanya dapat mingguan atau bulanan.',
          ),
        );
      } else if (!categoryCadences.add('$categoryId|${item.cadence!.name}')) {
        issues.add(
          const FfmAssistantBudgetHabitProposalValidationIssue(
            code: 'duplicate_budget',
            message: 'Kategori dan periode anggaran tidak boleh diusulkan lebih dari sekali.',
          ),
        );
      }
    }
    return List.unmodifiable(issues);
  }

  bool get isValid => validate().isEmpty;
}

/// Immutable display and planning metadata for one contiguous proposal page.
class FfmAssistantBudgetHabitProposalBatch {
  FfmAssistantBudgetHabitProposalBatch({
    required this.batchNumber,
    required this.totalBatches,
    required this.startIndex,
    required List<FfmAssistantBudgetHabitProposalItem> items,
  }) : items = List.unmodifiable(items);

  /// One-based position, suitable for user-facing batch labels.
  final int batchNumber;
  final int totalBatches;

  /// Zero-based position of the first item in the original proposal.
  final int startIndex;
  final List<FfmAssistantBudgetHabitProposalItem> items;
}

class FfmAssistantBudgetHabitProposalValidationIssue {
  const FfmAssistantBudgetHabitProposalValidationIssue({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;
}
