import 'package:flutter/material.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../core/ownership/owner_labels.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/date_time_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../data/services/receipt_import_service.dart';
import '../../domain/entities/transaction_entity.dart';
import '../widgets/voice_review_widgets.dart';
import 'json_transaction_batch_page.dart';

class QuickTransactionRowDraft {
  QuickTransactionRowDraft({
    required this.type,
    required this.categoryId,
    required this.accountId,
    DateTime? date,
  }) : date = date ?? DateTime.now();

  TransactionType type;
  String? categoryId;
  String? merchantId;
  String? accountId;
  String partyName = '';
  DateTime date;
  final amountController = TextEditingController();
  final locationController = TextEditingController();
  final noteController = TextEditingController();
  final items = <JsonTransactionItemDraft>[];

  int get itemsTotal => items.fold(0, (sum, item) => sum + item.total);

  void dispose() {
    amountController.dispose();
    locationController.dispose();
    noteController.dispose();
    for (final item in items) {
      item.dispose();
    }
  }
}

class QuickTransactionBatchPage extends StatefulWidget {
  const QuickTransactionBatchPage({
    super.key,
    required this.categories,
    required this.merchants,
    required this.accounts,
    required this.onSave,
    this.onSaveJsonResult,
    this.onSaveStatement,
  });

  final List<Category> categories;
  final List<Merchant> merchants;
  final List<Account> accounts;
  final Future<void> Function(List<TransactionDraft> drafts) onSave;
  final Future<void> Function(JsonBatchResult result)? onSaveJsonResult;
  final Future<void> Function(ReceiptBatchImport? statement)? onSaveStatement;

  @override
  State<QuickTransactionBatchPage> createState() =>
      _QuickTransactionBatchPageState();
}

class _QuickTransactionBatchPageState extends State<QuickTransactionBatchPage> {
  final _formKey = GlobalKey<FormState>();
  final _rows = <QuickTransactionRowDraft>[];
  late DateTime _day;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _day = DateTime.now();
    _rows.add(_newRow());
  }

  QuickTransactionRowDraft _newRow({
    TransactionType type = TransactionType.expense,
  }) {
    final categoryOptions = _categoryOptions(type);
    return QuickTransactionRowDraft(
      type: type,
      categoryId: categoryOptions.firstOrNull?.id,
      accountId: widget.accounts.firstOrNull?.id,
      date: DateTime(
        _day.year,
        _day.month,
        _day.day,
        DateTime.now().hour,
        DateTime.now().minute,
        DateTime.now().second,
      ),
    );
  }

  List<Category> _categoryOptions(TransactionType type, {String? selectedId}) {
    return transactionCategoryOptions(
      widget.categories,
      type == TransactionType.income ? 'income' : 'expense',
      selectedId: selectedId,
    );
  }

  String _categoryLabel(Category category) {
    return transactionCategoryLabel(widget.categories, category);
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Pilih tanggal kejadian',
      cancelText: AppCopy.batal,
      confirmText: 'Pakai tanggal',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _day = picked;
      for (final row in _rows) {
        row.date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          row.date.hour,
          row.date.minute,
          row.date.second,
        );
      }
    });
  }

  Future<void> _pickTime(QuickTransactionRowDraft row) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(row.date),
      helpText: 'Pilih jam kejadian',
      cancelText: AppCopy.batal,
      confirmText: 'Pakai jam',
    );
    if (picked == null || !mounted) return;
    setState(() {
      row.date = DateTime(
        row.date.year,
        row.date.month,
        row.date.day,
        picked.hour,
        picked.minute,
        row.date.second,
      );
    });
  }

  void _changeType(QuickTransactionRowDraft row, TransactionType type) {
    setState(() {
      row.type = type;
      row.categoryId = _categoryOptions(type).firstOrNull?.id;
    });
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final drafts = <TransactionDraft>[];
    for (final row in _rows) {
      final typedAmount = parseRupiah(row.amountController.text);
      final amount = typedAmount > 0 ? typedAmount : row.itemsTotal;
      final categoryId = row.categoryId;
      final accountId = row.accountId;
      if (amount <= 0 || categoryId == null || accountId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Lengkapi nominal, kategori, dan rekening tiap baris.',
            ),
          ),
        );
        return;
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
      drafts.add(
        TransactionDraft(
          type: row.type,
          categoryId: categoryId,
          owner: OwnerLabels.family,
          partyName: row.partyName.trim().isEmpty ? null : row.partyName.trim(),
          date: row.date,
          amount: row.type == TransactionType.expense ? -amount : amount,
          note: row.noteController.text.trim(),
          location: row.locationController.text.trim().isEmpty
              ? null
              : row.locationController.text.trim(),
          source: 'manual',
          merchantId: row.merchantId,
          accountId: accountId,
          items: items,
        ),
      );
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(drafts);
      if (!mounted) return;
      Navigator.of(context).pop(drafts);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Input Banyak Transaksi'),
        actions: [
          IconButton(
            tooltip: 'Simpan semua transaksi',
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            const AppHelpBanner(
              title: 'Catat banyak transaksi sekaligus',
              message: 'Pilih satu tanggal kejadian untuk hari ini, lalu isi setiap baris. Jam tiap transaksi bisa dibedakan. Waktu input sistem tetap dicatat saat kamu menekan Simpan semua.',
              icon: Icons.playlist_add_check_rounded,
            ),
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.event_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tanggal kejadian',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(formatTanggalLengkap(_day, includeSeconds: false)),
                        HijriDateLabel(date: _day),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _pickDay,
                    child: const Text('Ganti tanggal'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ...List.generate(_rows.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildRow(index, _rows[index]),
              );
            }),
            OutlinedButton.icon(
              onPressed: () => setState(() => _rows.add(_newRow())),
              icon: const Icon(Icons.add),
              label: const Text('Tambah baris transaksi'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_saving ? 'Menyimpan...' : 'Simpan semua'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(int index, QuickTransactionRowDraft row) {
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
                  tooltip: 'Hapus baris',
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
                    labelText: 'Nominal total (boleh kosong jika ada rincian)',
                    prefixText: 'Rp ',
                    helperText: row.items.isEmpty
                        ? 'Atau buka Rincian barang di bawah.'
                        : 'Total rincian: ${formatRupiahInput(row.itemsTotal.toString())}',
                  ),
                  validator: (value) {
                    if (parseRupiah(value ?? '') <= 0 && row.itemsTotal <= 0) {
                      return 'Isi nominal atau rincian barang';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _pickTime(row),
                icon: const Icon(Icons.schedule_outlined, size: 18),
                label: Text(formatJam(row.date)),
              ),
            ],
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
          DropdownButtonFormField<String>(
            initialValue: row.accountId,
            decoration: const InputDecoration(
              labelText: 'Rekening tempat uang',
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
            initialValue: row.partyName,
            decoration: InputDecoration(
              labelText: row.type == TransactionType.income
                  ? 'Sumber pemasukan (opsional)'
                  : 'Dipakai oleh (opsional)',
              hintText: 'Contoh: Keluarga, Suami, Istri',
              prefixIcon: const Icon(Icons.people_outline),
            ),
            onChanged: (value) => row.partyName = value,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: row.merchantId,
            decoration: const InputDecoration(
              labelText: 'Toko/tempat (opsional)',
              prefixIcon: Icon(Icons.storefront_outlined),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Tidak diisi'),
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
          const SizedBox(height: 10),
          TextFormField(
            controller: row.locationController,
            decoration: const InputDecoration(
              labelText: 'Lokasi (opsional)',
              hintText: 'Contoh: pasar pagi, SPBU, rumah',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: row.noteController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Catatan transaksi (opsional)',
              hintText: 'Contoh: belanja pasar pagi',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: row.items.isNotEmpty,
            title: Text('Rincian barang (${row.items.length})'),
            subtitle: Text(
              row.items.isEmpty
                  ? 'Opsional: isi beras, sayur, BBM, dan barang lain'
                  : 'Total rincian ${formatRupiahInput(row.itemsTotal.toString())}',
            ),
            children: [
              ...List.generate(
                row.items.length,
                (itemIndex) =>
                    _buildQuickItem(row, itemIndex, row.items[itemIndex]),
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

  Widget _buildQuickItem(
    QuickTransactionRowDraft row,
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
