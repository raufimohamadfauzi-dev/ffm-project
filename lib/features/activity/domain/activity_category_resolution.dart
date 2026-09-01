import '../../../core/database/app_database.dart';
import '../../assistant/data/ffm_assistant_fuzzy_matcher.dart';

/// Outcome of resolving a free-text category request against the active
/// master categories for a household.
enum ActivityCategoryResolutionKind {
  /// A single unambiguous match was found (exact, or a clear fuzzy winner).
  resolved,

  /// More than one close candidate; the caller must ask the user to disambiguate.
  ambiguous,

  /// No acceptable match; the caller must reject the request.
  notFound,
}

class ActivityCategoryResolution {
  const ActivityCategoryResolution.resolved(this.category)
    : kind = ActivityCategoryResolutionKind.resolved,
      candidates = const [];

  const ActivityCategoryResolution.ambiguous(this.candidates)
    : kind = ActivityCategoryResolutionKind.ambiguous,
      category = null;

  const ActivityCategoryResolution.notFound()
    : kind = ActivityCategoryResolutionKind.notFound,
      category = null,
      candidates = const [];

  final ActivityCategoryResolutionKind kind;
  final Category? category;
  final List<Category> candidates;

  bool get isResolved => category != null;
  bool get isAmbiguous => kind == ActivityCategoryResolutionKind.ambiguous;
}

/// Resolves a requested category name against the active master categories.
///
/// Order of matching, deliberately deterministic and single-source:
/// 1. exact (case-insensitive) name match → resolved;
/// 2. a single clear fuzzy winner (`bestUnique`) → resolved;
/// 3. multiple close candidates → ambiguous (caller asks the user);
/// 4. otherwise → notFound.
///
/// This keeps category decisions authoritative in application logic and never
/// lets free-text voice/LLM input silently create an ad-hoc category.
ActivityCategoryResolution resolveActivityCategoryName(
  Iterable<Category> activeCategories,
  String? requestedName,
) {
  final name = requestedName?.trim();
  if (name == null || name.isEmpty) {
    return const ActivityCategoryResolution.notFound();
  }

  final categories = activeCategories.toList();

  final exact = categories
      .where(
        (category) =>
            (category.name).toLowerCase() == name.toLowerCase(),
      )
      .toList();
  if (exact.length == 1) {
    return ActivityCategoryResolution.resolved(exact.single);
  }
  if (exact.length > 1) {
    return ActivityCategoryResolution.ambiguous(exact);
  }

  final top = FfmAssistantFuzzyMatcher.bestUnique(
    name,
    categories,
    textOf: (category) => category.name,
    minimumScore: .70,
    minimumLead: .05,
  );
  if (top != null) {
    return ActivityCategoryResolution.resolved(top.value);
  }

  final fuzzyCandidates = categories
      .map(
        (category) => (
          category,
          FfmAssistantFuzzyMatcher.similarity(name, category.name),
        ),
      )
      .where((entry) => entry.$2 >= .40)
      .toList()
    ..sort((left, right) => right.$2.compareTo(left.$2));
  if (fuzzyCandidates.length == 1) {
    return ActivityCategoryResolution.resolved(fuzzyCandidates.single.$1);
  }
  if (fuzzyCandidates.length > 1) {
    return ActivityCategoryResolution.ambiguous(
      fuzzyCandidates.map((entry) => entry.$1).toList(),
    );
  }

  return const ActivityCategoryResolution.notFound();
}
