import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/theme/app_theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('AppThemeController Unit Tests', () {
    test('default initial theme mode adalah light', () {
      final controller = AppThemeController();
      expect(controller.themeMode, ThemeMode.light);
      expect(controller.isDark, isFalse);
    });

    test('setThemeMode mengubah themeMode dan memicu listener', () async {
      final controller = AppThemeController();
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      await controller.setThemeMode(ThemeMode.dark);

      expect(controller.themeMode, ThemeMode.dark);
      expect(controller.isDark, isTrue);
      expect(notifyCount, 1);

      await controller.setThemeMode(ThemeMode.light);
      expect(controller.themeMode, ThemeMode.light);
      expect(controller.isDark, isFalse);
      expect(notifyCount, 2);
    });

    test('setByName mengenali kata kunci gelap/dark/malam/hitam/redup', () async {
      final controller = AppThemeController();

      var result = await controller.setByName('ubah ke dark mode');
      expect(result, 'dark');
      expect(controller.themeMode, ThemeMode.dark);

      result = await controller.setByName('ganti tema gelap');
      expect(result, 'dark');
      expect(controller.themeMode, ThemeMode.dark);

      result = await controller.setByName('aktifkan mode malam');
      expect(result, 'dark');
      expect(controller.themeMode, ThemeMode.dark);

      result = await controller.setByName('mode hitam');
      expect(result, 'dark');
      expect(controller.themeMode, ThemeMode.dark);

      result = await controller.setByName('mode redup');
      expect(result, 'dark');
      expect(controller.themeMode, ThemeMode.dark);
    });

    test('setByName mengenali kata kunci terang/light/siang/putih', () async {
      final controller = AppThemeController(initialMode: ThemeMode.dark);

      var result = await controller.setByName('ubah ke light mode');
      expect(result, 'light');
      expect(controller.themeMode, ThemeMode.light);

      result = await controller.setByName('tema terang');
      expect(result, 'light');
      expect(controller.themeMode, ThemeMode.light);

      result = await controller.setByName('mode siang');
      expect(result, 'light');
      expect(controller.themeMode, ThemeMode.light);

      result = await controller.setByName('mode putih');
      expect(result, 'light');
      expect(controller.themeMode, ThemeMode.light);
    });

    test('setByName toggleTheme membalikkan tema', () async {
      final controller = AppThemeController(initialMode: ThemeMode.light);

      var result = await controller.setByName('ganti tema');
      expect(result, 'dark');
      expect(controller.themeMode, ThemeMode.dark);

      result = await controller.setByName('tukar tema');
      expect(result, 'light');
      expect(controller.themeMode, ThemeMode.light);
    });

    test('setByName kata kunci default/defaut dan kata tidak dikenal beralih ke mode terang', () async {
      final controller = AppThemeController(initialMode: ThemeMode.dark);

      var result = await controller.setByName('kembalikan ke default');
      expect(result, 'light');
      expect(controller.themeMode, ThemeMode.light);

      await controller.setThemeMode(ThemeMode.dark);
      result = await controller.setByName('jadikan defaut mode terang ya, jangan mengikuti device');
      expect(result, 'light');
      expect(controller.themeMode, ThemeMode.light);

      await controller.setThemeMode(ThemeMode.dark);
      result = await controller.setByName('random text fallback');
      expect(result, 'light');
      expect(controller.themeMode, ThemeMode.light);
    });

    test('setByName mengenali kata kunci sistem jika diminta secara eksplisit', () async {
      final controller = AppThemeController(initialMode: ThemeMode.dark);

      final result = await controller.setByName('kembalikan ke sistem');
      expect(result, 'system');
      expect(controller.themeMode, ThemeMode.system);
    });

    test('loadSavedTheme menormalkan preferensi system atau kosong ke light mode', () async {
      final controller = AppThemeController();
      await controller.loadSavedTheme();
      expect(controller.themeMode, ThemeMode.light);

      // Simulasikan nilai tersimpan lama 'system'
      await FlutterSecureStorage().write(key: 'ffm_theme_mode', value: 'system');
      await controller.loadSavedTheme();
      expect(controller.themeMode, ThemeMode.light);
    });
  });
}
