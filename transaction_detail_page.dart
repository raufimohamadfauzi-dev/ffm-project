import 'package:flutter/material.dart';

import '../../../../shared/widgets/app_components.dart';
import '../../domain/entities/transaction_entity.dart';

class TransactionDetailPage extends StatelessWidget {
  const TransactionDetailPage({super.key, required this.entry});

  final TransactionWithItems entry;

  @override
  Widget build(BuildContext context) {
    final transaction = entry.transaction;
    final isIncome = transaction.type == 'income';
    return Scaffold(
      appBar: AppBar(title: const Text('Detail transaksi')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isIncome ? 'Uang masuk' : 'Uang keluar', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  AppMoneyText(transaction.amount, compact: false),
                  const SizedBox(height: 14),
                  Text('Kejadian: ${transaction.date.day}/${transaction.date.month}/${transaction.date.year} ${transaction.date.hour.toString().padLeft(2, '0')}:${transaction.date.minute.toString().padLeft(2, '0')}:${transaction.date.second.toString().padLeft(2, '0')}'),
                  Text('Dicatat: ${transaction.recordedAt.day}/${transaction.recordedAt.month}/${transaction.recordedAt.year} ${transaction.recordedAt.hour.toString().padLeft(2, '0')}:${transaction.recordedAt.minute.toString().padLeft(2, '0')}:${transaction.recordedAt.second.toString().padLeft(2, '0')}'),
                  if (transaction.partyName?.trim().isNotEmpty == true) Text('Dipakai oleh / sumber: ${transaction.partyName}'),
                  if (transaction.note?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text(transaction.note!),
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
                  const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('Rincian belanja', style: TextStyle(fontWeight: FontWeight.w800))),
                  ...entry.items.map(
                    (item) => ListTile(
                      title: Text(item.itemName),
                      subtitle: Text('${item.qty} ${item.unit ?? ''}'),
                      trailing: AppMoneyText(item.amount > 0 ? item.amount : item.price, compact: true),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (entry.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            AppCard(child: ListTile(leading: const Icon(Icons.sell_outlined), title: Text(entry.tags.join(', ')))),
          ],
        ],
      ),
    );
  }
}
