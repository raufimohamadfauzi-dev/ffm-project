import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../advisor/presentation/widgets/context_suggestion_card.dart';
import '../../../transaction/domain/entities/transaction_entity.dart';
import '../../../transaction/domain/usecases/transaction_crud_usecases.dart';
import '../../../../shared/widgets/date_time_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';

enum _BudgetSort {
  nominalTerbesar,
  nominalTerkecil,
  tanggalTerbaru,
  tanggalTerlama,
}

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
  var _searchQuery = '';
  var _sort = _BudgetSort.nominalTerbesar;

  String get _monthKey {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

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
                    table.month.equals(_monthKey),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.name)]))
            .get();
    final rows = stored.map(EnvelopeBudgetRow.fromDrift).toList();
    final configuredIds = rows.expand((row) => row.categoryIds).toSet();
    for (final category in categories) {
      final coveredByConfiguredParent = _hasConfiguredAncestor(
        category,
        categories,
        configuredIds,
      );
      final coveredByConfiguredChild = categories.any(
        (candidate) =>
            candidate.parentId == category.id &&
            configuredIds.contains(candidate.id),
      );
      if (!configuredIds.contains(category.id) &&
          !coveredByConfiguredParent &&
          !coveredByConfiguredChild) {
        rows.add(EnvelopeBudgetRow.placeholder(category));
      }
    }
    final transactions = await getIt<GetTransactions>()(AppContext.householdId);
    final transfers =
        await (_database.select(_database.envelopeTransfers)
              ..where(
                (table) =>
                    table.householdId.equals(AppContext.householdId) &
                    table.month.equals(_monthKey),
              )
              ..orderBy([(table) => OrderingTerm.desc(table.createdAt)]))
            .get();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _envelopes = rows;
      _transactions = transactions.toList(growable: false);
      _transfers = transfers.map(EnvelopeTransferRow.fromDrift).toList();
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

  bool _hasConfiguredAncestor(
    Category category,
    List<Category> categories,
    Set<String> configuredIds,
  ) {
    var parentId = category.parentId;
    while (parentId != null) {
      if (configuredIds.contains(parentId)) return true;
      parentId = categories
          .where((item) => item.id == parentId)
          .firstOrNull
          ?.parentId;
    }
    return false;
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
              _categoryMatches(item.transaction.categoryId, envelope),
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
    return envelope.allocated +
        envelope.rollover +
        _transferredIn(envelope) -
        _transferredOut(envelope) -
        _spentFor(envelope);
  }

  double _progressFor(EnvelopeBudgetRow envelope) {
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
    if (envelope.allocated <= 0) return 'Belum diatur';
    final progress = _progressFor(envelope);
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
    final configured = _envelopes.where((item) => item.allocated > 0).toList();
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
            month: Value(_monthKey),
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
        title: const Text('Riwayat pindah dana'),
        content: SizedBox(
          width: double.maxFinite,
          child: _transfers.isEmpty
              ? const Text('Belum ada dana yang dipindahkan bulan ini.')
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
    final totalAllocated = _envelopes.fold<int>(
      0,
      (sum, envelope) => sum + envelope.allocated,
    );
    final totalRemaining = _envelopes.fold<int>(
      0,
      (sum, envelope) => sum + _remainingFor(envelope),
    );
    final unconfigured = filteredEnvelopes
        .where((envelope) => envelope.allocated <= 0)
        .toList(growable: false);
    final configured = filteredEnvelopes
        .where((envelope) => envelope.allocated > 0)
        .toList(growable: false);
    final attention = configured
        .where((envelope) => _statusFor(envelope) != 'Aman')
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anggaran berbasis pos'),
        actions: [
          PopupMenuButton<_BudgetSort>(
            tooltip: 'Urutkan pos anggaran',
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            icon: const Icon(Icons.sort_rounded),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _BudgetSort.nominalTerbesar,
                child: Text('Nominal terbesar'),
              ),
              PopupMenuItem(
                value: _BudgetSort.nominalTerkecil,
                child: Text('Nominal terkecil'),
              ),
              PopupMenuItem(
                value: _BudgetSort.tanggalTerbaru,
                child: Text('Tanggal terbaru'),
              ),
              PopupMenuItem(
                value: _BudgetSort.tanggalTerlama,
                child: Text('Tanggal terlama'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Riwayat pindah dana',
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
                        const AppHelpBanner(
                          title:
                              'Anggaran itu batas rencana, bukan tempat bayar',
                          message: 'Atur batas uang di sini. Pembayaran yang benar-benar terjadi tetap dicatat di Transaksi, lalu dihitung otomatis berdasarkan kategori yang kamu pilih.',
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                        const SizedBox(height: 12),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Ringkasan periode berjalan',
                                style: AppTextStyles.labelCaps,
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _SummaryValue(
                                      label: 'Dialokasikan',
                                      value: _money(totalAllocated),
                                    ),
                                  ),
                                  Expanded(
                                    child: _SummaryValue(
                                      label: 'Sisa semua pos',
                                      value: _money(totalRemaining),
                                      color: totalRemaining < 0
                                          ? AppColors.negative
                                          : AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                      decoration: InputDecoration(
                        labelText: 'Cari pos anggaran',
                        hintText: 'Misalnya listrik, makan, atau cicilan',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Hapus pencarian',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
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
                      Tab(text: 'Semua (${filteredEnvelopes.length})'),
                      Tab(text: 'Belum diatur (${unconfigured.length})'),
                      Tab(text: 'Aktif (${configured.length})'),
                      Tab(text: 'Perlu perhatian (${attention.length})'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _envelopeList(
                          _sortEnvelopes(filteredEnvelopes),
                          suggestionTitle: totalAllocated == 0
                              ? 'Mulai dari target pertama'
                              : 'Pantau laju pengeluaran',
                          suggestionMessage: totalAllocated == 0
                              ? 'Pilih kategori yang mau kamu kontrol, lalu isi target nominal dan periodenya. Kategori lain tetap boleh dibiarkan Belum diatur.'
                              : 'Kalau pemakaian lebih cepat dari waktu berjalan, kurangi pengeluaran pada minggu berikutnya supaya target periode tidak jebol.',
                        ),
                        _envelopeList(
                          _sortEnvelopes(unconfigured),
                          suggestionTitle: 'Atur pos yang mau kamu pantau',
                          suggestionMessage: 'Tekan kartu kategori untuk mengisi target nominal dan periode. Kalau belum perlu dipantau, biarkan saja Belum diatur.',
                        ),
                        _envelopeList(_sortEnvelopes(configured)),
                        _envelopeList(
                          _sortEnvelopes(attention),
                          suggestionTitle: 'Cek pos yang perlu perhatian',
                          suggestionMessage: 'Lihat pos yang mendekati batas, pemakaiannya terlalu cepat, atau sudah melewati target.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _transferFunds,
        icon: const Icon(Icons.swap_horiz),
        label: const Text('Pindah dana'),
      ),
    );
  }

  Widget _envelopeList(
    List<EnvelopeBudgetRow> envelopes, {
    String? suggestionTitle,
    String? suggestionMessage,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
      children: [
        if (suggestionTitle != null && suggestionMessage != null)
          ContextSuggestionCard(
            title: suggestionTitle,
            message: suggestionMessage,
          ),
        if (envelopes.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: AppEmptyState(
              icon: Icons.inbox_outlined,
              title: 'Belum ada pos di sini',
              message: 'Coba buka tab lain atau atur target dari kategori yang tersedia.',
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
    if (amount <= 0) return;
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
              id: 'envelope-${widget.envelope.categoryIds.first}-$month',
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
      title: const Text('Pindah dana antarpos'),
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
              labelText: 'Dari pos',
              searchHintText: 'Cari pos asal',
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
              labelText: 'Ke pos',
              searchHintText: 'Cari pos tujuan',
              cacheKey: 'anggaran.pos_tujuan',
              onChanged: (envelope) => setState(() => _toId = envelope?.id),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: const [RupiahInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Nominal yang dipindah',
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
              'Nominal tidak boleh lebih besar dari sisa pos asal. Pemindahan ini hanya mengatur pembagian anggaran, bukan membuat saldo baru.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Pindahkan')),
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
    );
  }

  factory EnvelopeBudgetRow.placeholder(Category category) {
    final now = DateTime.now();
    return EnvelopeBudgetRow(
      id: 'placeholder-${category.id}',
      name: category.name,
      categoryIds: [category.id],
      allocated: 0,
      rollover: 0,
      periodType: 'monthly',
      startDate: DateTime(now.year, now.month, 1),
      endDate: DateTime(now.year, now.month + 1, 0),
      alertPercent: 80,
      isPlaceholder: true,
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
  });

  factory EnvelopeTransferRow.fromDrift(EnvelopeTransfer row) {
    return EnvelopeTransferRow(
      id: row.id,
      fromEnvelopeId: row.fromEnvelopeId,
      toEnvelopeId: row.toEnvelopeId,
      amount: row.amount,
      note: row.note,
    );
  }

  final String id;
  final String fromEnvelopeId;
  final String toEnvelopeId;
  final int amount;
  final String? note;
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
    final progress = base <= 0 ? 0.0 : spent / base;
    final progressValue = progress.clamp(0.0, 1.0);
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
            envelope.allocated == 0
                ? 'Belum ada target. Tekan untuk atur nominal dan periode.'
                : '${_money(spent)} terpakai dari ${_money(base)}',
          ),
          if (envelope.allocated > 0) ...[
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
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progressValue,
            minHeight: 8,
            borderRadius: BorderRadius.circular(99),
            color: statusColor,
          ),
          if (envelope.allocated > 0 && status == 'Pemakaian cepat') ...[
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
                  'Sisa ${_money(remaining)}',
                  style: TextStyle(
                    color: remaining < 0
                        ? AppColors.negative
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (transferredIn > 0 || transferredOut > 0)
                Text(
                  'Pindah +${_money(transferredIn)} / -${_money(transferredOut)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
