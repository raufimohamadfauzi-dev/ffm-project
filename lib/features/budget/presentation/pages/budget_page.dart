import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../settings/data/offline_tool_history_service.dart';
import '../../../transaction/domain/entities/transaction_entity.dart';
import '../../../transaction/domain/usecases/transaction_crud_usecases.dart';
import '../../../settings/presentation/pages/master_data_page.dart';
import '../../../../shared/widgets/date_time_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';

enum _BudgetSort {
  nominalTerbesar,
  nominalTerkecil,
  tanggalTerbaru,
  tanggalTerlama,
}

enum _BudgetMenuAction { transferFunds, weekStart }

class BudgetPage extends EnvelopeBudgetPage {
  const BudgetPage({super.key});
}

class EnvelopeBudgetPage extends StatefulWidget {
  const EnvelopeBudgetPage({super.key});

  @override
  State<EnvelopeBudgetPage> createState() => _EnvelopeBudgetPageState();
}

class _EnvelopeBudgetPageState extends State<EnvelopeBudgetPage> {
  final _database = getIt<AppDatabase>();
  var _loading = true;
  var _envelopes = <EnvelopeBudgetRow>[];
  var _transactions = <TransactionWithItems>[];
  var _transfers = <EnvelopeTransferRow>[];
  var _categories = <Category>[];
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _historyService = OfflineToolHistoryService();
  var _searchQuery = '';
  var _showSearch = false;
  var _sort = _BudgetSort.nominalTerbesar;
  var _periodTypeFilter = 'weekly';
  var _weekStartDay = DateTime.monday;

  DateTime _startOfWeek(DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    final offset =
        (date.weekday - _weekStartDay + DateTime.daysPerWeek) %
        DateTime.daysPerWeek;
    return date.subtract(Duration(days: offset));
  }

  DateTime _periodStart(DateTime value, String periodType) {
    final date = DateTime(value.year, value.month, value.day);
    switch (periodType) {
      case 'weekly':
        return _startOfWeek(date);
      case 'biweekly':
        final weekStart = _startOfWeek(date);
        final anchor = _startOfWeek(DateTime(weekStart.year, 1, 1));
        final weeks = weekStart.difference(anchor).inDays ~/ 7;
        return weekStart.subtract(Duration(days: (weeks % 2) * 7));
      default:
        return DateTime(date.year, date.month, 1);
    }
  }

  DateTime _periodEnd(DateTime start, String periodType) {
    switch (periodType) {
      case 'weekly':
        return start.add(
          const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
        );
      case 'biweekly':
        return start.add(
          const Duration(days: 13, hours: 23, minutes: 59, seconds: 59),
        );
      default:
        return DateTime(
          start.year,
          start.month + 1,
          1,
        ).subtract(const Duration(seconds: 1));
    }
  }

  bool _isInActivePeriod(DateTime value) {
    final start = _periodStart(DateTime.now(), _periodTypeFilter);
    final end = _periodEnd(start, _periodTypeFilter);
    final date = value.toLocal();
    return !date.isBefore(start) && !date.isAfter(end);
  }

  String get _activePeriodKey {
    final start = _periodStart(DateTime.now(), _periodTypeFilter);
    return '${_periodTypeFilter}-${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<int> _readWeekStartDay() async {
    try {
      return await _historyService.readBudgetWeekStartDay();
    } catch (_) {
      return DateTime.monday;
    }
  }

  Future<void> _load() async {
    final storedWeekStartDay = await _readWeekStartDay();
    _weekStartDay = storedWeekStartDay;

    final categories =
        await (_database.select(_database.categories)
              ..where(
                (table) =>
                    table.householdId.equals(AppContext.householdId) &
                    table.type.equals('expense') &
                    table.isActive.equals(true),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.name)]))
            .get();
    final stored =
        await (_database.select(_database.envelopeBudgets)
              ..where(
                (table) =>
                    table.householdId.equals(AppContext.householdId) &
                    table.isActive.equals(true),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.name)]))
            .get();
    final rows = stored
        .map(EnvelopeBudgetRow.fromDrift)
        .where(
          (row) =>
              row.periodType == _periodTypeFilter &&
              _isInActivePeriod(row.startDate) &&
              _isInActivePeriod(row.endDate),
        )
        .toList();
    final transactions = await getIt<GetTransactions>()(AppContext.householdId);
    final transactionList = transactions.toList(growable: false);
    final activeCategoryIds = transactionList
        .where(
          (item) =>
              item.transaction.amount < 0 &&
              item.transaction.source != 'transfer' &&
              _isInActivePeriod(item.transaction.date),
        )
        .map((item) => item.transaction.categoryId)
        .whereType<String>()
        .toSet();
    final configuredIds = rows.expand((row) => row.categoryIds).toSet();
    if (!rows.any((row) => row.isOverall)) {
      rows.insert(
        0,
        EnvelopeBudgetRow.overallPlaceholder(
          _periodTypeFilter,
          weekStartDay: _weekStartDay,
        ),
      );
    }
    for (final category in categories) {
      if (activeCategoryIds.contains(category.id) &&
          !configuredIds.contains(category.id)) {
        rows.add(
          EnvelopeBudgetRow.placeholder(
            category,
            _periodTypeFilter,
            weekStartDay: _weekStartDay,
          ),
        );
      }
    }
    final transfers =
        await (_database.select(_database.envelopeTransfers)
              ..where(
                (table) => table.householdId.equals(AppContext.householdId),
              )
              ..orderBy([(table) => OrderingTerm.desc(table.createdAt)]))
            .get();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _envelopes = rows;
      _transactions = transactionList;
      _transfers = transfers
          .map(EnvelopeTransferRow.fromDrift)
          .where((row) => _isInActivePeriod(row.createdAt))
          .toList(growable: false);
      _loading = false;
    });
  }

  bool _isInPeriod(DateTime date, EnvelopeBudgetRow envelope) {
    final value = date.toLocal();
    final start = envelope.startDate.toLocal();
    final end = envelope.endDate.toLocal();
    return !value.isBefore(DateTime(start.year, start.month, start.day)) &&
        !value.isAfter(DateTime(end.year, end.month, end.day, 23, 59, 59));
  }

  bool _categoryMatches(String? categoryId, EnvelopeBudgetRow envelope) {
    if (categoryId == null) return false;
    if (envelope.categoryIds.contains(categoryId)) return true;
    for (final category in _categories) {
      var parentId = category.parentId;
      while (parentId != null) {
        if (category.id == categoryId &&
            envelope.categoryIds.contains(parentId)) {
          return true;
        }
        parentId = _categories
            .where((item) => item.id == parentId)
            .firstOrNull
            ?.parentId;
      }
    }
    return false;
  }

  int _spentFor(EnvelopeBudgetRow envelope) {
    return _transactions
        .where(
          (item) =>
              item.transaction.amount < 0 &&
              item.transaction.source != 'transfer' &&
              _isInPeriod(item.transaction.date, envelope) &&
              (envelope.isOverall ||
                  _categoryMatches(item.transaction.categoryId, envelope)),
        )
        .fold<int>(0, (sum, item) => sum + item.transaction.amount.abs());
  }

  int _transferredIn(EnvelopeBudgetRow envelope) {
    return _transfers
        .where((transfer) => transfer.toEnvelopeId == envelope.id)
        .fold<int>(0, (sum, transfer) => sum + transfer.amount);
  }

  int _transferredOut(EnvelopeBudgetRow envelope) {
    return _transfers
        .where((transfer) => transfer.fromEnvelopeId == envelope.id)
        .fold<int>(0, (sum, transfer) => sum + transfer.amount);
  }

  int _remainingFor(EnvelopeBudgetRow envelope) {
    if (!envelope.isOverall && envelope.allocated <= 0) return 0;
    return envelope.allocated +
        envelope.rollover +
        _transferredIn(envelope) -
        _transferredOut(envelope) -
        _spentFor(envelope);
  }

  double? _progressFor(EnvelopeBudgetRow envelope) {
    if (!envelope.isOverall && envelope.allocated <= 0) return null;
    final base =
        envelope.allocated + envelope.rollover + _transferredIn(envelope);
    if (base <= 0) return 0;
    return _spentFor(envelope) / base;
  }

  double _elapsedFor(EnvelopeBudgetRow envelope) {
    final now = DateTime.now();
    final start = envelope.startDate;
    final end = envelope.endDate.add(const Duration(days: 1));
    if (now.isBefore(start)) return 0;
    if (!now.isBefore(end)) return 1;
    return now.difference(start).inSeconds / end.difference(start).inSeconds;
  }

  String _statusFor(EnvelopeBudgetRow envelope) {
    if (!envelope.isOverall && envelope.allocated <= 0) return 'Tanpa target';
    final progress = _progressFor(envelope) ?? 0;
    if (progress >= 1) return 'Melewati batas';
    if (progress * 100 >= envelope.alertPercent) return 'Mendekati batas';
    if (progress > _elapsedFor(envelope) + .15) return 'Pemakaian cepat';
    return 'Aman';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Aman':
        return AppColors.positive;
      case 'Mendekati batas':
      case 'Pemakaian cepat':
        return AppColors.warning;
      case 'Melewati batas':
        return AppColors.negative;
      default:
        return AppColors.inkMuted;
    }
  }

  String _money(int value) {
    final digits = value.abs().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      final start = (end - 3).clamp(0, end);
      groups.insert(0, digits.substring(start, end));
    }
    return '${value < 0 ? '-' : ''}Rp${groups.join('.')}';
  }

  Future<void> _editEnvelope(EnvelopeBudgetRow envelope) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            EnvelopeEditPage(envelope: envelope, categories: _categories),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _transferFunds() async {
    final configured = _envelopes
        .where((item) => item.allocated > 0 && !item.isOverall)
        .toList();
    if (configured.length < 2) {
      await _showMessage(
        'Pos belum siap',
        'Atur minimal dua pos dulu sebelum memindahkan dana.',
      );
      return;
    }
    final result = await showDialog<EnvelopeTransferDraft>(
      context: context,
      builder: (_) => EnvelopeTransferDialog(
        envelopes: configured,
        remainingFor: _remainingFor,
      ),
    );
    if (!mounted || result == null) return;
    await _database
        .into(_database.envelopeTransfers)
        .insert(
          EnvelopeTransfersCompanion.insert(
            id: const Uuid().v4(),
            householdId: AppContext.householdId,
            month: Value(_activePeriodKey),
            fromEnvelopeId: result.fromEnvelopeId,
            toEnvelopeId: result.toEnvelopeId,
            amount: result.amount,
            note: Value(result.note),
            createdAt: DateTime.now(),
          ),
        );
    await _load();
  }

  Future<void> _showTransfers() async {
    final names = {for (final item in _envelopes) item.id: item.name};
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Riwayat atur ulang alokasi'),
        content: SizedBox(
          width: double.maxFinite,
          child: _transfers.isEmpty
              ? const Text('Belum ada alokasi yang diatur ulang bulan ini.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _transfers.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final transfer = _transfers[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${names[transfer.fromEnvelopeId] ?? 'Pos'} → ${names[transfer.toEnvelopeId] ?? 'Pos'}',
                      ),
                      subtitle: Text(
                        '${_money(transfer.amount)}${transfer.note == null ? '' : ' · ${transfer.note}'}',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  String _weekdayName(int weekday) => const [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ][weekday - 1];

  String _weekdayEndName(int weekday) =>
      _weekdayName(weekday == DateTime.monday ? DateTime.sunday : weekday - 1);

  String _monthName(int month) => const [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ][month - 1];

  String _activePeriodLabel() {
    final start = _periodStart(DateTime.now(), _periodTypeFilter);
    final end = _periodEnd(start, _periodTypeFilter);
    if (_periodTypeFilter == 'weekly') {
      return '${_weekdayName(start.weekday)} ${start.day}–${_weekdayName(end.weekday)} ${end.day} ${_monthName(end.month)} ${end.year}';
    }
    return '${start.day} ${_monthName(start.month)}–${end.day} ${_monthName(end.month)} ${end.year}';
  }

  Future<void> _showBudgetHelp() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cara kerja anggaran'),
        content: const Text(
          'Anggaran adalah batas rencana, bukan tempat mencatat pembayaran. '
          'Catat transaksi seperti biasa; pengeluaran akan dihitung otomatis dari tanggal kejadian dan kategori. '
          'Target total adalah batas utama, sedangkan target kategori bersifat opsional. '
          'Kalau belum diatur, aplikasi tidak menganggap targetnya nol.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Oke, paham'),
          ),
        ],
      ),
    );
  }

  Future<void> _showWeekStartPicker() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Hari mulai minggu'),
        children: [
          RadioGroup<int>(
            groupValue: _weekStartDay,
            onChanged: (value) {
              if (value != null) Navigator.of(dialogContext).pop(value);
            },
            child: Column(
              children: [
                for (
                  var weekday = DateTime.monday;
                  weekday <= DateTime.sunday;
                  weekday++
                )
                  RadioListTile<int>(
                    value: weekday,
                    title: Text(
                      '${_weekdayName(weekday)}–${_weekdayEndName(weekday)}',
                    ),
                    subtitle: Text(
                      weekday == DateTime.monday
                          ? 'Setelan bawaan: Senin sampai Minggu'
                          : 'Rentang 7 hari, mulai ${_weekdayName(weekday)}',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (!mounted || selected == null || selected == _weekStartDay) return;
    await _historyService.saveBudgetWeekStartDay(selected);
    if (!mounted) return;
    setState(() {
      _weekStartDay = selected;
      _loading = true;
    });
    await _load();
  }

  Future<void> _handleMenuAction(_BudgetMenuAction action) async {
    switch (action) {
      case _BudgetMenuAction.transferFunds:
        await _transferFunds();
      case _BudgetMenuAction.weekStart:
        await _showWeekStartPicker();
    }
  }

  void _openSearch() {
    setState(() => _showSearch = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _showSearch = false;
    });
  }

  Future<void> _showMessage(String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  List<EnvelopeBudgetRow> _sortEnvelopes(List<EnvelopeBudgetRow> envelopes) {
    final sorted = List<EnvelopeBudgetRow>.of(envelopes);
    sorted.sort((a, b) {
      final comparison = switch (_sort) {
        _BudgetSort.nominalTerbesar => b.allocated.compareTo(a.allocated),
        _BudgetSort.nominalTerkecil => a.allocated.compareTo(b.allocated),
        _BudgetSort.tanggalTerbaru => b.startDate.compareTo(a.startDate),
        _BudgetSort.tanggalTerlama => a.startDate.compareTo(b.startDate),
      };
      return comparison == 0 ? a.name.compareTo(b.name) : comparison;
    });
    return sorted;
  }

  List<EnvelopeBudgetRow> _filterEnvelopes(List<EnvelopeBudgetRow> envelopes) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return envelopes;
    final categoryNames = {
      for (final category in _categories)
        category.id: category.name.toLowerCase(),
    };
    return envelopes
        .where(
          (envelope) =>
              envelope.name.toLowerCase().contains(query) ||
              envelope.categoryIds.any(
                (id) => categoryNames[id]?.contains(query) ?? false,
              ),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filteredEnvelopes = _filterEnvelopes(_envelopes);
    final overall = _envelopes
        .where((envelope) => envelope.isOverall)
        .firstOrNull;
    final totalAllocated = overall?.allocated ?? 0;
    final totalSpent = overall == null ? 0 : _spentFor(overall);
    final totalRemaining = overall == null ? 0 : _remainingFor(overall);
    final categoryEnvelopes = filteredEnvelopes
        .where((envelope) => !envelope.isOverall)
        .toList(growable: false);
    final unconfigured = categoryEnvelopes
        .where((envelope) => envelope.allocated <= 0)
        .toList(growable: false);
    final configured = categoryEnvelopes
        .where((envelope) => envelope.allocated > 0)
        .toList(growable: false);
    final attention = configured
        .where((envelope) => _statusFor(envelope) != 'Aman')
        .toList(growable: false);

    final hasTotalTarget = totalAllocated > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anggaran berbasis pos'),
        actions: [
          IconButton(
            tooltip: _showSearch ? 'Tutup pencarian' : 'Cari pos anggaran',
            onPressed: _showSearch ? _closeSearch : _openSearch,
            icon: Icon(_showSearch ? Icons.close : Icons.search),
          ),
          PopupMenuButton<_BudgetMenuAction>(
            tooltip: 'Aksi anggaran lainnya',
            onSelected: _handleMenuAction,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _BudgetMenuAction.transferFunds,
                child: Text('Atur ulang alokasi antarpos'),
              ),
              if (_periodTypeFilter == 'weekly')
                PopupMenuItem(
                  value: _BudgetMenuAction.weekStart,
                  child: Text('Hari mulai: ${_weekdayName(_weekStartDay)}'),
                ),
            ],
          ),
          IconButton(
            tooltip: 'Riwayat atur ulang alokasi',
            onPressed: _loading ? null : _showTransfers,
            icon: const Icon(Icons.history_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 4,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Batas pengeluaran keluarga',
                                style: AppTextStyles.labelCaps,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Cara kerja anggaran',
                              onPressed: _showBudgetHelp,
                              icon: const Icon(Icons.info_outline),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'weekly',
                              label: Text('Mingguan'),
                              icon: Icon(Icons.view_week_outlined),
                            ),
                            ButtonSegment(
                              value: 'monthly',
                              label: Text('Bulanan'),
                              icon: Icon(Icons.calendar_month_outlined),
                            ),
                          ],
                          selected: {_periodTypeFilter},
                          onSelectionChanged: (selection) {
                            final value = selection.first;
                            if (value == _periodTypeFilter) return;
                            setState(() {
                              _periodTypeFilter = value;
                              _loading = true;
                            });
                            _load();
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.date_range_outlined, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _activePeriodLabel(),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            if (_periodTypeFilter == 'weekly')
                              TextButton(
                                onPressed: _showWeekStartPicker,
                                child: Text(
                                  'Mulai ${_weekdayName(_weekStartDay)}',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        AppCard(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: _SummaryValue(
                                  label: 'Target total',
                                  value: hasTotalTarget
                                      ? _money(totalAllocated)
                                      : 'Belum diatur',
                                ),
                              ),
                              Expanded(
                                child: _SummaryValue(
                                  label: 'Sudah keluar',
                                  value: _money(totalSpent),
                                  color: AppColors.negative,
                                ),
                              ),
                              Expanded(
                                child: _SummaryValue(
                                  label: hasTotalTarget
                                      ? 'Sisa periode'
                                      : 'Status',
                                  value: hasTotalTarget
                                      ? _money(totalRemaining)
                                      : 'Atur target',
                                  color: hasTotalTarget && totalRemaining < 0
                                      ? AppColors.negative
                                      : AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_showSearch)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                        decoration: InputDecoration(
                          labelText: 'Cari pos anggaran',
                          hintText: 'Misalnya listrik, makan, atau cicilan',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            tooltip: 'Hapus pencarian',
                            onPressed: _closeSearch,
                            icon: const Icon(Icons.clear),
                          ),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  TabBar(
                    isScrollable: true,
                    tabs: [
                      Tab(text: 'Semua (${categoryEnvelopes.length})'),
                      Tab(text: 'Belum diatur (${unconfigured.length})'),
                      Tab(text: 'Aktif (${configured.length})'),
                      Tab(text: 'Perlu perhatian (${attention.length})'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _envelopeList(_sortEnvelopes(categoryEnvelopes)),
                        _envelopeList(_sortEnvelopes(unconfigured)),
                        _envelopeList(_sortEnvelopes(configured)),
                        _envelopeList(_sortEnvelopes(attention)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _envelopeList(List<EnvelopeBudgetRow> envelopes) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
      children: [
        if (envelopes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: AppEmptyState(
              icon: Icons.inbox_outlined,
              title: _categories.isEmpty
                  ? 'Kategori pengeluaran belum ada'
                  : 'Belum ada pos di sini',
              message: _categories.isEmpty
                  ? 'Buat kategori pengeluaran di Data Utama dulu. Setelah itu pos anggaran bisa diatur dari sini.'
                  : 'Coba buka tab lain atau atur target dari kategori yang tersedia.',
              action: _categories.isEmpty
                  ? FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MasterDataPage(),
                        ),
                      ),
                      icon: const Icon(Icons.tune_outlined),
                      label: const Text('Buka Data Utama'),
                    )
                  : null,
            ),
          )
        else
          ...envelopes.map(
            (envelope) => Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _EnvelopeCard(
                envelope: envelope,
                spent: _spentFor(envelope),
                remaining: _remainingFor(envelope),
                status: _statusFor(envelope),
                statusColor: _statusColor(_statusFor(envelope)),
                transferredIn: _transferredIn(envelope),
                transferredOut: _transferredOut(envelope),
                onTap: () => _editEnvelope(envelope),
              ),
            ),
          ),
      ],
    );
  }
}

class EnvelopeEditPage extends StatefulWidget {
  const EnvelopeEditPage({
    required this.envelope,
    required this.categories,
    super.key,
  });

  final EnvelopeBudgetRow envelope;
  final List<Category> categories;

  @override
  State<EnvelopeEditPage> createState() => _EnvelopeEditPageState();
}

class _EnvelopeEditPageState extends State<EnvelopeEditPage> {
  late final TextEditingController _amountController;
  late final TextEditingController _rolloverController;
  final _formKey = GlobalKey<FormState>();
  var _saving = false;
  late DateTime _startDate;
  late DateTime _endDate;
  late String _periodType;
  var _alertPercent = 80;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.envelope.allocated == 0
          ? ''
          : formatRupiahInput(widget.envelope.allocated.toString()),
    );
    _rolloverController = TextEditingController(
      text: widget.envelope.rollover == 0
          ? ''
          : formatRupiahInput(widget.envelope.rollover.toString()),
    );
    _startDate = widget.envelope.startDate;
    _endDate = widget.envelope.endDate;
    _periodType = widget.envelope.periodType;
    _alertPercent = widget.envelope.alertPercent.clamp(50, 100);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _rolloverController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = parseRupiah(_amountController.text);
    if (amount <= 0) {
      if (widget.envelope.isOverall) {
        await _showBudgetMessage('Target total harus diisi lebih dari nol.');
      }
      return;
    }
    setState(() => _saving = true);
    final database = getIt<AppDatabase>();
    final now = DateTime.now();
    final month =
        '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}';
    final values = EnvelopeBudgetsCompanion(
      allocated: Value(amount),
      rollover: Value(parseRupiah(_rolloverController.text)),
      periodType: Value(_periodType),
      startDate: Value(_startDate),
      endDate: Value(_endDate),
      alertPercent: Value(_alertPercent),
      updatedAt: Value(now),
    );
    if (widget.envelope.isPlaceholder) {
      await database
          .into(database.envelopeBudgets)
          .insert(
            EnvelopeBudgetsCompanion.insert(
              id: widget.envelope.isOverall
                  ? 'overall-${_periodType}-${_startDate.year}-${_startDate.month}-${_startDate.day}'
                  : 'envelope-${widget.envelope.categoryIds.first}-$month',
              householdId: AppContext.householdId,
              month: Value(month),
              name: widget.envelope.name,
              categoryIdsJson: Value(jsonEncode(widget.envelope.categoryIds)),
              allocated: Value(amount),
              rollover: Value(parseRupiah(_rolloverController.text)),
              periodType: Value(_periodType),
              startDate: _startDate,
              endDate: _endDate,
              alertPercent: Value(_alertPercent),
              createdAt: now,
              updatedAt: Value(now),
            ),
          );
    } else {
      await (database.update(
        database.envelopeBudgets,
      )..where((table) => table.id.equals(widget.envelope.id))).write(values);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _showBudgetMessage(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Target belum lengkap'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Oke'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _startDate,
      helpText: 'Pilih awal periode',
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked;
      _endDate = _periodEnd(picked, _periodType);
    });
  }

  DateTime _periodEnd(DateTime start, String type) {
    switch (type) {
      case 'weekly':
        return start.add(const Duration(days: 6));
      case 'biweekly':
        return start.add(const Duration(days: 13));
      case 'bimonthly':
        return DateTime(
          start.year,
          start.month + 2,
          start.day,
        ).subtract(const Duration(days: 1));
      case 'fourmonthly':
        return DateTime(
          start.year,
          start.month + 4,
          start.day,
        ).subtract(const Duration(days: 1));
      case 'fivemonthly':
        return DateTime(
          start.year,
          start.month + 5,
          start.day,
        ).subtract(const Duration(days: 1));
      default:
        return DateTime(
          start.year,
          start.month + 1,
          start.day,
        ).subtract(const Duration(days: 1));
    }
  }

  String _periodName(String value) {
    switch (value) {
      case 'weekly':
        return '1 minggu';
      case 'biweekly':
        return '2 minggu';
      case 'bimonthly':
        return '2 bulan';
      case 'fourmonthly':
        return '4 bulan';
      case 'fivemonthly':
        return '5 bulan';
      default:
        return '1 bulan';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Atur pos ${widget.envelope.name}')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            AppHelpBanner(
              title: 'Pos ${widget.envelope.name}',
              message: widget.envelope.categoryIds.isEmpty
                  ? 'Pos ini dipakai sebagai tempat alokasi. Pengeluaran otomatis tidak dikurangi dari pos ini karena belum ada kategori transaksi khusus.'
                  : 'Pengeluaran dari kategori yang terkait akan mengurangi sisa pos ini secara otomatis.',
              icon: Icons.mail_outline,
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: const [RupiahInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Target nominal periode ini',
                prefixText: 'Rp ',
                helperText: 'Transaksi dengan kategori terkait akan mengurangi target ini.',
              ),
              validator: (value) =>
                  parseRupiah(value ?? '') < 0 ? 'Nominal belum valid.' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _rolloverController,
              keyboardType: TextInputType.number,
              inputFormatters: const [RupiahInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Sisa bulan lalu (opsional)',
                prefixText: 'Rp ',
              ),
              validator: (value) =>
                  parseRupiah(value ?? '') < 0 ? 'Nominal belum valid.' : null,
            ),
            const SizedBox(height: 16),
            SearchableDropdown<String>(
              items: const [
                'weekly',
                'biweekly',
                'monthly',
                'bimonthly',
                'fourmonthly',
                'fivemonthly',
              ],
              selectedItem: _periodType,
              itemLabel: (value) => switch (value) {
                'weekly' => '1 minggu',
                'biweekly' => '2 minggu',
                'monthly' => '1 bulan',
                'bimonthly' => '2 bulan',
                'fourmonthly' => '4 bulan',
                'fivemonthly' => '5 bulan',
                _ => value,
              },
              labelText: 'Periode target',
              helperText:
                  'Pemakaian akan mulai dari nol saat periode baru dimulai.',
              searchHintText: 'Cari periode target',
              cacheKey: 'anggaran.periode_target',
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _periodType = value;
                  _endDate = _periodEnd(_startDate, value);
                });
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickStartDate,
              icon: const Icon(Icons.event_outlined),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Mulai: ${formatTanggalLengkap(_startDate, includeSeconds: false)}',
                ),
              ),
            ),
            const SizedBox(height: 6),
            HijriDateLabel(date: _startDate),
            Text(
              'Selesai: ${formatTanggalLengkap(_endDate, includeSeconds: false)} (${_periodName(_periodType)})',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            HijriDateLabel(date: _endDate),
            const SizedBox(height: 12),
            SearchableDropdown<int>(
              items: const [70, 80, 90],
              selectedItem: _alertPercent,
              itemLabel: (value) => '$value% terpakai',
              labelText: 'Peringatan mulai dari',
              helperText: 'Contoh: 80% berarti peringatan muncul saat pemakaian mencapai 80%.',
              searchHintText: 'Cari ambang peringatan',
              cacheKey: 'anggaran.ambang_peringatan',
              onChanged: (value) => setState(() => _alertPercent = value ?? 80),
            ),
            const SizedBox(height: 16),
            Text(
              widget.envelope.categoryIds.isEmpty
                  ? 'Kategori terkait: belum ada'
                  : 'Kategori terkait: ${_categoryNames(widget.envelope.categoryIds)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Menyimpan...' : 'Simpan target'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryNames(List<String> ids) {
    final names = {
      for (final category in widget.categories) category.id: category.name,
    };
    return ids.map((id) => names[id] ?? 'Kategori lain').join(', ');
  }
}

class EnvelopeTransferDraft {
  const EnvelopeTransferDraft({
    required this.fromEnvelopeId,
    required this.toEnvelopeId,
    required this.amount,
    required this.note,
  });

  final String fromEnvelopeId;
  final String toEnvelopeId;
  final int amount;
  final String? note;
}

class EnvelopeTransferDialog extends StatefulWidget {
  const EnvelopeTransferDialog({
    required this.envelopes,
    required this.remainingFor,
    super.key,
  });

  final List<EnvelopeBudgetRow> envelopes;
  final int Function(EnvelopeBudgetRow) remainingFor;

  @override
  State<EnvelopeTransferDialog> createState() => _EnvelopeTransferDialogState();
}

class _EnvelopeTransferDialogState extends State<EnvelopeTransferDialog> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String? _fromId;
  String? _toId;

  @override
  void initState() {
    super.initState();
    _fromId = widget.envelopes.first.id;
    _toId = widget.envelopes.length > 1 ? widget.envelopes[1].id : null;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = parseRupiah(_amountController.text);
    final from = widget.envelopes.firstWhere((item) => item.id == _fromId);
    if (_fromId == _toId) return;
    if (amount <= 0 || amount > widget.remainingFor(from)) return;
    Navigator.of(context).pop(
      EnvelopeTransferDraft(
        fromEnvelopeId: _fromId!,
        toEnvelopeId: _toId!,
        amount: amount,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Atur ulang alokasi antarpos'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SearchableDropdown(
              items: widget.envelopes,
              selectedItem: widget.envelopes
                  .where((envelope) => envelope.id == _fromId)
                  .firstOrNull,
              itemLabel: (envelope) => envelope.name,
              itemId: (envelope) => envelope.id,
              labelText: 'Dari pos anggaran',
              searchHintText: 'Cari pos anggaran asal',
              cacheKey: 'anggaran.pos_asal',
              onChanged: (envelope) => setState(() => _fromId = envelope?.id),
            ),
            const SizedBox(height: 12),
            SearchableDropdown(
              items: widget.envelopes,
              selectedItem: widget.envelopes
                  .where((envelope) => envelope.id == _toId)
                  .firstOrNull,
              itemLabel: (envelope) => envelope.name,
              itemId: (envelope) => envelope.id,
              labelText: 'Ke pos anggaran',
              searchHintText: 'Cari pos anggaran tujuan',
              cacheKey: 'anggaran.pos_tujuan',
              onChanged: (envelope) => setState(() => _toId = envelope?.id),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: const [RupiahInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Nominal alokasi yang diatur ulang',
                prefixText: 'Rp ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Nominal tidak boleh lebih besar dari sisa pos asal. Fitur ini hanya mengatur ulang batas antarpos anggaran; uang di Tunai, Rekening, dan Dompet digital tidak berpindah.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Atur ulang alokasi'),
        ),
      ],
    );
  }
}

class EnvelopeBudgetRow {
  const EnvelopeBudgetRow({
    required this.id,
    required this.name,
    required this.categoryIds,
    required this.allocated,
    required this.rollover,
    required this.periodType,
    required this.startDate,
    required this.endDate,
    required this.alertPercent,
    this.isPlaceholder = false,
    this.isOverall = false,
  });

  factory EnvelopeBudgetRow.fromDrift(EnvelopeBudget row) {
    final decoded = jsonDecode(row.categoryIdsJson);
    return EnvelopeBudgetRow(
      id: row.id,
      name: row.name,
      categoryIds: decoded is List ? decoded.cast<String>() : const [],
      allocated: row.allocated,
      rollover: row.rollover,
      periodType: row.periodType,
      startDate: row.startDate,
      endDate: row.endDate,
      alertPercent: row.alertPercent,
      isOverall: row.id.startsWith('overall-'),
    );
  }

  factory EnvelopeBudgetRow.placeholder(
    Category category,
    String periodType, {
    int weekStartDay = DateTime.monday,
  }) {
    final now = DateTime.now();
    final start = periodType == 'weekly'
        ? DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: (now.weekday - weekStartDay + 7) % 7))
        : DateTime(now.year, now.month, 1);
    final end = periodType == 'weekly'
        ? start.add(
            const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
          )
        : DateTime(
            start.year,
            start.month + 1,
            1,
          ).subtract(const Duration(seconds: 1));
    return EnvelopeBudgetRow(
      id: 'placeholder-${category.id}-$periodType',
      name: category.name,
      categoryIds: [category.id],
      allocated: 0,
      rollover: 0,
      periodType: periodType,
      startDate: start,
      endDate: end,
      alertPercent: 80,
      isPlaceholder: true,
    );
  }

  factory EnvelopeBudgetRow.overallPlaceholder(
    String periodType, {
    int weekStartDay = DateTime.monday,
  }) {
    final now = DateTime.now();
    final start = periodType == 'weekly'
        ? DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: (now.weekday - weekStartDay + 7) % 7))
        : DateTime(now.year, now.month, 1);
    final end = periodType == 'weekly'
        ? start.add(
            const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
          )
        : DateTime(
            start.year,
            start.month + 1,
            1,
          ).subtract(const Duration(seconds: 1));
    return EnvelopeBudgetRow(
      id: 'overall-$periodType-${start.year}-${start.month}-${start.day}',
      name:
          'Total pengeluaran ${periodType == 'weekly' ? 'minggu ini' : 'bulan ini'}',
      categoryIds: const [],
      allocated: 0,
      rollover: 0,
      periodType: periodType,
      startDate: start,
      endDate: end,
      alertPercent: 80,
      isPlaceholder: true,
      isOverall: true,
    );
  }

  final String id;
  final String name;
  final List<String> categoryIds;
  final int allocated;
  final int rollover;
  final String periodType;
  final DateTime startDate;
  final DateTime endDate;
  final int alertPercent;
  final bool isPlaceholder;
  final bool isOverall;

  String get periodLabel =>
      '${startDate.day}/${startDate.month}/${startDate.year} sampai ${endDate.day}/${endDate.month}/${endDate.year}';
}

class EnvelopeTransferRow {
  const EnvelopeTransferRow({
    required this.id,
    required this.fromEnvelopeId,
    required this.toEnvelopeId,
    required this.amount,
    required this.note,
    required this.createdAt,
  });

  factory EnvelopeTransferRow.fromDrift(EnvelopeTransfer row) {
    return EnvelopeTransferRow(
      id: row.id,
      fromEnvelopeId: row.fromEnvelopeId,
      toEnvelopeId: row.toEnvelopeId,
      amount: row.amount,
      note: row.note,
      createdAt: row.createdAt,
    );
  }

  final String id;
  final String fromEnvelopeId;
  final String toEnvelopeId;
  final int amount;
  final String? note;
  final DateTime createdAt;
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _EnvelopeCard extends StatelessWidget {
  const _EnvelopeCard({
    required this.envelope,
    required this.spent,
    required this.remaining,
    required this.status,
    required this.statusColor,
    required this.transferredIn,
    required this.transferredOut,
    required this.onTap,
  });

  final EnvelopeBudgetRow envelope;
  final int spent;
  final int remaining;
  final String status;
  final Color statusColor;
  final int transferredIn;
  final int transferredOut;
  final VoidCallback onTap;

  String _money(int value) {
    final digits = value.abs().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      final start = (end - 3).clamp(0, end);
      groups.insert(0, digits.substring(start, end));
    }
    return '${value < 0 ? '-' : ''}Rp${groups.join('.')}';
  }

  @override
  Widget build(BuildContext context) {
    final base = envelope.allocated + envelope.rollover + transferredIn;
    final progress = !envelope.isOverall && envelope.allocated <= 0
        ? null
        : base <= 0
        ? 0.0
        : spent / base;
    final progressValue = (progress ?? 0).clamp(0.0, 1.0);
    final statusBackground = switch (status) {
      'Aman' => AppColors.positiveSoft,
      'Melewati batas' => AppColors.negativeSoft,
      'Mendekati batas' || 'Pemakaian cepat' => AppColors.warningSoft,
      _ => AppColors.surfaceContainer,
    };
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  envelope.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              AppStatusChip(
                label: status,
                color: statusColor,
                backgroundColor: statusBackground,
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.edit_outlined,
                size: 20,
                color: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            progress == null
                ? '${_money(spent)} terpakai • target kategori belum diisi'
                : '${_money(spent)} terpakai dari ${_money(base)}',
          ),
          if (progress != null) ...[
            const SizedBox(height: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${envelope.periodLabel} • ${(progressValue * 100).toStringAsFixed(1)}% terpakai',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                HijriDateRangeLabel(
                  start: envelope.startDate,
                  end: envelope.endDate,
                ),
              ],
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progressValue,
              minHeight: 8,
              borderRadius: BorderRadius.circular(99),
              color: statusColor,
            ),
          ],
          if (progress != null && status == 'Pemakaian cepat') ...[
            const SizedBox(height: 6),
            Text(
              'Pemakaian lebih cepat dari waktu berjalan. Coba rem pengeluaran berikutnya.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  progress == null
                      ? 'Belum ada target kategori'
                      : 'Sisa ${_money(remaining)}',
                  style: TextStyle(
                    color: progress != null && remaining < 0
                        ? AppColors.negative
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (transferredIn > 0 || transferredOut > 0)
                Text(
                  'Atur ulang +${_money(transferredIn)} / -${_money(transferredOut)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
