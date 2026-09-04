import 'package:flutter/material.dart';
import 'theme_preference.dart';

/// Pengendali tema global aplikasi FFM yang dapat dikendalikan via AI Assistant.
class AppThemeController extends ChangeNotifier {
  AppThemeController({ThemeMode initialMode = ThemeMode.system})
      : _themeMode = initialMode;

  ThemeMode _themeMode;

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  /// Memuat preferensi tema yang tersimpan di lokal.
  Future<void> loadSavedTheme() async {
    final saved = await ThemePreference.getThemeMode();
    _themeMode = switch (saved.toLowerCase()) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
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

  /// Mengubah tema berdasarkan string kata kunci (misal dari perintah teks asisten).
  Future<String> setByName(String name) async {
    final clean = name.trim().toLowerCase();
    if (clean.contains('dark') || clean.contains('gelap') || clean.contains('malam')) {
      await setThemeMode(ThemeMode.dark);
      return 'dark';
    } else if (clean.contains('light') || clean.contains('terang') || clean.contains('siang')) {
      await setThemeMode(ThemeMode.light);
      return 'light';
    } else {
      await setThemeMode(ThemeMode.system);
      return 'system';
    }
  }
}
