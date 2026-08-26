import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class SupabaseConfig {
  static const _urlKey = 'supabase_url';
  static const _anonKey = 'supabase_anon_key';
  static const _userKey = 'supabase_user_id';
  static const _geminiKey = 'gemini_api_key';
  static const _llmModeKey = 'preferred_llm_mode';
  
  // No longer hardcoded defaults for keys to encourage UI setup
  static const defaultUrl = '';
  static const defaultAnonKey = '';

  final _storage = const FlutterSecureStorage();

  Future<String?> getUrl() async => await _storage.read(key: _urlKey);
  Future<String?> getAnonKey() async => await _storage.read(key: _anonKey);
  Future<String?> getGeminiKey() async => await _storage.read(key: _geminiKey);

  Future<String> getLlmMode() async {
    return await _storage.read(key: _llmModeKey) ?? 'auto';
  }

  Future<void> setLlmMode(String mode) async {
    await _storage.write(key: _llmModeKey, value: mode);
  }

  Future<void> saveGeminiKey(String key) async {
    await _storage.write(key: _geminiKey, value: key);
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
