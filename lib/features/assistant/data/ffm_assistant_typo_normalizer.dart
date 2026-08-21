/// Koreksi ringan untuk kata perintah yang jelas, bukan untuk nama orang,
/// catatan transaksi, atau nominal. Bila ragu, kata asli tetap dipertahankan.
abstract final class FfmAssistantTypoNormalizer {
  static const _exactCorrections = <String, String>{
    'teansaksi': 'transaksi',
    'tansaksi': 'transaksi',
    'transakzi': 'transaksi',
    'pengeluaram': 'pengeluaran',
    'pengeluarann': 'pengeluaran',
    'pemasuka': 'pemasukan',
    'anggaram': 'anggaran',
    'angaran': 'anggaran',
    'budjet': 'budget',
    'tranfer': 'transfer',
    'aktipitas': 'aktivitas',
    'akitivitas': 'aktivitas',
    'ringkasn': 'ringkasan',
    'hutng': 'hutang',
    'pituang': 'piutang',
    'rekning': 'rekening',
    'mingg': 'minggu',
  };

  static const _safeWords = <String>{
    'transaksi',
    'pemasukan',
    'pengeluaran',
    'anggaran',
    'budget',
    'transfer',
    'pindahkan',
    'rekening',
    'aktivitas',
    'ringkasan',
    'hutang',
    'utang',
    'piutang',
    'minggu',
    'bulan',
    'hari',
    'konfirmasi',
    'simpan',
    'batalkan',
  };

  static String correct(String text) => text.replaceAllMapped(
    RegExp(r'\b[a-z]+\b'),
    (match) => correctWord(match.group(0)!),
  );

  static String correctWord(String word) {
    final exact = _exactCorrections[word];
    if (exact != null) return exact;
    if (word.length < 5 || _safeWords.contains(word)) return word;

    final candidates = _safeWords.where(
      (candidate) =>
          (candidate.length - word.length).abs() <= 1 &&
          levenshteinDistance(candidate, word) <= (word.length >= 8 ? 2 : 1),
    );
    return candidates.length == 1 ? candidates.single : word;
  }

  static bool isSafeNearMatch(String value, String expected) {
    final normalizedValue = value.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normalizedExpected = expected.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normalizedValue.isEmpty || normalizedExpected.isEmpty) return false;
    return (normalizedValue.length - normalizedExpected.length).abs() <= 1 &&
        levenshteinDistance(normalizedValue, normalizedExpected) <= 1;
  }

  static int levenshteinDistance(String source, String target) {
    if (source == target) return 0;
    if (source.isEmpty) return target.length;
    if (target.isEmpty) return source.length;
    var previous = List<int>.generate(target.length + 1, (index) => index);
    for (var sourceIndex = 1; sourceIndex <= source.length; sourceIndex++) {
      final current = List<int>.filled(target.length + 1, 0);
      current[0] = sourceIndex;
      for (var targetIndex = 1; targetIndex <= target.length; targetIndex++) {
        final cost = source[sourceIndex - 1] == target[targetIndex - 1] ? 0 : 1;
        current[targetIndex] = [
          current[targetIndex - 1] + 1,
          previous[targetIndex] + 1,
          previous[targetIndex - 1] + cost,
        ].reduce((smallest, value) => value < smallest ? value : smallest);
      }
      previous = current;
    }
    return previous.last;
  }
}
