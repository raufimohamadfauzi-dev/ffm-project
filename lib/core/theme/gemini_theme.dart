import 'package:flutter/material.dart';

abstract final class GeminiColors {
  // Teal accent as primary
  static const Color primary = Color(0xFF00C5FF);
  static const Color onPrimary = Colors.white;
  static const Color surface = Color(0xFF1E1E1E);
  static const Color background = Color(0xFF121212);
  static const Color onSurface = Colors.white70;
  static const Color outline = Color(0xFF555555);
}

class GeminiTheme {
  static ThemeData getTheme(bool isDark) {
    final brightness = isDark ? Brightness.dark : Brightness.light;
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      fontFamily: 'Hanken Grotesk',
    );
    final colorScheme = ColorScheme.fromSeed(
      seedColor: GeminiColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: GeminiColors.primary,
      onPrimary: GeminiColors.onPrimary,
      surface: isDark ? GeminiColors.surface : Colors.white,
      onSurface: isDark ? GeminiColors.onSurface : const Color(0xFF10201F),
      outline: GeminiColors.outline,
    );
    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark ? GeminiColors.background : const Color(0xFFF7FAF9),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? GeminiColors.background : const Color(0xFFF7FAF9),
        foregroundColor: isDark ? GeminiColors.onSurface : const Color(0xFF10201F),
        elevation: 0,
        titleTextStyle: TextStyle(
          color: isDark ? GeminiColors.onSurface : const Color(0xFF10201F),
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? GeminiColors.surface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? GeminiColors.surface : Colors.white,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
    );
  }
}
