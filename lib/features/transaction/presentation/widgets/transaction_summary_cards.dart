import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../domain/entities/transaction_entity.dart';

class TransferHistoryCard extends StatelessWidget {
  const TransferHistoryCard({
    super.key,
    required this.transfer,
    required this.fromLabel,
    required this.toLabel,
    required this.dateLabel,
    required this.onDelete,
    this.onEdit,
  });

  final Transfer transfer;
  final String fromLabel;
  final String toLabel;
  final String Function(DateTime) dateLabel;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AppCard(
      color: AppColors.primarySoft.withValues(alpha: .48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: color.withValues(alpha: .14),
            foregroundColor: color,
            child: const Icon(Icons.swap_horiz_rounded, size: 25),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppStatusChip(
                  label: 'Transfer',
                  color: color,
                  backgroundColor: color.withValues(alpha: .14),
                ),
                const SizedBox(height: 7),
                Text(
                  fromLabel.isEmpty ? 'Rekening asal' : fromLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: Icon(Icons.arrow_downward_rounded, size: 16),
                ),
                Text(
                  toLabel.isEmpty ? 'Rekening tujuan' : toLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (transfer.note?.isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(
                    transfer.note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 4),
                HijriDateText(
                  date: transfer.date,
                  includeSeconds: true,
                  compact: true,
                  color: AppColors.inkMuted,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Pindah',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
              AppMoneyText(transfer.amount, compact: true, color: color),
              if (transfer.adminFee > 0)
                Text(
                  'Admin ${formatRupiahInput(transfer.adminFee.toString())}',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: AppColors.inkMuted),
                ),
              PopupMenuButton<String>(
                tooltip: 'Aksi transfer',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onSelected: (value) {
                  if (value == 'edit') onEdit?.call();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  if (onEdit != null)
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit transfer'),
                    ),
                  const PopupMenuItem(value: 'delete', child: Text('Hapus transfer')),
                ],
                icon: const Icon(Icons.more_vert),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AccountBalancesCard extends StatelessWidget {
  const AccountBalancesCard({
    super.key,
    required this.accounts,
    required this.transactions,
    required this.transfers,
    required this.accountTypeLabel,
  });

  final List<Account> accounts;
  final List<TransactionWithItems> transactions;
  final List<Transfer> transfers;
  final String Function(String) accountTypeLabel;

  int _balance(Account account) {
    final transactionTotal = transactions
        .where((entry) => entry.transaction.accountId == account.id)
        .fold<int>(0, (sum, entry) => sum + entry.transaction.amount);
    final incoming = transfers
        .where((transfer) => transfer.toAccountId == account.id)
        .fold<int>(0, (sum, transfer) => sum + transfer.amount);
    final outgoing = transfers
        .where((transfer) => transfer.fromAccountId == account.id)
        .fold<int>(0, (sum, transfer) => sum + transfer.amount);
    return account.openingBalance + transactionTotal + incoming - outgoing;
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Saldo per rekening',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                'Saldo saat ini · transfer ikut dihitung',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.inkMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (accounts.isEmpty)
            const Text('Belum ada rekening. Tambahkan lewat Data Utama.')
          else
            ...accounts.map((account) {
              final balance = _balance(account);
              final color = balance >= 0
                  ? AppColors.positive
                  : AppColors.negative;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 8, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            account.name,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            accountTypeLabel(account.type),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    AppMoneyText(balance, compact: true, color: color),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class TransactionFlowSummary extends StatelessWidget {
  const TransactionFlowSummary({
    super.key,
    required this.incomeTotal,
    required this.expenseTotal,
    required this.transactionCount,
    required this.transferCount,
  });

  final int incomeTotal;
  final int expenseTotal;
  final int transactionCount;
  final int transferCount;

  @override
  Widget build(BuildContext context) {
    final net = incomeTotal - expenseTotal;
    final netColor = net >= 0 ? AppColors.positive : AppColors.negative;
    return AppCard(
      color: AppColors.primarySoft.withValues(alpha: .82),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ringkasan transaksi',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${transactionCount + transferCount} catatan',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.inkMuted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TransactionFlowTile(
                  label: 'Pemasukan',
                  amount: incomeTotal,
                  color: AppColors.positive,
                  icon: Icons.south_west_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TransactionFlowTile(
                  label: 'Pengeluaran',
                  amount: expenseTotal,
                  color: AppColors.negative,
                  icon: Icons.north_east_rounded,
                ),
              ),
            ],
          ),
          if (transferCount > 0) ...[
            const SizedBox(height: 10),
            Text(
              '$transferCount transfer tidak mengubah total pemasukan atau pengeluaran.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.inkMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Selisih arus kas',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: AppMoneyText(net, compact: true, color: netColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class TransactionFlowTile extends StatelessWidget {
  const TransactionFlowTile({
    super.key,
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  final String label;
  final int amount;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: .4,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AppMoneyText(amount, compact: true, color: color),
          ),
        ],
      ),
    );
  }
}
