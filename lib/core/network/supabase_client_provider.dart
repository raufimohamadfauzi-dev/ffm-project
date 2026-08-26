import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';

class SupabaseClientProvider {
  static SupabaseClient? _client;

  static Future<SupabaseClient?> getInstance() async {
    if (_client != null) return _client;

    final config = SupabaseConfig();
    final url = await config.getUrl();
    final anonKey = await config.getAnonKey();

    if (url == null || anonKey == null) return null;

    try {
      await Supabase.initialize(
        url: url,
        publishableKey: anonKey,
        debug: false,
      );
      _client = Supabase.instance.client;
      return _client;
    } catch (e) {
      // Failed to initialize (e.g. invalid URL)
      return null;
    }
  }

  static Future<void> reset() async {
    _client = null;
    // Supabase.dispose() doesn't exist in the same way, but we reset our singleton
  }
}
