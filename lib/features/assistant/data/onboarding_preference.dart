import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Menyimpan status penyelesaian onboarding asisten lokal.
abstract final class OnboardingPreference {
  static const _storage = FlutterSecureStorage();
  static const _key = 'ffm_onboarding_completed';

  static Future<bool> isCompleted() async {
    final value = await _storage.read(key: _key);
    return value == 'true';
  }

  static Future<void> setCompleted(bool completed) {
    return _storage.write(key: _key, value: completed ? 'true' : 'false');
  }
}
