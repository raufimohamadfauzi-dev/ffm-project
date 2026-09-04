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
    });

    test('FfmAssistantInterpreter mengenali berbagai variasi permintaan tema', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final interpreter = FfmAssistantInterpreter(db);

      // Skenario 1: Mode Gelap
      final darkIntent = await interpreter.interpret('ubah ke dark mode');
      expect(darkIntent.type, FfmAssistantIntentType.changeTheme);
      expect(darkIntent.pluginMetadata?['theme'], 'dark');
      expect(darkIntent.response, contains('mode gelap'));

      // Skenario 2: Mode Terang
      final lightIntent = await interpreter.interpret('ganti tema terang');
      expect(lightIntent.type, FfmAssistantIntentType.changeTheme);
      expect(lightIntent.pluginMetadata?['theme'], 'light');
      expect(lightIntent.response, contains('mode terang'));

      // Skenario 3: Mode Sistem
      final systemIntent = await interpreter.interpret('tema ikuti sistem');
      expect(systemIntent.type, FfmAssistantIntentType.changeTheme);
      expect(systemIntent.pluginMetadata?['theme'], 'system');
      expect(systemIntent.response, contains('sistem'));

      await db.close();
    });
  });
}
