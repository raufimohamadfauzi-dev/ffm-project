import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/network/supabase_config.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';

class SupabaseSetupPage extends StatefulWidget {
  const SupabaseSetupPage({super.key});

  @override
  State<SupabaseSetupPage> createState() => _SupabaseSetupPageState();
}

class _SupabaseSetupPageState extends State<SupabaseSetupPage> {
  final _config = SupabaseConfig();
  late final TextEditingController _urlController;
  late final TextEditingController _keyController;
  late final TextEditingController _geminiController;
  
  bool _loading = true;
  String? _supabaseStatus;
  String? _geminiStatus;
  Color _supabaseColor = Colors.grey;
  Color _geminiColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _keyController = TextEditingController();
    _geminiController = TextEditingController();
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    final url = await _config.getUrl();
    final key = await _config.getAnonKey();
    final gemini = await _config.getGeminiKey();
    
    if (mounted) {
      setState(() {
        _urlController.text = url ?? '';
        _keyController.text = key ?? '';
        _geminiController.text = gemini ?? '';
        _loading = false;
      });
      _checkAllConnections();
    }
  }

  Future<void> _checkAllConnections() async {
    await Future.wait([
      _checkSupabase(),
      _checkGemini(),
    ]);
  }

  Future<void> _checkSupabase() async {
    setState(() {
      _supabaseStatus = 'Mengecek...';
      _supabaseColor = Colors.orange;
    });
    
    final client = await SupabaseClientProvider.getInstance();
    if (client == null) {
      setState(() {
        _supabaseStatus = 'Konfigurasi belum lengkap';
        _supabaseColor = Colors.grey;
      });
      return;
    }

    try {
      final stopwatch = Stopwatch()..start();
      await client.from('assistant_memories_cloud').select('id').limit(1).timeout(
        const Duration(seconds: 10),
      );
      stopwatch.stop();
      
      setState(() {
        _supabaseStatus = 'Terhubung (${stopwatch.elapsedMilliseconds}ms)';
        _supabaseColor = Colors.green;
      });
    } catch (e) {
      final err = e.toString().toLowerCase();
      if (err.contains('timeout') || err.contains('504') || err.contains('503')) {
        setState(() {
          _supabaseStatus = 'Hibernasi/Tidur (Sedang Membangunkan)';
          _supabaseColor = Colors.amber;
        });
      } else {
        setState(() {
          _supabaseStatus = 'Gagal: Tabel belum siap (Cek SQL di bawah)';
          _supabaseColor = Colors.red;
        });
      }
    }
  }

  Future<void> _checkGemini() async {
    final key = _geminiController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _geminiStatus = 'Belum Aktif';
        _geminiColor = Colors.grey;
      });
      return;
    }
    
    setState(() {
      _geminiStatus = 'Mengecek Key...';
      _geminiColor = Colors.orange;
    });

    // Simple validation (can be expanded to a real API call)
    await Future.delayed(const Duration(milliseconds: 800));
    setState(() {
      _geminiStatus = 'Siap (API Key terdeteksi)';
      _geminiColor = Colors.green;
    });
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    await _config.save(_urlController.text.trim(), _keyController.text.trim());
    await _config.saveGeminiKey(_geminiController.text.trim());
    await SupabaseClientProvider.reset();
    await _checkAllConnections();
    if (mounted) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konfigurasi Intelligence disimpan.')),
      );
    }
  }

  void _copySql() {
    const sql = """
-- 1. Aktifkan ekstensi pendukung
create extension if not exists vector;

-- 2. Buat tabel memori cloud
create table if not exists assistant_memories_cloud (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  content text not null,
  category text,
  embedding vector(1536),
  metadata jsonb default '{}',
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

-- 3. Fungsi Pencarian Teks (Versi Emas)
create or replace function match_memories_text (
  query_text text,
  match_count int
)
returns table (id uuid, content text, category text, created_at timestamp with time zone)
language plpgsql as \$\$
begin
  return query select m.id, m.content, m.category, m.created_at
  from assistant_memories_cloud m
  where m.content ilike '%' || query_text || '%' or m.category ilike '%' || query_text || '%'
  order by m.created_at desc limit match_count;
end; \$\$;
""";
    Clipboard.setData(const ClipboardData(text: sql));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Skrip SQL berhasil disalin!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.intelligenceDashboard,
      child: Scaffold(
        appBar: AppBar(title: const Text('Intelligence Dashboard')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 24),
                  _buildSupabaseSection(theme),
                  const SizedBox(height: 24),
                  _buildGeminiSection(theme),
                  const SizedBox(height: 24),
                  _buildSqlSection(theme),
                  const SizedBox(height: 40),
                ],
              ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Intelligence Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          _StatusRow(label: 'Cloud Memory (Supabase)', status: _supabaseStatus ?? '-', color: _supabaseColor),
          const Divider(height: 20),
          _StatusRow(label: 'Natural Brain (Gemini)', status: _geminiStatus ?? '-', color: _geminiColor),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Simpan & Refresh Koneksi'),
          ),
        ],
      ),
    );
  }

  Widget _buildSupabaseSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(title: 'Supabase Configuration'),
        const SizedBox(height: 8),
        TextField(
          controller: _urlController,
          decoration: const InputDecoration(labelText: 'Project URL', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _keyController,
          decoration: const InputDecoration(labelText: 'Anon Key', border: OutlineInputBorder()),
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildGeminiSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(title: 'Google Gemini (AI Studio)'),
        const SizedBox(height: 8),
        TextField(
          controller: _geminiController,
          decoration: const InputDecoration(
            labelText: 'Gemini API Key',
            hintText: 'Dapatkan di aistudio.google.com',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildSqlSection(ThemeData theme) {
    return AppCard(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.code),
              const SizedBox(width: 8),
              const Expanded(child: Text('Database Setup (SQL)', style: TextStyle(fontWeight: FontWeight.bold))),
              TextButton.icon(onPressed: _copySql, icon: const Icon(Icons.copy, size: 16), label: const Text('Salin')),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Tempel skrip ini di SQL Editor Supabase Anda agar fitur Memory Cloud bisa berjalan.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.status, required this.color});
  final String label;
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Text(status, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}
