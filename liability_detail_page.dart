import 'package:flutter/material.dart';

import '../../../../shared/widgets/app_components.dart';
import '../../domain/entities/liability_entity.dart';

class LiabilityDetailPage extends StatelessWidget {
  const LiabilityDetailPage({super.key, required this.liability});

  final LiabilityEntity liability;

  @override
  Widget build(BuildContext context) {
    final progress = liability.originalAmount <= 0
        ? 0.0
        : (1 - liability.remainingBalance / liability.originalAmount).clamp(0.0, 1.0);
    return Scaffold(
      appBar: AppBar(title: const Text('Detail hutang')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(liability.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 18),
                  Text('Sisa hutang', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  AppMoneyText(liability.remainingBalance, compact: false),
                  const SizedBox(height: 14),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 8),
                  Text('${(progress * 100).round()}% sudah terbayar dari ${formatRupiahInput(liability.originalAmount.toString())}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              children: [
                ListTile(title: const Text('Cicilan per bulan'), trailing: AppMoneyText(liability.monthlyInstallment, compact: true)),
                ListTile(title: const Text('Jatuh tempo'), trailing: Text('${liability.dueDate.day}/${liability.dueDate.month}/${liability.dueDate.year}')),
                if (liability.interestRate != null) ListTile(title: const Text('Bunga'), trailing: Text('${liability.interestRate!.toStringAsFixed(2)}%')),
                if (liability.note?.trim().isNotEmpty == true) ListTile(title: const Text('Catatan'), subtitle: Text(liability.note!)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
