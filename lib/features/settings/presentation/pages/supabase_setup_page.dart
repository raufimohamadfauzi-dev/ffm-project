import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/gemini_diagnostics.dart';
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
  final List<GeminiDiagnosticEvent> _geminiDiagnostics = [];
  GeminiUsageSnapshot? _lastGeminiUsage;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _keyController = TextEditingController();
    _geminiController = TextEditingController();
    _loadCredentials();
  }

  void _addGeminiDiagnostic({
    required String code,
    required String message,
    required GeminiDiagnosticLevel level,
    String? model,
    int? httpStatus,
    Duration? latency,
  }) {
    if (!mounted) return;
    setState(() {
      _geminiDiagnostics.insert(
        0,
        GeminiDiagnosticEvent(
          code: code,
          message: message,
          level: level,
          at: DateTime.now(),
          model: model,
          httpStatus: httpStatus,
          latency: latency,
        ),
      );
      if (_geminiDiagnostics.length > 12) {
        _geminiDiagnostics.removeRange(12, _geminiDiagnostics.length);
      }
    });
  }

  Future<void> _loadCredentials() async {
    final url = await _config.getUrl();
    final key = await _config.getAnonKey();
    final gemini = await _config.getGeminiKey();
    final geminiModel = await _config.getGeminiModel();
    final geminiVerified = await _config.isGeminiVerified();
    final lastUsage = await _config.getGeminiUsage();

    if (mounted) {
      setState(() {
        _urlController.text = url ?? '';
        _keyController.text = key ?? '';
        _geminiController.text = gemini ?? '';
        _selectedGeminiModel = geminiModel?.trim().isEmpty == true
            ? null
            : geminiModel;
        _geminiVerified = geminiVerified;
        _lastGeminiUsage = lastUsage;
        _loading = false;
      });
      if (lastUsage != null) {
        _addGeminiDiagnostic(
          code: GeminiDiagnosticCodes.usageLoaded,
          message: GeminiDiagnosticCodes.descriptionFor(
            GeminiDiagnosticCodes.usageLoaded,
          ),
          level: GeminiDiagnosticLevel.info,
          model: lastUsage.model,
          httpStatus: lastUsage.httpStatus,
          latency: lastUsage.latencyMs == null
              ? null
              : Duration(milliseconds: lastUsage.latencyMs!),
        );
      }
      _checkSupabase();
    }
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
      _addGeminiDiagnostic(
        code: GeminiDiagnosticCodes.keyEmpty,
        message: GeminiDiagnosticCodes.descriptionFor(
          GeminiDiagnosticCodes.keyEmpty,
        ),
        level: GeminiDiagnosticLevel.warning,
      );
      if (persist) {
        await _config.saveVerifiedGeminiConfiguration(
          key: '',
          model: '',
          verified: false,
        );
      }
      return;
    }

    _addGeminiDiagnostic(
      code: GeminiDiagnosticCodes.modelsRequest,
      message: GeminiDiagnosticCodes.descriptionFor(
        GeminiDiagnosticCodes.modelsRequest,
      ),
      level: GeminiDiagnosticLevel.info,
    );
    if (mounted) {
      setState(() {
        _geminiStatus = 'Mencari model untuk API key...';
        _geminiColor = Colors.orange;
        _geminiVerified = false;
      });
    }
    final modelsResult = await _gemini.fetchModels(apiKey: key);
    final models = modelsResult.models;
    _addGeminiDiagnostic(
      code:
          modelsResult.diagnosticCode ??
          (models.isEmpty
              ? GeminiDiagnosticCodes.modelsUnavailable
              : GeminiDiagnosticCodes.modelsSuccess),
      message: modelsResult.message,
      level: models.isEmpty
          ? GeminiDiagnosticLevel.error
          : GeminiDiagnosticLevel.success,
      httpStatus: modelsResult.statusCode,
    );
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
        await _config.saveVerifiedGeminiConfiguration(
          key: key,
          model: '',
          verified: false,
        );
        _addGeminiDiagnostic(
          code: GeminiDiagnosticCodes.configRejected,
          message: GeminiDiagnosticCodes.descriptionFor(
            GeminiDiagnosticCodes.configRejected,
          ),
          level: GeminiDiagnosticLevel.warning,
        );
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
    _addGeminiDiagnostic(
      code: GeminiDiagnosticCodes.testRequest,
      message: GeminiDiagnosticCodes.descriptionFor(
        GeminiDiagnosticCodes.testRequest,
      ),
      level: GeminiDiagnosticLevel.info,
      model: model,
    );
    final result = await _gemini.testConnection(apiKey: key, model: model);
    _addGeminiDiagnostic(
      code:
          result.diagnosticCode ??
          (result.ok
              ? GeminiDiagnosticCodes.verified
              : GeminiDiagnosticCodes.chatError),
      message: result.message,
      level: result.ok
          ? GeminiDiagnosticLevel.success
          : GeminiDiagnosticLevel.error,
      model: result.model,
      httpStatus: result.statusCode,
      latency: result.latency,
    );
    if (mounted) {
      setState(() {
        _geminiModels = models;
        _geminiVerified = result.ok;
        _geminiStatus = result.message;
        _geminiColor = result.ok ? Colors.green : Colors.red;
      });
    }
    if (persist) {
      await _config.saveVerifiedGeminiConfiguration(
        key: key,
        model: model ?? '',
        verified: result.ok,
      );
      _addGeminiDiagnostic(
        code: result.ok
            ? GeminiDiagnosticCodes.configSaved
            : GeminiDiagnosticCodes.configRejected,
        message: GeminiDiagnosticCodes.descriptionFor(
          result.ok
              ? GeminiDiagnosticCodes.configSaved
              : GeminiDiagnosticCodes.configRejected,
        ),
        level: result.ok
            ? GeminiDiagnosticLevel.success
            : GeminiDiagnosticLevel.warning,
        model: model,
      );
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
    if (key.isEmpty) {
      _addGeminiDiagnostic(
        code: GeminiDiagnosticCodes.keyEmpty,
        message: GeminiDiagnosticCodes.descriptionFor(
          GeminiDiagnosticCodes.keyEmpty,
        ),
        level: GeminiDiagnosticLevel.warning,
      );
      return;
    }
    if (_geminiModelsLoading) return;
    setState(() => _geminiModelsLoading = true);
    _addGeminiDiagnostic(
      code: GeminiDiagnosticCodes.modelsRequest,
      message: GeminiDiagnosticCodes.descriptionFor(
        GeminiDiagnosticCodes.modelsRequest,
      ),
      level: GeminiDiagnosticLevel.info,
    );
    final result = await _gemini.fetchModels(apiKey: key);
    _addGeminiDiagnostic(
      code:
          result.diagnosticCode ??
          (result.models.isEmpty
              ? GeminiDiagnosticCodes.modelsUnavailable
              : GeminiDiagnosticCodes.modelsSuccess),
      message: result.message,
      level: result.models.isEmpty
          ? GeminiDiagnosticLevel.error
          : GeminiDiagnosticLevel.success,
      httpStatus: result.statusCode,
    );
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
    await _config.save(_urlController.text.trim(), _keyController.text.trim());
    await _checkGemini(persist: true);
    await SupabaseClientProvider.reset();
    if (mounted) setState(() => _loading = false);
    await _checkSupabase();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _geminiVerified
                ? 'Konfigurasi tersimpan dan Gemini berhasil diuji.'
                : 'Supabase tersimpan, tetapi Gemini belum diaktifkan. Lihat kode diagnostik di bawah.',
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
                  const SizedBox(height: 16),
                  _buildGeminiDiagnostics(theme),
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
            _config.invalidateGeminiVerification();
            _addGeminiDiagnostic(
              code: GeminiDiagnosticCodes.keyChanged,
              message: GeminiDiagnosticCodes.descriptionFor(
                GeminiDiagnosticCodes.keyChanged,
              ),
              level: GeminiDiagnosticLevel.warning,
            );
          },
          decoration: const InputDecoration(
            labelText: 'Gemini API Key',
            hintText: 'Dapatkan di aistudio.google.com',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Gratis di Google AI Studio. Login akun Google, klik "Get API key", buat dan salin key ke sini.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://aistudio.google.com/'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text('Buka aistudio.google.com'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ),
            ],
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
            _config.invalidateGeminiVerification();
            _addGeminiDiagnostic(
              code: GeminiDiagnosticCodes.modelSelected,
              message: GeminiDiagnosticCodes.descriptionFor(
                GeminiDiagnosticCodes.modelSelected,
              ),
              level: GeminiDiagnosticLevel.info,
              model: model,
            );
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

  Widget _buildGeminiDiagnostics(ThemeData theme) {
    final keyReady = _geminiController.text.trim().isNotEmpty;
    final modelReady = _selectedGeminiModel?.trim().isNotEmpty == true;
    final modelsReady = _geminiModels.isNotEmpty;
    final steps =
        <
          ({
            String title,
            String code,
            String meaning,
            Color color,
            IconData icon,
          })
        >[
          (
            title: '1. API key diisi',
            code: keyReady
                ? GeminiDiagnosticCodes.keyReady
                : GeminiDiagnosticCodes.keyEmpty,
            meaning: keyReady
                ? GeminiDiagnosticCodes.descriptionFor(
                    GeminiDiagnosticCodes.keyReady,
                  )
                : GeminiDiagnosticCodes.descriptionFor(
                    GeminiDiagnosticCodes.keyEmpty,
                  ),
            color: keyReady ? Colors.green : Colors.grey,
            icon: keyReady ? Icons.check_circle : Icons.radio_button_unchecked,
          ),
          (
            title: '2. Daftar model diambil',
            code: modelsReady
                ? GeminiDiagnosticCodes.modelsSuccess
                : GeminiDiagnosticCodes.modelsRequest,
            meaning: modelsReady
                ? '${_geminiModels.length} model generateContent tersedia.'
                : 'Tekan “Muat model dari key” untuk memeriksa key ke endpoint models.',
            color: modelsReady ? Colors.green : Colors.orange,
            icon: modelsReady ? Icons.check_circle : Icons.pending,
          ),
          (
            title: '3. Model dipilih',
            code: modelReady
                ? GeminiDiagnosticCodes.modelSelected
                : GeminiDiagnosticCodes.modelEmpty,
            meaning: modelReady
                ? 'Model $_selectedGeminiModel dipilih; perubahan tetap perlu dites.'
                : GeminiDiagnosticCodes.descriptionFor(
                    GeminiDiagnosticCodes.modelEmpty,
                  ),
            color: modelReady ? Colors.blue : Colors.grey,
            icon: modelReady
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
          ),
          (
            title: '4. Test generateContent',
            code: _geminiVerified
                ? GeminiDiagnosticCodes.verified
                : (_geminiStatus == null
                      ? GeminiDiagnosticCodes.testRequest
                      : GeminiDiagnosticCodes.testPending),
            meaning: _geminiVerified
                ? 'Request test berhasil dengan model pilihan.'
                : (_geminiStatus ?? 'Belum ada test berhasil.'),
            color: _geminiVerified ? Colors.green : Colors.orange,
            icon: _geminiVerified ? Icons.check_circle : Icons.pending,
          ),
          (
            title: '5. Tersimpan dan siap chatbot',
            code: _geminiVerified
                ? GeminiDiagnosticCodes.configSaved
                : GeminiDiagnosticCodes.configRejected,
            meaning: _geminiVerified
                ? 'Tuple key + model + verified tersimpan; chatbot membaca tuple yang sama.'
                : GeminiDiagnosticCodes.descriptionFor(
                    GeminiDiagnosticCodes.configRejected,
                  ),
            color: _geminiVerified ? Colors.green : Colors.red,
            icon: _geminiVerified ? Icons.check_circle : Icons.error_outline,
          ),
        ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(title: 'Pelacakan Gemini'),
        const SizedBox(height: 8),
        AppCard(
          child: Column(
            children: [
              for (final step in steps)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(step.icon, color: step.color),
                  title: Text(step.title),
                  subtitle: Text('${step.code} · ${step.meaning}'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildLastGeminiUsageCard(),
        const SizedBox(height: 12),
        _buildGeminiLogCard(theme),
      ],
    );
  }

  Widget _buildLastGeminiUsageCard() {
    final usage = _lastGeminiUsage;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Pemakaian chatbot terakhir',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Segarkan',
                onPressed: () async {
                  final latest = await _config.getGeminiUsage();
                  if (mounted) setState(() => _lastGeminiUsage = latest);
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (usage == null)
            const Text(
              'Belum ada request chatbot yang tercatat pada perangkat ini.',
            )
          else ...[
            Text('Status: ${usage.ok ? 'berhasil' : 'gagal'} · ${usage.code}'),
            Text('Model: ${usage.model.isEmpty ? '-' : usage.model}'),
            Text(
              'HTTP: ${usage.httpStatus?.toString() ?? '-'} · Waktu: ${usage.latencyMs?.toString() ?? '-'} ms',
            ),
            Text('Terakhir: ${_formatTime(usage.at)}'),
          ],
          const SizedBox(height: 6),
          const Text(
            'Metadata saja: API key, prompt, konteks, dan respons tidak disimpan di log ini.',
            style: TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildGeminiLogCard(ThemeData theme) {
    final logText = _geminiDiagnostics.isEmpty
        ? 'Belum ada event. Jalankan Muat model atau Test API Key.'
        : _geminiDiagnostics.map(_formatDiagnostic).join('\\n');
    return AppCard(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Log diagnostik aman',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                onPressed: _geminiDiagnostics.isEmpty
                    ? null
                    : () {
                        final safeLog = [
                          'Gemini diagnostics aman.',
                          'API key, prompt, konteks, dan raw response sengaja tidak dicatat.',
                          ..._geminiDiagnostics.map(_formatDiagnostic),
                        ].join('\\n');
                        Clipboard.setData(ClipboardData(text: safeLog));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Log aman disalin. Rahasia tidak termasuk.',
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Salin log aman'),
              ),
              IconButton(
                tooltip: 'Hapus log tampilan',
                onPressed: _geminiDiagnostics.isEmpty
                    ? null
                    : () => setState(_geminiDiagnostics.clear),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(logText, style: const TextStyle(fontSize: 11, height: 1.35)),
          const SizedBox(height: 6),
          const Text(
            'Maksimal 12 event disimpan hanya selama halaman ini terbuka.',
            style: TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _formatDiagnostic(GeminiDiagnosticEvent event) {
    final http = event.httpStatus == null ? '' : ' · HTTP ${event.httpStatus}';
    final latency = event.latency == null
        ? ''
        : ' · ${event.latency!.inMilliseconds} ms';
    final model = event.model == null || event.model!.isEmpty
        ? ''
        : ' · model ${event.model}';
    return '[${_formatTime(event.at)}] ${event.code}$http$latency$model\\n${event.message}';
  }

  String _formatTime(DateTime time) =>
      time.toLocal().toIso8601String().replaceFirst('T', ' ').split('.').first;

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
