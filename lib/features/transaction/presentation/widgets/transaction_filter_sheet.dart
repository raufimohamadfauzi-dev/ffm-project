import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';

class TransactionFilter {
  const TransactionFilter({
    required this.typeFilter,
    required this.currentMonthOnly,
    this.accountId,
    this.categoryId,
    this.merchantId,
    this.owner,
    this.startDate,
    this.endDate,
  });

  final String typeFilter;
  final bool currentMonthOnly;
  final String? accountId;
  final String? categoryId;
  final String? merchantId;
  final String? owner;
  final DateTime? startDate;
  final DateTime? endDate;
}

class TransactionFilterSheet extends StatefulWidget {
  const TransactionFilterSheet({
    super.key,
    required this.typeFilter,
    required this.currentMonthOnly,
    required this.accounts,
    required this.categories,
    this.merchants = const [],
    this.owners = const [],
    this.accountId,
    this.categoryId,
    this.merchantId,
    this.owner,
    this.startDate,
    this.endDate,
  });

  final String typeFilter;
  final bool currentMonthOnly;
  final List<Account> accounts;
  final List<Category> categories;
  final List<Merchant> merchants;
  final List<String> owners;
  final String? accountId;
  final String? categoryId;
  final String? merchantId;
  final String? owner;
  final DateTime? startDate;
  final DateTime? endDate;

  @override
  State<TransactionFilterSheet> createState() => _TransactionFilterSheetState();
}

class _TransactionFilterSheetState extends State<TransactionFilterSheet> {
  late String _typeFilter;
  late bool _currentMonthOnly;
  String? _accountId;
  String? _categoryId;
  String? _merchantId;
  String? _owner;

  @override
  void initState() {
    super.initState();
    _typeFilter = widget.typeFilter;
    _currentMonthOnly = widget.currentMonthOnly;
    _accountId = widget.accountId;
    _categoryId = widget.categoryId;
    _merchantId = widget.merchantId;
    _owner = widget.owner;
    _startDate = widget.startDate;
    _endDate = widget.endDate;
  }

  DateTime? _startDate;
  DateTime? _endDate;

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (!mounted || range == null) return;
    setState(() {
      _startDate = range.start;
      _endDate = range.end;
      _currentMonthOnly = false;
    });
  }

  String _dateRangeLabel(BuildContext context) {
    if (_startDate == null || _endDate == null) return 'Pilih rentang tanggal';
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatShortDate(_startDate!)} - ${localizations.formatShortDate(_endDate!)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saring transaksi',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Text('Jenis', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Semua', label: Text('Semua')),
                ButtonSegment(value: 'Pemasukan', label: Text('Pemasukan')),
                ButtonSegment(value: 'Pengeluaran', label: Text('Pengeluaran')),
                ButtonSegment(value: 'Transfer', label: Text('Transfer')),
              ],
              selected: {_typeFilter},
              onSelectionChanged: (value) {
                setState(() => _typeFilter = value.first);
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bulan berjalan saja'),
              value: _currentMonthOnly,
              onChanged: (value) => setState(() {
                _currentMonthOnly = value;
                if (value) {
                  _startDate = null;
                  _endDate = null;
                }
              }),
            ),
            OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(_dateRangeLabel(context)),
            ),
            if (widget.accounts.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _accountId,
                decoration: const InputDecoration(labelText: 'Rekening'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Semua rekening'),
                  ),
                  ...widget.accounts.map(
                    (account) => DropdownMenuItem<String?>(
                      value: account.id,
                      child: Text(account.name),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _accountId = value),
              ),
            ],
            if (widget.categories.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Semua kategori'),
                  ),
                  ...widget.categories.map(
                    (category) => DropdownMenuItem<String?>(
                      value: category.id,
                      child: Text(category.name),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              ),
            ],
            if (widget.merchants.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _merchantId,
                decoration: const InputDecoration(labelText: 'Toko / Merchant'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Semua toko / merchant'),
                  ),
                  ...widget.merchants.map(
                    (merchant) => DropdownMenuItem<String?>(
                      value: merchant.id,
                      child: Text(merchant.name),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _merchantId = value),
              ),
            ],
            if (widget.owners.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _owner,
                decoration: const InputDecoration(labelText: 'Pemilik / Anggota'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Semua anggota'),
                  ),
                  ...widget.owners.map(
                    (owner) => DropdownMenuItem<String?>(
                      value: owner,
                      child: Text(owner),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _owner = value),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const TransactionFilter(
                        typeFilter: 'Semua',
                        currentMonthOnly: false,
                        accountId: null,
                        categoryId: null,
                        merchantId: null,
                        owner: null,
                        startDate: null,
                        endDate: null,
                      ),
                    ),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      TransactionFilter(
                        typeFilter: _typeFilter,
                        currentMonthOnly: _currentMonthOnly,
                        accountId: _accountId,
                        categoryId: _categoryId,
                        merchantId: _merchantId,
                        owner: _owner,
                        startDate: _startDate,
                        endDate: _endDate,
                      ),
                    ),
                    child: const Text('Terapkan'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
