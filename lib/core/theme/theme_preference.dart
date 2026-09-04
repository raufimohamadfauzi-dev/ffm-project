import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Preferensi tampilan yang tersimpan lokal dan tidak memengaruhi data keuangan.
abstract final class ThemePreference {
  static const _storage = FlutterSecureStorage();
  static const _key = 'ffm_theme_mode';

  static Future<String> getThemeMode() async {
    final value = await _storage.read(key: _key);
    return value ?? 'system';
  }

  static Future<bool> isDark() async {
    final value = await _storage.read(key: _key);
    return value == 'dark';
  }

  static Future<void> saveThemeMode(String mode) {
    return _storage.write(key: _key, value: mode);
  }

  static Future<void> saveDark(bool isDark) {
    return _storage.write(key: _key, value: isDark ? 'dark' : 'light');
  }
}
