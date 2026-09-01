import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/date_time_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../domain/entities/audit_log_entity.dart';
import '../../domain/usecases/audit_log_usecases.dart';

class ActivityLogPage extends StatefulWidget {
  const ActivityLogPage({super.key});

  @override
  State<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<ActivityLogPage> {
  final _searchController = TextEditingController();
  List<AuditLogEntity> _logs = const [];
  String? _action;
  DateTime? _from;
  DateTime? _to;
  bool _loading = true;
  String? _error;

  static const _actions = <String, String>{
    'tambah': 'Tambah transaksi/transfer',
    'create': 'Tambah data utama',
    'simpan target': 'Tambah target keuangan',
    'simpan aset': 'Tambah aset',
    'simpan hutang': 'Tambah hutang',
    'simpan piutang': 'Tambah piutang',
    'simpan pengingat': 'Tambah pengingat',
    'simpan aturan berkala': 'Tambah transaksi berkala',
    'buat transaksi berkala': 'Buat transaksi dari jadwal',
    'ubah': 'Ubah transaksi',
    'update': 'Ubah data utama/anggaran',
    'ubah aturan berkala': 'Ubah transaksi berkala',
    'ubah status pengingat': 'Ubah status pengingat',
    'hapus': 'Hapus transaksi/transfer',
    'archive': 'Arsip data utama/anggaran',
    'arsip target': 'Arsip target keuangan',
    'arsip aset': 'Arsip aset',
    'arsip hutang': 'Arsip hutang',
    'arsip piutang': 'Arsip piutang',
    'arsip aturan berkala': 'Arsip transaksi berkala',
    'hapus pengingat': 'Hapus pengingat',
    'delete_permanently': 'Hapus permanen',
    'recover_active_sessions': 'Pulihkan aktivitas aktif',
    'start_session': 'Mulai aktivitas',
    'finish_session': 'Selesai aktivitas',
    'add_checkpoint': 'Tambah checkpoint aktivitas',
    'add_quick_note': 'Tambah catatan cepat',
    'update_settings': 'Ubah pengaturan',
    'delete_override': 'Hapus koreksi kalender',
    'impor': 'Impor data',
    'rekonsiliasi': 'Rekonsiliasi saldo',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final logs = await getIt<GetAuditLogs>()(
        action: _action,
        from: _from == null ? null : _dateOnly(_from!),
        to: _to == null ? null : _dateOnly(_to!).add(const Duration(days: 1)),
        search: _searchController.text,
      );
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Log aktivitas belum bisa dibaca. Coba muat ulang.';
      });
    }
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  Future<void> _pickDate({required bool start}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: (start ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: start ? 'Pilih tanggal mulai' : 'Pilih tanggal akhir',
      cancelText: 'Batal',
      confirmText: 'Pakai tanggal',
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _from = selected;
        if (_to != null && _to!.isBefore(selected)) _to = selected;
      } else {
        _to = selected;
        if (_from != null && _from!.isAfter(selected)) _from = selected;
      }
    });
  }

  void _resetFilter() {
    _searchController.clear();
    setState(() {
      _action = null;
      _from = null;
      _to = null;
    });
    _load();
  }

  String _actionLabel(String action) => _actions[action] ?? _fallbackActionLabel(action);

  String _fallbackActionLabel(String action) {
    final normalized = action.replaceAll('_', ' ').trim();
    if (normalized.isEmpty) return 'Aktivitas penting';
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  String _entityLabel(String entity) {
    const labels = {
      'transaksi': 'Transaksi',
      'transfer': 'Transfer saldo',
      'saldo_rekening': 'Saldo rekening',
      'aset': 'Aset',
      'target': 'Target keuangan',
      'anggaran': 'Anggaran',
    };
    return labels[entity] ?? entity.replaceAll('_', ' ');
  }

  String _summary(AuditLogEntity log) {
    final fields = log.changedFields.toList()..sort();
    if (fields.isEmpty) {
      return 'Perubahan penting tercatat tanpa detail sensitif.';
    }
    final visible = fields.take(4).map((field) => field.replaceAll('_', ' '));
    final suffix = fields.length > 4 ? ' dan lainnya' : '';
    return 'Bagian yang berubah: ${visible.join(', ')}$suffix.';
  }

  @override
  Widget build(BuildContext context) {
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.activityLog,
      dataSummary: _loading
          ? 'Sedang memuat log...'
          : 'Melihat log audit: ada ${_logs.length} perubahan terakhir yang tercatat di perangkat ini.',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Log aktivitas'),
          actions: [
            IconButton(
              tooltip: 'Muat ulang',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: [
              const AppHelpBanner(
                title: 'Jejak perubahan keluarga',
                message: 'Di sini kamu bisa melihat perubahan penting seperti transaksi, transfer, impor, dan rekonsiliasi. Nilai rahasia seperti PIN atau kredensial tidak ditampilkan.',
                icon: Icons.history,
              ),
              const SizedBox(height: 16),
              _buildFilters(),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                AppCard(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.error_outline),
                    title: Text(_error!),
                    trailing: TextButton(
                      onPressed: _load,
                      child: const Text('Coba lagi'),
                    ),
                  ),
                )
              else if (_logs.isEmpty)
                const AppCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.inbox_outlined),
                    title: Text('Belum ada aktivitas penting'),
                    subtitle: Text(
                      'Setelah kamu menambah transaksi atau melakukan rekonsiliasi, jejaknya akan muncul di sini.',
                    ),
                  ),
                )
              else ...[
                Text(
                  '${_logs.length} aktivitas ditemukan',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (final log in _logs) _buildLogCard(log),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Saring aktivitas',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            decoration: const InputDecoration(
              labelText: 'Cari aktivitas',
              hintText: 'Contoh: transfer, rekonsiliasi, atau transaksi',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _action,
            decoration: const InputDecoration(
              labelText: 'Jenis aksi / perubahan',
              helperText: 'Filter berdasarkan aksi yang tercatat di log audit.',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Semua aksi'),
              ),
              ..._actions.entries.map(
                (entry) => DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _action = value),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _dateButton('Dari', _from, () => _pickDate(start: true)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dateButton(
                  'Sampai',
                  _to,
                  () => _pickDate(start: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.filter_alt_outlined),
                  label: const Text('Terapkan filter'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Hapus filter',
                onPressed: _loading ? null : _resetFilter,
                icon: const Icon(Icons.filter_alt_off_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateButton(String label, DateTime? date, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.calendar_today_outlined, size: 18),
      label: Text(
        date == null ? label : '$label\n${formatTanggalSingkat(date)}',
      ),
    );
  }

  Widget _buildLogCard(AuditLogEntity log) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: Icon(_iconFor(log)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_actionLabel(log.action)} ${_entityLabel(log.entity)}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(_summary(log)),
                  const SizedBox(height: 8),
                  HijriDateText(
                    date: log.timestamp,
                    includeSeconds: true,
                    compact: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(AuditLogEntity log) {
    switch (log.entity) {
      case 'transfer':
        return Icons.swap_horiz;
      case 'saldo_rekening':
        return Icons.account_balance_wallet_outlined;
      case 'transaksi':
        return log.action == 'hapus'
            ? Icons.remove_circle_outline
            : Icons.receipt_long_outlined;
      case 'aset':
        return Icons.inventory_2_outlined;
      default:
        return Icons.history;
    }
  }
}
