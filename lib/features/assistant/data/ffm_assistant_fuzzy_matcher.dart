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
    final editScore = 1 - (_damerauLevenshtein(a, b) / maxLength);
    final aTokens = a.split(' ').where((item) => item.isNotEmpty).toSet();
    final bTokens = b.split(' ').where((item) => item.isNotEmpty).toSet();
    final union = <String>{...aTokens, ...bTokens};
    final intersection = aTokens.intersection(bTokens);
    final tokenScore = union.isEmpty ? 0 : intersection.length / union.length;
    return (editScore * .65) + (tokenScore * .35);
  }

  /// Variasi optimal string alignment dari Damerau-Levenshtein. Selain
  /// substitusi, tambah, dan hapus, pertukaran dua huruf bersebelahan hanya
  /// dihitung satu kesalahan: misalnya `pni` terhadap `pin`.
  static int _damerauLevenshtein(String source, String target) {
    final matrix = List<List<int>>.generate(
      source.length + 1,
      (_) => List<int>.filled(target.length + 1, 0),
    );
    for (var sourceIndex = 0; sourceIndex <= source.length; sourceIndex++) {
      matrix[sourceIndex][0] = sourceIndex;
    }
    for (var targetIndex = 0; targetIndex <= target.length; targetIndex++) {
      matrix[0][targetIndex] = targetIndex;
    }
    for (var sourceIndex = 1; sourceIndex <= source.length; sourceIndex++) {
      for (var targetIndex = 1; targetIndex <= target.length; targetIndex++) {
        final substitution =
            matrix[sourceIndex - 1][targetIndex - 1] +
            (source[sourceIndex - 1] == target[targetIndex - 1] ? 0 : 1);
        var distance = [
          substitution,
          matrix[sourceIndex - 1][targetIndex] + 1,
          matrix[sourceIndex][targetIndex - 1] + 1,
        ].reduce((lowest, value) => lowest < value ? lowest : value);
        if (sourceIndex > 1 &&
            targetIndex > 1 &&
            source[sourceIndex - 1] == target[targetIndex - 2] &&
            source[sourceIndex - 2] == target[targetIndex - 1]) {
          distance = [
            distance,
            matrix[sourceIndex - 2][targetIndex - 2] + 1,
          ].reduce((lowest, value) => lowest < value ? lowest : value);
        }
        matrix[sourceIndex][targetIndex] = distance;
      }
    }
    return matrix[source.length][target.length];
  }
}
