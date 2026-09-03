import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../../liability/domain/debt_receivable_validation.dart';
import '../../../liability/presentation/widgets/debt_payment_dialog.dart';
import '../../domain/entities/receivable_entity.dart';
import '../../domain/usecases/receivable_crud_usecases.dart';

enum _ReceivableSort {
  sisaTerbesar,
  sisaTerkecil,
  cicilanTerbesar,
  jatuhTempoTerdekat,
}

class ReceivableListPage extends StatefulWidget {
  const ReceivableListPage({this.embedded = false, super.key});

  final bool embedded;

  @override
  State<ReceivableListPage> createState() => _ReceivableListPageState();
}

class _ReceivableListPageState extends State<ReceivableListPage> {
  var _receivables = <ReceivableEntity>[];
  var _loading = true;
  Object? _loadError;
  var _sort = _ReceivableSort.sisaTerbesar;
  var _searchQuery = '';
  final _searchController = TextEditingController();

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
    try {
      final items = await getIt<GetReceivables>()(AppContext.householdId);
      if (!mounted) return;
      setState(() {
        _receivables = items;
        _loadError = null;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  String _moneyLabel(int value) {
    final digits = value.abs().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      final start = (end - 3).clamp(0, end);
      groups.insert(0, digits.substring(start, end));
    }
    return 'Rp${groups.join('.')}';
  }

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  Future<void> _openForm() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ReceivableFormPage()),
    );
    if (saved == true) await _load();
  }

  List<ReceivableEntity> _sortItems(List<ReceivableEntity> items) {
    final sorted = List<ReceivableEntity>.of(items);
    sorted.sort((a, b) {
      final comparison = switch (_sort) {
        _ReceivableSort.sisaTerbesar => b.remainingBalance.compareTo(
          a.remainingBalance,
        ),
        _ReceivableSort.sisaTerkecil => a.remainingBalance.compareTo(
          b.remainingBalance,
        ),
        _ReceivableSort.cicilanTerbesar => b.monthlyInstallment.compareTo(
          a.monthlyInstallment,
        ),
        _ReceivableSort.jatuhTempoTerdekat => a.dueDate.compareTo(b.dueDate),
      };
      return comparison == 0 ? a.name.compareTo(b.name) : comparison;
    });
    return sorted;
  }

  bool _isDueWithin(ReceivableEntity item, int startDay, int endDay) {
    if (item.remainingBalance <= 0) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(
      item.dueDate.year,
      item.dueDate.month,
      item.dueDate.day,
    );
    final daysUntilDue = dueDate.difference(today).inDays;
    return daysUntilDue >= startDay && daysUntilDue <= endDay;
  }

  bool _isDueAfter(ReceivableEntity item, int days) {
    if (item.remainingBalance <= 0) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(
      item.dueDate.year,
      item.dueDate.month,
      item.dueDate.day,
    );
    final daysUntilDue = dueDate.difference(today).inDays;
    return daysUntilDue > days;
  }

  bool _isOverdue(ReceivableEntity item) {
    if (item.remainingBalance <= 0) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(
      item.dueDate.year,
      item.dueDate.month,
      item.dueDate.day,
    );
    return dueDate.isBefore(today);
  }

  String _statusLabel(ReceivableEntity item) {
    final status = classifyDebtReceivableDue(
      remainingBalance: item.remainingBalance,
      dueDate: item.dueDate,
      today: DateTime.now(),
    );
    return debtReceivableDueStatusLabel(status);
  }

  Widget _list(
    List<ReceivableEntity> items, {
    required String emptyTitle,
    required String emptyMessage,
  }) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
        children: [
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: AppEmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: emptyTitle,
                message: emptyMessage,
                action: FilledButton.icon(
                  onPressed: _openForm,
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah piutang'),
                ),
              ),
            )
          else
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ReceivableDetailPage(receivable: item),
                        ),
                      );
                      if (mounted) _load();
                    },
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.positiveSoft,
                      foregroundColor: AppColors.positive,
                      child: Icon(Icons.account_balance_wallet_outlined),
                    ),
                    title: Text(item.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cicilan ${_moneyLabel(item.monthlyInstallment)} per bulan\nJatuh tempo ${_dateLabel(item.dueDate)}',
                        ),
                        Text(
                          _statusLabel(item),
                          style: TextStyle(
                            color: _isOverdue(item)
                                ? AppColors.negative
                                : AppColors.inkMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        HijriDateLabel(date: item.dueDate),
                      ],
                    ),
                    trailing: AppMoneyText(item.remainingBalance, compact: true),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _receivables.where((item) {
      if (_searchQuery.isEmpty) return true;
      return item.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList(growable: false);

    final total = filtered.fold<int>(
      0,
      (sum, item) => sum + item.remainingBalance,
    );
    final active = filtered
        .where((item) => item.remainingBalance > 0)
        .toList(growable: false);
    final dueWithinWeek = active
        .where((item) => _isDueWithin(item, 0, 7))
        .toList(growable: false);
    final dueWithinMonth = active
        .where((item) => _isDueWithin(item, 8, 30))
        .toList(growable: false);
    final dueOverMonth = active
        .where((item) => _isDueAfter(item, 30))
        .toList(growable: false);
    final overdue = active.where(_isOverdue).toList(growable: false);
    final paidOff = filtered
        .where((item) => item.remainingBalance <= 0)
        .toList(growable: false);

    final totalMonthlyInstallment = active.fold<int>(
      0,
      (sum, i) => sum + i.monthlyInstallment,
    );
    final totalOverdue = overdue.fold<int>(
      0,
      (sum, i) => sum + i.remainingBalance,
    );
    final totalDueWeek = dueWithinWeek.fold<int>(
      0,
      (sum, i) => sum + i.remainingBalance,
    );

    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.liabilities,
      dataSummary:
          'Total sisa piutang: ${_moneyLabel(total)}. Ada ${active.length} piutang aktif, ${dueWithinWeek.length + dueWithinMonth.length} jatuh tempo dalam 30 hari.',
      child: Scaffold(
        appBar: widget.embedded
            ? null
            : AppBar(
                title: const Text('Piutang keluarga'),
                actions: [
                  PopupMenuButton<_ReceivableSort>(
                    tooltip: 'Urutkan piutang',
                    initialValue: _sort,
                    onSelected: (value) => setState(() => _sort = value),
                    icon: const Icon(Icons.sort_rounded),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _ReceivableSort.sisaTerbesar,
                        child: Text('Sisa terbesar'),
                      ),
                      PopupMenuItem(
                        value: _ReceivableSort.sisaTerkecil,
                        child: Text('Sisa terkecil'),
                      ),
                      PopupMenuItem(
                        value: _ReceivableSort.cicilanTerbesar,
                        child: Text('Cicilan terbesar'),
                      ),
                      PopupMenuItem(
                        value: _ReceivableSort.jatuhTempoTerdekat,
                        child: Text('Jatuh tempo terdekat'),
                      ),
                    ],
                  ),
                ],
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? _LoadError(onRetry: _load)
            : DefaultTabController(
                length: 7,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Column(
                        children: [
                          AppCard(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                const CircleAvatar(
                                  backgroundColor: AppColors.positiveSoft,
                                  foregroundColor: AppColors.positive,
                                  child: Icon(
                                    Icons.account_balance_wallet_outlined,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Total Sisa Piutang',
                                        style: AppTextStyles.labelCaps,
                                      ),
                                      const SizedBox(height: 2),
                                      AppMoneyText(total, compact: true),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    _StatBadge(
                                      label: 'Estimasi/bln',
                                      value: _moneyLabel(totalMonthlyInstallment),
                                    ),
                                    if (totalOverdue > 0) ...[
                                      const SizedBox(height: 4),
                                      _StatBadge(
                                        label: 'Terlambat',
                                        value: _moneyLabel(totalOverdue),
                                        isNegative: true,
                                      ),
                                    ],
                                    if (totalDueWeek > 0) ...[
                                      const SizedBox(height: 4),
                                      _StatBadge(
                                        label: '0-7 hari',
                                        value: _moneyLabel(totalDueWeek),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Search field
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Cari nama piutang...',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    )
                                  : null,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onChanged: (val) =>
                                setState(() => _searchQuery = val.trim()),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TabBar(
                      isScrollable: true,
                      tabs: [
                        Tab(text: 'Semua (${filtered.length})'),
                        Tab(text: 'Aktif (${active.length})'),
                        Tab(text: 'Terlambat (${overdue.length})'),
                        Tab(text: '0-7 hari (${dueWithinWeek.length})'),
                        Tab(text: '8-30 hari (${dueWithinMonth.length})'),
                        Tab(text: '> 30 hari (${dueOverMonth.length})'),
                        Tab(text: 'Lunas (${paidOff.length})'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _list(
                            _sortItems(filtered),
                            emptyTitle: 'Belum ada piutang',
                            emptyMessage:
                                'Catat uang yang masih harus diterima supaya lebih gampang dipantau.',
                          ),
                          _list(
                            _sortItems(active),
                            emptyTitle: 'Tidak ada piutang aktif',
                            emptyMessage:
                                'Semua piutang sudah lunas atau belum dicatat.',
                          ),
                          _list(
                            _sortItems(overdue),
                            emptyTitle: 'Tidak ada piutang terlambat',
                            emptyMessage:
                                'Piutang yang melewati jatuh tempo akan muncul di sini.',
                          ),
                          _list(
                            _sortItems(dueWithinWeek),
                            emptyTitle: 'Belum ada jatuh tempo 0-7 hari',
                            emptyMessage:
                                'Piutang dengan jatuh tempo satu minggu ke depan akan muncul di sini.',
                          ),
                          _list(
                            _sortItems(dueWithinMonth),
                            emptyTitle: 'Belum ada jatuh tempo 8-30 hari',
                            emptyMessage:
                                'Piutang dengan jatuh tempo 8 sampai 30 hari ke depan akan muncul di sini.',
                          ),
                          _list(
                            _sortItems(dueOverMonth),
                            emptyTitle: 'Belum ada jatuh tempo > 30 hari',
                            emptyMessage:
                                'Piutang dengan jatuh tempo lebih dari 30 hari akan muncul di sini.',
                          ),
                          _list(
                            _sortItems(paidOff),
                            emptyTitle: 'Belum ada piutang lunas',
                            emptyMessage:
                                'Piutang yang saldonya sudah nol akan muncul di sini.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'receivable_add_fab',
          onPressed: _openForm,
          icon: const Icon(Icons.add),
          label: const Text('Tambah piutang'),
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.label,
    required this.value,
    this.isNegative = false,
  });

  final String label;
  final String value;
  final bool isNegative;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isNegative ? AppColors.negativeSoft : AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isNegative ? AppColors.negative : AppColors.ink,
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.negative),
            const SizedBox(height: 12),
            Text(
              'Gagal memuat data piutang',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Periksa koneksi atau coba muat ulang data.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

class ReceivableFormPage extends StatefulWidget {
  const ReceivableFormPage({
    this.initialName,
    this.initialAmount,
    this.initialDueDate,
    super.key,
  });

  final String? initialName;
  final int? initialAmount;
  final DateTime? initialDueDate;

  @override
  State<ReceivableFormPage> createState() => _ReceivableFormPageState();
}

class _ReceivableFormPageState extends State<ReceivableFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _originalController = TextEditingController();
  final _remainingController = TextEditingController();
  final _installmentController = TextEditingController();
  final _interestController = TextEditingController();
  late DateTime _dueDate;

  @override
  void initState() {
    super.initState();
    _dueDate =
        widget.initialDueDate ?? DateTime.now().add(const Duration(days: 30));
    _nameController.text = widget.initialName ?? '';
    if (widget.initialAmount != null) {
      final amount = widget.initialAmount.toString();
      _originalController.text = amount;
      _remainingController.text = amount;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _originalController.dispose();
    _remainingController.dispose();
    _installmentController.dispose();
    _interestController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _dueDate,
      helpText: 'Pilih tanggal jatuh tempo',
      cancelText: 'Batal',
      confirmText: 'Selesai',
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final originalAmount = parseRupiah(_originalController.text);
    final remainingBalance = parseRupiah(_remainingController.text);
    final monthlyInstallment = parseRupiah(_installmentController.text);
    final interestText = _interestController.text.trim();
    final interestRate = interestText.isEmpty
        ? null
        : double.tryParse(interestText.replaceAll(',', '.'));
    final validationError = interestText.isNotEmpty && interestRate == null
        ? 'Bunga belum valid.'
        : validateDebtReceivableAmounts(
            originalAmount: originalAmount,
            remainingBalance: remainingBalance,
            monthlyInstallment: monthlyInstallment,
            interestRate: interestRate,
          );
    if (validationError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(validationError)));
      return;
    }

    final dateError = validateDebtReceivableDates(
      startDate: DateTime.now(),
      dueDate: _dueDate,
    );
    if (dateError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dateError)));
      return;
    }

    final now = DateTime.now();
    await getIt<SaveReceivable>()(
      ReceivableEntity(
        id: const Uuid().v4(),
        householdId: AppContext.householdId,
        name: _nameController.text.trim(),
        originalAmount: originalAmount,
        remainingBalance: remainingBalance,
        monthlyInstallment: monthlyInstallment,
        interestRate: interestRate,
        startDate: now,
        dueDate: _dueDate,
        updatedAt: now,
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  String? _requiredMoney(String? value) {
    return parseRupiah(value ?? '') <= 0 ? 'Isi nominalnya dulu' : null;
  }

  @override
  Widget build(BuildContext context) {
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.liabilities,
      child: Scaffold(
        appBar: AppBar(title: const Text('Tambah piutang')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const AppHelpBanner(
                title: 'Catat uang yang masih harus diterima',
                message:
                    'Piutang belum dihitung sebagai pemasukan. Saat uang benar-benar masuk, catat transaksi pemasukan ke rekening atau dompet yang menerima.',
                icon: Icons.info_outline,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nama piutang'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Nama piutang belum diisi'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _originalController,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: const InputDecoration(labelText: 'Nominal awal'),
                validator: _requiredMoney,
                onChanged: (val) {
                  if (_remainingController.text.isEmpty) {
                    _remainingController.text = val;
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _remainingController,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Sisa yang belum diterima',
                ),
                validator: _requiredMoney,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _installmentController,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Perkiraan cicilan per bulan (0 jika sekali bayar)',
                ),
                validator: (val) => parseRupiah(val ?? '') < 0
                    ? 'Cicilan tidak boleh negatif'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _interestController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Bunga per tahun (opsional)',
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Jatuh tempo'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_dateLabel(_dueDate)),
                    HijriDateLabel(date: _dueDate),
                  ],
                ),
                trailing: OutlinedButton(
                  onPressed: _pickDueDate,
                  child: const Text('Pilih tanggal'),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Simpan piutang'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReceivableDetailPage extends StatefulWidget {
  const ReceivableDetailPage({required this.receivable, super.key});

  final ReceivableEntity receivable;

  @override
  State<ReceivableDetailPage> createState() => _ReceivableDetailPageState();
}

class _ReceivableDetailPageState extends State<ReceivableDetailPage> {
  late ReceivableEntity _receivable;
  List<Transaction> _paymentHistory = [];
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _receivable = widget.receivable;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final db = getIt<AppDatabase>();
      final txs = await (db.select(db.transactions)
            ..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.source.equals('receivable_payment') &
                  row.sourceId.equals(_receivable.id),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.date)]))
          .get();

      if (!mounted) return;
      setState(() {
        _paymentHistory = txs;
        _loadingHistory = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _refreshData() async {
    final db = getIt<AppDatabase>();
    final row = await (db.select(db.receivables)
          ..where(
            (r) =>
                r.householdId.equals(AppContext.householdId) &
                r.id.equals(_receivable.id),
          ))
        .getSingleOrNull();

    if (row != null && mounted) {
      setState(() {
        _receivable = ReceivableEntity(
          id: row.id,
          householdId: row.householdId,
          name: row.name,
          originalAmount: row.originalAmount,
          remainingBalance: row.remainingBalance,
          monthlyInstallment: row.monthlyInstallment,
          interestRate: row.interestRate,
          startDate: row.startDate,
          dueDate: row.dueDate ?? row.startDate,
          updatedAt: row.createdAt,
          note: row.note,
        );
      });
      await _loadHistory();
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _receivable.originalAmount <= 0
        ? 0.0
        : (1 - _receivable.remainingBalance / _receivable.originalAmount).clamp(
            0.0,
            1.0,
          );
    final status = classifyDebtReceivableDue(
      remainingBalance: _receivable.remainingBalance,
      dueDate: _receivable.dueDate,
      today: DateTime.now(),
    );

    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.liabilities,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Detail piutang'),
          actions: [
            IconButton(
              tooltip: 'Edit piutang',
              onPressed: () async {
                final updated = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReceivableEditPage(receivable: _receivable),
                  ),
                );
                if (updated == true) {
                  await _refreshData();
                }
              },
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refreshData,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              // Kartu Status Utama & Progress
              AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _receivable.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Sisa piutang',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      AppMoneyText(_receivable.remainingBalance, compact: false),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _receivable.remainingBalance <= 0
                              ? AppColors.positiveSoft
                              : status == DebtReceivableDueStatus.overdue
                              ? AppColors.negativeSoft
                              : AppColors.positiveSoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          debtReceivableDueStatusLabel(status),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _receivable.remainingBalance <= 0
                                ? AppColors.positive
                                : status == DebtReceivableDueStatus.overdue
                                ? AppColors.negative
                                : AppColors.positive,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      LinearProgressIndicator(
                        value: progress,
                        color: AppColors.positive,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(progress * 100).round()}% sudah diterima dari ${formatRupiahInput(_receivable.originalAmount.toString())}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Tombol Utama: Terima Pembayaran Piutang
              if (_receivable.remainingBalance > 0)
                FilledButton.icon(
                  onPressed: () async {
                    final paid = await DebtPaymentDialog.show(
                      context,
                      targetId: _receivable.id,
                      targetName: _receivable.name,
                      remainingBalance: _receivable.remainingBalance,
                      isLiability: false,
                    );
                    if (paid == true) {
                      await _refreshData();
                    }
                  },
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Terima Pembayaran Piutang'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.positive,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),

              const SizedBox(height: 16),

              // Rincian Informasi
              AppCard(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Nominal awal'),
                      trailing: AppMoneyText(_receivable.originalAmount, compact: true),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('Tanggal mulai'),
                      trailing: Text(_formatDate(_receivable.startDate)),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('Cicilan per bulan'),
                      trailing: AppMoneyText(
                        _receivable.monthlyInstallment,
                        compact: true,
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('Jatuh tempo'),
                      subtitle: HijriDateLabel(date: _receivable.dueDate),
                      trailing: Text(_formatDate(_receivable.dueDate)),
                    ),
                    if (_receivable.interestRate != null) ...[
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('Bunga per tahun'),
                        trailing: Text(
                          '${_receivable.interestRate!.toStringAsFixed(2)}%',
                        ),
                      ),
                    ],
                    if (_receivable.note?.trim().isNotEmpty == true) ...[
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('Catatan'),
                        subtitle: Text(_receivable.note!),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Riwayat Pembayaran Kas
              Text(
                'Riwayat Penerimaan Kas',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              if (_loadingHistory)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_paymentHistory.isEmpty)
                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'Belum ada riwayat pembayaran yang diterima.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                )
              else
                AppCard(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _paymentHistory.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final tx = _paymentHistory[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppColors.positiveSoft,
                          foregroundColor: AppColors.positive,
                          child: Icon(Icons.check_circle_outline, size: 20),
                        ),
                        title: Text(tx.note ?? 'Penerimaan piutang'),
                        subtitle: Text(_formatDate(tx.date)),
                        trailing: AppMoneyText(tx.amount.abs(), compact: true),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 24),

              // Tombol Arsip
              OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Arsipkan piutang?'),
                      content: const Text(
                        'Piutang akan disembunyikan dari daftar aktif, tetapi datanya tetap tersimpan.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Batal'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Arsipkan'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  await getIt<DeleteReceivable>()(
                    _receivable.householdId,
                    _receivable.id,
                  );
                  if (context.mounted) Navigator.pop(context, true);
                },
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Arsipkan piutang'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReceivableEditPage extends StatefulWidget {
  const ReceivableEditPage({required this.receivable, super.key});

  final ReceivableEntity receivable;

  @override
  State<ReceivableEditPage> createState() => _ReceivableEditPageState();
}

class _ReceivableEditPageState extends State<ReceivableEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _remainingController;
  late final TextEditingController _installmentController;
  late final TextEditingController _interestController;

  @override
  void initState() {
    super.initState();
    _remainingController = TextEditingController(
      text: formatRupiahInput('${widget.receivable.remainingBalance}'),
    );
    _installmentController = TextEditingController(
      text: formatRupiahInput('${widget.receivable.monthlyInstallment}'),
    );
    _interestController = TextEditingController(
      text: widget.receivable.interestRate?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _remainingController.dispose();
    _installmentController.dispose();
    _interestController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final interestText = _interestController.text.trim();
    final interestRate = interestText.isEmpty
        ? null
        : double.tryParse(interestText.replaceAll(',', '.'));
    final validationError = interestText.isNotEmpty && interestRate == null
        ? 'Bunga belum valid.'
        : validateDebtReceivableAmounts(
            originalAmount: widget.receivable.originalAmount,
            remainingBalance: parseRupiah(_remainingController.text),
            monthlyInstallment: parseRupiah(_installmentController.text),
            interestRate: interestRate,
          );
    if (validationError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(validationError)));
      return;
    }
    await getIt<SaveReceivable>()(
      ReceivableEntity(
        id: widget.receivable.id,
        householdId: AppContext.householdId,
        name: widget.receivable.name,
        originalAmount: widget.receivable.originalAmount,
        remainingBalance: parseRupiah(_remainingController.text),
        monthlyInstallment: parseRupiah(_installmentController.text),
        interestRate: interestRate,
        startDate: widget.receivable.startDate,
        dueDate: widget.receivable.dueDate,
        updatedAt: DateTime.now(),
        note: widget.receivable.note,
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.liabilities,
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit piutang')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                'Piutang: ${widget.receivable.name}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _remainingController,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: const InputDecoration(labelText: 'Sisa piutang'),
                validator: (value) => parseRupiah(value ?? '') < 0
                    ? 'Sisa piutang belum valid.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _installmentController,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Cicilan per bulan',
                ),
                validator: (value) => parseRupiah(value ?? '') < 0
                    ? 'Cicilan belum valid.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _interestController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Bunga per tahun (opsional)',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Simpan perubahan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
