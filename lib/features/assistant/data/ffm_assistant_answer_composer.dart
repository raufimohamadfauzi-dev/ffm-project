/// Kontrak penyusunan jawaban naratif oleh SLM lokal.
///
/// Guard deterministik tetap menentukan intent dan menyusun fakta resmi;
/// SLM hanya merangkai kalimat jawaban dari fakta tersebut sehingga jawaban
/// terasa natural dan berbeda setiap saat. Pemanggil wajib memiliki teks
/// fallback lokal jika SLM gagal, sibuk, atau tidak tersedia.
abstract interface class FfmAssistantAnswerComposer {
  /// Menyusun jawaban dari [facts] untuk menjawab [question].
  ///
  /// Mengembalikan null bila SLM tidak siap, gagal, atau hasilnya tidak
  /// lolos sanitasi — pemanggil kemudian memakai fallback lokal.
  Future<String?> composeGroundedAnswer({
    required String question,
    required String facts,
  });
}

/// Validator hasil rangkuman SLM sebelum ditampilkan ke pengguna.
class FfmAssistantComposedAnswerContract {
  const FfmAssistantComposedAnswerContract._();

  static const int minLength = 12;
  static const int maxLength = 1200;

  /// Mengembalikan teks bersih atau null bila output SLM tidak layak pakai.
  static String? sanitize(String raw) {
    var value = raw.trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1).trim();
    }
    if (value.startsWith('```') || value.endsWith('```')) {
      value = value
          .replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '')
          .replaceFirst(RegExp(r'\n?```$'), '')
          .trim();
    }
    if (value.length < minLength) return null;
    if (value.startsWith('{') || value.startsWith('[')) return null;
    if (value.length > maxLength) return null;
    return value.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }
}
