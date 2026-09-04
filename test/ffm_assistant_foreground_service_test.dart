import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_foreground_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FfmAssistantForegroundServiceManager', () {
    late SharedPreferences prefs;
    late FfmAssistantForegroundServiceManager manager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      manager = FfmAssistantForegroundServiceManager(preferences: prefs);
    });

    test('default status is disabled (false)', () async {
      final enabled = await manager.isEnabled();
      expect(enabled, isFalse);
    });

    test('setEnabled updates SharedPreferences preference correctly', () async {
      expect(await manager.isEnabled(), isFalse);

      await manager.setEnabled(true);
      expect(await manager.isEnabled(), isTrue);
      expect(
        prefs.getBool(FfmAssistantForegroundServiceManager.preferenceKey),
        isTrue,
      );

      await manager.setEnabled(false);
      expect(await manager.isEnabled(), isFalse);
      expect(
        prefs.getBool(FfmAssistantForegroundServiceManager.preferenceKey),
        isFalse,
      );
    });

    test('constants have valid values for Android Foreground Service', () {
      expect(FfmAssistantForegroundServiceManager.serviceId, equals(256));
      expect(
        FfmAssistantForegroundServiceManager.intervalMillis,
        equals(15 * 60 * 1000),
      );
      expect(FfmAssistantForegroundServiceManager.channelId, isNotEmpty);
      expect(FfmAssistantForegroundServiceManager.channelName, isNotEmpty);
    });
  });
}
