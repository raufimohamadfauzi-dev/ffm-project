import 'package:flutter/material.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../data/services/voice_transaction_parser.dart';
import '../../domain/entities/transaction_entity.dart';

List<Category> transactionCategoryOptions(
  List<Category> categories,
  String type, {
  String? selectedId,
}) {
  final typed = categories.where((category) => category.type == type).toList();
  final parentIds = typed
      .map((category) => category.parentId)
      .whereType<String>()
      .toSet();
  return typed
      .where(
        (category) =>
            !parentIds.contains(category.id) || category.id == selectedId,
      )
      .toList(growable: false);
}

String transactionCategoryLabel(
  List<Category> categories,
  Category category, {
  bool markLegacyParent = true,
}) {
  final parent = categories
      .where((item) => item.id == category.parentId)
      .firstOrNull;
  if (parent != null) return '${parent.name} · ${category.name}';
  final hasChildren = categories.any((item) => item.parentId == category.id);
  return hasChildren && markLegacyParent
      ? '${category.name} · kelompok'
      : category.name;
}

class VoiceBatchReviewDialog extends StatefulWidget {
  const VoiceBatchReviewDialog({
    super.key,
    required this.transcript,
    required this.results,
    required this.categories,
    required this.merchants,
    required this.accounts,
    required this.parties,
    required this.tagsMaster,
  });

  final String transcript;
  final List<VoiceTransactionParseResult> results;
  final List<Category> categories;
  final List<Merchant> merchants;
  final List<Account> accounts;
  final List<TransactionParty> parties;
  final List<Tag> tagsMaster;

  @override
  State<VoiceBatchReviewDialog> createState() =>
      _VoiceBatchReviewDialogState();
}

class _VoiceBatchReviewDialogState extends State<VoiceBatchReviewDialog> {
  late final List<VoiceBatchRowDraft> _rows;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _rows = widget.results.map(VoiceBatchRowDraft.new).toList();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  List<Category> _categoriesFor(VoiceBatchRowDraft row) =>
      transactionCategoryOptions(
        widget.categories,
        row.type == TransactionType.income ? 'income' : 'expense',
        selectedId: row.categoryId,
      );

  List<TransactionParty> _partiesFor(VoiceBatchRowDraft row) {
    if (row.type == TransactionType.income) {
      return widget.parties
          .where((party) => party.kind == 'income_source')
          .toList(growable: false);
    }
    final seen = <String>{};
    return [
          ...widget.parties.where((party) => party.kind == 'husband'),
          ...widget.parties.where((party) => party.kind == 'wife'),
          ...widget.parties.where((party) => party.kind == 'used_by'),
        ]
        .where((party) {
          final name = party.name.trim().toLowerCase();
          return name.isNotEmpty && seen.add(name);
        })
        .toList(growable: false);
  }

  String _categoryLabel(Category category) =>
      transactionCategoryLabel(widget.categories, category);

  String _accountLabel(Account account) {
    final type = switch (account.type) {
      'cash' => 'Tunai',
      'bank' => 'Rekening',
      'ewallet' => 'Dompet digital',
      _ => account.type,
    };
    return '${account.name} · $type';
  }

  void _changeType(VoiceBatchRowDraft row, TransactionType type) {
    setState(() {
      row.type = type;
      if (!_categoriesFor(row).any((item) => item.id == row.categoryId)) {
        row.categoryId = null;
      }
      final partyNames = _partiesFor(row).map((party) => party.name).toSet();
      if (row.partyName.isNotEmpty && !partyNames.contains(row.partyName)) {
        row.partyName = '';
        row.partyController.clear();
      }
    });
  }

  void _addRow() {
    setState(() => _rows.add(VoiceBatchRowDraft.empty()));
  }

  void _removeRow(int index) {
    if (_rows.length == 1) return;
    final row = _rows.removeAt(index);
    row.dispose();
    setState(() {});
  }

  String? _validateRows() {
    for (var index = 0; index < _rows.length; index++) {
      final row = _rows[index];
      if (parseRupiah(row.amountController.text) <= 0) {
        return 'Transaksi ${index + 1}: nominal belum valid.';
      }
      if (row.categoryId == null) {
        return 'Transaksi ${index + 1}: kategori belum dipilih dari Data Utama.';
      }
      if (row.accountId == null) {
        return 'Transaksi ${index + 1}: rekening atau dompet belum dipilih.';
      }
      if (row.type == TransactionType.income &&
          row.partyController.text.trim().isEmpty) {
        return 'Transaksi ${index + 1}: sumber pemasukan belum diisi.';
      }
    }
    return null;
  }

  void _saveAll() {
    final error = _validateRows();
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    final drafts = _rows
        .map(
          (row) => TransactionDraft(
            type: row.type,
            categoryId: row.categoryId!,
            owner: row.partyController.text.trim(),
            date: DateTime.now(),
            amount: row.type == TransactionType.income
                ? parseRupiah(row.amountController.text)
                : -parseRupiah(row.amountController.text),
            note: row.noteController.text.trim(),
            source: 'voice',
            merchantId: row.merchantId,
            accountId: row.accountId,
            items: const [],
            tags: row.tags,
          ),
        )
        .toList(growable: false);
    Navigator.of(context).pop(drafts);
  }

  Widget _buildRow(BuildContext context, int index, VoiceBatchRowDraft row) {
    final scheme = Theme.of(context).colorScheme;
    final categories = _categoriesFor(row);
    final parties = _partiesFor(row);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: scheme.primaryContainer,
                  child: Text('${index + 1}'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Transaksi ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (_rows.length > 1)
                  IconButton(
                    tooltip: 'Hapus baris ini',
                    onPressed: () => _removeRow(index),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<TransactionType>(
              initialValue: row.type,
              decoration: const InputDecoration(labelText: 'Jenis transaksi'),
              items: const [
                DropdownMenuItem(
                  value: TransactionType.expense,
                  child: Text('Uang keluar'),
                ),
                DropdownMenuItem(
                  value: TransactionType.income,
                  child: Text('Uang masuk'),
                ),
              ],
              onChanged: (value) {
                if (value != null) _changeType(row, value);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: row.amountController,
              keyboardType: TextInputType.number,
              inputFormatters: const [RupiahInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Nominal',
                prefixText: 'Rp ',
                helperText: 'Bisa ketik angka atau koreksi hasil terbilang.',
              ),
            ),
            const SizedBox(height: 10),
            if (categories.isEmpty)
              const Text('Kategori belum ada. Tambahkan dulu di Data Utama.')
            else
              DropdownButtonFormField<String>(
                initialValue:
                    categories.any((category) => category.id == row.categoryId)
                    ? row.categoryId
                    : null,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: categories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category.id,
                        child: Text(_categoryLabel(category)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => row.categoryId = value),
              ),
            const SizedBox(height: 10),
            if (widget.accounts.isEmpty)
              const AppCard(
                padding: EdgeInsets.all(10),
                child: Text(
                  'Rekening atau dompet belum ada. Tutup dulu, tambahkan dari Data Utama, lalu rekam ulang Voice Note.',
                ),
              )
            else
              DropdownButtonFormField<String>(
                initialValue:
                    widget.accounts.any(
                      (account) => account.id == row.accountId,
                    )
                    ? row.accountId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Rekening atau dompet',
                  helperText: 'Tempat uang masuk atau keluar.',
                ),
                items: widget.accounts
                    .map(
                      (account) => DropdownMenuItem<String>(
                        value: account.id,
                        child: Text(_accountLabel(account)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => row.accountId = value),
              ),
            if (widget.merchants.isNotEmpty) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue:
                    widget.merchants.any(
                      (merchant) => merchant.id == row.merchantId,
                    )
                    ? row.merchantId
                    : null,
                decoration: const InputDecoration(labelText: 'Toko / tempat'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Belum dipilih'),
                  ),
                  ...widget.merchants.map(
                    (merchant) => DropdownMenuItem<String?>(
                      value: merchant.id,
                      child: Text(merchant.name),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => row.merchantId = value),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: row.partyController,
              onChanged: (value) => row.partyName = value,
              decoration: InputDecoration(
                labelText: row.type == TransactionType.income
                    ? 'Sumber pemasukan'
                    : 'Dipakai oleh',
                helperText: parties.isEmpty
                    ? 'Bisa diisi manual; lebih rapi kalau dibuat di Data Utama.'
                    : 'Pilih saran di bawah atau ubah manual.',
              ),
            ),
            if (parties.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: parties
                    .map(
                      (party) => InputChip(
                        label: Text(party.name),
                        selected: row.partyController.text == party.name,
                        onPressed: () => setState(() {
                          row.partyController.text = party.name;
                          row.partyName = party.name;
                        }),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: row.noteController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Catatan'),
            ),
            const SizedBox(height: 10),
            if (widget.tagsMaster.isEmpty)
              const Text('Tag belum tersedia. Tambahkan dulu dari Data Utama.')
            else ...[
              const Text('Tag dari Data Utama'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: widget.tagsMaster.map((tag) {
                  final selected = row.tags.any(
                    (current) =>
                        current.toLowerCase() == tag.name.toLowerCase(),
                  );
                  return FilterChip(
                    label: Text('#${tag.name}'),
                    selected: selected,
                    onSelected: (_) {
                      final next = [...row.tags];
                      if (selected) {
                        next.removeWhere(
                          (current) =>
                              current.toLowerCase() == tag.name.toLowerCase(),
                        );
                      } else {
                        next.add(tag.name);
                      }
                      row.tagsController.text = next.join(', ');
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.table_rows_outlined),
          SizedBox(width: 10),
          Expanded(child: Text('Cek banyak transaksi')),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: MediaQuery.sizeOf(context).height * .72,
        child: ListView(
          children: [
            Text(
              'Voice Note berhasil dipecah menjadi ${_rows.length} draf. Kolom kosong bisa kamu isi manual. Tidak ada yang disimpan sebelum tombol Simpan semua ditekan.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            if (widget.transcript.trim().isNotEmpty)
              AppCard(
                color: Theme.of(context).colorScheme.primaryContainer
                    .withValues(alpha: .4),
                child: Text('“${widget.transcript}”'),
              ),
            const SizedBox(height: 12),
            if (_errorText != null)
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 4),
            ..._rows.asMap().entries.map(
              (entry) => _buildRow(context, entry.key, entry.value),
            ),
            OutlinedButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add),
              label: const Text('Tambah transaksi manual'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppCopy.batal),
        ),
        FilledButton.icon(
          onPressed: _saveAll,
          icon: const Icon(Icons.save_outlined),
          label: Text('Simpan semua (${_rows.length})'),
        ),
      ],
    );
  }
}

class VoiceReviewDraft {
  const VoiceReviewDraft({
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.merchantId,
    required this.accountId,
    required this.partyName,
    required this.note,
    required this.tags,
  });

  final TransactionType type;
  final int amount;
  final String? categoryId;
  final String? merchantId;
  final String? accountId;
  final String partyName;
  final String note;
  final List<String> tags;
}

class VoiceReviewDialog extends StatefulWidget {
  const VoiceReviewDialog({
    super.key,
    required this.transcript,
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.merchantId,
    required this.accountId,
    required this.partyName,
    required this.note,
    required this.tags,
    required this.categories,
    required this.merchants,
    required this.accounts,
    required this.parties,
    required this.tagsMaster,
  });

  final String transcript;
  final TransactionType type;
  final int amount;
  final String? categoryId;
  final String? merchantId;
  final String? accountId;
  final String partyName;
  final String note;
  final List<String> tags;
  final List<Category> categories;
  final List<Merchant> merchants;
  final List<Account> accounts;
  final List<TransactionParty> parties;
  final List<Tag> tagsMaster;

  @override
  State<VoiceReviewDialog> createState() => _VoiceReviewDialogState();
}

class _VoiceReviewDialogState extends State<VoiceReviewDialog> {
  late TransactionType _type;
  late String? _categoryId;
  late String? _merchantId;
  late String? _accountId;
  late String _partyName;
  late List<String> _tags;
  late final TextEditingController _amountController;
  late final TextEditingController _partyController;
  late final TextEditingController _noteController;
  late final TextEditingController _tagController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _type = widget.type;
    _categoryId = widget.categoryId;
    _merchantId = widget.merchantId;
    _accountId = widget.accountId;
    _partyName = widget.partyName;
    _tags = [...widget.tags];
    _amountController = TextEditingController(
      text: widget.amount > 0
          ? formatRupiahInput(widget.amount.toString())
          : '',
    );
    _partyController = TextEditingController(text: _partyName);
    _noteController = TextEditingController(text: widget.note);
    _tagController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _partyController.dispose();
    _noteController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  List<Category> get _availableCategories => transactionCategoryOptions(
    widget.categories,
    _type == TransactionType.income ? 'income' : 'expense',
    selectedId: _categoryId,
  );

  List<TransactionParty> get _availableParties {
    if (_type == TransactionType.income) {
      return widget.parties
          .where((party) => party.kind == 'income_source')
          .toList(growable: false);
    }
    final seen = <String>{};
    return [
          ...widget.parties.where((party) => party.kind == 'husband'),
          ...widget.parties.where((party) => party.kind == 'wife'),
          ...widget.parties.where((party) => party.kind == 'used_by'),
        ]
        .where((party) {
          final name = party.name.trim().toLowerCase();
          return name.isNotEmpty && seen.add(name);
        })
        .toList(growable: false);
  }

  void _changeType(TransactionType type) {
    setState(() {
      _type = type;
      if (!_availableCategories.any((category) => category.id == _categoryId)) {
        _categoryId = null;
      }
      if (!_availableParties.any((party) => party.name == _partyName)) {
        _partyName = '';
        _partyController.clear();
      }
    });
  }

  void _addTag(String rawTag) {
    final tag = rawTag.trim().replaceFirst(RegExp(r'^#'), '');
    if (tag.isEmpty) return;
    final existingIndex = _tags.indexWhere(
      (current) => current.toLowerCase() == tag.toLowerCase(),
    );
    setState(() {
      if (existingIndex >= 0) {
        _tags = [..._tags]..removeAt(existingIndex);
      } else {
        _tags = [..._tags, tag];
      }
      _tagController.clear();
    });
  }

  void _save() {
    final amount = parseRupiah(_amountController.text);
    final needsParty = _type == TransactionType.income;
    if (amount <= 0) {
      setState(() => _errorText = 'Nominal belum valid. Isi nominal dulu.');
      return;
    }
    if (_categoryId == null) {
      setState(
        () => _errorText = 'Kategori belum dipilih. Pilih dari Data Utama.',
      );
      return;
    }
    if (needsParty && _partyName.trim().isEmpty) {
      setState(
        () => _errorText = 'Sumber pemasukan belum dipilih dari Data Utama.',
      );
      return;
    }
    Navigator.of(context).pop(
      VoiceReviewDraft(
        type: _type,
        amount: amount,
        categoryId: _categoryId,
        merchantId: _merchantId,
        accountId: _accountId,
        partyName: _partyName.trim(),
        note: _noteController.text.trim(),
        tags: _tags,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = _type == TransactionType.income;
    final categoryItems = _availableCategories;
    final partyItems = _availableParties;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.fact_check_outlined),
          SizedBox(width: 10),
          Expanded(child: Text('Cek hasil Voice Note')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ini masih draf. Periksa dan edit dulu sebelum diterapkan ke formulir transaksi.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('“${widget.transcript}”'),
            ),
            const SizedBox(height: 16),
            SegmentedButton<TransactionType>(
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Uang keluar'),
                  icon: Icon(Icons.north_east_rounded),
                ),
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Uang masuk'),
                  icon: Icon(Icons.south_west_rounded),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (value) => _changeType(value.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: const [RupiahInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Nominal',
                prefixText: 'Rp ',
              ),
            ),
            const SizedBox(height: 12),
            if (categoryItems.isEmpty)
              VoiceReviewWarning(
                icon: Icons.category_outlined,
                text:
                    'Kategori ${isIncome ? 'pemasukan' : 'pengeluaran'} belum ada. Buat dulu di Data Utama.',
              )
            else
              DropdownButtonFormField<String>(
                initialValue:
                    categoryItems.any((item) => item.id == _categoryId)
                    ? _categoryId
                    : null,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: categoryItems
                    .map(
                      (category) => DropdownMenuItem<String>(
                        value: category.id,
                        child: Text(
                          transactionCategoryLabel(
                            widget.categories,
                            category,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _categoryId = value),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: widget.accounts.any((item) => item.id == _accountId)
                  ? _accountId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Rekening / tempat uang',
                helperText: 'Opsional. Pilih dari Data Utama.',
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Belum dipilih'),
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
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue:
                  widget.merchants.any((item) => item.id == _merchantId)
                  ? _merchantId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Toko / tempat',
                helperText: 'Opsional. Pilih dari Data Utama.',
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Belum dipilih'),
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
            const SizedBox(height: 12),
            if (partyItems.isEmpty)
              VoiceReviewWarning(
                icon: Icons.person_outline_rounded,
                text: isIncome
                    ? 'Sumber pemasukan belum ada. Buat dulu di Data Utama.'
                    : 'Dipakai oleh belum ada. Bagian ini boleh dilewati.',
              )
            else
              DropdownButtonFormField<String>(
                initialValue: partyItems.any((item) => item.name == _partyName)
                    ? _partyName
                    : null,
                decoration: InputDecoration(
                  labelText: isIncome ? 'Sumber pemasukan' : 'Dipakai oleh',
                  helperText: isIncome
                      ? 'Wajib untuk pemasukan. Pilih dari Data Utama.'
                      : 'Opsional, cuma untuk rincian pemakaian.',
                ),
                items: partyItems
                    .map(
                      (party) => DropdownMenuItem<String>(
                        value: party.name,
                        child: Text(party.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _partyName = value ?? ''),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Catatan transaksi',
                helperText: 'Boleh diedit supaya maksud ucapan lebih jelas.',
              ),
            ),
            const SizedBox(height: 12),
            if (widget.tagsMaster.isEmpty)
              const Text('Tag belum tersedia. Tambahkan dulu dari Data Utama.')
            else ...[
              const Text('Pilih tag dari Data Utama'),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final tag in widget.tagsMaster)
                    FilterChip(
                      label: Text('#${tag.name}'),
                      selected: _tags.any(
                        (current) =>
                            current.toLowerCase() == tag.name.toLowerCase(),
                      ),
                      onSelected: (_) => _addTag(tag.name),
                    ),
                ],
              ),
            ],
            if (_tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final tag in _tags)
                    InputChip(
                      label: Text('#$tag'),
                      onDeleted: () =>
                          setState(() => _tags = [..._tags]..remove(tag)),
                    ),
                ],
              ),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorText!,
                style: TextStyle(
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Rincian nota seperti nama barang dan harga item bisa ditambahkan setelah hasil ini diterapkan ke formulir.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Terapkan ke form'),
        ),
      ],
    );
  }
}

class VoiceReviewWarning extends StatelessWidget {
  const VoiceReviewWarning({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class VoiceBatchRowDraft {
  VoiceBatchRowDraft(VoiceTransactionParseResult result)
    : type = result.type == VoiceTransactionType.income
          ? TransactionType.income
          : TransactionType.expense,
      categoryId = result.categoryId,
      merchantId = result.merchantId,
      accountId = result.accountId,
      partyName = result.partyName ?? '',
      amountController = TextEditingController(
        text: result.hasAmount
            ? formatRupiahInput(result.amount.toString())
            : '',
      ),
      partyController = TextEditingController(text: result.partyName ?? ''),
      noteController = TextEditingController(text: result.note ?? ''),
      tagsController = TextEditingController(text: result.tagNames.join(', '));

  VoiceBatchRowDraft.empty()
    : this(
        const VoiceTransactionParseResult(
          amount: 0,
          type: VoiceTransactionType.expense,
          owner: '',
          hasExplicitType: false,
          hasAmount: false,
          note: '',
        ),
      );

  TransactionType type;
  String? categoryId;
  String? merchantId;
  String? accountId;
  String partyName;
  final TextEditingController amountController;
  final TextEditingController partyController;
  final TextEditingController noteController;
  final TextEditingController tagsController;

  List<String> get tags => tagsController.text
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  void dispose() {
    amountController.dispose();
    partyController.dispose();
    noteController.dispose();
    tagsController.dispose();
  }
}

class VoiceInputGuide extends StatelessWidget {
  const VoiceInputGuide({super.key, required this.isIncome});

  final bool isIncome;

  @override
  Widget build(BuildContext context) {
    final example = isIncome
        ? '“Uang masuk, gaji, tiga juta, untuk Keluarga.”'
        : '“Uang keluar, beli makan, lima puluh ribu, untuk Anak.”';
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.menu_book_outlined, color: AppColors.primary),
          SizedBox(width: 10),
          Expanded(child: Text('Cara pakai input suara')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Suara diproses langsung di HP tanpa internet. Kalau model Whisper sudah diimpor, tombol memakai Whisper lokal. Kalau belum, aplikasi memakai pengenalan suara offline dari perangkat. Hasilnya cuma isian sementara, jadi tetap wajib dicek sebelum disimpan.',
            ),
            const SizedBox(height: 12),
            VoiceGuideStep(
              number: '1',
              title: 'Pilih arah transaksi',
              description: isIncome
                  ? 'Pastikan pilihan Uang masuk aktif.'
                  : 'Pastikan pilihan Uang keluar aktif.',
            ),
            VoiceGuideStep(
              number: '2',
              title: 'Tekan ikon mikrofon',
              description: 'Tunggu sampai tulisan berubah menjadi sedang mendengar, lalu ucapkan satu kalimat pendek.',
            ),
            VoiceGuideStep(
              number: '3',
              title: 'Ucapkan dengan urutan ini',
              description: 'Arah transaksi, keperluan, nominal, lalu rincian Keluarga, Istri, atau Anak bila perlu.',
            ),
            const SizedBox(height: 8),
            Text(
              'Contoh: $example',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Setelah selesai, aplikasi membuka editor pratinjau. Cek arah, nominal, kategori, rekening, toko, sumber/pemakai, tag, dan catatan sebelum menerapkan hasil ke formulir. Pada mode Whisper, tekan ikon mikrofon sekali lagi untuk berhenti; mode perangkat bisa berhenti otomatis setelah jeda singkat.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Oke, ngerti'),
        ),
      ],
    );
  }
}

class VoiceGuideStep extends StatelessWidget {
  const VoiceGuideStep({
    super.key,
    required this.number,
    required this.title,
    required this.description,
  });

  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: AppColors.primary,
            child: Text(
              number,
              style: const TextStyle(
                color: AppColors.onPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: '$title. ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: description),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class VoiceResultLine extends StatelessWidget {
  const VoiceResultLine({
    super.key,
    required this.label,
    required this.value,
    required this.isValid,
  });

  final String label;
  final String value;
  final bool isValid;

  @override
  Widget build(BuildContext context) {
    final color = isValid ? AppColors.positive : AppColors.warning;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isValid ? Icons.check_circle_outline : Icons.help_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
