abstract final class OwnerLabels {
  static const family = 'Keluarga';
  static const husband = 'Suami';
  static const wife = 'Istri';
  static const child = 'Anak';

  static String normalizeForStorage(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return family;
    return text;
  }
}
