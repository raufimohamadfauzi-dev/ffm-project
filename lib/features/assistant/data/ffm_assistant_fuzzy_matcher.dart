/// Pencocokan teks ringan berbasis Dart murni. Dipakai hanya untuk membantu
/// menemukan pertanyaan atau ajaran yang sangat mirip; tidak pernah mengubah
/// teks pengguna secara otomatis.
class FfmAssistantFuzzyMatch<T> {
  const FfmAssistantFuzzyMatch({required this.value, required this.score});

  final T value;
  final double score;
}

class FfmAssistantFuzzyMatcher {
  const FfmAssistantFuzzyMatcher._();

  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Mengembalikan kandidat tunggal hanya bila skornya cukup tinggi dan
  /// unggul dari kandidat kedua. Dengan begitu typo dibantu, tetapi dua
  /// ajaran yang berbeda tidak tercampur sembarangan.
  static FfmAssistantFuzzyMatch<T>? bestUnique<T>(
    String query,
    Iterable<T> candidates, {
    required String Function(T item) textOf,
    double minimumScore = .84,
    double minimumLead = .07,
  }) {
    final source = normalize(query);
    if (source.length < 4) return null;
    final ranked =
        candidates
            .map(
              (item) => FfmAssistantFuzzyMatch<T>(
                value: item,
                score: similarity(source, textOf(item)),
              ),
            )
            .where((item) => item.score >= minimumScore)
            .toList()
          ..sort((left, right) => right.score.compareTo(left.score));
    if (ranked.isEmpty) return null;
    if (ranked.length > 1 &&
        ranked.first.score - ranked[1].score < minimumLead) {
      return null;
    }
    return ranked.first;
  }

  static double similarity(String left, String right) {
    final a = normalize(left);
    final b = normalize(right);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final maxLength = a.length > b.length ? a.length : b.length;
    final editScore = 1 - (_levenshtein(a, b) / maxLength);
    final aTokens = a.split(' ').where((item) => item.isNotEmpty).toSet();
    final bTokens = b.split(' ').where((item) => item.isNotEmpty).toSet();
    final union = <String>{...aTokens, ...bTokens};
    final intersection = aTokens.intersection(bTokens);
    final tokenScore = union.isEmpty ? 0 : intersection.length / union.length;
    return (editScore * .65) + (tokenScore * .35);
  }

  static int _levenshtein(String source, String target) {
    if (source.length < target.length) {
      return _levenshtein(target, source);
    }
    var previous = List<int>.generate(target.length + 1, (index) => index);
    for (var sourceIndex = 1; sourceIndex <= source.length; sourceIndex++) {
      final current = <int>[sourceIndex];
      for (var targetIndex = 1; targetIndex <= target.length; targetIndex++) {
        final substitution =
            previous[targetIndex - 1] +
            (source[sourceIndex - 1] == target[targetIndex - 1] ? 0 : 1);
        final insertion = current[targetIndex - 1] + 1;
        final deletion = previous[targetIndex] + 1;
        current.add(
          [
            substitution,
            insertion,
            deletion,
          ].reduce((lowest, value) => lowest < value ? lowest : value),
        );
      }
      previous = current;
    }
    return previous.last;
  }
}
