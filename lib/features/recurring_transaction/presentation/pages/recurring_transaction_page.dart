import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../../../shared/widgets/date_time_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../domain/usecases/recurring_transaction_crud_usecases.dart';

class RecurringTransactionPage extends StatefulWidget {
  const RecurringTransactionPage({super.key});

  @override
  State<RecurringTransactionPage> createState() =>
      _RecurringTransactionPageState();
}

class _RecurringTransactionPageState extends State<RecurringTransactionPage> {
  final _database = getIt<AppDatabase>();
  late Future<_RecurringOptions> _optionsFuture;
  List<RecurringTransaction> _rules = const [];

  @override
  void initState() {
    super.initState();
    _optionsFuture = _loadOptions();
  }

  Future<_RecurringOptions> _loadOptions() async {
    final householdId = AppContext.householdId;
    final accounts =
        await (_database.select(_database.accounts)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isActive.equals(true) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .get();
    final categories =
        await (_database.select(_database.categories)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isActive.equals(true),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .get();
    final sources =
        await (_database.select(_database.transactionParties)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.kind.equals('income_source') &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .get();
    final rules = await GetRecurringTransactions(_database)(householdId);
    final warnings = await GetRecurringBalanceWarnings(_database)(householdId);
    if (mounted) setState(() => _rules = rules);
    return _RecurringOptions(
      accounts: accounts,
      categories: categories,
      sources: sources,
      warnings: warnings,
    );
  }

  Future<void> _refresh() async {
    setState(() => _optionsFuture = _loadOptions());
    await _optionsFuture;
  }

  Future<void> _openEditor({RecurringTransaction? existing}) async {
    final options = await _optionsFuture;
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _RecurringEditorDialog(options: options, existing: existing),
    );
    if (saved == true && mounted) await _refresh();
  }

  Future<void> _archive(RecurringTransaction rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nonaktifkan jadwal?'),
        content: Text(
          'Jadwal “${rule.name}” tidak akan membuat transaksi baru. Riwayat yang sudah dibuat tetap aman.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Nonaktifkan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ArchiveRecurringTransaction(_database)(
      AppContext.householdId,
      rule.id,
    );
    if (mounted) await _refresh();
  }

  String _typeLabel(String type) =>
      type == 'expense' ? 'Biaya/pengeluaran' : 'Pemasukan';

  String _periodLabel(String period) => switch (period) {
    'daily' => 'Harian',
    'weekly' => 'Mingguan',
    'biweekly' => 'Dua mingguan',
    _ => 'Bulanan',
  };

  String _amountLabel(RecurringTransaction rule) {
    if (rule.calcMode == 'percent' && rule.ratePercent != null) {
      return '${rule.ratePercent!.toStringAsFixed(2).replaceAll(RegExp(r'\.00$'), '')}% dari saldo';
    }
    return 'Rp ${formatRupiahInput(rule.amount.toString())}';
  }

  @override
  Widget build(BuildContext context) {
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.recurringTransaction,
      child: Scaffold(
        appBar: AppBar(title: const Text('Pemasukan & biaya berkala')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.add),
          label: const Text('Tambah jadwal'),
        ),
        body: FutureBuilder<_RecurringOptions>(
          future: _optionsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('Gagal memuat jadwal: ${snapshot.error}'),
              );
            }
            final options = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                const AppHelpBanner(
                  title: 'Bunga dan biaya tetap offline',
                  message: 'Atur bunga, pemasukan rutin, atau biaya admin bulanan di sini. Saat FFM dibuka, jadwal jatuh tempo dibuat menjadi transaksi satu kali saja.',
                  icon: Icons.autorenew_rounded,
                ),
                const SizedBox(height: 16),
                if (options.accounts.isEmpty)
                  const AppCard(
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Lengkapi Data Utama dulu'),
                      subtitle: Text(
                        'Siapkan rekening, kategori, dan sumber pemasukan supaya jadwalnya punya tujuan yang jelas.',
                      ),
                    ),
                  ),
                if (options.warnings.isNotEmpty)
                  AppCard(
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_rounded),
                      title: const Text('Ada jadwal yang perlu dicek'),
                      subtitle: Text(
                        options.warnings
                            .map(
                              (warning) => warning.willSkip
                                  ? '${warning.rule.name}: saldo nol/minus, jadwal persentase akan dilewati.'
                                  : '${warning.rule.name}: biaya sekitar Rp ${formatRupiahInput(warning.estimatedAmount.toString())} melebihi saldo buku Rp ${formatRupiahInput(warning.bookBalance.toString())}.',
                            )
                            .join('\\n'),
                      ),
                    ),
                  ),
                if (_rules.isEmpty)
                  const AppEmptyState(
                    icon: Icons.event_repeat_outlined,
                    title: 'Belum ada jadwal berkala',
                    message: 'Tambahkan bunga harian, pemasukan mingguan, atau biaya admin bulanan. Jadwal tidak mengubah saldo sebelum tanggalnya jatuh tempo.',
                  )
                else
                  ..._rules.map(
                    (rule) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppCard(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(
                              rule.type == 'expense'
                                  ? Icons.trending_down_rounded
                                  : Icons.trending_up_rounded,
                            ),
                          ),
                          title: Text(rule.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_typeLabel(rule.type)} · ${_periodLabel(rule.periodType)}\n'
                                '${_amountLabel(rule)} · Mulai ${formatTanggalLengkap(rule.startDate)}',
                              ),
                              HijriDateLabel(date: rule.startDate),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') _openEditor(existing: rule);
                              if (value == 'archive') _archive(rule);
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(
                                value: 'archive',
                                child: Text('Nonaktifkan'),
                              ),
                            ],
                          ),
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
}

class _RecurringOptions {
  const _RecurringOptions({
    required this.accounts,
    required this.categories,
    required this.sources,
    required this.warnings,
  });

  final List<Account> accounts;
  final List<Category> categories;
  final List<TransactionParty> sources;
  final List<RecurringBalanceWarning> warnings;
}

class _RecurringEditorDialog extends StatefulWidget {
  const _RecurringEditorDialog({required this.options, this.existing});

  final _RecurringOptions options;
  final RecurringTransaction? existing;

  @override
  State<_RecurringEditorDialog> createState() => _RecurringEditorDialogState();
}

class _RecurringEditorDialogState extends State<_RecurringEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _rateController;
  late final TextEditingController _noteController;
  late String _type;
  late String _period;
  late String _calcMode;
  String? _accountId;
  String? _categoryId;
  String? _sourceId;
  late DateTime _startDate;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _amountController = TextEditingController(
      text: existing == null || existing.amount == 0
          ? ''
          : formatRupiahInput(existing.amount.toString()),
    );
    _rateController = TextEditingController(
      text: existing?.ratePercent?.toString() ?? '',
    );
    _noteController = TextEditingController(text: existing?.note ?? '');
    _type = existing?.type ?? 'income';
    _period = existing?.periodType ?? 'monthly';
    _calcMode = existing?.calcMode ?? 'fixed';
    _accountId = existing?.accountId;
    _categoryId = existing?.categoryId;
    _sourceId = existing?.sourceId;
    _startDate = existing?.startDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _rateController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _startDate,
      helpText: 'Pilih tanggal mulai',
      cancelText: 'Batal',
      confirmText: 'Pakai tanggal',
    );
    if (picked != null && mounted) setState(() => _startDate = picked);
  }

  double? _parseRate() {
    final normalized = _rateController.text.trim().replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  Future<int> _currentBookBalance() async {
    final accountId = _accountId;
    if (accountId == null) return 0;
    return GetAccountBookBalance(getIt<AppDatabase>())(
      AppContext.householdId,
      accountId,
    );
  }

  String _previewAmount(int balance) {
    if (_calcMode == 'fixed') {
      final amount = parseRupiah(_amountController.text);
      return 'Rp ${formatRupiahInput(amount.toString())}';
    }
    final rate = _parseRate() ?? 0;
    final amount = balance <= 0 ? 0 : (balance * rate / 100).round();
    return 'Rp ${formatRupiahInput(amount.toString())}';
  }

  String? _validateAmount(String? value) {
    if (_calcMode == 'percent') return null;
    return parseRupiah(value ?? '') <= 0
        ? 'Nominal harus lebih dari nol.'
        : null;
  }

  String? _validateRate(String? value) {
    if (_calcMode != 'percent') return null;
    final rate = _parseRate();
    return rate == null || rate <= 0 || rate > 100
        ? 'Isi persentase antara 0,01 sampai 100.'
        : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih rekening dulu supaya saldo jelas.'),
        ),
      );
      return;
    }
    final amount = parseRupiah(_amountController.text);
    final rate = _calcMode == 'percent' ? _parseRate() : null;
    final database = getIt<AppDatabase>();
    final note = _noteController.text.trim();
    try {
      if (widget.existing == null) {
        await CreateRecurringTransaction(database)(
          householdId: AppContext.householdId,
          name: _nameController.text,
          type: _type,
          amount: amount,
          startDate: _startDate,
          periodType: _period,
          categoryId: _categoryId,
          accountId: _accountId,
          sourceId: _type == 'income' ? _sourceId : null,
          note: note.isEmpty ? null : note,
          calcMode: _calcMode,
          ratePercent: rate,
        );
      } else {
        await UpdateRecurringTransaction(database)(
          id: widget.existing!.id,
          householdId: AppContext.householdId,
          name: _nameController.text,
          type: _type,
          amount: amount,
          startDate: _startDate,
          periodType: _period,
          categoryId: _categoryId,
          accountId: _accountId,
          sourceId: _type == 'income' ? _sourceId : null,
          note: note.isEmpty ? null : note,
          calcMode: _calcMode,
          ratePercent: rate,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on ArgumentError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message?.toString() ?? 'Data belum valid.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    final filteredCategories = options.categories
        .where((item) => item.type == _type)
        .toList();
    final selectedCategory =
        filteredCategories.any((item) => item.id == _categoryId)
        ? _categoryId
        : null;
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Tambah jadwal berkala'
            : 'Edit jadwal berkala',
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nama jadwal',
                    hintText: 'Contoh: Bunga SeaBank atau admin bulanan',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nama jadwal wajib diisi.'
                      : null,
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'income',
                      label: Text('Pemasukan'),
                      icon: Icon(Icons.add_circle_outline),
                    ),
                    ButtonSegment(
                      value: 'expense',
                      label: Text('Biaya'),
                      icon: Icon(Icons.remove_circle_outline),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (value) => setState(() {
                    _type = value.first;
                    _categoryId = null;
                    if (_type == 'expense') _sourceId = null;
                  }),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'fixed',
                      label: Text('Nominal tetap'),
                      icon: Icon(Icons.payments_outlined),
                    ),
                    ButtonSegment(
                      value: 'percent',
                      label: Text('Persentase saldo'),
                      icon: Icon(Icons.percent_rounded),
                    ),
                  ],
                  selected: {_calcMode},
                  onSelectionChanged: (value) =>
                      setState(() => _calcMode = value.first),
                ),
                const SizedBox(height: 8),
                Text(
                  _calcMode == 'percent'
                      ? 'Nominal dihitung dari saldo buku saat jadwal diproses. Kalau saldo nol atau minus, jadwal dilewati.'
                      : 'Nominal yang sama dibuat pada setiap periode yang jatuh tempo.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (_calcMode == 'fixed')
                  TextFormField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [RupiahInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Nominal setiap periode',
                      prefixText: 'Rp ',
                    ),
                    validator: _validateAmount,
                    onChanged: (_) => setState(() {}),
                  )
                else
                  TextFormField(
                    controller: _rateController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Persentase per periode',
                      suffixText: '%',
                      hintText: 'Contoh: 0,5',
                    ),
                    validator: _validateRate,
                    onChanged: (_) => setState(() {}),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _period,
                  decoration: const InputDecoration(labelText: 'Periode'),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Harian')),
                    DropdownMenuItem(value: 'weekly', child: Text('Mingguan')),
                    DropdownMenuItem(
                      value: 'biweekly',
                      child: Text('Dua mingguan'),
                    ),
                    DropdownMenuItem(value: 'monthly', child: Text('Bulanan')),
                  ],
                  onChanged: (value) =>
                      setState(() => _period = value ?? 'monthly'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue:
                      options.accounts.any((item) => item.id == _accountId)
                      ? _accountId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Rekening tempat uangnya',
                    helperText: 'Wajib dipilih supaya saldo bisa dilacak.',
                  ),
                  items: options.accounts
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _accountId = value),
                ),
                const SizedBox(height: 8),
                FutureBuilder<int>(
                  future: _currentBookBalance(),
                  builder: (context, snapshot) {
                    final balance = snapshot.data ?? 0;
                    final preview = _previewAmount(balance);
                    final fixedAmount = parseRupiah(_amountController.text);
                    final warning =
                        _type == 'expense' &&
                        _calcMode == 'fixed' &&
                        balance < fixedAmount;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText:
                                'Preview berdasarkan saldo buku sekarang',
                          ),
                          child: Text(
                            '$preview · Saldo buku Rp ${formatRupiahInput(balance.toString())}',
                          ),
                        ),
                        if (warning)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Perhatian: biaya ini lebih besar dari saldo buku sekarang. Saat diproses, saldo bisa menjadi minus; cek dulu sebelum jadwal aktif.',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                if (_type == 'income') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue:
                        options.sources.any((item) => item.id == _sourceId)
                        ? _sourceId
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Sumber pemasukan (opsional)',
                    ),
                    items: options.sources
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _sourceId = value),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: InputDecoration(
                    labelText: _type == 'expense'
                        ? 'Kategori biaya (opsional)'
                        : 'Kategori pemasukan (opsional)',
                  ),
                  items: filteredCategories
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Mulai berlaku'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatTanggalLengkap(_startDate)),
                      HijriDateLabel(date: _startDate),
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
                    hintText: 'Contoh: sesuai mutasi bank atau biaya admin',
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
        FilledButton(onPressed: _save, child: const Text('Simpan jadwal')),
      ],
    );
  }
}
