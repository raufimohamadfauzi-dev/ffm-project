import 'package:flutter/material.dart';

import '../../../../shared/widgets/app_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../domain/entities/transaction_entity.dart';

enum TransactionDetailAction { edit, delete }

class TransactionDetailPage extends StatelessWidget {
  const TransactionDetailPage({
    super.key,
    required this.entry,
    this.categoryLabel,
    this.accountLabel,
    this.merchantLabel,
    this.onEdit,
    this.onDelete,
  });

  final TransactionWithItems entry;
  final String? categoryLabel;
  final String? accountLabel;
  final String? merchantLabel;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus transaksi?'),
        content: const Text(
          'Transaksi ini akan disembunyikan dari riwayat. Tindakan ini tidak menghapus data secara permanen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      if (onDelete != null) {
        onDelete!();
      } else {
        Navigator.of(context).pop(TransactionDetailAction.delete);
      }
    }
  }

  void _triggerEdit(BuildContext context) {
    if (onEdit != null) {
      onEdit!();
    } else {
      Navigator.of(context).pop(TransactionDetailAction.edit);
    }
  }

  @override
  Widget build(BuildContext context) {
    final transaction = entry.transaction;
    final isIncome = transaction.type == 'income';
    final isTransfer = transaction.type == 'transfer' || transaction.transferId != null;

    final itemsSubtotal = entry.items.fold<int>(
      0,
      (sum, it) => sum + (it.amount > 0 ? it.amount : (it.price * it.qty).round()),
    );

    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.transactions,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Detail transaksi'),
          actions: [
            IconButton(
              tooltip: 'Edit transaksi',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _triggerEdit(context),
            ),
            IconButton(
              tooltip: 'Hapus transaksi',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            AppCard(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isTransfer
                              ? 'Transfer Antar Rekening'
                              : (isIncome ? 'Uang masuk' : 'Uang keluar'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (transaction.source?.trim().isNotEmpty == true)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              transaction.source!.toUpperCase(),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    AppMoneyText(transaction.amount, compact: false),
                    const SizedBox(height: 14),
                    if (categoryLabel?.trim().isNotEmpty == true)
                      _DetailLine(label: 'Kategori', value: categoryLabel!),
                    if (accountLabel?.trim().isNotEmpty == true)
                      _DetailLine(label: 'Rekening', value: accountLabel!),
                    if (merchantLabel?.trim().isNotEmpty == true)
                      _DetailLine(label: 'Toko / Merchant', value: merchantLabel!),
                    if (transaction.receiptNumber?.trim().isNotEmpty == true)
                      _DetailLine(label: 'No. Nota', value: transaction.receiptNumber!),
                    if (transaction.receiptPaidAmount != null && transaction.receiptPaidAmount! > 0)
                      _DetailLine(label: 'Nominal Dibayar', value: 'Rp ${transaction.receiptPaidAmount}'),
                    if (transaction.receiptChangeAmount != null && transaction.receiptChangeAmount! > 0)
                      _DetailLine(label: 'Kembalian', value: 'Rp ${transaction.receiptChangeAmount}'),
                    if (transaction.location?.trim().isNotEmpty == true)
                      _DetailLine(
                        label: 'Lokasi',
                        value: transaction.location!,
                      ),
                    _DetailLine(
                      label: 'Sumber Input',
                      value: transaction.source ?? 'manual',
                    ),
                    Text(
                      'Kejadian: ${transaction.date.day}/${transaction.date.month}/${transaction.date.year} ${transaction.date.hour.toString().padLeft(2, '0')}:${transaction.date.minute.toString().padLeft(2, '0')}:${transaction.date.second.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'Dicatat: ${transaction.recordedAt.day}/${transaction.recordedAt.month}/${transaction.recordedAt.year} ${transaction.recordedAt.hour.toString().padLeft(2, '0')}:${transaction.recordedAt.minute.toString().padLeft(2, '0')}:${transaction.recordedAt.second.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (transaction.partyName?.trim().isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          'Dipakai oleh / sumber: ${transaction.partyName}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (transaction.note?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          transaction.note!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (entry.items.isNotEmpty) ...[
              const SizedBox(height: 12),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Rincian belanja',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '${entry.items.length} item',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    ...entry.items.map(
                      (item) {
                        final itemSubtotal = item.amount > 0 ? item.amount : (item.price * item.qty).round();
                        return ListTile(
                          dense: true,
                          title: Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            'Jumlah: ${item.qty} ${item.unit ?? 'item'} · Harga satuan: Rp ${item.price}',
                          ),
                          trailing: AppMoneyText(
                            itemSubtotal,
                            compact: true,
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Subtotal Item',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          AppMoneyText(itemsSubtotal, compact: false),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (entry.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              AppCard(
                child: ListTile(
                  leading: const Icon(Icons.sell_outlined),
                  title: Text(entry.tags.join(', ')),
                ),
              ),
            ],
            if (transaction.receiptRawText?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 12),
              AppCard(
                child: ExpansionTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text(
                    'Teks Mentah Nota / OCR',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          transaction.receiptRawText!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Hapus'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(color: Theme.of(context).colorScheme.error),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _confirmDelete(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _triggerEdit(context),
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

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
