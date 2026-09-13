/// Outcome of resolving a user-facing name against household master data.
enum FfmAssistantReferenceStatus { resolved, missing, ambiguous }

class FfmAssistantReferenceResolution<T> {
  const FfmAssistantReferenceResolution._({
    required this.status,
    this.value,
    this.matches = const [],
  });

  final FfmAssistantReferenceStatus status;
  final T? value;
  final List<T> matches;

  bool get isResolved => status == FfmAssistantReferenceStatus.resolved;

  static FfmAssistantReferenceResolution<T> resolved<T>(T value) =>
      FfmAssistantReferenceResolution._(
        status: FfmAssistantReferenceStatus.resolved,
        value: value,
        matches: [value],
      );
}

/// Exact, case-insensitive name resolution shared by draft adapters and tests.
abstract final class FfmAssistantReferenceResolver {
  static FfmAssistantReferenceResolution<T> resolve<T>(
    String? requested,
    Iterable<T> candidates,
    String Function(T) nameOf,
  ) {
    final normalized = requested?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return const FfmAssistantReferenceResolution._(
        status: FfmAssistantReferenceStatus.missing,
      );
    }
    final matches = candidates
        .where(
          (candidate) => nameOf(candidate).trim().toLowerCase() == normalized,
        )
        .toList(growable: false);
    if (matches.isEmpty) {
      return const FfmAssistantReferenceResolution._(
        status: FfmAssistantReferenceStatus.missing,
      );
    }
    if (matches.length > 1) {
      return FfmAssistantReferenceResolution._(
        status: FfmAssistantReferenceStatus.ambiguous,
        matches: matches,
      );
    }
    return FfmAssistantReferenceResolution._(
      status: FfmAssistantReferenceStatus.resolved,
      value: matches.single,
      matches: matches,
    );
  }
}
