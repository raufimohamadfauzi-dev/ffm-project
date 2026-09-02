import 'package:flutter/material.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../domain/entities/transaction_entity.dart';

class ReceiptItemEditorDialog extends StatefulWidget {
  const ReceiptItemEditorDialog({super.key, required this.item});

  final ReceiptItemDraft item;

  @override
  State<ReceiptItemEditorDialog> createState() => _ReceiptItemEditorDialogState();
}

class _ReceiptItemEditorDialogState extends State<ReceiptItemEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _qtyController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item.name);
    _priceController = TextEditingController(
      text: formatRupiahInput('${widget.item.price}'),
    );
    _qtyController = TextEditingController(text: widget.item.qty.toString());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    final price = parseRupiah(_priceController.text);
    final qty = double.tryParse(_qtyController.text.replaceAll(',', '.')) ?? 0;
    if (name.isEmpty || price <= 0 || qty <= 0) return;
    Navigator.of(context)
        .pop(ReceiptItemDraft(name: name, price: price, qty: qty));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ubah item nota'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nama barang'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
              decoration: const InputDecoration(labelText: 'Harga satuan'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _qtyController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Jumlah barang'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppCopy.batal),
        ),
        FilledButton(onPressed: _save, child: const Text('Simpan item')),
      ],
    );
  }
}

class FirstTransactionGuide extends StatelessWidget {
  const FirstTransactionGuide({
    super.key,
    required this.isIncome,
    required this.onOpenLiability,
  });

  final bool isIncome;
  final VoidCallback onOpenLiability;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      color: scheme.primaryContainer.withValues(alpha: .42),
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        leading: Icon(Icons.flag_outlined, color: scheme.primary),
        title: const Text(
          'Mulai dari sini',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text('Ketuk kalau ini transaksi pertamamu'),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              isIncome
                  ? 'Pemasukan menambah saldo keluarga. Kalau ini uang pertama yang mau dicatat, langkah ini cocok untuk membuat titik awal saldo.'
                  : 'Pengeluaran mengurangi saldo keluarga. Kalau belum ada pemasukan yang dicatat, hasilnya bisa membuat saldo minus. Minus ini bukan otomatis hutang.',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              isIncome
                  ? 'Setelah itu, setiap pengeluaran akan mengurangi saldo yang sudah masuk.'
                  : 'Kalau uang pengeluaran memang berasal dari pinjaman, catat juga hutangnya supaya sisa cicilan dan dampaknya ikut terbaca.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          if (!isIncome) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onOpenLiability,
                icon: const Icon(Icons.credit_score_outlined),
                label: const Text('Buka catatan hutang'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
