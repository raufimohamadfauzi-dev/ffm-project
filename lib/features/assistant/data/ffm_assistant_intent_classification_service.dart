import '../domain/ffm_assistant_models.dart';

/// Service untuk klasifikasi intent yang lebih cerdas khusus untuk membedakan
/// antara pembuatan tag vs draft, dan konteks editing lainnya.
class FfmAssistantIntentClassificationService {
  FfmAssistantIntentClassificationService();

  /// Menganalisis teks user untuk menentukan intent yang lebih spesifik
  /// terutama untuk membedakan "buat tag" vs "buat draft"
  FfmAssistantIntentType? classifySpecificIntent(String normalizedText) {
    final text = normalizedText.toLowerCase().trim();

    // Deteksi pembuatan tag secara eksplisit
    if (_isCreateTagIntent(text)) {
      return FfmAssistantIntentType.createTag;
    }

    // Deteksi editing draft yang ada
    if (_isEditDraftIntent(text)) {
      return FfmAssistantIntentType.editDraft;
    }

    // Deteksi revisi draft
    if (_isReviseDraftIntent(text)) {
      return FfmAssistantIntentType.reviseDraft;
    }

    return null; // Gunakan classifier default
  }

  /// Mendapatkan penjelasan mengapa intent diinterpretasikan seperti itu
  String? getIntentExplanation(FfmAssistantIntentType intent, String text) {
    switch (intent) {
      case FfmAssistantIntentType.createTag:
        return 'Intent: Membuat tag baru (bukan draft) karena kata kunci: tag, label, kategori';
      case FfmAssistantIntentType.editDraft:
        return 'Intent: Mengedit draft yang sudah ada karena konteks revisi/koreksi';
      case FfmAssistantIntentType.reviseDraft:
        return 'Intent: Revisi draft karena ada kata revisi/perbaikan';
      default:
        return null;
    }
  }

  bool _isCreateTagIntent(String text) {
    // Pattern untuk pembuatan tag yang eksplisit
    final tagPatterns = [
      RegExp(r'buat\s+tag\s+([\w\s]+)'),
      RegExp(r'tambah\s+tag\s+([\w\s]+)'),
      RegExp(r'buat\s+label\s+([\w\s]+)'),
      RegExp(r'tambah\s+label\s+([\w\s]+)'),
      RegExp(r'create\s+tag\s+([\w\s]+)'),
      RegExp(r'new\s+tag\s+([\w\s]+)'),
      RegExp(r'tag\s+(?:baru|baru|buat)\s+([\w\s]+)'),
    ];

    for (final pattern in tagPatterns) {
      if (pattern.hasMatch(text)) {
        return true;
      }
    }

    // Cek jika ada kata "tag" tanpa kata draft
    if (text.contains('tag') && !text.contains('draft')) {
      return true;
    }

    return false;
  }

  bool _isEditDraftIntent(String text) {
    final editPatterns = [
      RegExp(r'edit\s+draft'),
      RegExp(r'ubah\s+draft'),
      RegExp(r'koreksi\s+draft'),
      RegExp(r'modif\s+draft'),
      RegExp(r'perbaiki\s+draft'),
      RegExp(r'ganti\s+nama\s+draft'),
    ];

    for (final pattern in editPatterns) {
      if (pattern.hasMatch(text)) {
        return true;
      }
    }

    return false;
  }

  bool _isReviseDraftIntent(String text) {
    final revisePatterns = [
      RegExp(r'revisi\s+draft'),
      RegExp(r'revisi\s+nama'),
      RegExp(r'ubah\s+nama\s+(?:menjadi|ke|jadikan)'),
      RegExp(r'ganti\s+nama'),
    ];

    for (final pattern in revisePatterns) {
      if (pattern.hasMatch(text)) {
        return true;
      }
    }

    return false;
  }

  /// Mendapatkan entity yang diekstrak dari teks (untuk tag, dll)
  String? extractEntity(String text, FfmAssistantIntentType intent) {
    switch (intent) {
      case FfmAssistantIntentType.createTag:
        return _extractTagEntity(text);
      default:
        return null;
    }
  }

  String? _extractTagEntity(String text) {
    final patterns = [
      RegExp(r'buat\s+tag\s+([\w\s]+)'),
      RegExp(r'tambah\s+tag\s+([\w\s]+)'),
      RegExp(r'buat\s+label\s+([\w\s]+)'),
      RegExp(r'tambah\s+label\s+([\w\s]+)'),
      RegExp(r'tag\s+(?:baru|baru|buat)\s+([\w\s]+)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.groupCount >= 1) {
        return match.group(1)?.trim();
      }
    }

    return null;
  }
}
