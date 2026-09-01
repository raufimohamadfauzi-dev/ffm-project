import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class GeminiUsageSnapshot {
  const GeminiUsageSnapshot({
    required this.code,
    required this.model,
    required this.ok,
    required this.at,
    this.httpStatus,
    this.latencyMs,
  });

  final String code;
  final String model;
  final bool ok;
  final DateTime at;
  final int? httpStatus;
  final int? latencyMs;
}

class SupabaseConfig {
  static const _urlKey = 'supabase_url';
  static const _anonKey = 'supabase_anon_key';
  static const _userKey = 'supabase_user_id';
  static const _geminiKey = 'gemini_api_key';
  static const _geminiModelKey = 'gemini_model';
  static const _geminiVerifiedKey = 'gemini_api_verified';
  static const _geminiUsageCodeKey = 'gemini_last_usage_code';
  static const _geminiUsageModelKey = 'gemini_last_usage_model';
  static const _geminiUsageOkKey = 'gemini_last_usage_ok';
  static const _geminiUsageAtKey = 'gemini_last_usage_at';
  static const _geminiUsageHttpKey = 'gemini_last_usage_http';
  static const _geminiUsageLatencyKey = 'gemini_last_usage_latency_ms';
  static const _llmModeKey = 'preferred_llm_mode';

  static const defaultUrl = '';
  static const defaultAnonKey = '';

  final _storage = const FlutterSecureStorage();

  Future<String?> getUrl() async => await _storage.read(key: _urlKey);
  Future<String?> getAnonKey() async => await _storage.read(key: _anonKey);
  Future<String?> getGeminiKey() async => await _storage.read(key: _geminiKey);

  Future<String?> getGeminiModel() async =>
      await _storage.read(key: _geminiModelKey);

  Future<bool> isGeminiVerified() async =>
      (await _storage.read(key: _geminiVerifiedKey)) == 'true';

  Future<GeminiUsageSnapshot?> getGeminiUsage() async {
    final code = await _storage.read(key: _geminiUsageCodeKey);
    final model = await _storage.read(key: _geminiUsageModelKey);
    final ok = await _storage.read(key: _geminiUsageOkKey);
    final at = await _storage.read(key: _geminiUsageAtKey);
    if (code == null || model == null || ok == null || at == null) return null;
    final parsedAt = DateTime.tryParse(at);
    if (parsedAt == null) return null;
    return GeminiUsageSnapshot(
      code: code,
      model: model,
      ok: ok == 'true',
      at: parsedAt,
      httpStatus: int.tryParse(
        (await _storage.read(key: _geminiUsageHttpKey)) ?? '',
      ),
      latencyMs: int.tryParse(
        (await _storage.read(key: _geminiUsageLatencyKey)) ?? '',
      ),
    );
  }

  Future<String> getLlmMode() async {
    return await _storage.read(key: _llmModeKey) ?? 'gemini_cloud';
  }

  Future<void> setLlmMode(String mode) async {
    await _storage.write(key: _llmModeKey, value: mode);
  }

  Future<void> saveGeminiKey(String key) async {
    await _storage.write(key: _geminiKey, value: key);
    await invalidateGeminiVerification();
  }

  Future<void> saveGeminiModel(String model) async {
    await _storage.write(key: _geminiModelKey, value: model);
    await invalidateGeminiVerification();
  }

  Future<void> setGeminiVerified(bool verified) async {
    await _storage.write(
      key: _geminiVerifiedKey,
      value: verified ? 'true' : 'false',
    );
  }

  Future<void> invalidateGeminiVerification() async {
    await setGeminiVerified(false);
  }

  Future<void> saveVerifiedGeminiConfiguration({
    required String key,
    required String model,
    required bool verified,
  }) async {
    await _storage.write(key: _geminiKey, value: key);
    await _storage.write(key: _geminiModelKey, value: model);
    await setGeminiVerified(verified);
  }

  Future<void> saveGeminiUsage({
    required String code,
    required String model,
    required bool ok,
    required DateTime at,
    int? httpStatus,
    Duration? latency,
  }) async {
    await _storage.write(key: _geminiUsageCodeKey, value: code);
    await _storage.write(key: _geminiUsageModelKey, value: model);
    await _storage.write(key: _geminiUsageOkKey, value: ok ? 'true' : 'false');
    await _storage.write(key: _geminiUsageAtKey, value: at.toIso8601String());
    if (httpStatus == null) {
      await _storage.delete(key: _geminiUsageHttpKey);
    } else {
      await _storage.write(
        key: _geminiUsageHttpKey,
        value: httpStatus.toString(),
      );
    }
    if (latency == null) {
      await _storage.delete(key: _geminiUsageLatencyKey);
    } else {
      await _storage.write(
        key: _geminiUsageLatencyKey,
        value: latency.inMilliseconds.toString(),
      );
    }
  }

  Future<String> getUserId() async {
    final stored = await _storage.read(key: _userKey);
    if (stored != null) return stored;
    final newId = const Uuid().v4();
    await _storage.write(key: _userKey, value: newId);
    return newId;
  }

  Future<void> save(String url, String anonKey) async {
    await _storage.write(key: _urlKey, value: url);
    await _storage.write(key: _anonKey, value: anonKey);
  }

  Future<void> clear() async {
    await _storage.delete(key: _urlKey);
    await _storage.delete(key: _anonKey);
    await _storage.delete(key: _userKey);
  }
}
