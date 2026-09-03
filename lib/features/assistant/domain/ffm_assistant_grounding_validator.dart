/// Validasi ringan klaim finansial berisiko tanpa chain-of-thought.
///
/// Hanya memeriksa jejak deterministik: angka/tanggal yang disebut Gemini
/// harus ada di fakta terverifikasi atau hasil capability. Tidak menampilkan
/// reasoning tersembunyi, hanya mengembalikan pesan fallback jujur.
class FfmAssistantGroundingValidator {
  const FfmAssistantGroundingValidator._();

  static final _saveClaim = RegExp(
    r'(sudah\s+tersimpan|berhasil\s+disimpan|sudah\s+dicatat|data\s+sudah\s+diperbarui)',
    caseSensitive: false,
  );

  static final _financialNumber = RegExp(
    r'(rp\s*\d[\d.,]*|\b\d[\d.,]{3,}\b|\b\d+\s*(juta|ribu|miliar|jt|m)\b)',
    caseSensitive: false,
  );

  static final _dateLike = RegExp(
    r'(\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}\s+(januari|februari|maret|april|mei|juni|juli|agustus|september|oktober|november|desember)\b)',
    caseSensitive: false,
  );

  /// Kembalikan `null` bila lolos, atau pesan fallback bila klaim berisiko.
  static String? validatePlainText({
    required String geminiText,
    required String? verifiedFacts,
    required String? analysisFacts,
    required String? capabilityEvidence,
  }) {
    final normalized = geminiText.toLowerCase();

    // Jangan pernah klaim save sebelum executor.
    if (_saveClaim.hasMatch(normalized)) {
      return 'Jawaban tidak dapat menampilkan klaim penyimpanan. Silakan cek riwayat atau minta ringkasan terbaru.';
    }

    final hasFinancialNumber = _financialNumber.hasMatch(geminiText);
    final hasDate = _dateLike.hasMatch(geminiText);

    if (!hasFinancialNumber && !hasDate) return null;

    // Gabungkan evidence yang diizinkan sebagai sumber kebenaran.
    final evidence = [
      if (verifiedFacts case final String v) v,
      if (analysisFacts case final String a) a,
      if (capabilityEvidence case final String c) c,
    ].join(' ');

    if (evidence.trim().isEmpty) {
      return 'Data lokal belum tersedia untuk mendukung angka/tanggal tersebut. Coba minta ringkasan atau transaksi terbaru.';
    }

    // Untuk angka besar, pastikan setidaknya satu angka dari jawaban muncul di evidence.
    // Ini ringan: cek digit murni tanpa formatting.
    if (hasFinancialNumber) {
      final numbers = _extractNumbers(geminiText);
      final evidenceDigits = _normalizeDigits(evidence);
      final grounded = numbers.any((n) => evidenceDigits.contains(n));
      // Jika tidak ada satu pun angka yang grounded, anggap berisiko.
      if (numbers.isNotEmpty && !grounded && _hasLargeNumber(geminiText)) {
        return 'Angka pada jawaban belum dapat diverifikasi dari data lokal. Minta ringkasan terbaru untuk angka yang pasti.';
      }
    }

    return null;
  }

  static List<String> _extractNumbers(String text) {
    return RegExp(r'\d+(?:[.,]\d{3})+|\d+')
        .allMatches(text)
        .map((m) => m.group(0)!.replaceAll(RegExp(r'[,.]'), ''))
        .where((n) => n.length >= 4)
        .map((n) => n.replaceAll(RegExp(r'^0+'), ''))
        .where((n) => n.isNotEmpty)
        .toList(growable: false);
  }

  static String _normalizeDigits(String text) {
    return text.replaceAll(RegExp(r'[^0-9]'), ' ');
  }

  static bool _hasLargeNumber(String text) {
    if (RegExp(
      r'\b\d+\s*(juta|miliar|ribu)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return true;
    }
    final extracted = _extractNumbers(text);
    return extracted.any((n) => n.length >= 5);
  }
}
