import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart' show getIt;
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../../recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: .14),
            foregroundColor: color,
            child: const Icon(Icons.swap_horiz_rounded, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppStatusChip(
                      label: 'Transfer',
                      color: color,
                      backgroundColor: color.withValues(alpha: .14),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        fromLabel.isEmpty ? 'Rekening asal' : fromLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.arrow_forward_rounded, size: 13),
                    ),
                    Flexible(
                      child: Text(
                        toLabel.isEmpty ? 'Rekening tujuan' : toLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (transfer.note?.isNotEmpty == true) ...[
                      Flexible(
                        child: Text(
                          transfer.note!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.inkMuted,
                                fontSize: 11,
                              ),
                        ),
                      ),
                      const Text(
                        ' · ',
                        style: TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    HijriDateText(
                      date: transfer.date,
                      includeSeconds: false,
                      compact: true,
                      color: AppColors.inkMuted,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AppMoneyText(transfer.amount, compact: true, color: color),
              if (transfer.adminFee > 0)
                Text(
                  'Admin ${formatRupiahInput(transfer.adminFee.toString())}',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: AppColors.inkMuted, fontSize: 10),
                ),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: 'Aksi transfer',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.more_vert, size: 18),
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
              const PopupMenuItem(
                value: 'delete',
                child: Text('Hapus transfer'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AccountBalancesCard extends StatefulWidget {
  const AccountBalancesCard({
    super.key,
    required this.householdId,
    required this.accounts,
  });

  final String householdId;
  final List<Account> accounts;

  @override
  State<AccountBalancesCard> createState() => _AccountBalancesCardState();
}

class _AccountBalancesCardState extends State<AccountBalancesCard> {
  var _balances = <String, int>{};
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBalances();
  }

  @override
  void didUpdateWidget(covariant AccountBalancesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accounts != widget.accounts ||
        oldWidget.householdId != widget.householdId) {
      _loadBalances();
    }
  }

  Future<void> _loadBalances() async {
    setState(() {
      _loading = true;
      _balances = <String, int>{};
    });
    final service = getIt<GetAccountBookBalance>();
    final balances = <String, int>{};
    for (final account in widget.accounts) {
      balances[account.id] = await service(
        widget.householdId,
        account.id,
      );
    }
    if (!mounted) return;
    setState(() {
      _balances = balances;
      _loading = false;
    });
  }

  int _balance(Account account) => _balances[account.id] ?? 0;

  @override
  Widget build(BuildContext context) {
    final accounts = widget.accounts;
    return AppCard(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Saldo rekening',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${accounts.length} rekening aktif',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.inkMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (accounts.isEmpty)
            const Text(
              'Belum ada rekening. Tambahkan lewat Data Utama.',
              style: TextStyle(fontSize: 12),
            )
          else if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: accounts.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final account = accounts[i];
                  final balance = _balance(account);
                  final color = balance >= 0
                      ? AppColors.positive
                      : AppColors.negative;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant
                            .withValues(alpha: .4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 7, color: color),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              account.name,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            AppMoneyText(balance, compact: true, color: color),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Ringkasan transaksi',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${transactionCount + transferCount} catatan',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.inkMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
              const SizedBox(width: 8),
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
            const SizedBox(height: 6),
            Text(
              '$transferCount transfer tidak mengubah total pemasukan atau pengeluaran.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.inkMuted,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Selisih arus kas',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.inkMuted, fontSize: 11.5),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: AppMoneyText(net, compact: true, color: netColor),
                ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
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
