import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../data/ffm_assistant_autonomy_repository.dart';
import '../../data/ffm_assistant_foreground_service.dart';
import '../../data/ffm_assistant_insight_repository.dart';
import '../../domain/ffm_assistant_autonomy_policy.dart';
import '../../domain/ffm_assistant_insight.dart';
import 'agent_inbox_page.dart';

class FfmAssistantAutonomyMonitorPage extends StatefulWidget {
  const FfmAssistantAutonomyMonitorPage({
    super.key,
    this.repository,
    this.householdId = FfmAssistantAutonomyRepository.householdId,
  });

  final FfmAssistantAutonomyRepository? repository;
  final String householdId;

  @override
  State<FfmAssistantAutonomyMonitorPage> createState() =>
      _FfmAssistantAutonomyMonitorPageState();
}

class _FfmAssistantAutonomyMonitorPageState
    extends State<FfmAssistantAutonomyMonitorPage> {
  List<AssistantAgentRun> _runs = const [];
  FfmAssistantAutonomyPolicy _policy = const FfmAssistantAutonomyPolicy();
  int _activeInsightCount = 0;
  int _actedInsightCount = 0;
  int _dismissedInsightCount = 0;
  bool _foregroundServiceEnabled = false;
  bool _isIgnoringBatteryOptimizations = true;
  bool _updatingForegroundService = false;
  bool _loading = true;
  bool _savingPolicy = false;
  bool _policyChanged = false;
  String? _error;

  FfmAssistantAutonomyRepository get _repository =>
      widget.repository ?? getIt<FfmAssistantAutonomyRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final runs = await _repository.recentRuns(
        householdId: widget.householdId,
      );
      final policy =
          await _repository.loadPolicy(householdId: widget.householdId) ??
          const FfmAssistantAutonomyPolicy();

      var activeCount = 0;
      var actedCount = 0;
      var dismissedCount = 0;
      try {
        final insightRepo = FfmAssistantInsightRepository(getIt<AppDatabase>());
        final allInsights = await insightRepo.getAllInsights(
          householdId: widget.householdId,
        );
        activeCount = allInsights
            .where((i) =>
                i.status == FfmAssistantInsightStatus.newInsight ||
                i.status == FfmAssistantInsightStatus.seen)
            .length;
        actedCount = allInsights
            .where((i) => i.status == FfmAssistantInsightStatus.acted)
            .length;
        dismissedCount = allInsights
            .where((i) =>
                i.status == FfmAssistantInsightStatus.dismissed ||
                i.status == FfmAssistantInsightStatus.expired)
            .length;
      } catch (_) {}

      var fgEnabled = false;
      var isIgnoringBattery = true;
      try {
        if (getIt.isRegistered<FfmAssistantForegroundServiceManager>()) {
          final fg = getIt<FfmAssistantForegroundServiceManager>();
          fgEnabled = await fg.isEnabled();
          isIgnoringBattery = await fg.isIgnoringBatteryOptimizations();
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _runs = runs;
        _policy = policy;
        _activeInsightCount = activeCount;
        _actedInsightCount = actedCount;
        _dismissedInsightCount = dismissedCount;
        _foregroundServiceEnabled = fgEnabled;
        _isIgnoringBatteryOptimizations = isIgnoringBattery;
        _policyChanged = false;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Riwayat run Agent belum bisa dibaca.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoring Agent'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Muat ulang riwayat Agent',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _buildIntro(context),
                  const SizedBox(height: 16),
                  _buildForegroundServiceCard(context),
                  const SizedBox(height: 16),
                  _buildInsightSummary(context),
                  const SizedBox(height: 16),
                  _buildPolicyCard(context),
                  const SizedBox(height: 16),
                  if (_error != null) _buildError(context),
                  if (_error == null && _runs.isEmpty) _buildEmpty(context),
                  if (_error == null && _runs.isNotEmpty) ...[
                    _buildSummary(context),
                    const SizedBox(height: 16),
                    ..._runs.map(
                      (run) => _RunCard(
                        run: run,
                        repository: _repository,
                        householdId: widget.householdId,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Future<void> _toggleForegroundService(bool enabled) async {
    setState(() => _updatingForegroundService = true);
    try {
      final fg = getIt<FfmAssistantForegroundServiceManager>();
      await fg.setEnabled(enabled);
      final actuallyEnabled = await fg.isEnabled();
      final isIgnoring = await fg.isIgnoringBatteryOptimizations();
      if (!mounted) return;
      setState(() {
        _foregroundServiceEnabled = actuallyEnabled;
        _isIgnoringBatteryOptimizations = isIgnoring;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            actuallyEnabled
                ? 'Mode Siaga Status Bar aktif. Asisten kebal dari pembatasan Android.'
                : 'Mode Siaga Status Bar dinonaktifkan. Menggunakan WorkManager standar.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengubah mode status bar: $e')),
      );
    } finally {
      if (mounted) setState(() => _updatingForegroundService = false);
    }
  }

  Future<void> _requestIgnoreBattery() async {
    try {
      final fg = getIt<FfmAssistantForegroundServiceManager>();
      await fg.requestIgnoreBatteryOptimization();
      final isIgnoring = await fg.isIgnoringBatteryOptimizations();
      if (!mounted) return;
      setState(() => _isIgnoringBatteryOptimizations = isIgnoring);
    } catch (_) {}
  }

  Widget _buildForegroundServiceCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isDark ? const Color(0xFF35302B) : const Color(0xFFE8E0D0),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _foregroundServiceEnabled
                        ? Colors.teal.withValues(alpha: 0.15)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _foregroundServiceEnabled
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    size: 20,
                    color: _foregroundServiceEnabled
                        ? Colors.teal
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ketahanan Background & Status Bar',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Anti-Kill: Mencegah agen tertidur oleh OS Android',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _foregroundServiceEnabled
                        ? Colors.green.withValues(alpha: 0.15)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _foregroundServiceEnabled ? 'STATUS BAR AKTIF' : 'WORKMANAGER',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _foregroundServiceEnabled
                          ? Colors.green.shade700
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Mode Siaga Status Bar (Foreground Service)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: Text(
                _foregroundServiceEnabled
                    ? 'Agen aktif di status bar, radar keuangan berdetak setiap 15 menit tanpa terputus oleh Doze Mode.'
                    : 'Agen menggunakan jadwal berkala standar Android. Dapat ditunda jika HP mengaktifkan hemat baterai.',
                style: const TextStyle(fontSize: 12),
              ),
              value: _foregroundServiceEnabled,
              onChanged: _updatingForegroundService
                  ? null
                  : (val) => _toggleForegroundService(val),
            ),
            if (!_isIgnoringBatteryOptimizations) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.battery_alert_rounded,
                      color: Colors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Optimasi baterai Android masih membatasi FFM di latar belakang.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.amber.shade200
                              : Colors.amber.shade900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: _requestIgnoreBattery,
                      child: const Text('Buka Izin',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInsightSummary(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isDark ? const Color(0xFF35302B) : const Color(0xFFE8E0D0),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 20,
                  color: isDark ? const Color(0xFFC49A6B) : const Color(0xFFB07A4A),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Wawasan & Notifikasi Proaktif',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AgentInboxPage()),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('Buka Inbox'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_activeInsightCount',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text('Aktif & Baru', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_actedInsightCount',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text('Ditindaklanjuti', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_dismissedInsightCount',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text('Riwayat Selesai', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyCard(BuildContext context) {
    final levels = FfmAssistantAutonomyLevel.values;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Batas kerja Agent',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Pilih izin maksimum Agent saat menjalankan tugas di latar belakang. Agent tidak pernah mengubah data keuangan tanpa persetujuan kamu.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<FfmAssistantAutonomyLevel>(
              initialValue: _policy.level,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Izin maksimum Agent',
                helperText: 'Ini adalah batas, bukan perintah agar Agent berjalan sendiri.',
                border: OutlineInputBorder(),
              ),
              items: levels
                  .map(
                    (level) => DropdownMenuItem(
                      value: level,
                      child: Text(
                        _levelLabel(level),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _savingPolicy
                  ? null
                  : (level) {
                      if (level == null) return;
                      setState(() {
                        _policy = _withPolicy(level: level);
                        _policyChanged = true;
                      });
                    },
            ),
            const SizedBox(height: 12),
            _PolicyExplanation(level: _policy.level),
            const SizedBox(height: 8),
            Text('Batas langkah per tugas: ${_policy.maxActionsPerRun}'),
            const SizedBox(height: 2),
            const Text(
              'Satu tugas adalah satu rencana kerja Agent. Batas ini menghentikan rencana yang terlalu panjang.',
            ),
            Slider(
              value: _policy.maxActionsPerRun.toDouble(),
              min: 1,
              max: 20,
              divisions: 19,
              label: '${_policy.maxActionsPerRun}',
              onChanged: _savingPolicy
                  ? null
                  : (value) {
                      setState(() {
                        _policy = _withPolicy(maxActions: value.round());
                        _policyChanged = true;
                      });
                    },
            ),
            const _AutonomyLevelGuide(),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _savingPolicy || !_policyChanged
                    ? null
                    : _savePolicy,
                icon: _savingPolicy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _savingPolicy
                      ? 'Menerapkan...'
                      : _policyChanged
                      ? 'Terapkan batas'
                      : 'Batas tersimpan',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  FfmAssistantAutonomyPolicy _withPolicy({
    FfmAssistantAutonomyLevel? level,
    int? maxActions,
  }) {
    return FfmAssistantAutonomyPolicy(
      level: level ?? _policy.level,
      maxActionsPerRun: maxActions ?? _policy.maxActionsPerRun,
      maxEstimatedTokensPerRun: _policy.maxEstimatedTokensPerRun,
      maxEstimatedCostMicrosPerRun: _policy.maxEstimatedCostMicrosPerRun,
      estimatedTokensPerAction: _policy.estimatedTokensPerAction,
      estimatedCostMicrosPerAction: _policy.estimatedCostMicrosPerAction,
      allowedCapabilityIds: _policy.allowedCapabilityIds,
    );
  }

  Future<void> _savePolicy() async {
    setState(() => _savingPolicy = true);
    try {
      await _repository.savePolicy(
        policy: _policy,
        householdId: widget.householdId,
      );
      if (!mounted) return;
      setState(() => _policyChanged = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Batas kerja Agent diterapkan.')),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kebijakan belum berhasil disimpan.')),
      );
    } finally {
      if (mounted) setState(() => _savingPolicy = false);
    }
  }

  String _levelLabel(FfmAssistantAutonomyLevel level) => switch (level) {
    FfmAssistantAutonomyLevel.readOnly => 'Hanya baca data',
    FfmAssistantAutonomyLevel.analyze => 'Baca dan analisis',
    FfmAssistantAutonomyLevel.suggest => 'Beri rekomendasi',
    FfmAssistantAutonomyLevel.createDraft => 'Siapkan draft untuk dicek',
    FfmAssistantAutonomyLevel.executeLowRisk =>
      'Aksi risiko rendah setelah persetujuan',
    FfmAssistantAutonomyLevel.explicitApproval =>
      'Aksi sensitif setelah persetujuan eksplisit',
  };

  Widget _buildIntro(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.monitor_heart_outlined),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Riwayat tugas Agent di perangkat ini. Gunakan halaman ini bila ingin mengecek apa yang dicoba Agent dan membatasi izin kerjanya. Isi percakapan dan parameter tool tidak ditampilkan.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final completed = _runs.where((run) => run.status == 'completed').length;
    final attention = _runs.length - completed;
    return Row(
      children: [
        Expanded(
          child: _MetricCard(label: 'Total run', value: '${_runs.length}'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricCard(label: 'Selesai', value: '$completed'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricCard(label: 'Perlu cek', value: '$attention'),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Belum ada run Agent yang tercatat.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.error_outline),
        title: const Text('Monitoring belum tersedia'),
        subtitle: Text(_error!),
        trailing: TextButton(onPressed: _load, child: const Text('Coba lagi')),
      ),
    );
  }
}

class _PolicyExplanation extends StatelessWidget {
  const _PolicyExplanation({required this.level});

  final FfmAssistantAutonomyLevel level;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _description(level),
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  static String _description(FfmAssistantAutonomyLevel level) =>
      switch (level) {
        FfmAssistantAutonomyLevel.readOnly => 'Agent hanya boleh membaca informasi yang diizinkan. Tidak membuat draft atau perubahan.',
        FfmAssistantAutonomyLevel.analyze => 'Agent dapat membaca data yang diizinkan untuk membuat analisis. Tidak membuat draft atau perubahan.',
        FfmAssistantAutonomyLevel.suggest => 'Agent dapat membaca dan memberi saran. Tidak membuat draft atau perubahan data.',
        FfmAssistantAutonomyLevel.createDraft => 'Agent dapat menyiapkan draft agar kamu periksa. Draft belum menyimpan atau mengubah data.',
        FfmAssistantAutonomyLevel.executeLowRisk => 'Agent dapat menyiapkan aksi risiko rendah, tetapi tetap membutuhkan persetujuan kamu sebelum data berubah.',
        FfmAssistantAutonomyLevel.explicitApproval => 'Agent dapat menyiapkan aksi termasuk yang sensitif. Semua perubahan tetap membutuhkan persetujuan eksplisit kamu.',
      };
}

class _AutonomyLevelGuide extends StatelessWidget {
  const _AutonomyLevelGuide();

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      leading: const Icon(Icons.help_outline),
      title: const Text('Arti setiap izin'),
      subtitle: const Text('Perubahan data selalu butuh persetujuan'),
      children: FfmAssistantAutonomyLevel.values
          .map(
            (level) => ListTile(
              dense: true,
              title: Text(_label(level)),
              subtitle: Text(_PolicyExplanation._description(level)),
            ),
          )
          .toList(growable: false),
    );
  }

  String _label(FfmAssistantAutonomyLevel level) => switch (level) {
    FfmAssistantAutonomyLevel.readOnly => 'Hanya baca data',
    FfmAssistantAutonomyLevel.analyze => 'Baca dan analisis',
    FfmAssistantAutonomyLevel.suggest => 'Beri rekomendasi',
    FfmAssistantAutonomyLevel.createDraft => 'Siapkan draft untuk dicek',
    FfmAssistantAutonomyLevel.executeLowRisk =>
      'Aksi risiko rendah setelah persetujuan',
    FfmAssistantAutonomyLevel.explicitApproval =>
      'Aksi sensitif setelah persetujuan eksplisit',
  };
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({
    required this.run,
    required this.repository,
    required this.householdId,
  });

  final AssistantAgentRun run;
  final FfmAssistantAutonomyRepository repository;
  final String householdId;

  Color _statusColor(BuildContext context) {
    return switch (run.status) {
      'completed' => Colors.green,
      'failed' ||
      'blocked' ||
      'blockedByBudget' => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(Icons.circle, size: 12, color: color),
        title: Text(run.summary),
        subtitle: Text('${run.status} • ${_formatDate(run.updatedAt)}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (run.decisionSummary?.isNotEmpty == true)
            _InfoLine(label: 'Keputusan', value: run.decisionSummary!),
          if (run.error?.isNotEmpty == true)
            _InfoLine(label: 'Catatan', value: run.error!),
          FutureBuilder<List<AssistantAgentToolExecution>>(
            future: repository.toolExecutionsForRun(
              run.id,
              householdId: householdId,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                );
              }
              final executions = snapshot.data ?? const [];
              if (executions.isEmpty) {
                return const _InfoLine(
                  label: 'Tool',
                  value: 'Belum ada detail eksekusi.',
                );
              }
              return Column(
                children: executions
                    .map(
                      (execution) => _InfoLine(
                        label: execution.capabilityId,
                        value:
                            '${execution.status} • ${execution.resultSummary ?? execution.error ?? '-'}',
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label\n',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: value),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${local.day}/${local.month}/${local.year} ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
