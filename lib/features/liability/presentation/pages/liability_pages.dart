import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../../receivable/presentation/pages/receivable_pages.dart';
import '../../domain/entities/liability_entity.dart';
import '../../domain/debt_receivable_validation.dart';
import '../../domain/usecases/liability_crud_usecases.dart';
import 'debt_payoff_strategy_page.dart';
import 'liability_detail_page.dart';

enum _LiabilitySort {
  sisaTerbesar,
  sisaTerkecil,
  cicilanTerbesar,
  jatuhTempoTerdekat,
}

class LiabilityReceivablePage extends StatelessWidget {
  const LiabilityReceivablePage({super.key});

  @override
  Widget build(BuildContext context) {
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.liabilities,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Hutang & piutang'),
            actions: [
              IconButton(
                tooltip: 'Simulator Bebas Hutang',
                icon: const Icon(Icons.calculate_outlined),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DebtPayoffStrategyPage(),
                    ),
                  );
                },
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Hutang'),
                Tab(text: 'Piutang'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              LiabilityListPage(embedded: true),
              ReceivableListPage(embedded: true),
            ],
          ),
        ),
      ),
    );
  }
}

class LiabilityListPage extends StatefulWidget {
  const LiabilityListPage({this.embedded = false, super.key});

  final bool embedded;

  @override
  State<LiabilityListPage> createState() => _LiabilityListPageState();
}

class _LiabilityListPageState extends State<LiabilityListPage> {
  var _liabilities = <LiabilityEntity>[];
  var _loading = true;
  Object? _loadError;
  var _sort = _LiabilitySort.sisaTerbesar;
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
      final items = await getIt<GetLiabilities>()(AppContext.householdId);
      if (!mounted) return;
      setState(() {
        _liabilities = items;
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
      MaterialPageRoute(builder: (_) => const LiabilityFormPage()),
    );
    if (saved == true) await _load();
  }

  List<LiabilityEntity> _sortLiabilities(List<LiabilityEntity> items) {
    final sorted = List<LiabilityEntity>.of(items);
    sorted.sort((a, b) {
      final comparison = switch (_sort) {
        _LiabilitySort.sisaTerbesar => b.remainingBalance.compareTo(
          a.remainingBalance,
        ),
        _LiabilitySort.sisaTerkecil => a.remainingBalance.compareTo(
          b.remainingBalance,
        ),
        _LiabilitySort.cicilanTerbesar => b.monthlyInstallment.compareTo(
          a.monthlyInstallment,
        ),
        _LiabilitySort.jatuhTempoTerdekat => a.dueDate.compareTo(b.dueDate),
      };
      return comparison == 0 ? a.name.compareTo(b.name) : comparison;
    });
    return sorted;
  }

  bool _isDueWithin(LiabilityEntity item, int startDay, int endDay) {
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

  bool _isDueAfter(LiabilityEntity item, int days) {
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

  bool _isOverdue(LiabilityEntity item) {
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

  String _statusLabel(LiabilityEntity item) {
    final status = classifyDebtReceivableDue(
      remainingBalance: item.remainingBalance,
      dueDate: item.dueDate,
      today: DateTime.now(),
    );
    return debtReceivableDueStatusLabel(status);
  }

  Widget _liabilityList(
    List<LiabilityEntity> items, {
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
                icon: Icons.credit_card_off_outlined,
                title: emptyTitle,
                message: emptyMessage,
                action: FilledButton.icon(
                  onPressed: _openForm,
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah hutang'),
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
                          builder: (_) => LiabilityDetailPage(liability: item),
                        ),
                      );
                      if (mounted) _load();
                    },
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.warningSoft,
                      foregroundColor: AppColors.warning,
                      child: Icon(Icons.credit_card_outlined),
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
    final filtered = _liabilities.where((item) {
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
          'Total sisa hutang: ${_moneyLabel(total)}. Ada ${active.length} hutang aktif, ${dueWithinWeek.length + dueWithinMonth.length} jatuh tempo dalam 30 hari.',
      child: Scaffold(
        appBar: widget.embedded
            ? null
            : AppBar(
                title: const Text('Hutang keluarga'),
                actions: [
                  PopupMenuButton<_LiabilitySort>(
                    tooltip: 'Urutkan hutang',
                    initialValue: _sort,
                    onSelected: (value) => setState(() => _sort = value),
                    icon: const Icon(Icons.sort_rounded),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _LiabilitySort.sisaTerbesar,
                        child: Text('Sisa terbesar'),
                      ),
                      PopupMenuItem(
                        value: _LiabilitySort.sisaTerkecil,
                        child: Text('Sisa terkecil'),
                      ),
                      PopupMenuItem(
                        value: _LiabilitySort.cicilanTerbesar,
                        child: Text('Cicilan terbesar'),
                      ),
                      PopupMenuItem(
                        value: _LiabilitySort.jatuhTempoTerdekat,
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
                                  backgroundColor: AppColors.warningSoft,
                                  foregroundColor: AppColors.warning,
                                  child: Icon(Icons.credit_score_outlined),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Total Sisa Hutang',
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
                                      label: 'Cicilan/bln',
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
                          if (total > 0) ...[
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const DebtPayoffStrategyPage(),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySoft,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppColors.primary.withAlpha(50),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.bolt,
                                      size: 18,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Simulasi Bebas Hutang (Snowball vs Avalanche)',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primary,
                                            ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right,
                                      size: 18,
                                      color: AppColors.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          // Search field
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Cari nama hutang...',
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
                          _liabilityList(
                            _sortLiabilities(filtered),
                            emptyTitle: 'Belum ada hutang',
                            emptyMessage:
                                'Catat cicilan supaya strategi pelunasanmu lebih jelas.',
                          ),
                          _liabilityList(
                            _sortLiabilities(active),
                            emptyTitle: 'Tidak ada hutang aktif',
                            emptyMessage:
                                'Semua hutang sudah lunas atau belum dicatat.',
                          ),
                          _liabilityList(
                            _sortLiabilities(overdue),
                            emptyTitle: 'Tidak ada hutang terlambat',
                            emptyMessage:
                                'Hutang yang melewati jatuh tempo akan muncul di sini.',
                          ),
                          _liabilityList(
                            _sortLiabilities(dueWithinWeek),
                            emptyTitle: 'Belum ada jatuh tempo 0-7 hari',
                            emptyMessage:
                                'Hutang dengan jatuh tempo satu minggu ke depan akan muncul di sini.',
                          ),
                          _liabilityList(
                            _sortLiabilities(dueWithinMonth),
                            emptyTitle: 'Belum ada jatuh tempo 8-30 hari',
                            emptyMessage:
                                'Hutang dengan jatuh tempo 8 sampai 30 hari ke depan akan muncul di sini.',
                          ),
                          _liabilityList(
                            _sortLiabilities(dueOverMonth),
                            emptyTitle: 'Belum ada jatuh tempo > 30 hari',
                            emptyMessage:
                                'Hutang dengan jatuh tempo lebih dari 30 hari akan muncul di sini.',
                          ),
                          _liabilityList(
                            _sortLiabilities(paidOff),
                            emptyTitle: 'Belum ada hutang lunas',
                            emptyMessage:
                                'Hutang yang saldonya sudah nol akan muncul di sini.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'liability_add_fab',
          onPressed: _openForm,
          icon: const Icon(Icons.add),
          label: const Text('Tambah hutang'),
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
              'Gagal memuat data hutang',
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

class LiabilityFormPage extends StatefulWidget {
  const LiabilityFormPage({
    this.initialName,
    this.initialAmount,
    this.initialDueDate,
    super.key,
  });

  final String? initialName;
  final int? initialAmount;
  final DateTime? initialDueDate;

  @override
  State<LiabilityFormPage> createState() => _LiabilityFormPageState();
}

class _LiabilityFormPageState extends State<LiabilityFormPage> {
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
    _dueDate = widget.initialDueDate ?? DateTime.now().add(const Duration(days: 30));
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

  int _parseMoney(String text) {
    return parseRupiah(text);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final originalAmount = _parseMoney(_originalController.text);
    final remainingBalance = _parseMoney(_remainingController.text);
    final monthlyInstallment = _parseMoney(_installmentController.text);
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

    await getIt<SaveLiability>()(
      LiabilityEntity(
        id: const Uuid().v4(),
        householdId: AppContext.householdId,
        name: _nameController.text.trim(),
        originalAmount: originalAmount,
        remainingBalance: remainingBalance,
        monthlyInstallment: monthlyInstallment,
        interestRate: interestRate,
        startDate: DateTime.now(),
        dueDate: _dueDate,
        updatedAt: DateTime.now(),
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.liabilities,
      child: Scaffold(
        appBar: AppBar(title: const Text('Tambah hutang')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nama hutang'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Nama wajib diisi.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _originalController,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: const InputDecoration(labelText: 'Nominal awal'),
                validator: (value) => _parseMoney(value ?? '') <= 0
                    ? 'Nominal awal harus lebih besar dari nol.'
                    : null,
                onChanged: (value) {
                  if (_remainingController.text.isEmpty) {
                    _remainingController.text = value;
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _remainingController,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: const InputDecoration(labelText: 'Sisa hutang'),
                validator: (value) => _parseMoney(value ?? '') < 0
                    ? 'Sisa hutang belum valid.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _installmentController,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Cicilan per bulan (0 jika sekali bayar)',
                ),
                validator: (value) => _parseMoney(value ?? '') < 0
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
                  labelText: 'Bunga per tahun (opsional, contoh: 5.5)',
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tanggal jatuh tempo'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_dueDate.day}/${_dueDate.month}/${_dueDate.year}',
                    ),
                    HijriDateLabel(date: _dueDate),
                  ],
                ),
                trailing: TextButton.icon(
                  onPressed: _pickDueDate,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('Pilih'),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Simpan hutang'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
