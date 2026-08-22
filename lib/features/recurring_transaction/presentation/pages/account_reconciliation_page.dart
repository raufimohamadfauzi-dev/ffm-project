import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/audit_logger.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/date_time_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../domain/usecases/recurring_transaction_crud_usecases.dart';

class AccountReconciliationPage extends StatefulWidget {
  const AccountReconciliationPage({super.key});

  @override
  State<AccountReconciliationPage> createState() =>
      _AccountReconciliationPageState();
}

class _AccountReconciliationPageState extends State<AccountReconciliationPage> {
  final _database = getIt<AppDatabase>();
  late Future<_ReconciliationOverview> _overviewFuture;

  @override
  void initState() {
    super.initState();
    _overviewFuture = _loadOverview();
  }

  Future<_ReconciliationOverview> _loadOverview() async {
    final accounts =
        await (_database.select(_database.accounts)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isActive.equals(true) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .get();
    final balanceService = GetAccountBookBalance(_database);
    final historyService = GetReconciliationHistory(_database);
    final balances = await Future.wait(
      accounts.map(
        (account) async => _AccountBalance(
          account: account,
          bookBalance: await balanceService(AppContext.householdId, account.id),
          latest: (await historyService(
            householdId: AppContext.householdId,
            accountId: account.id,
            limit: 1,
          )).firstOrNull,
        ),
      ),
    );
    final history = await historyService(
      householdId: AppContext.householdId,
      limit: 50,
    );
    return _ReconciliationOverview(balances: balances, history: history);
  }

  Future<void> _refresh() async {
    setState(() => _overviewFuture = _loadOverview());
    await _overviewFuture;
  }

  Future<void> _openEditor(
    List<_AccountBalance> balances, {
    String? initialAccountId,
  }) async {
    if (balances.isEmpty) return;
    final saved = await showDialog<AccountReconciliationLog>(
      context: context,
      builder: (_) => _ReconciliationDialog(
        balances: balances,
        initialAccountId: initialAccountId,
      ),
    );
    if (saved != null && mounted) {
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pemeriksaan tersimpan: ${saved.id} · ${_stamp(saved.checkedAt)}',
          ),
        ),
      );
    }
  }

  String _balanceLabel(int value) =>
      'Rp ${formatRupiahInput(value.toString())}';

  @override
  Widget build(BuildContext context) {
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.reconciliation,
      child: Scaffold(
        appBar: AppBar(title: const Text('Rekonsiliasi saldo')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final overview = await _overviewFuture;
            if (mounted) await _openEditor(overview.balances);
          },
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Cek saldo nyata'),
        ),
        body: FutureBuilder<_ReconciliationOverview>(
          future: _overviewFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('Gagal memuat saldo: ${snapshot.error}'),
              );
            }
            final overview = snapshot.data!;
            if (overview.balances.isEmpty) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: const [
                  AppEmptyState(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Belum ada rekening aktif',
                    message: 'Tambahkan rekening, tunai, atau dompet digital di Data Utama terlebih dahulu.',
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                const AppHelpBanner(
                  title: 'Saldo catatan vs saldo nyata',
                  message: 'Masukkan saldo yang benar-benar terlihat di rekening. FFM tidak menghapus transaksi lama; selisihnya dicatat sebagai transaksi penyesuaian.',
                  icon: Icons.fact_check_outlined,
                ),
                const SizedBox(height: 16),
                ...overview.balances.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.account_balance_wallet_outlined),
                        ),
                        title: Text(item.account.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Saldo buku\n${_balanceLabel(item.bookBalance)}'
                              '${item.latest == null ? '' : '\nTerakhir dicek ${_stamp(item.latest!.checkedAt)}\nSaldo nyata ${_balanceLabel(item.latest!.actualBalance)} · Selisih ${_balanceLabel(item.latest!.difference)}'}',
                            ),
                            if (item.latest != null)
                              HijriDateLabel(date: item.latest!.checkedAt),
                          ],
                        ),
                        isThreeLine: item.latest != null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openEditor(
                          overview.balances,
                          initialAccountId: item.account.id,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Riwayat pemeriksaan',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (overview.history.isEmpty)
                  const AppCard(
                    child: ListTile(
                      leading: Icon(Icons.history_outlined),
                      title: Text('Belum ada riwayat'),
                      subtitle: Text(
                        'Setelah cek saldo nyata, hasil pemeriksaannya akan muncul di sini.',
                      ),
                    ),
                  )
                else
                  ...overview.history.map(
                    (log) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        child: ListTile(
                          leading: Icon(
                            log.difference == 0
                                ? Icons.check_circle_outline
                                : Icons.tune_rounded,
                          ),
                          title: Text(
                            '${_balanceLabel(log.actualBalance)} · Selisih ${_balanceLabel(log.difference)}',
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_accountName(overview.balances, log.accountId)} · ${_stamp(log.checkedAt)}\nID ${log.id}',
                              ),
                              HijriDateLabel(date: log.checkedAt),
                            ],
                          ),
                          isThreeLine: true,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _accountName(List<_AccountBalance> balances, String id) {
    return balances
            .where((item) => item.account.id == id)
            .map((item) => item.account.name)
            .firstOrNull ??
        'Rekening tidak ditemukan';
  }
}

class _ReconciliationOverview {
  const _ReconciliationOverview({
    required this.balances,
    required this.history,
  });

  final List<_AccountBalance> balances;
  final List<AccountReconciliationLog> history;
}

class _AccountBalance {
  const _AccountBalance({
    required this.account,
    required this.bookBalance,
    required this.latest,
  });

  final Account account;
  final int bookBalance;
  final AccountReconciliationLog? latest;
}

class _ReconciliationDialog extends StatefulWidget {
  const _ReconciliationDialog({required this.balances, this.initialAccountId});

  final List<_AccountBalance> balances;
  final String? initialAccountId;

  @override
  State<_ReconciliationDialog> createState() => _ReconciliationDialogState();
}

class _ReconciliationDialogState extends State<_ReconciliationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _actualBalanceController = TextEditingController();
  final _noteController = TextEditingController();
  late String _accountId;
  late DateTime _date;

  _AccountBalance get _selected =>
      widget.balances.firstWhere((item) => item.account.id == _accountId);

  int get _actual => parseRupiah(_actualBalanceController.text);
  int get _difference => _actual - _selected.bookBalance;

  @override
  void initState() {
    super.initState();
    _accountId = widget.initialAccountId ?? widget.balances.first.account.id;
    _date = DateTime.now();
  }

  @override
  void dispose() {
    _actualBalanceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _date,
      helpText: 'Pilih tanggal pemeriksaan',
      cancelText: 'Batal',
      confirmText: 'Pakai tanggal',
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_difference != 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Simpan penyesuaian saldo?'),
          content: const Text(
            'Saldo catatan akan dikoreksi lewat transaksi penyesuaian; riwayat lama tidak dihapus.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cek lagi'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ya, simpan'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    final checkedAt = DateTime(
      _date.year,
      _date.month,
      _date.day,
      DateTime.now().hour,
      DateTime.now().minute,
      DateTime.now().second,
    );
    final database = getIt<AppDatabase>();
    final log = await CreateReconciliationLog(database)(
      householdId: AppContext.householdId,
      accountId: _accountId,
      actualBalance: _actual,
      checkedAt: checkedAt,
      note: _noteController.text,
    );
    await AuditLogger(database).record(
      action: 'rekonsiliasi',
      entity: 'saldo_rekening',
      oldValue: {'account_id': _accountId, 'saldo_buku': log.bookBalance},
      newValue: {
        'account_id': _accountId,
        'saldo_nyata': log.actualBalance,
        'selisih': log.difference,
        'adjustment_transaction_id': log.adjustmentTransactionId,
      },
    );
    if (mounted) Navigator.pop(context, log);
  }

  String _money(int value) => 'Rp ${formatRupiahInput(value.toString())}';

  @override
  Widget build(BuildContext context) {
    final differenceColor = _difference == 0
        ? Colors.green
        : _difference > 0
        ? Colors.blue
        : Colors.red;
    return AlertDialog(
      title: const Text('Cek saldo nyata'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _accountId,
                  decoration: const InputDecoration(labelText: 'Rekening'),
                  items: widget.balances
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.account.id,
                          child: Text(item.account.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _accountId = value;
                        _actualBalanceController.clear();
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                _BalanceMetric(
                  label: 'Saldo buku',
                  value: _money(_selected.bookBalance),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _actualBalanceController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Saldo nyata sekarang',
                    prefixText: 'Rp ',
                    helperText: 'Contoh: saldo yang terlihat di aplikasi bank.',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) => parseRupiah(value ?? '') < 0
                      ? 'Saldo tidak boleh negatif.'
                      : null,
                ),
                const SizedBox(height: 8),
                _BalanceMetric(
                  label: 'Selisih',
                  value: _money(_difference),
                  valueColor: differenceColor,
                ),
                const SizedBox(height: 4),
                Text(
                  _difference == 0
                      ? 'Saldo sudah cocok. Tetap bisa disimpan sebagai catatan pemeriksaan.'
                      : _difference > 0
                      ? 'Saldo nyata lebih besar. FFM akan mencatat pemasukan penyesuaian.'
                      : 'Saldo nyata lebih kecil. FFM akan mencatat pengeluaran penyesuaian.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Tanggal pemeriksaan'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${formatTanggalLengkap(_date)} ${_stamp(_date).substring(11)}',
                      ),
                      HijriDateLabel(date: _date),
                    ],
                  ),
                  trailing: TextButton(
                    onPressed: _pickDate,
                    child: const Text('Ganti'),
                  ),
                ),
                TextFormField(
                  controller: _noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                    hintText: 'Contoh: cek saldo setelah mutasi bank',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _save, child: const Text('Simpan cek saldo')),
      ],
    );
  }
}

class _BalanceMetric extends StatelessWidget {
  const _BalanceMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Text(
        value,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: valueColor, fontWeight: FontWeight.w700),
      ),
    );
  }
}

String _stamp(DateTime value) =>
    DateFormat('dd/MM/yyyy HH:mm:ss').format(value);
