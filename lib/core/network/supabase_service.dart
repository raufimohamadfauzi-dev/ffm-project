import 'supabase_client_provider.dart';
import 'supabase_config.dart';

class SupabaseService {
  final _config = SupabaseConfig();

  Future<void> saveMemory({
    required String content,
    required String category,
    Map<String, dynamic>? metadata,
  }) async {
    final client = await SupabaseClientProvider.getInstance();
    if (client == null) return;

    final userId = await _config.getUserId();

    try {
      await client.from('assistant_memories_cloud').upsert({
        'user_id': userId,
        'content': content,
        'category': category,
        'metadata': metadata ?? {},
      }).timeout(const Duration(seconds: 10));
    } catch (e) {
      // Background sync, fail silently
    }
  }

  Future<List<Map<String, dynamic>>> searchMemories({
    required String query,
    int limit = 5,
  }) async {
    final client = await SupabaseClientProvider.getInstance();
    if (client == null) return [];

    try {
      final response = await client.rpc('match_memories_text', params: {
        'query_text': query,
        'match_count': limit,
      }).timeout(const Duration(seconds: 8));
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteMemory(String id) async {
    final client = await SupabaseClientProvider.getInstance();
    if (client == null) return;
    try {
      await client.from('assistant_memories_cloud').delete().eq('id', id).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> fetchAll() async {
    final client = await SupabaseClientProvider.getInstance();
    if (client == null) return [];
    try {
      final response = await client
          .from('assistant_memories_cloud')
          .select()
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 15));
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }
}
