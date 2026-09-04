import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capabilities.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Assistant Theme Capability Tests', () {
    test('capability system.set_theme terdaftar di registry', () {
      final capability = FfmAssistantCapabilityRegistry.find('system.set_theme');
      expect(capability, isNotNull);
      expect(capability!.id, 'system.set_theme');
      expect(capability.readOnly, isTrue);
      expect(capability.risk, FfmAssistantCapabilityRisk.readOnly);
    });

    test('FfmAssistantActionPlanner menyusun action step system.set_theme', () {
      const planner = FfmAssistantActionPlanner();
      const intent = FfmAssistantIntent(
        rawText: 'ubah ke mode gelap',
        normalizedText: 'ubah ke mode gelap',
        type: FfmAssistantIntentType.changeTheme,
        confidence: 1.0,
        pluginMetadata: {'theme': 'dark'},
      );

      final plan = planner.planFor(intent);
      expect(plan, isNotNull);
      expect(plan!.steps.length, 1);
      expect(plan.steps.first.capabilityId, 'system.set_theme');
      expect(plan.steps.first.parameters['theme'], 'dark');
      expect(plan.requiresConfirmation, isFalse,
          reason: 'Ganti tema adalah UI preference aman, tidak boleh menuntut dialog konfirmasi');
    });

    test('FfmAssistantInterpreter mengenali berbagai variasi ekspresi tema bahasa Indonesia', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final interpreter = FfmAssistantInterpreter(db);

      // 1. Variasi Gelap: mode redup, mode hitam, gelapkan, bikin gelap, matiin lampu
      final phrasesDark = [
        'ubah ke dark mode',
        'mode redup',
        'mode hitam',
        'gelapkan',
        'hitamkan',
        'bikin gelap',
        'matiin lampu',
        'layar hitam',
        'tema malam',
      ];
      for (final phrase in phrasesDark) {
        final res = await interpreter.interpret(phrase);
        expect(res.type, FfmAssistantIntentType.changeTheme, reason: 'Failed on: $phrase');
        expect(res.pluginMetadata?['theme'], 'dark', reason: 'Failed theme on: $phrase');
        expect(res.response, contains('mode gelap'), reason: 'Failed response on: $phrase');
      }

      // 2. Variasi Terang: mode terang, mode putih, terangkan, nyalain lampu, bikin terang
      final phrasesLight = [
        'ganti tema terang',
        'mode putih',
        'terangkan',
        'nyalain lampu',
        'bikin terang',
        'layar putih',
      ];
      for (final phrase in phrasesLight) {
        final res = await interpreter.interpret(phrase);
        expect(res.type, FfmAssistantIntentType.changeTheme, reason: 'Failed on: $phrase');
        expect(res.pluginMetadata?['theme'], 'light', reason: 'Failed theme on: $phrase');
        expect(res.response, contains('mode terang'), reason: 'Failed response on: $phrase');
      }

      // 3. Variasi Sistem
      final systemIntent = await interpreter.interpret('tema ikuti sistem');
      expect(systemIntent.type, FfmAssistantIntentType.changeTheme);
      expect(systemIntent.pluginMetadata?['theme'], 'system');
      expect(systemIntent.response, contains('sistem'));

      // 4. Perintah Toggle Umum: ubah mode, ganti tema, ganti warna, tema ganti
      final phrasesToggle = [
        'ubah mode',
        'ganti tema',
        'ganti warna',
        'tema ganti',
      ];
      for (final phrase in phrasesToggle) {
        final res = await interpreter.interpret(phrase);
        expect(res.type, FfmAssistantIntentType.changeTheme, reason: 'Failed on: $phrase');
        // Default awal adalah light, jadi toggle menghasilkan dark
        expect(res.pluginMetadata?['theme'], 'dark', reason: 'Failed toggle on: $phrase');
      }

      // 5. Query / Deteksi Status Tema: "mode apa sekarang?", "cek mode"
      final queryIntent = await interpreter.interpret('mode apa sekarang?');
      expect(queryIntent.type, FfmAssistantIntentType.queryData);
      expect(queryIntent.response, contains('Mode Terang'));

      // 6. Gemini Cloud routing tetap deterministik menangani ganti tema secara instan
      final geminiCloudDarkIntent = await interpreter.interpret(
        'pindah mode gelap',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );
      expect(geminiCloudDarkIntent.type, FfmAssistantIntentType.changeTheme);
      expect(geminiCloudDarkIntent.pluginMetadata?['theme'], 'dark');
      expect(geminiCloudDarkIntent.response, contains('mode gelap'));

      // 7. Koreksi user
      final correctionIntent = await interpreter.interpret(
        'salah, sekarang harusnya mode gelap',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );
      expect(correctionIntent.type, FfmAssistantIntentType.changeTheme);
      expect(correctionIntent.pluginMetadata?['theme'], 'dark');

      await db.close();
    });
  });
}
