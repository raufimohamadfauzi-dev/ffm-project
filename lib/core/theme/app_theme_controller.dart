import 'package:flutter/material.dart';
import 'theme_preference.dart';

/// Pengendali tema global aplikasi FFM yang dapat dikendalikan via AI Assistant.
class AppThemeController extends ChangeNotifier {
  AppThemeController({ThemeMode initialMode = ThemeMode.light})
      : _themeMode = initialMode;

  ThemeMode _themeMode;

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  /// Memuat preferensi tema yang tersimpan di lokal.
  Future<void> loadSavedTheme() async {
    final saved = await ThemePreference.getThemeMode();
    _themeMode = switch (saved.toLowerCase()) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
    notifyListeners();
  }

  /// Mengubah tema aplikasi secara langsung dan menyimpannya.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final modeName = switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    };
    await ThemePreference.saveThemeMode(modeName);
  }

  /// Membalik tema saat ini: jika gelap jadi terang, jika terang/sistem jadi gelap.
  Future<String> toggleTheme() async {
    final nextMode = isDark ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(nextMode);
    return nextMode == ThemeMode.dark ? 'dark' : 'light';
  }

  /// Mengubah tema berdasarkan string kata kunci (misal dari perintah teks asisten).
  Future<String> setByName(String name) async {
    final clean = name.trim().toLowerCase();
    if (clean.contains('sistem') ||
        clean.contains('system') ||
        clean.contains('default')) {
      await setThemeMode(ThemeMode.system);
      return 'system';
    } else if (clean.contains('dark') ||
        clean.contains('gelap') ||
        clean.contains('hitam') ||
        clean.contains('redup') ||
        clean.contains('black') ||
        clean.contains('malam')) {
      await setThemeMode(ThemeMode.dark);
      return 'dark';
    } else if (clean.contains('light') ||
        clean.contains('terang') ||
        clean.contains('putih') ||
        clean.contains('white') ||
        clean.contains('siang')) {
      await setThemeMode(ThemeMode.light);
      return 'light';
    } else if (clean.contains('toggle') ||
        clean.contains('tukar') ||
        clean.contains('ganti') ||
        clean.contains('ubah')) {
      return toggleTheme();
    } else {
      await setThemeMode(ThemeMode.system);
      return 'system';
    }
  }
}
