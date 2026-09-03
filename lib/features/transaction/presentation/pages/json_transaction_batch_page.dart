import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../core/ownership/owner_labels.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/date_time_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../data/services/receipt_import_service.dart';
import '../../data/services/receipt_import_models.dart';
import '../../domain/entities/transaction_entity.dart';
import '../widgets/voice_review_widgets.dart';

class JsonBudgetOption {
  const JsonBudgetOption({
    required this.id,
    required this.label,
    required this.categoryIds,
  });

  final String id;
  final String label;
  final List<String> categoryIds;
}

class JsonTransferDraft {
  const JsonTransferDraft({
    required this.date,
    required this.amount,
    required this.adminFee,
    required this.fromAccountId,
    required this.toAccountId,
    this.note,
  });

  final DateTime date;
  final int amount;
  final int adminFee;
  final String fromAccountId;
  final String toAccountId;
  final String? note;
}

class JsonBatchResult {
  const JsonBatchResult({
    required this.drafts,
    required this.transfers,
    this.statement,
  });

  final List<TransactionDraft> drafts;
  final List<JsonTransferDraft> transfers;
  final ReceiptBatchImport? statement;
}

class JsonTransactionItemDraft {
  JsonTransactionItemDraft({String name = '', double quantity = 1, int price = 0})
    : nameController = TextEditingController(text: name),
      quantityController = TextEditingController(
        text: quantity == quantity.roundToDouble()
            ? quantity.toInt().toString()
            : quantity.toString(),
      ),
      priceController = TextEditingController(
        text: price > 0 ? formatRupiahInput(price.toString()) : '',
      );

  final TextEditingController nameController;
  final TextEditingController quantityController;
  final TextEditingController priceController;

  int get price => parseRupiah(priceController.text);

  double get quantity =>
      double.tryParse(quantityController.text.trim().replaceAll(',', '.')) ?? 1;

  int get total => (price * (quantity <= 0 ? 1 : quantity)).round();

  void dispose() {
    nameController.dispose();
    quantityController.dispose();
    priceController.dispose();
  }
}

class JsonTransactionRowDraft {
  JsonTransactionRowDraft({
    required this.type,
    required this.date,
    String? time,
    int? amount,
    String? merchantName,
    String? partyName,
    String? location,
    List<String> tags = const [],
    this.receiptNumber,
    String? note,
    this.categoryId,
    this.accountId,
    this.budgetId,
    List<ReceiptOcrItem> items = const [],
  }) : amountController = TextEditingController(
          text: amount != null && amount > 0 ? formatRupiahInput(amount.toString()) : '',
        ),
        merchantController = TextEditingController(text: merchantName ?? ''),
        partyController = TextEditingController(text: partyName ?? ''),
        locationController = TextEditingController(text: location ?? ''),
        tagsController = TextEditingController(text: tags.join(', ')),
        noteController = TextEditingController(text: note ?? ''),
        time = DateTime.now(),
        items = items
            .map(
              (item) => JsonTransactionItemDraft(
                name: item.name,
                price: item.price,
                quantity: item.quantity,
              ),
            )
            .toList() {
    if (time != null) {
      final parts = time.split(':');
      if (parts.length >= 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null && minute != null) {
          this.time = DateTime(
            date.year,
            date.month,
            date.day,
            hour,
            minute,
          );
        }
      }
    }
  }

  TransactionType type;
  DateTime date;
  DateTime time;
  String? categoryId;
  String? accountId;
  String? budgetId;
  final String? receiptNumber;
  final TextEditingController amountController;
  final TextEditingController merchantController;
  final TextEditingController partyController;
  final TextEditingController locationController;
  final TextEditingController tagsController;
  final TextEditingController noteController;
  final List<JsonTransactionItemDraft> items;

  int get itemsTotal => items.fold(0, (sum, item) => sum + item.total);

  void dispose() {
    amountController.dispose();
    merchantController.dispose();
    partyController.dispose();
    locationController.dispose();
    tagsController.dispose();
    noteController.dispose();
    for (final item in items) {
      item.dispose();
    }
  }
}

class JsonTransferRowDraft {
  JsonTransferRowDraft({
    required this.date,
    String? time,
    int? amount,
    int? adminFee,
    this.fromAccountId,
    this.toAccountId,
    String? note,
  }) : amountController = TextEditingController(
          text: amount != null && amount > 0 ? formatRupiahInput(amount.toString()) : '',
        ),
        adminFeeController = TextEditingController(
          text: adminFee != null && adminFee > 0 ? formatRupiahInput(adminFee.toString()) : '',
        ),
        noteController = TextEditingController(text: note ?? ''),
        time = DateTime.now() {
    if (time != null) {
      final parts = time.split(':');
      if (parts.length >= 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null && minute != null) {
          this.time = DateTime(
            date.year,
            date.month,
            date.day,
            hour,
            minute,
          );
        }
      }
    }
  }

  DateTime date;
  DateTime time;
  String? fromAccountId;
  String? toAccountId;
  final TextEditingController amountController;
  final TextEditingController adminFeeController;
  final TextEditingController noteController;

  int get amount => parseRupiah(amountController.text);
  int get adminFee => parseRupiah(adminFeeController.text);

  void dispose() {
    amountController.dispose();
    adminFeeController.dispose();
    noteController.dispose();
  }
}

class JsonTransactionBatchPage extends StatefulWidget {
  const JsonTransactionBatchPage({
    super.key,
    required this.categories,
    required this.merchants,
    required this.accounts,
    required this.budgetOptions,
  });

  final List<Category> categories;
  final List<Merchant> merchants;
  final List<Account> accounts;
  final List<JsonBudgetOption> budgetOptions;

  @override
  State<JsonTransactionBatchPage> createState() =>
      JsonTransactionBatchPageState();
}

class JsonTransactionBatchPageState extends State<JsonTransactionBatchPage> {
  final _jsonController = TextEditingController();
  final _rows = <JsonTransactionRowDraft>[];
  final _transferRows = <JsonTransferRowDraft>[];
  List<String> _warnings = const [];
  ReceiptBatchImport? _statementImport;
  var _showJsonBox = false;
  var _loading = false;

  @override
  void initState() {
    super.initState();
    _rows.add(_newRow());
  }

  JsonTransactionRowDraft _newRow({
    TransactionType type = TransactionType.expense,
    DateTime? date,
    String? time,
    int? amount,
    String? merchant,
    String? categoryId,
    String? accountId,
    String? budgetId,
    String? partyName,
    String? location,
    List<String> tags = const [],
    String? receiptNumber,
    String? note,
    List<ReceiptOcrItem> items = const [],
  }) {
    final effectiveType = type;
    final selectedBudget = _findBudgetOption(budgetId);
    final categories = _categoryOptions(effectiveType, selectedId: categoryId);
    final budgetCategory = selectedBudget?.categoryIds
        .map(
          (id) => categories.where((category) => category.id == id).firstOrNull,
        )
        .whereType<Category>()
        .firstOrNull;
    final validCategory =
        categories.any((item) => item.id == categoryId) &&
            (selectedBudget == null ||
                selectedBudget.categoryIds.contains(categoryId))
        ? categoryId
        : budgetCategory?.id ?? categories.firstOrNull?.id;
    final validAccount = widget.accounts.any((item) => item.id == accountId)
        ? accountId
        : widget.accounts.firstOrNull?.id;
    return JsonTransactionRowDraft(
      type: effectiveType,
      date: date ?? DateTime.now(),
      time: time,
      amount: amount,
      merchantName: merchant,
      partyName: partyName,
      location: location,
      tags: tags,
      receiptNumber: receiptNumber,
      note: note,
      categoryId: validCategory,
      accountId: validAccount,
      budgetId: selectedBudget?.id,
      items: items,
    );
  }

  JsonBudgetOption? _findBudgetOption(String? idOrName) {
    final query = idOrName?.trim();
    if (query == null || query.isEmpty) return null;
    final exactId = widget.budgetOptions
        .where((option) => option.id == query)
        .firstOrNull;
    if (exactId != null) return exactId;
    final normalized = query.toLowerCase();
    return widget.budgetOptions
        .where((option) => option.label.toLowerCase() == normalized)
        .firstOrNull;
  }

  JsonBudgetOption? _findBudgetByName(String? name) {
    final query = name?.trim().toLowerCase();
    if (query == null || query.isEmpty) return null;
    return widget.budgetOptions
        .where(
          (option) =>
              option.label.toLowerCase().contains(query) ||
              query.contains(option.label.toLowerCase()),
        )
        .firstOrNull;
  }

  JsonBudgetOption? _selectedBudget(JsonTransactionRowDraft row) => widget
      .budgetOptions
      .where((option) => option.id == row.budgetId)
      .firstOrNull;

  JsonTransferRowDraft _newTransferRow({
    DateTime? date,
    String? time,
    int? amount,
    int? adminFee,
    String? fromAccountId,
    String? toAccountId,
    String? note,
    bool preserveMissingAccounts = false,
  }) {
    final accountIds = widget.accounts.map((item) => item.id).toList();
    final validFrom = preserveMissingAccounts
        ? (accountIds.contains(fromAccountId) ? fromAccountId : null)
        : (accountIds.contains(fromAccountId)
              ? fromAccountId
              : accountIds.firstOrNull);
    final validTo = preserveMissingAccounts
        ? (accountIds.contains(toAccountId) && toAccountId != validFrom
              ? toAccountId
              : null)
        : (accountIds.contains(toAccountId) && toAccountId != validFrom
              ? toAccountId
              : accountIds.where((id) => id != validFrom).firstOrNull);
    return JsonTransferRowDraft(
      date: date ?? DateTime.now(),
      time: time,
      amount: amount,
      adminFee: adminFee,
      fromAccountId: validFrom,
      toAccountId: validTo,
      note: note,
    );
  }

  List<Category> _categoryOptions(TransactionType type, {String? selectedId}) =>
      transactionCategoryOptions(
        widget.categories,
        type == TransactionType.income ? 'income' : 'expense',
        selectedId: selectedId,
      );

  String _categoryLabel(Category category) =>
      transactionCategoryLabel(widget.categories, category);

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result.isEmpty || result.single.path == null) return;
    try {
      _jsonController.text = await File(result.single.path!).readAsString();
      await _loadJson();
    } catch (_) {
      _showMessage('File JSON belum berhasil dibaca.');
    }
  }

  Future<void> _loadJson() async {
    final text = _jsonController.text.trim();
    if (text.isEmpty) {
      _showMessage('Tempel JSON dulu atau pilih file JSON.');
      return;
    }
    setState(() => _loading = true);
    try {
      final imported = ReceiptImportService.parseBatchJson(text);
      final warnings = [...imported.warnings];
      final transferEntries = imported.entries
          .where((entry) => entry.type == 'transfer')
          .toList();
      final transferRows = transferEntries
          .map(
            (entry) => _newTransferRow(
              date: entry.date,
              time: entry.time,
              amount: entry.amount,
              adminFee: entry.adminFee,
              fromAccountId: entry.fromAccountId,
              toAccountId: entry.toAccountId,
              note: entry.note,
              preserveMissingAccounts: true,
            ),
          )
          .toList();
      for (var index = 0; index < transferEntries.length; index++) {
        final entry = transferEntries[index];
        if (entry.fromAccountId == null || entry.toAccountId == null) {
          warnings.add(
            'Transfer ke-${index + 1}: pilih rekening asal dan tujuan sebelum konfirmasi.',
          );
        }
      }
      final rows = imported.entries
          .where((entry) => entry.type != 'transfer')
          .map((entry) {
            final type = entry.type == 'income'
                ? TransactionType.income
                : TransactionType.expense;
            return _newRow(
              type: type,
              date: entry.date,
              time: entry.time,
              amount: entry.amount,
              merchant: entry.merchant,
              categoryId: entry.categoryId,
              accountId: entry.accountId,
              budgetId:
                  _findBudgetOption(entry.budgetId)?.id ??
                  _findBudgetByName(entry.budgetName)?.id,
              partyName: entry.partyName,
              location: entry.location,
              tags: entry.tags,
              receiptNumber: entry.receiptNumber,
              note: entry.note,
              items: entry.items,
            );
          })
          .toList();
      for (var index = 0; index < imported.entries.length; index++) {
        final entry = imported.entries[index];
        if (entry.type != 'expense') continue;
        final budgetHint = entry.budgetId ?? entry.budgetName;
        if (budgetHint != null &&
            _findBudgetOption(budgetHint) == null &&
            _findBudgetByName(entry.budgetName) == null) {
          warnings.add(
            'Transaksi ke-${index + 1}: pos anggaran "$budgetHint" belum cocok; pilih manual.',
          );
        }
      }
      if (rows.isEmpty && transferRows.isEmpty) {
        warnings.add('Belum ada mutasi yang bisa ditinjau.');
      }
      for (final row in _rows) {
        row.dispose();
      }
      for (final row in _transferRows) {
        row.dispose();
      }
      setState(() {
        _rows
          ..clear()
          ..addAll(rows);
        _transferRows
          ..clear()
          ..addAll(transferRows);
        _warnings = warnings;
        _statementImport = imported.isBankStatement ? imported : null;
        _showJsonBox = false;
      });
      final statementMessage =
          imported.isBankStatement && imported.closingBalance != null
          ? ' Saldo akhir akan direkonsiliasi setelah konfirmasi.'
          : '';
      final totalRows = rows.length + transferRows.length;
      _showMessage(
        '$totalRows mutasi dimuat sebagai draft: ${rows.length} pemasukan/pengeluaran dan ${transferRows.length} transfer. Cek dan edit sebelum konfirmasi.$statementMessage',
      );
    } on ReceiptImportException catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _showMessage('Clipboard belum berisi JSON.');
      return;
    }
    setState(() {
      _jsonController.text = text;
      _showJsonBox = true;
    });
  }

  Future<void> _copyTemplate() async {
    await Clipboard.setData(
      ClipboardData(text: ReceiptImportService.templateBatchJson()),
    );
    _showMessage('Contoh JSON transaksi sudah disalin.');
  }

  Future<void> _copyPrompt() async {
    await Clipboard.setData(
      ClipboardData(text: ReceiptImportService.buildExternalLlmBatchPrompt()),
    );
    _showMessage('Instruksi JSON untuk LLM eksternal sudah disalin.');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _addRow() => setState(() => _rows.add(_newRow()));

  void _changeType(JsonTransactionRowDraft row, TransactionType type) {
    final categories = _categoryOptions(type);
    setState(() {
      row.type = type;
      row.categoryId = categories.firstOrNull?.id;
      if (type == TransactionType.income) row.budgetId = null;
    });
  }

  Future<void> _pickDate(JsonTransactionRowDraft row) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: row.date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Pilih tanggal kejadian',
      cancelText: AppCopy.batal,
      confirmText: 'Pakai tanggal',
    );
    if (picked == null || !mounted) return;
    setState(() {
      row.date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        row.time.hour,
        row.time.minute,
        row.time.second,
      );
      row.time = row.date;
    });
  }

  Future<void> _pickTime(JsonTransactionRowDraft row) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(row.time),
      helpText: 'Pilih jam kejadian',
      cancelText: AppCopy.batal,
      confirmText: 'Pakai jam',
    );
    if (picked == null || !mounted) return;
    setState(() {
      row.time = DateTime(
        row.date.year,
        row.date.month,
        row.date.day,
        picked.hour,
        picked.minute,
        DateTime.now().second,
      );
      row.date = row.time;
    });
  }

  List<TransactionDraft>? _buildDrafts() {
    final drafts = <TransactionDraft>[];
    for (var index = 0; index < _rows.length; index++) {
      final row = _rows[index];
      final amount = parseRupiah(row.amountController.text) > 0
          ? parseRupiah(row.amountController.text)
          : row.itemsTotal;
      if (amount <= 0 || row.categoryId == null || row.accountId == null) {
        _showMessage(
          'Transaksi ${index + 1}: isi nominal, kategori, dan rekening.',
        );
        return null;
      }
      final items = row.items
          .where((item) => item.nameController.text.trim().isNotEmpty)
          .map(
            (item) => ReceiptItemDraft(
              name: item.nameController.text.trim(),
              price: item.price,
              qty: item.quantity <= 0 ? 1 : item.quantity,
            ),
          )
          .toList();
      final merchantName = row.merchantController.text.trim();
      final matchedMerchant = widget.merchants
          .where(
            (merchant) =>
                merchant.name.toLowerCase() == merchantName.toLowerCase(),
          )
          .firstOrNull;
      final tags = row.tagsController.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList();

      drafts.add(
        TransactionDraft(
          type: row.type,
          categoryId: row.categoryId,
          owner: OwnerLabels.family,
          partyName: row.partyController.text.trim().isEmpty
              ? null
              : row.partyController.text.trim(),
          date: row.date,
          amount: row.type == TransactionType.expense ? -amount : amount,
          note: row.noteController.text.trim(),
          location: row.locationController.text.trim().isEmpty
              ? null
              : row.locationController.text.trim(),
          source: 'json_batch',
          accountId: row.accountId,
          merchantId: matchedMerchant?.id,
          assistantMerchantName:
              matchedMerchant == null && merchantName.isNotEmpty
                  ? merchantName
                  : null,
          receiptNumber: row.receiptNumber,
          tags: tags,
          items: items,
        ),
      );
    }
    return drafts;
  }

  List<JsonTransferDraft>? _buildTransfers() {
    final transfers = <JsonTransferDraft>[];
    for (var index = 0; index < _transferRows.length; index++) {
      final row = _transferRows[index];
      if (row.amount <= 0 ||
          row.fromAccountId == null ||
          row.toAccountId == null) {
        _showMessage(
          'Transfer ${index + 1}: isi nominal, rekening asal, dan rekening tujuan.',
        );
        return null;
      }
      if (row.fromAccountId == row.toAccountId) {
        _showMessage(
          'Transfer ${index + 1}: rekening asal dan tujuan harus berbeda.',
        );
        return null;
      }
      transfers.add(
        JsonTransferDraft(
          date: row.date,
          amount: row.amount,
          adminFee: row.adminFee,
          fromAccountId: row.fromAccountId!,
          toAccountId: row.toAccountId!,
          note: row.noteController.text.trim(),
        ),
      );
    }
    return transfers;
  }

  void _confirm() {
    final drafts = _buildDrafts();
    final transfers = _buildTransfers();
    if (drafts == null || transfers == null) return;
    if (drafts.isEmpty && transfers.isEmpty) {
      _showMessage('Belum ada mutasi yang bisa dikonfirmasi.');
      return;
    }
    Navigator.of(context).pop(
      JsonBatchResult(
        drafts: drafts,
        transfers: transfers,
        statement: _statementImport,
      ),
    );
  }

  @override
  void dispose() {
    _jsonController.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tempel Hasil dari Asisten AI'),
        actions: [
          IconButton(
            tooltip: 'Pakai semua draft',
            onPressed: _confirm,
            icon: const Icon(Icons.check_circle_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          AppCard(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .3),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Langkah penggunaan:',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _step(1, 'Minta Asisten AI di HP/Web untuk merangkum nota atau daftar transaksi.'),
                _step(2, 'Salin (Copy) hasil teks JSON yang diberikan Asisten.'),
                _step(3, 'Tempel (Paste) di kotak bawah ini, lalu periksa hasilnya.'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Tempel JSON di sini',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Kirim foto nota atau screenshot mutasi ke LLM eksternal bersama instruksi yang disalin dari sini. Setelah dimuat, semua hasil masih bisa diedit.',
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _copyPrompt,
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Salin instruksi untuk LLM'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _copyTemplate,
                      icon: const Icon(Icons.data_object_outlined),
                      label: const Text('Salin contoh JSON'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pasteFromClipboard,
                      icon: const Icon(Icons.content_paste_go_outlined),
                      label: const Text('Tempel JSON'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Pilih file hasil'),
                    ),
                  ],
                ),
                if (_showJsonBox) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _jsonController,
                    minLines: 8,
                    maxLines: 16,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      labelText: 'JSON transaksi',
                      hintText: '{ "format": "ffm-transaction-batch-v1", ... }',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _loading ? null : _loadJson,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.playlist_add_check_rounded),
                    label: Text(
                      _loading
                          ? 'Memeriksa hasil...'
                          : 'Periksa dan tampilkan transaksi',
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_statementImport != null) ...[
            const SizedBox(height: 10),
            AppCard(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ringkasan mutasi rekening',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _statementImport!.statementAccountName == null
                        ? 'Rekening dari screenshot'
                        : 'Rekening: ${_statementImport!.statementAccountName}',
                  ),
                  if (_statementImport!.openingBalance != null)
                    Text(
                      'Saldo awal: ${formatRupiahInput(_statementImport!.openingBalance!.toString())}',
                    ),
                  if (_statementImport!.closingBalance != null)
                    Text(
                      'Saldo akhir: ${formatRupiahInput(_statementImport!.closingBalance!.toString())}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  const SizedBox(height: 4),
                  const Text(
                    'Saldo akhir tidak dibuat sebagai pemasukan. Setelah konfirmasi, angka ini dipakai untuk rekonsiliasi rekening.',
                  ),
                ],
              ),
            ),
          ],
          if (_warnings.isNotEmpty) ...[
            const SizedBox(height: 10),
            AppCard(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Text('Catatan impor:\n• ${_warnings.join('\n• ')}'),
            ),
          ],
          if (_transferRows.isNotEmpty) ...[
            const SizedBox(height: 12),
            AppCard(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Transfer rekening',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Transfer hanya memindahkan lokasi uang. Tidak masuk hitungan pemasukan atau pengeluaran. Biaya admin dicatat terpisah sebagai pengeluaran dari rekening asal.',
                  ),
                  const SizedBox(height: 10),
                  ...List.generate(
                    _transferRows.length,
                    (index) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildJsonTransferRow(index, _transferRows[index]),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _transferRows.add(_newTransferRow());
                    }),
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah transfer'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          ...List.generate(
            _rows.length,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildJsonRow(index, _rows[index]),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _addRow,
            icon: const Icon(Icons.add),
            label: const Text('Tambah transaksi lain'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _confirm,
            icon: const Icon(Icons.check_circle_outline),
            label: Text(
              'Konfirmasi ${_rows.length + _transferRows.length} mutasi',
            ),
          ),
        ],
      ),
    );
  }

  String _jsonAccountLabel(Account account) {
    final type = switch (account.type) {
      'cash' => 'Tunai',
      'bank' => 'Rekening',
      'ewallet' => 'Dompet digital',
      _ => account.type,
    };
    return '${account.name} · $type';
  }

  Widget _step(int number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$number. ', style: const TextStyle(fontWeight: FontWeight.w900)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildJsonTransferRow(int index, JsonTransferRowDraft row) {
    final fromAccount = widget.accounts
        .where((account) => account.id == row.fromAccountId)
        .firstOrNull;
    final toAccount = widget.accounts
        .where((account) => account.id == row.toAccountId)
        .firstOrNull;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Transfer ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Hapus transfer',
                onPressed: () => setState(() {
                  row.dispose();
                  _transferRows.removeAt(index);
                }),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          SearchableDropdown(
            items: widget.accounts,
            selectedItem: fromAccount,
            itemLabel: _jsonAccountLabel,
            itemId: (account) => account.id,
            labelText: 'Dari tempat uang',
            searchHintText: 'Cari rekening, Tunai, atau dompet',
            cacheKey: 'json_transfer.asal',
            onChanged: (account) => setState(() {
              row.fromAccountId = account?.id;
            }),
          ),
          const SizedBox(height: 10),
          SearchableDropdown(
            items: widget.accounts,
            selectedItem: toAccount,
            itemLabel: _jsonAccountLabel,
            itemId: (account) => account.id,
            labelText: 'Ke tempat uang',
            searchHintText: 'Cari rekening, Tunai, atau dompet',
            cacheKey: 'json_transfer.tujuan',
            onChanged: (account) => setState(() {
              row.toAccountId = account?.id;
            }),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: row.amountController,
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Nominal yang dipindahkan',
              prefixText: 'Rp ',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: row.adminFeeController,
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Biaya admin (opsional)',
              prefixText: 'Rp ',
              helperText: 'Biaya ini mengurangi saldo tempat asal.',
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: row.date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      helpText: 'Pilih tanggal transfer',
                      cancelText: AppCopy.batal,
                      confirmText: 'Pakai tanggal',
                    );
                    if (picked == null || !mounted) return;
                    setState(() {
                      row.date = DateTime(
                        picked.year,
                        picked.month,
                        picked.day,
                        row.time.hour,
                        row.time.minute,
                        row.time.second,
                      );
                      row.time = row.date;
                    });
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(formatTanggalSingkat(row.date)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(row.time),
                      helpText: 'Pilih jam transfer',
                      cancelText: AppCopy.batal,
                      confirmText: 'Pakai jam',
                    );
                    if (picked == null || !mounted) return;
                    setState(() {
                      row.time = DateTime(
                        row.date.year,
                        row.date.month,
                        row.date.day,
                        picked.hour,
                        picked.minute,
                        DateTime.now().second,
                      );
                      row.date = row.time;
                    });
                  },
                  icon: const Icon(Icons.schedule_outlined),
                  label: Text(formatJam(row.time)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: row.noteController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Catatan transfer (opsional)',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJsonRow(int index, JsonTransactionRowDraft row) {
    final categories = _categoryOptions(row.type, selectedId: row.categoryId);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Transaksi ${index + 1}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_rows.length > 1)
                IconButton(
                  tooltip: 'Hapus transaksi ini',
                  onPressed: () => setState(() {
                    row.dispose();
                    _rows.removeAt(index);
                  }),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          DropdownButtonFormField<TransactionType>(
            initialValue: row.type,
            decoration: const InputDecoration(
              labelText: 'Jenis transaksi',
              prefixIcon: Icon(Icons.swap_vert_rounded),
            ),
            items: const [
              DropdownMenuItem(
                value: TransactionType.expense,
                child: Text('Pengeluaran'),
              ),
              DropdownMenuItem(
                value: TransactionType.income,
                child: Text('Pemasukan'),
              ),
            ],
            onChanged: (value) {
              if (value != null) _changeType(row, value);
            },
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: row.amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  decoration: InputDecoration(
                    labelText: row.items.isEmpty
                        ? 'Nominal total'
                        : 'Nominal total (boleh kosong)',
                    prefixText: 'Rp ',
                    helperText: row.items.isEmpty
                        ? null
                        : 'Total rincian: ${formatRupiahInput(row.itemsTotal.toString())}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _pickTime(row),
                icon: const Icon(Icons.schedule_outlined, size: 18),
                label: Text(formatJam(row.time)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _pickDate(row),
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatTanggalLengkap(row.date, includeSeconds: false)),
                HijriDateLabel(date: row.date),
              ],
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: row.categoryId,
            decoration: const InputDecoration(
              labelText: 'Kategori',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: categories
                .map(
                  (category) => DropdownMenuItem(
                    value: category.id,
                    child: Text(_categoryLabel(category)),
                  ),
                )
                .toList(),
            onChanged: categories.isEmpty
                ? null
                : (value) => setState(() => row.categoryId = value),
            validator: (_) => row.categoryId == null ? 'Pilih kategori' : null,
          ),
          const SizedBox(height: 10),
          if (row.type == TransactionType.expense) ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedBudget(row)?.id,
              decoration: const InputDecoration(
                labelText: 'Arahkan ke pos anggaran (opsional)',
                prefixIcon: Icon(Icons.track_changes_outlined),
                helperText: 'Pos membantu memilih kategori. Target tetap dihitung dari pengeluaran dan tanggal kejadian.',
              ),
              items: widget.budgetOptions
                  .map(
                    (option) => DropdownMenuItem<String>(
                      value: option.id,
                      child: Text(
                        option.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: widget.budgetOptions.isEmpty
                  ? null
                  : (value) {
                      final option = widget.budgetOptions
                          .where((item) => item.id == value)
                          .firstOrNull;
                      setState(() {
                        row.budgetId = option?.id;
                        final categoryId = option?.categoryIds
                            .map(
                              (id) =>
                                  _categoryOptions(row.type)
                                      .where((category) => category.id == id)
                                      .firstOrNull,
                            )
                            .whereType<Category>()
                            .firstOrNull
                            ?.id;
                        if (categoryId != null) row.categoryId = categoryId;
                      });
                    },
            ),
            const SizedBox(height: 10),
          ] else
            const Text(
              'Anggaran hanya dipakai untuk memantau pengeluaran, bukan pemasukan.',
              style: TextStyle(fontSize: 12),
            ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: row.accountId,
            decoration: const InputDecoration(
              labelText: 'Rekening/tempat uang',
              prefixIcon: Icon(Icons.account_balance_wallet_outlined),
            ),
            items: widget.accounts
                .map(
                  (account) => DropdownMenuItem(
                    value: account.id,
                    child: Text(account.name),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => row.accountId = value),
            validator: (_) => row.accountId == null ? 'Pilih rekening' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: row.merchantController,
            decoration: const InputDecoration(
              labelText: 'Toko/tempat (opsional)',
              prefixIcon: Icon(Icons.storefront_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: row.locationController,
            decoration: const InputDecoration(
              labelText: 'Lokasi / alamat (opsional)',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: row.tagsController,
            decoration: const InputDecoration(
              labelText: 'Tag transaksi (opsional, pisahkan koma)',
              prefixIcon: Icon(Icons.label_outline),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: row.partyController,
            decoration: InputDecoration(
              labelText: row.type == TransactionType.income
                  ? 'Sumber pemasukan (opsional)'
                  : 'Dipakai oleh (opsional)',
              prefixIcon: const Icon(Icons.people_outline),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: row.noteController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Catatan transaksi (opsional)',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: row.items.isNotEmpty,
            title: Text('Rincian item (${row.items.length})'),
            subtitle: Text(
              row.items.isEmpty
                  ? 'Tambah barang seperti beras, sayur, atau BBM'
                  : 'Total rincian ${formatRupiahInput(row.itemsTotal.toString())}',
            ),
            children: [
              ...List.generate(
                row.items.length,
                (itemIndex) =>
                    _buildJsonItem(row, itemIndex, row.items[itemIndex]),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => row.items.add(JsonTransactionItemDraft())),
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah rincian barang'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildJsonItem(
    JsonTransactionRowDraft row,
    int index,
    JsonTransactionItemDraft item,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: item.nameController,
              decoration: const InputDecoration(labelText: 'Nama barang'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: item.quantityController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Qty'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: TextField(
              controller: item.priceController,
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
              decoration: const InputDecoration(labelText: 'Harga'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            tooltip: 'Hapus rincian',
            onPressed: () => setState(() {
              item.dispose();
              row.items.removeAt(index);
            }),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
