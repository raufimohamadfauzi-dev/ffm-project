import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../transaction/domain/entities/transaction_entity.dart';
import '../../../transaction/domain/usecases/transaction_crud_usecases.dart';
import '../../../transaction/presentation/pages/transaction_form_page.dart';
import '../../data/payment_draft_repository.dart';
import '../../data/payment_notification_parser.dart';

/// Kartu interaktif di Beranda / Asisten untuk mengonfirmasi transaksi yang
/// terdeteksi secara otomatis dari notifikasi perbankan & e-wallet (QRIS/Bank).
///
/// Menyediakan aksi 1-ketukan:
/// - [Simpan]: Menyimpan transaksi langsung ke database secara deterministik.
/// - [Edit]: Membuka form transaksi dengan data yang sudah terisi otomatis.
/// - [Abaikan]: Menghapus draft dari daftar tunggu.
class PendingPaymentDraftsCard extends StatefulWidget {
  const PendingPaymentDraftsCard({
    super.key,
    this.onDraftProcessed,
  });

  final VoidCallback? onDraftProcessed;

  @override
  State<PendingPaymentDraftsCard> createState() =>
      _PendingPaymentDraftsCardState();
}

class _PendingPaymentDraftsCardState extends State<PendingPaymentDraftsCard>
    with WidgetsBindingObserver {
  late final PaymentDraftRepository _draftRepo;
  List<PaymentDraft> _pendingDrafts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _draftRepo = getIt<PaymentDraftRepository>();
    _loadPendingDrafts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPendingDrafts();
    }
  }

  Future<void> _loadPendingDrafts() async {
    try {
      final drafts = await _draftRepo.getPendingDrafts();
      if (mounted) {
        setState(() {
          _pendingDrafts = drafts;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _confirmDraft(PaymentDraft draft) async {
    try {
      final db = getIt<AppDatabase>();
      final isDebit = draft.mutationType == PaymentMutationType.debit;
      final signedAmount =
          isDebit ? -draft.amount.round() : draft.amount.round();
      final txId = 'tx_notif_${draft.id}';

      // 1. Cari akun yang cocok berdasarkan sourceApp & accountLabel
      final accounts = await (db.select(db.accounts)
            ..where((a) => a.isArchived.equals(false)))
          .get();
      Account? matchedAccount;
      final lowerSource = draft.sourceApp.toLowerCase();
      final lowerLabel = draft.accountLabel.toLowerCase();

      for (final a in accounts) {
        final aName = a.name.toLowerCase();
        if (lowerLabel.contains('seabank') || lowerSource.contains('seabank')) {
          if (aName.contains('seabank')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('gopay') ||
            lowerSource.contains('gojek') ||
            lowerSource.contains('gopay')) {
          if (aName.contains('gopay') || aName.contains('gojek')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('bca') || lowerSource.contains('bca')) {
          if (aName.contains('bca')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('mandiri') ||
            lowerSource.contains('mandiri')) {
          if (aName.contains('mandiri')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('bri') || lowerSource.contains('bri')) {
          if (aName.contains('bri')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('bni') ||
            lowerSource.contains('bni') ||
            lowerSource.contains('wondr')) {
          if (aName.contains('bni') || aName.contains('wondr')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('dana') ||
            lowerSource.contains('dana')) {
          if (aName.contains('dana')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('ovo') || lowerSource.contains('ovo')) {
          if (aName.contains('ovo')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('shopee') ||
            lowerSource.contains('shopee')) {
          if (aName.contains('shopee')) {
            matchedAccount = a;
            break;
          }
        } else if (aName.contains(lowerLabel)) {
          matchedAccount = a;
          break;
        }
      }
      matchedAccount ??= accounts.isNotEmpty ? accounts.first : null;

      // 2. Cari kategori yang cocok
      final categories = await (db.select(db.categories)
            ..where((c) => c.isActive.equals(true)))
          .get();
      Category? matchedCategory;
      if (draft.suggestedCategory != null) {
        final targetCat = draft.suggestedCategory!.toLowerCase();
        for (final c in categories) {
          if (c.name.toLowerCase().contains(targetCat) ||
              targetCat.contains(c.name.toLowerCase())) {
            matchedCategory = c;
            break;
          }
        }
      }
      if (matchedCategory == null) {
        final targetType = isDebit ? 'expense' : 'income';
        matchedCategory =
            categories.where((c) => c.type == targetType).firstOrNull ??
                categories.firstOrNull;
      }

      // 3. Simpan transaksi secara nyata ke database
      final saveTx = getIt.isRegistered<SaveTransaction>()
          ? getIt<SaveTransaction>()
          : SaveTransaction(db);

      await saveTx(
        TransactionEntity(
          id: txId,
          householdId: AppContext.householdId,
          date: draft.createdAt,
          amount: signedAmount,
          owner: 'Asisten (Notifikasi)',
          categoryId: matchedCategory?.id,
          accountId: matchedAccount?.id,
          note:
              'Otomatis dari notifikasi ${draft.accountLabel}${draft.merchantName.isNotEmpty ? ' (${draft.merchantName})' : ''}',
          source: 'notification_detector',
          sourceId: draft.id,
          partyName: draft.merchantName.isNotEmpty ? draft.merchantName : null,
          recordedAt: DateTime.now(),
        ),
      );

      await _draftRepo.updateStatus(draft.id, PaymentDraftStatus.confirmed);
      await _loadPendingDrafts();
      widget.onDraftProcessed?.call();

      if (mounted) {
        final targetInfo =
            matchedAccount != null ? ' ke ${matchedAccount.name}' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Transaksi ${draft.formattedAmount} berhasil disimpan$targetInfo.',
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan transaksi: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _editDraft(PaymentDraft draft) async {
    final isDebit = draft.mutationType == PaymentMutationType.debit;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionFormPage(
          initialType:
              isDebit ? TransactionType.expense : TransactionType.income,
          initialAmount: draft.amount.round(),
          initialDate: draft.createdAt,
          initialAccountName: draft.accountLabel,
          initialCategoryName: draft.suggestedCategory,
          initialPartyName:
              draft.merchantName.isNotEmpty ? draft.merchantName : null,
          initialNote:
              'Otomatis dari notifikasi ${draft.accountLabel}${draft.merchantName.isNotEmpty ? ' (${draft.merchantName})' : ''}',
        ),
      ),
    );

    if (saved == true) {
      await _draftRepo.updateStatus(draft.id, PaymentDraftStatus.confirmed);
      await _loadPendingDrafts();
      widget.onDraftProcessed?.call();
    }
  }

  Future<void> _dismissDraft(PaymentDraft draft) async {
    await _draftRepo.updateStatus(draft.id, PaymentDraftStatus.dismissed);
    await _loadPendingDrafts();
    widget.onDraftProcessed?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Draft ${draft.formattedAmount} diabaikan.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _pendingDrafts.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Notifikasi Pembayaran Terdeteksi',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_pendingDrafts.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _pendingDrafts.length,
            separatorBuilder: (_, index) =>
                const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (context, index) {
              final draft = _pendingDrafts[index];
              final isExpense =
                  draft.mutationType == PaymentMutationType.debit;
              final amountColor =
                  isExpense ? Colors.red.shade400 : Colors.green.shade500;
              final prefix = isExpense ? '-' : '+';

              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isExpense
                                    ? Icons.account_balance_wallet_outlined
                                    : Icons.savings_outlined,
                                size: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                draft.accountLabel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatTimeAgo(draft.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$prefix${draft.formattedAmount}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: amountColor,
                          ),
                        ),
                        if (draft.suggestedCategory != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '• ${draft.suggestedCategory}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (draft.merchantName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        isExpense
                            ? 'Ke: ${draft.merchantName}'
                            : 'Dari: ${draft.merchantName}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => _dismissDraft(draft),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Abaikan'),
                          style: TextButton.styleFrom(
                            foregroundColor: colorScheme.error,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _editDraft(draft),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Edit'),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () => _confirmDraft(draft),
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Simpan'),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mnt lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    return '${diff.inDays} hari lalu';
  }
}
