import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../data/ffm_assistant_autonomy_repository.dart';
import '../../domain/ffm_assistant_autonomy_policy.dart';

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
  bool _loading = true;
  bool _savingPolicy = false;
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
      if (!mounted) return;
      setState(() {
        _runs = runs;
        _policy = policy;
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

  Widget _buildPolicyCard(BuildContext context) {
    final levels = FfmAssistantAutonomyLevel.values;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kebijakan Autonomy',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Atur batas Agent. Perubahan hanya berlaku untuk household ini dan tetap melewati approval untuk mutasi sensitif.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<FfmAssistantAutonomyLevel>(
              initialValue: _policy.level,
              decoration: const InputDecoration(
                labelText: 'Level autonomy',
                border: OutlineInputBorder(),
              ),
              items: levels
                  .map(
                    (level) => DropdownMenuItem(
                      value: level,
                      child: Text(_levelLabel(level)),
                    ),
                  )
                  .toList(),
              onChanged: _savingPolicy
                  ? null
                  : (level) {
                      if (level == null) return;
                      setState(() {
                        _policy = _withPolicy(level: level);
                      });
                    },
            ),
            const SizedBox(height: 8),
            Text('Maksimal action per run: ${_policy.maxActionsPerRun}'),
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
                      });
                    },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _savingPolicy ? null : _savePolicy,
                icon: _savingPolicy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _savingPolicy ? 'Menyimpan...' : 'Simpan kebijakan',
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kebijakan autonomy tersimpan.')),
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
    FfmAssistantAutonomyLevel.readOnly => 'Read only',
    FfmAssistantAutonomyLevel.analyze => 'Analisis',
    FfmAssistantAutonomyLevel.suggest => 'Rekomendasi',
    FfmAssistantAutonomyLevel.createDraft => 'Buat draft',
    FfmAssistantAutonomyLevel.executeLowRisk => 'Eksekusi risiko rendah',
    FfmAssistantAutonomyLevel.explicitApproval => 'Approval eksplisit',
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
                'Riwayat eksekusi Agent di perangkat ini. Yang ditampilkan hanya metadata aman dan ringkasan hasil, bukan isi percakapan atau parameter tool.',
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
