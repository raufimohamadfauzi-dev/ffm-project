import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/audit_logger.dart';
import '../../../../core/di/injection.dart';
import '../../../budget/data/budget_repository.dart';
import '../../data/ffm_assistant_budget_autonomy_repository.dart';
import '../../domain/ffm_assistant_budget_autonomy_service.dart';
import '../../domain/ffm_assistant_models.dart';
import '../widgets/ffm_assistant_page_context.dart';

/// Read-only monitor plus narrowly scoped safety controls for budget delegation.
class FfmAssistantBudgetDelegationsPage extends StatefulWidget {
  const FfmAssistantBudgetDelegationsPage({
    super.key,
    this.database,
    this.repository,
    this.service,
    this.householdId = 'local-household',
  });

  final AppDatabase? database;
  final FfmAssistantBudgetAutonomyRepository? repository;
  final FfmAssistantBudgetAutonomyService? service;
  final String householdId;

  @override
  State<FfmAssistantBudgetDelegationsPage> createState() =>
      _FfmAssistantBudgetDelegationsPageState();
}

class _FfmAssistantBudgetDelegationsPageState
    extends State<FfmAssistantBudgetDelegationsPage> {
  List<BudgetAutonomyDelegation> _delegations = const [];
  List<BudgetAutonomyExecutionLedger> _ledger = const [];
  Map<String, String> _budgetNames = const {};
  bool _loading = true;
  String? _error;

  AppDatabase get _database => widget.database ?? getIt<AppDatabase>();

  FfmAssistantBudgetAutonomyRepository get _repository =>
      widget.repository ?? FfmAssistantBudgetAutonomyRepository(_database);

  FfmAssistantBudgetAutonomyService get _service =>
      widget.service ??
      FfmAssistantBudgetAutonomyService(
        _database,
        BudgetRepository(_database, AuditLogger(_database)),
        _repository,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repository.activeDelegations(householdId: widget.householdId),
        (_database.select(
          _database.budgetAutonomyExecutionLedgers,
        )..where((row) => row.householdId.equals(widget.householdId))).get(),
        (_database.select(
          _database.envelopeBudgets,
        )..where((row) => row.householdId.equals(widget.householdId))).get(),
      ]);
      final ledger = results[1] as List<BudgetAutonomyExecutionLedger>;
      final budgets = results[2] as List<EnvelopeBudget>;
      if (!mounted) return;
      setState(() {
        _delegations = results[0] as List<BudgetAutonomyDelegation>;
        _ledger = ledger..sort((a, b) => b.executedAt.compareTo(a.executedAt));
        _budgetNames = {for (final budget in budgets) budget.id: budget.name};
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Delegasi dan riwayat eksekusi belum dapat dimuat.';
      });
    }
  }

  Future<void> _setStatus(
    BudgetAutonomyDelegation delegation,
    FfmAssistantBudgetDelegationStatus status,
  ) async {
    if (status == FfmAssistantBudgetDelegationStatus.revoked) {
      final confirmed = await _confirmRevoke(delegation);
      if (!confirmed || !mounted) return;
    }
    try {
      final changed = await _service.setDelegationStatus(
        householdId: widget.householdId,
        budgetId: delegation.budgetId,
        status: status,
      );
      if (!mounted) return;
      if (!changed) {
        _showMessage(
          'Delegasi tidak lagi tersedia. Muat ulang untuk melihat data terbaru.',
        );
        await _load();
        return;
      }
      _showMessage(
        status == FfmAssistantBudgetDelegationStatus.paused
            ? 'Delegasi dijeda. Asisten tidak dapat menyesuaikan pos ini.'
            : 'Delegasi dicabut. Asisten tidak dapat menyesuaikan pos ini lagi.',
      );
      await _load();
    } on Object {
      if (!mounted) return;
      _showMessage('Status delegasi belum dapat diubah. Coba lagi.');
    }
  }

  Future<bool> _confirmRevoke(BudgetAutonomyDelegation delegation) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cabut delegasi?'),
            content: Text(
              'Asisten tidak lagi dapat menyesuaikan ${_budgetName(delegation.budgetId)}. Riwayat eksekusi tetap tersimpan.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Cabut delegasi'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _undo(BudgetAutonomyExecutionLedger entry) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Batalkan eksekusi ini?'),
            content: Text(
              'Alokasi ${_budgetName(entry.budgetId)} akan dikembalikan dari ${_rupiah(entry.appliedAllocated)} ke ${_rupiah(entry.previousAllocated)}. Pembatalan hanya berjalan bila pos belum berubah sejak eksekusi ini.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Kembali'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Batalkan eksekusi'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      await _service.undo(
        householdId: widget.householdId,
        ledgerId: entry.id,
        idempotencyKey: const Uuid().v4(),
      );
      if (!mounted) return;
      _showMessage('Eksekusi dibatalkan dan dicatat sebagai riwayat baru.');
      await _load();
    } on StateError {
      if (!mounted) return;
      _showMessage(
        'Pembatalan tidak dapat diterapkan. Alokasi mungkin telah berubah, delegasi tidak aktif, atau eksekusi sudah dibatalkan.',
      );
      await _load();
    } on Object {
      if (!mounted) return;
      _showMessage('Pembatalan belum berhasil. Coba lagi.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _budgetName(String budgetId) =>
      _budgetNames[budgetId] ?? 'Pos Anggaran';

  bool _hasUndo(BudgetAutonomyExecutionLedger entry) => _ledger.any(
    (item) => item.operation == 'undo' && item.reversesLedgerId == entry.id,
  );

  @override
  Widget build(BuildContext context) {
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.autonomyMonitor,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Delegasi Anggaran Asisten'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Muat ulang delegasi anggaran',
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
                    _IntroCard(),
                    const SizedBox(height: 20),
                    Text(
                      'Delegasi aktif',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (_error != null)
                      _ErrorCard(message: _error!, onRetry: _load),
                    if (_error == null && _delegations.isEmpty)
                      const _EmptyCard(
                        message: 'Belum ada delegasi aktif untuk penyesuaian alokasi Anggaran.',
                      ),
                    ..._delegations.map(_delegationCard),
                    const SizedBox(height: 20),
                    Text(
                      'Riwayat eksekusi',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Riwayat ini append-only dan tidak dapat diubah atau dihapus.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    if (_error == null && _ledger.isEmpty)
                      const _EmptyCard(
                        message: 'Belum ada eksekusi delegasi yang tercatat.',
                      ),
                    ..._ledger.map(_ledgerCard),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _delegationCard(BudgetAutonomyDelegation delegation) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _budgetName(delegation.budgetId),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Chip(label: const Text('Aktif')),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Maks. satu penyesuaian: ${_rupiah(delegation.maxAdjustmentAmount)}',
            ),
            Text('Maks. alokasi: ${_rupiah(delegation.maxAllocatedAmount)}'),
            Text('Maks. eksekusi: ${delegation.maxExecutions} kali'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _setStatus(
                    delegation,
                    FfmAssistantBudgetDelegationStatus.paused,
                  ),
                  icon: const Icon(Icons.pause_circle_outline),
                  label: const Text('Jeda'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _setStatus(
                    delegation,
                    FfmAssistantBudgetDelegationStatus.revoked,
                  ),
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('Cabut'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ledgerCard(BudgetAutonomyExecutionLedger entry) {
    final isAdjustment = entry.operation == 'adjustment';
    final canUndo = isAdjustment && !_hasUndo(entry);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(isAdjustment ? Icons.tune_rounded : Icons.undo_rounded),
        title: Text(_budgetName(entry.budgetId)),
        subtitle: Text(
          '${isAdjustment ? 'Penyesuaian' : 'Pembatalan'} • ${_formatDate(entry.executedAt)}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _InfoLine(
            label: 'Alokasi',
            value:
                '${_rupiah(entry.previousAllocated)} menjadi ${_rupiah(entry.appliedAllocated)}',
          ),
          _InfoLine(label: 'Perubahan', value: _signedRupiah(entry.delta)),
          _InfoLine(
            label: 'Revisi',
            value: '${entry.previousRevision} menjadi ${entry.appliedRevision}',
          ),
          if (entry.reversesLedgerId != null)
            const _InfoLine(
              label: 'Status',
              value: 'Mencatat pembatalan eksekusi sebelumnya.',
            ),
          if (isAdjustment && !canUndo)
            const _InfoLine(
              label: 'Status',
              value: 'Sudah dibatalkan melalui riwayat baru.',
            ),
          if (canUndo) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () => _undo(entry),
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Batalkan dengan aman'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _rupiah(int value) =>
      'Rp ${value.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => '.')}';

  static String _signedRupiah(int value) =>
      '${value >= 0 ? '+' : '-'}${_rupiah(value.abs())}';

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year} ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}

class _IntroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: const Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Delegasi hanya berlaku untuk pos dan batas yang sudah disetujui. Halaman ini tidak membuat delegasi baru atau memberi akses tanpa batas.',
            ),
          ),
        ],
      ),
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(20), child: Text(message)),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.error_outline),
      title: const Text('Data belum tersedia'),
      subtitle: Text(message),
      trailing: TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
    ),
  );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
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
  );
}
