/// Utility untuk sanitasi string dan mencegah UTF-16 render crashes.
///
/// Masalah: Teks dinamis (dari input user, database, atau response LLM/API)
/// kadang mengandung byte rusak, surrogate pair terpotong, atau encoding UTF-16 tidak valid
/// saat dirender ke widget teks, menyebabkan ArgumentError: string is not well-formed UTF-16.
///
/// Solusi: Gunakan sanitasi string sebelum dilempar ke TextSpan / Text.
class StringSanitizer {
  /// Sanitasi string untuk memastikan valid UTF-16 encoding.
  ///
  /// Menggunakan manual rune-level sanitization untuk kompatibilitas lintas SDK.
  /// Filter surrogate pairs, non-characters, dan invalid code points.
  static String sanitizeText(String? text) {
    if (text == null) return '';
    return _manualSanitize(text);
  }

  /// Manual sanitasi: iterasi rune-per-rune dan buang yang tidak valid.
  static String _manualSanitize(String text) {
    final buffer = StringBuffer();
    final length = text.length;

    for (var i = 0; i < length; i++) {
      final codeUnit = text.codeUnitAt(i);

      // Handle surrogate pairs (UTF-16 encoding)
      if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF) {
        // High surrogate — check if followed by valid low surrogate
        if (i + 1 < length) {
          final nextCodeUnit = text.codeUnitAt(i + 1);
          if (nextCodeUnit >= 0xDC00 && nextCodeUnit <= 0xDFFF) {
            // Valid surrogate pair — decode and validate the full code point
            final rune = 0x10000 +
                ((codeUnit - 0xD800) << 10) +
                (nextCodeUnit - 0xDC00);
            if (_isValidRune(rune)) {
              buffer.writeCharCode(rune);
            }
            i++; // Skip low surrogate
            continue;
          }
        }
        // Orphan high surrogate — skip
        continue;
      }

      if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) {
        // Orphan low surrogate — skip
        continue;
      }

      // Single code unit (BMP character)
      if (_isValidRune(codeUnit)) {
        buffer.writeCharCode(codeUnit);
      }
    }

    return buffer.toString();
  }

  /// Cek apakah rune valid untuk UTF-16 encoding.
  static bool _isValidRune(int rune) {
    // Hindari non-characters: 0xFDD0-0xFDEF
    if (rune >= 0xFDD0 && rune <= 0xFDEF) {
      return false;
    }

    // Hindari non-characters di low BMP dan supplementary: xxxFFFE / xxxFFFF
    if ((rune & 0xFFFE) == 0xFFFE) {
      return false;
    }

    //超出 Unicode maximum
    if (rune > 0x10FFFF) {
      return false;
    }

    return true;
  }

  /// Sanitasi string khusus untuk rendering di Text widgets.
  /// Versi lebih agresif untuk mencegah crash di TextSpan / _NativeParagraphBuilder.
  static String sanitizeForTextWidget(String? text) {
    if (text == null) return '';

    // Sanitasi dasar: perbaiki surrogate pairs
    String sanitized = sanitizeText(text);

    // Hapus karakter kontrol yang bisa menyebabkan rendering issues
    // (kecuali tab \t = 0x09, newline \n = 0x0A, carriage return \r = 0x0D)
    sanitized = sanitized.replaceAll(RegExp(r'[\x00-\x08\x0B-\x0C\x0E-\x1F]'), '');

    // Ganti line/paragraph separator yang sering menyebabkan crash
    sanitized = sanitized.replaceAll(RegExp(r'[\u2028\u2029]'), ' ');

    return sanitized;
  }

  /// Sanitasi string untuk display di UI dengan panjang terbatas.
  static String sanitizeForDisplay(String? text, {int maxLength = 1000}) {
    if (text == null) return '';

    String sanitized = sanitizeForTextWidget(text);

    if (sanitized.length > maxLength) {
      sanitized = sanitized.substring(0, maxLength);
    }

    return sanitized;
  }

  /// Sanitasi string dari LLM/API response yang mungkin mengandung formatting.
  static String sanitizeFromApiResponse(String? text) {
    if (text == null) return '';

    String sanitized = sanitizeForTextWidget(text);

    // Hapus semua karakter kontrol untuk keamanan parsing
    sanitized = sanitized.replaceAll(RegExp(r'[\u0000-\u001F]'), '');

    return sanitized;
  }
}