import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/network/gemini_service.dart';
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
  final _gemini = GeminiService();
  late final TextEditingController _urlController;
  late final TextEditingController _keyController;
  late final TextEditingController _geminiController;

  bool _loading = true;
  bool _geminiTesting = false;
  bool _geminiVerified = false;
  bool _geminiModelsLoading = false;
  String? _selectedGeminiModel;
  List<GeminiModelOption> _geminiModels = const <GeminiModelOption>[];
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
    final geminiModel = await _config.getGeminiModel();
    final geminiVerified = await _config.isGeminiVerified();

    if (mounted) {
      setState(() {
        _urlController.text = url ?? '';
        _keyController.text = key ?? '';
        _geminiController.text = gemini ?? '';
        _selectedGeminiModel = geminiModel?.trim().isEmpty == true
            ? null
            : geminiModel;
        _geminiVerified = geminiVerified;
        _loading = false;
      });
      _checkAllConnections(persistGemini: true);
    }
  }

  Future<void> _checkAllConnections({bool persistGemini = false}) async {
    await Future.wait([_checkSupabase(), _checkGemini(persist: persistGemini)]);
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
      await client
          .from('assistant_memories_cloud')
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 10));
      stopwatch.stop();

      setState(() {
        _supabaseStatus = 'Terhubung (${stopwatch.elapsedMilliseconds}ms)';
        _supabaseColor = Colors.green;
      });
    } catch (e) {
      final err = e.toString().toLowerCase();
      if (err.contains('timeout') ||
          err.contains('504') ||
          err.contains('503')) {
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

  Future<void> _checkGemini({bool persist = false}) async {
    final key = _geminiController.text.trim();
    if (key.isEmpty) {
      if (!mounted) return;
      setState(() {
        _geminiModels = const <GeminiModelOption>[];
        _geminiVerified = false;
        _geminiStatus = 'Belum Aktif';
        _geminiColor = Colors.grey;
      });
      if (persist) {
        await _config.saveGeminiKey('');
        await _config.saveGeminiModel('');
        await _config.setGeminiVerified(false);
      }
      return;
    }

    if (mounted) {
      setState(() {
        _geminiStatus = 'Mencari model untuk API key...';
        _geminiColor = Colors.orange;
        _geminiVerified = false;
      });
    }
    final modelsResult = await _gemini.fetchModels(apiKey: key);
    final models = modelsResult.models;
    if (models.isEmpty) {
      if (mounted) {
        setState(() {
          _geminiModels = const <GeminiModelOption>[];
          _geminiVerified = false;
          _geminiStatus = modelsResult.message;
          _geminiColor = Colors.red;
        });
      }
      if (persist) {
        await _config.saveGeminiKey(key);
        await _config.saveGeminiModel('');
        await _config.setGeminiVerified(false);
      }
      return;
    }

    final model = models.any((item) => item.id == _selectedGeminiModel)
        ? _selectedGeminiModel
        : models.first.id;
    if (mounted) {
      setState(() {
        _geminiModels = models;
        _selectedGeminiModel = model;
        _geminiStatus = 'Menguji $model...';
        _geminiColor = Colors.orange;
        _geminiVerified = false;
      });
    }
    final result = await _gemini.testConnection(apiKey: key, model: model);
    if (mounted) {
      setState(() {
        _geminiModels = models;
        _geminiVerified = result.ok;
        _geminiStatus = result.message;
        _geminiColor = result.ok ? Colors.green : Colors.red;
      });
    }
    if (persist) {
      await _config.saveGeminiKey(key);
      await _config.saveGeminiModel(model ?? '');
      await _config.setGeminiVerified(result.ok);
    }
  }

  Future<void> _testGeminiKey() async {
    if (_geminiTesting) return;
    setState(() => _geminiTesting = true);
    try {
      await _checkGemini(persist: true);
    } finally {
      if (mounted) setState(() => _geminiTesting = false);
    }
  }

  Future<void> _loadGeminiModels() async {
    final key = _geminiController.text.trim();
    if (key.isEmpty || _geminiModelsLoading) return;
    setState(() => _geminiModelsLoading = true);
    final result = await _gemini.fetchModels(apiKey: key);
    if (!mounted) return;
    setState(() {
      _geminiModels = result.models;
      if (result.models.isNotEmpty &&
          !_geminiModels.any((model) => model.id == _selectedGeminiModel)) {
        _selectedGeminiModel = _geminiModels.first.id;
      }
      _geminiModelsLoading = false;
      if (result.models.isEmpty && !_geminiVerified) {
        _geminiStatus = result.message;
        _geminiColor = Colors.red;
      } else if (result.models.isNotEmpty && !_geminiVerified) {
        _geminiStatus = result.message;
        _geminiColor = Colors.orange;
      }
    });
  }

  Future<void> _save() async {
    if (_geminiTesting) return;
    setState(() => _loading = true);
    final key = _geminiController.text.trim();
    final model = _selectedGeminiModel;
    final result = key.isNotEmpty && model != null
        ? await _gemini.testConnection(apiKey: key, model: model)
        : null;
    final geminiSucceeded = result?.ok == true;
    await _config.save(_urlController.text.trim(), _keyController.text.trim());
    await _config.saveGeminiKey(key);
    await _config.saveGeminiModel(model ?? '');
    await _config.setGeminiVerified(geminiSucceeded);
    await SupabaseClientProvider.reset();
    if (mounted) setState(() => _loading = false);
    await _checkAllConnections(persistGemini: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            geminiSucceeded
                ? 'Konfigurasi tersimpan dan Gemini berhasil diuji.'
                : 'Supabase tersimpan, tetapi Gemini tidak diaktifkan karena test gagal atau model belum dipilih.',
          ),
        ),
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
          const Text(
            'Intelligence Status',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          _StatusRow(
            label: 'Cloud Memory (Supabase)',
            status: _supabaseStatus ?? '-',
            color: _supabaseColor,
          ),
          const Divider(height: 20),
          _StatusRow(
            label:
                _geminiVerified && (_selectedGeminiModel?.isNotEmpty ?? false)
                ? 'Gemini Cloud (· $_selectedGeminiModel)'
                : 'Gemini Cloud (belum aktif)',
            status: _geminiStatus ?? 'Belum Aktif',
            color: _geminiColor,
          ),
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
          decoration: const InputDecoration(
            labelText: 'Project URL',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _keyController,
          decoration: const InputDecoration(
            labelText: 'Anon Key',
            border: OutlineInputBorder(),
          ),
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
          obscureText: true,
          onChanged: (_) {
            setState(() {
              _selectedGeminiModel = null;
              _geminiModels = const <GeminiModelOption>[];
              _geminiVerified = false;
              _geminiStatus = 'Key berubah; tekan Test API Key lalu Simpan';
              _geminiColor = Colors.orange;
            });
          },
          decoration: const InputDecoration(
            labelText: 'Gemini API Key',
            hintText: 'Dapatkan di aistudio.google.com',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue:
              _geminiModels.any((model) => model.id == _selectedGeminiModel)
              ? _selectedGeminiModel
              : null,
          decoration: const InputDecoration(
            labelText: 'Model Gemini',
            border: OutlineInputBorder(),
          ),
          items: _geminiModels
              .map(
                (model) => DropdownMenuItem(
                  value: model.id,
                  child: Text(model.displayName),
                ),
              )
              .toList(),
          onChanged: (model) {
            if (model == null) return;
            setState(() {
              _selectedGeminiModel = model;
              _geminiVerified = false;
              _geminiStatus = 'Model berubah; tekan Test API Key lalu Simpan';
              _geminiColor = Colors.orange;
            });
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _geminiTesting ? null : _testGeminiKey,
              icon: _geminiTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check),
              label: Text(_geminiTesting ? 'Menguji...' : 'Test API Key'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _geminiModelsLoading ? null : _loadGeminiModels,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Muat model dari key'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _geminiVerified
              ? 'Gemini Cloud aktif di chat dengan model $_selectedGeminiModel yang tersimpan.'
              : 'Test API Key harus berhasil agar pasangan key + model disimpan dan dipakai chatbot.',
          style: const TextStyle(fontSize: 12),
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
              const Expanded(
                child: Text(
                  'Database Setup (SQL)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                onPressed: _copySql,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Salin'),
              ),
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
  const _StatusRow({
    required this.label,
    required this.status,
    required this.color,
  });
  final String label;
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          flex: 2,
          child: Text(
            status,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
