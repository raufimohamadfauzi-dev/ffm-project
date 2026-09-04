import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFFF7FAF9);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceContainer = Color(0xFFE8F1EF);
  static const surfaceContainerHigh = Color(0xFFD6E5E2);
  static const ink = Color(0xFF10201F);
  static const inkMuted = Color(0xFF3F514F);
  static const outline = Color(0xFF8FA9A5);
  static const primary = Color(0xFF005454);
  static const primaryContainer = Color(0xFFC7EFEB);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primarySoft = Color(0xFFC7EFEB);
  static const positive = Color(0xFF006B3A);
  static const positiveSoft = Color(0xFFD9F6E5);
  static const negative = Color(0xFFA32222);
  static const negativeSoft = Color(0xFFFFE4DF);
  static const warning = Color(0xFF8A4B00);
  static const warningSoft = Color(0xFFFFF0D2);
  static const accent = Color(0xFF8C5B00);
}

abstract final class AppTheme {
  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          surface: AppColors.background,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: AppColors.onPrimary,
          primaryContainer: AppColors.primarySoft,
          onPrimaryContainer: AppColors.ink,
          secondary: AppColors.primary,
          onSecondary: AppColors.onPrimary,
          secondaryContainer: AppColors.surfaceContainer,
          onSecondaryContainer: AppColors.ink,
          surface: AppColors.background,
          surfaceContainerLowest: AppColors.surface,
          surfaceContainerLow: AppColors.surface,
          surfaceContainer: AppColors.surfaceContainer,
          surfaceContainerHigh: AppColors.surfaceContainerHigh,
          onSurface: AppColors.ink,
          onSurfaceVariant: AppColors.inkMuted,
          outline: AppColors.outline,
          outlineVariant: AppColors.surfaceContainerHigh,
          error: AppColors.negative,
          onError: AppColors.onPrimary,
          errorContainer: AppColors.negativeSoft,
          onErrorContainer: AppColors.ink,
        );

    const roundedCard = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(18)),
      side: BorderSide(color: AppColors.outline, width: 0.7),
    );
    const roundedControl = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      visualDensity: VisualDensity.standard,
      textTheme: base.textTheme
          .apply(
            fontFamily: 'Hanken Grotesk',
            bodyColor: AppColors.ink,
            displayColor: AppColors.ink,
          )
          .copyWith(
            displayLarge: const TextStyle(
              color: AppColors.ink,
              fontSize: 32,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.64,
            ),
            headlineMedium: const TextStyle(
              color: AppColors.ink,
              fontSize: 22,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
            titleLarge: const TextStyle(
              color: AppColors.ink,
              fontSize: 20,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
            titleMedium: const TextStyle(
              color: AppColors.ink,
              fontSize: 17,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
            bodyLarge: const TextStyle(
              color: AppColors.ink,
              fontSize: 16,
              height: 1.5,
            ),
            bodyMedium: const TextStyle(
              color: AppColors.ink,
              fontSize: 14,
              height: 1.45,
            ),
            labelLarge: const TextStyle(
              color: AppColors.ink,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 22,
          height: 1.3,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: roundedCard,
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: AppColors.outline, width: 1),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: AppColors.outline, width: 1),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: AppColors.negative, width: 1.5),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: AppColors.negative, width: 2),
        ),
        labelStyle: const TextStyle(color: AppColors.inkMuted),
        floatingLabelStyle: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: const TextStyle(color: AppColors.inkMuted),
        helperStyle: const TextStyle(color: AppColors.inkMuted, height: 1.35),
        errorStyle: const TextStyle(
          color: AppColors.negative,
          fontWeight: FontWeight.w600,
        ),
        prefixStyle: const TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
        suffixStyle: const TextStyle(color: AppColors.ink),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: AppColors.outline),
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        minVerticalPadding: 8,
        iconColor: AppColors.primary,
        textColor: AppColors.ink,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(
          color: AppColors.inkMuted,
          fontSize: 13,
          height: 1.35,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.outline,
        thickness: 0.7,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceContainer,
        selectedColor: AppColors.primarySoft,
        side: const BorderSide(color: AppColors.outline),
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(
          color: AppColors.ink,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        indicatorColor: AppColors.primarySoft,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Hanken Grotesk',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        iconTheme: const WidgetStatePropertyAll(
          IconThemeData(color: AppColors.inkMuted, size: 24),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: roundedControl,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: const BorderSide(color: AppColors.primary, width: 1.4),
          shape: roundedControl,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 2,
        shape: roundedControl,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 18),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(color: AppColors.surface),
        shape: roundedControl,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: roundedCard,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }

  static ThemeData dark() {
    const background = Color(0xFF081110);
    const surface = Color(0xFF101D1C);
    const surfaceContainer = Color(0xFF19312F);
    const surfaceContainerHigh = Color(0xFF234743);
    const ink = Color(0xFFFFFFFF);
    const inkMuted = Color(0xFFD0E2DE);
    const outline = Color(0xFF789A93);
    const primary = Color(0xFF7FF5EA);
    const primaryContainer = Color(0xFF0B716B);
    const onPrimary = Color(0xFF00201E);
    const primarySoft = Color(0xFF18514D);
    const negative = Color(0xFFFFB4AB);
    const negativeSoft = Color(0xFF5B2523);

    final base = ThemeData.dark(useMaterial3: true);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
          surface: background,
        ).copyWith(
          primary: primary,
          onPrimary: onPrimary,
          primaryContainer: primaryContainer,
          onPrimaryContainer: ink,
          secondary: primary,
          onSecondary: onPrimary,
          secondaryContainer: primarySoft,
          onSecondaryContainer: ink,
          surface: background,
          surfaceContainerLowest: surface,
          surfaceContainerLow: surface,
          surfaceContainer: surfaceContainer,
          surfaceContainerHigh: surfaceContainerHigh,
          onSurface: ink,
          onSurfaceVariant: inkMuted,
          outline: outline,
          outlineVariant: outline,
          error: negative,
          onError: onPrimary,
          errorContainer: negativeSoft,
          onErrorContainer: ink,
        );

    const roundedCard = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(18)),
      side: BorderSide(color: outline, width: 0.7),
    );
    const roundedControl = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
    );
    final textTheme = base.textTheme
        .apply(fontFamily: 'Hanken Grotesk', bodyColor: ink, displayColor: ink)
        .copyWith(
          displayLarge: const TextStyle(
            color: ink,
            fontSize: 32,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.64,
          ),
          headlineMedium: const TextStyle(
            color: ink,
            fontSize: 22,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
          titleLarge: const TextStyle(
            color: ink,
            fontSize: 20,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
          titleMedium: const TextStyle(
            color: ink,
            fontSize: 17,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
          bodyLarge: const TextStyle(color: ink, fontSize: 16, height: 1.5),
          bodyMedium: const TextStyle(color: ink, fontSize: 14, height: 1.45),
          labelLarge: const TextStyle(
            color: ink,
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      visualDensity: VisualDensity.standard,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 22,
          height: 1.3,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: roundedCard,
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: outline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: outline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: negative, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: negative, width: 2),
        ),
        labelStyle: TextStyle(color: inkMuted),
        floatingLabelStyle: TextStyle(color: primary),
        hintStyle: TextStyle(color: inkMuted),
        helperStyle: TextStyle(color: inkMuted, height: 1.35),
        errorStyle: TextStyle(color: negative, fontWeight: FontWeight.w600),
        prefixStyle: TextStyle(color: ink, fontWeight: FontWeight.w700),
        suffixStyle: TextStyle(color: ink),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: outline),
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        minVerticalPadding: 8,
        iconColor: primary,
        textColor: ink,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(
          color: inkMuted,
          fontSize: 13,
          height: 1.35,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: outline,
        thickness: 0.7,
        space: 1,
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: surfaceContainer,
        selectedColor: primarySoft,
        side: BorderSide(color: outline),
        shape: StadiumBorder(),
        labelStyle: TextStyle(
          color: ink,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
        indicatorColor: primarySoft,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Hanken Grotesk',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: primary,
          ),
        ),
        iconTheme: WidgetStatePropertyAll(
          IconThemeData(color: inkMuted, size: 24),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: roundedControl,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: const BorderSide(color: primary, width: 1.4),
          shape: roundedControl,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 2,
        shape: roundedControl,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 18),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceContainerHigh,
        contentTextStyle: const TextStyle(color: ink),
        shape: roundedControl,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: roundedCard,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }
}

abstract final class AppTextStyles {
  static const moneyLarge = TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: 30,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  static const moneyMedium = TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: 17,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  static const labelCaps = TextStyle(
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.45,
  );
  static const bodyLarge = TextStyle(fontSize: 16, height: 1.5);
  static const bodyMedium = TextStyle(fontSize: 14, height: 1.45);
  static const bodySmall = TextStyle(fontSize: 12, height: 1.4);
}
