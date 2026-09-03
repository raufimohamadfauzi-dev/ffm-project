import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/audit_logger.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../core/ownership/owner_labels.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/date_time_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../data/services/receipt_import_service.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/usecases/transaction_crud_usecases.dart';
import 'transaction_detail_page.dart';
import 'transaction_form_page.dart';
import 'goal_contribution_form_page.dart';
import 'json_transaction_batch_page.dart';
import 'quick_transaction_batch_page.dart';
import '../widgets/new_entry_sheet.dart';
import '../widgets/transfer_form_dialog.dart';
import '../widgets/voice_review_widgets.dart';
import '../widgets/transaction_summary_cards.dart';
import '../widgets/transaction_filter_sheet.dart';
import '../../../goal/domain/usecases/goal_balance_usecases.dart';
import '../../../recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';
import '../../../settings/presentation/pages/master_data_page.dart';
import '../../../assistant/data/ffm_assistant_personalization_repository.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/domain/ffm_assistant_form_prefill.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';

class TransactionListPage extends StatefulWidget {
  const TransactionListPage({
    super.key,
    this.assistantDraft,
    this.assistantRequestId = 0,
    this.onOpenAssistant,
    this.onAssistantDraftSaved,
    this.onAssistantDraftReturnedWithoutSave,
  });

  final FfmAssistantDraft? assistantDraft;
  final int assistantRequestId;
  final Future<void> Function()? onOpenAssistant;
  final Future<void> Function()? onAssistantDraftSaved;
  final Future<void> Function()? onAssistantDraftReturnedWithoutSave;

  @override
  State<TransactionListPage> createState() => _TransactionListPageState();
}

class _TransactionListPageState extends State<TransactionListPage> {
  final _transactions = <TransactionWithItems>[];
  var _categories = <Category>[];
  var _merchants = <Merchant>[];
  var _accounts = <Account>[];
  var _transfers = <Transfer>[];
  Set<String>? _ftsTransactionIds;
  var _loading = true;
  String? _errorMessage;
  var _query = '';
  var _typeFilter = 'Semua';
  var _currentMonthOnly = false;
  String? _accountFilter;
  String? _categoryFilter;
  String? _merchantFilter;
  String? _ownerFilter;
  DateTime? _startDateFilter;
  DateTime? _endDateFilter;
  var _isSearchOpen = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  @override
  void didUpdateWidget(covariant TransactionListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.assistantRequestId == oldWidget.assistantRequestId ||
        widget.assistantDraft == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openAssistantDraft(widget.assistantDraft!);
    });
  }

  Future<void> _openAssistantDraft(FfmAssistantDraft draft) async {
    switch (draft.kind) {
      case FfmAssistantDraftKind.income:
      case FfmAssistantDraftKind.expense:
        if (_canSaveAssistantTransactionDirectly(draft)) {
          await _saveAssistantTransactionDirectly(draft);
          await widget.onAssistantDraftSaved?.call();
          return;
        }
        final prefill = FfmAssistantFormPrefillMapper.fromDraft(draft);
        final drafts = await Navigator.of(context).push<List<TransactionDraft>>(
          MaterialPageRoute(
            builder: (_) => TransactionFormPage(
              initialType: draft.kind == FfmAssistantDraftKind.income
                  ? TransactionType.income
                  : TransactionType.expense,
              initialAmount: int.tryParse(prefill.values['amount'] ?? ''),
              initialAccountName:
                  prefill.values[draft.kind == FfmAssistantDraftKind.income
                      ? 'toAccountName'
                      : 'fromAccountName'],
              initialCategoryName: prefill.values['categoryName'],
              initialNote: prefill.values['note'],
              initialDate: draft.date,
              initialPartyName: prefill.values['partyName'] ?? draft.partyName,
              assistantMerchantName: draft.merchantName,
              assistantSlmFieldValues: draft.slmFieldValues,
              assistantPrefill: prefill,
              onReturnToAssistant: widget.onOpenAssistant,
            ),
          ),
        );
        if (!mounted || drafts == null || drafts.isEmpty) {
          await widget.onAssistantDraftReturnedWithoutSave?.call();
          return;
        }
        await _saveDrafts(drafts);
        await widget.onAssistantDraftSaved?.call();
      case FfmAssistantDraftKind.goalDeposit:
        final saved = await _openGoalContribution(assistantDraft: draft);
        if (saved) {
          await widget.onAssistantDraftSaved?.call();
        } else {
          await widget.onAssistantDraftReturnedWithoutSave?.call();
        }
      case FfmAssistantDraftKind.goalUsage:
        final saved = await _openGoalContribution(
          usage: true,
          assistantDraft: draft,
        );
        if (saved) {
          await widget.onAssistantDraftSaved?.call();
        } else {
          await widget.onAssistantDraftReturnedWithoutSave?.call();
        }
      case FfmAssistantDraftKind.transfer:
        if (_canSaveAssistantTransferDirectly(draft)) {
          final saved = await _saveAssistantTransferDirectly(draft);
          if (!mounted) return;
          if (saved) {
            await widget.onAssistantDraftSaved?.call();
          } else {
            await widget.onAssistantDraftReturnedWithoutSave?.call();
          }
          return;
        }
        final saved = await _openTransfer(assistantDraft: draft);
        if (!mounted) return;
        if (saved) {
          await widget.onAssistantDraftSaved?.call();
        } else {
          await widget.onAssistantDraftReturnedWithoutSave?.call();
        }
      default:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Form untuk tipe draft ini belum mendukung prefill otomatis. Silakan buka halaman terkait secara manual.',
              ),
            ),
          );
        }
        return;
    }
  }

  bool _canSaveAssistantTransactionDirectly(FfmAssistantDraft draft) {
    final amount = draft.amount;
    final date = draft.date;
    final title = draft.title?.trim();
    if (amount == null ||
        amount <= 0 ||
        date == null ||
        title == null ||
        title.isEmpty) {
      return false;
    }
    final categoryId = assistantCategoryIdForDraft(draft);
    return categoryId != null && assistantAccountIdForDraft(draft) != null;
  }

  String? assistantCategoryIdForDraft(FfmAssistantDraft draft) {
    final targetName = draft.categoryName?.trim().toLowerCase();
    if (targetName == null || targetName.isEmpty) return null;
    final targetType = draft.kind == FfmAssistantDraftKind.income
        ? 'income'
        : 'expense';
    return _categories
        .where(
          (category) =>
              category.type == targetType &&
              category.name.trim().toLowerCase() == targetName,
        )
        .firstOrNull
        ?.id;
  }

  String? assistantAccountIdForDraft(FfmAssistantDraft draft) {
    return _assistantAccountIdByName(draft.toAccountName);
  }

  String? _assistantAccountIdByName(String? name) {
    final targetName = name?.trim().toLowerCase();
    if (targetName == null || targetName.isEmpty) return null;
    return _accounts
        .where((account) => account.name.trim().toLowerCase() == targetName)
        .firstOrNull
        ?.id;
  }

  Future<void> _saveAssistantTransactionDirectly(
    FfmAssistantDraft draft,
  ) async {
    final categoryId = assistantCategoryIdForDraft(draft);
    final accountId = assistantAccountIdForDraft(draft);
    if (categoryId == null ||
        accountId == null ||
        draft.amount == null ||
        draft.date == null) {
      return;
    }
    final merchantId = draft.merchantName != null
        ? _merchants
            .where((m) =>
                m.name.trim().toLowerCase() ==
                draft.merchantName!.trim().toLowerCase())
            .firstOrNull
            ?.id
        : null;

    final receiptNumber = draft.formValues['receiptNumber'];
    final receiptPaidAmount = int.tryParse(draft.formValues['receiptPaidAmount'] ?? '');
    final receiptChangeAmount = int.tryParse(draft.formValues['receiptChangeAmount'] ?? '');
    final receiptRawText = draft.formValues['receiptRawText'];
    var items = const <ReceiptItemDraft>[];
    if (draft.formValues['itemsJson']?.isNotEmpty == true) {
      try {
        final decoded = jsonDecode(draft.formValues['itemsJson']!);
        if (decoded is List) {
          items = decoded
              .map((item) {
                if (item is Map) {
                  final name = item['name']?.toString() ??
                      item['itemName']?.toString() ??
                      '';
                  final price =
                      int.tryParse(item['price']?.toString() ?? '0') ?? 0;
                  final qty =
                      double.tryParse(item['qty']?.toString() ??
                          item['quantity']?.toString() ??
                          '1') ??
                      1.0;
                  return ReceiptItemDraft(name: name, price: price, qty: qty);
                }
                return null;
              })
              .whereType<ReceiptItemDraft>()
              .where((item) => item.name.isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }

    final transactionDraft = TransactionDraft(
      type: draft.kind == FfmAssistantDraftKind.income
          ? TransactionType.income
          : TransactionType.expense,
      categoryId: categoryId,
      owner: OwnerLabels.family,
      date: draft.date!,
      amount: draft.amount!,
      note: draft.note ?? '',
      source: 'assistant',
      accountId: accountId,
      merchantId: merchantId,
      goalId: null,
      partyName: draft.partyName,
      receiptRawText: receiptRawText,
      receiptNumber: receiptNumber,
      receiptPaidAmount: receiptPaidAmount,
      receiptChangeAmount: receiptChangeAmount,
      items: items,
      assistantMerchantName: draft.merchantName,
      assistantSlmFieldValues: draft.slmFieldValues,
    );
    await _saveDrafts([transactionDraft]);
  }

  bool _canSaveAssistantTransferDirectly(FfmAssistantDraft draft) {
    final amount = draft.amount;
    final date = draft.date;
    final fromAccountId = _assistantAccountIdByName(draft.fromAccountName);
    final toAccountId = _assistantAccountIdByName(draft.toAccountName);
    return amount != null &&
        amount > 0 &&
        date != null &&
        fromAccountId != null &&
        toAccountId != null;
  }

  Future<bool> _saveAssistantTransferDirectly(FfmAssistantDraft draft) async {
    final fromAccountId = _assistantAccountIdByName(draft.fromAccountName);
    final toAccountId = _assistantAccountIdByName(draft.toAccountName);
    final amount = draft.amount;
    final date = draft.date;
    if (fromAccountId == null ||
        toAccountId == null ||
        amount == null ||
        amount <= 0 ||
        date == null) {
      return false;
    }
    final transfer = TransferDraft(
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      amount: amount,
      adminFee: draft.adminFee ?? 0,
      date: date,
      note: draft.note ?? '',
    );
    final now = DateTime.now();
    final transferDate = DateTime(
      transfer.date.year,
      transfer.date.month,
      transfer.date.day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
      now.microsecond,
    );
    final id = const Uuid().v4();
    final feeTransactionId = transfer.adminFee > 0 ? const Uuid().v4() : null;
    final database = getIt<AppDatabase>();
    Category? feeCategory;
    if (transfer.adminFee > 0) {
      feeCategory =
          await (database.select(database.categories)..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.type.equals('expense') &
                    row.name.equals('Biaya admin') &
                    row.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (feeCategory == null) return false;
    }
    await database.transaction(() async {
      if (transfer.adminFee > 0) {
        await database
            .into(database.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: feeTransactionId!,
                householdId: AppContext.householdId,
                type: 'expense',
                date: transferDate,
                recordedAt: now,
                amount: -transfer.adminFee,
                owner: const Value('Keluarga'),
                categoryId: Value(feeCategory!.id),
                note: Value(
                  'Biaya admin transfer ${_accountLabel(transfer.fromAccountId)} ke ${_accountLabel(transfer.toAccountId)}',
                ),
                source: const Value('transfer_fee'),
                accountId: Value(transfer.fromAccountId),
                merchantId: const Value(null),
                goalId: const Value(null),
                createdAt: now,
                updatedAt: Value(now),
                isDeleted: const Value(false),
              ),
            );
      }
      await database
          .into(database.transfers)
          .insert(
            TransfersCompanion.insert(
              id: id,
              householdId: AppContext.householdId,
              date: transferDate,
              recordedAt: now,
              amount: transfer.amount,
              adminFee: Value(transfer.adminFee),
              feeTransactionId: Value(feeTransactionId),
              fromAccountId: transfer.fromAccountId,
              toAccountId: transfer.toAccountId,
              note: Value(transfer.note.isEmpty ? null : transfer.note),
              source: const Value('assistant'),
              updatedAt: Value(now),
            ),
          );
    });
    await AuditLogger(database).record(
      action: 'tambah',
      entity: 'transfer',
      newValue: {
        'id': id,
        'amount': transfer.amount,
        'from_account_id': transfer.fromAccountId,
        'to_account_id': transfer.toAccountId,
        'admin_fee': transfer.adminFee,
        'source': 'assistant',
      },
    );
    await _loadTransactions();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transfer berhasil dicatat.')),
      );
    }
    return true;
  }

  Future<void> _loadTransactions() async {
    try {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
      final transactions = await getIt<GetTransactions>()(AppContext.householdId);
      final database = getIt<AppDatabase>();
      final categories =
          await (database.select(database.categories)
                ..where(
                  (table) =>
                      table.householdId.equals(AppContext.householdId) &
                      table.isActive.equals(true),
                )
                ..orderBy([(table) => OrderingTerm.asc(table.name)]))
              .get();
      final merchants =
          await (database.select(database.merchants)
                ..where(
                  (table) =>
                      table.householdId.equals(AppContext.householdId) &
                      table.isActive.equals(true),
                )
                ..orderBy([(table) => OrderingTerm.asc(table.name)]))
              .get();
      final accounts =
          await (database.select(database.accounts)
                ..where(
                  (table) =>
                      table.householdId.equals(AppContext.householdId) &
                      table.isArchived.equals(false),
                )
                ..orderBy([(table) => OrderingTerm.asc(table.name)]))
              .get();
      final transfers =
          await (database.select(database.transfers)
                ..where(
                  (table) =>
                      table.householdId.equals(AppContext.householdId) &
                      table.isDeleted.equals(false),
                )
                ..orderBy([(table) => OrderingTerm.desc(table.date)]))
              .get();
      if (!mounted) return;
      setState(() {
        _transactions
          ..clear()
          ..addAll(transactions);
        _categories = categories;
        _merchants = merchants;
        _accounts = accounts;
        _transfers = transfers;
        _loading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Gagal memuat transaksi: $e';
      });
    }
  }

  Future<bool> _openTransfer({
    FfmAssistantDraft? assistantDraft,
    Transfer? existingTransfer,
  }) async {
    if (_accounts.length < 2) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tambahkan minimal dua rekening di Data Utama dulu.'),
        ),
      );
      return false;
    }
    final draft = await showDialog<TransferDraft>(
      context: context,
      builder: (_) => TransferFormDialog(
        accounts: _accounts,
        assistantDraft: assistantDraft,
        existingTransfer: existingTransfer,
      ),
    );
    if (!mounted || draft == null) return false;
    final now = DateTime.now();
    final transferDate = DateTime(
      draft.date.year,
      draft.date.month,
      draft.date.day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
      now.microsecond,
    );
    final isEditing = existingTransfer != null;
    final id = existingTransfer?.id ?? const Uuid().v4();
    String? feeTransactionId = existingTransfer?.feeTransactionId;
    if (draft.adminFee > 0 && feeTransactionId == null) {
      feeTransactionId = const Uuid().v4();
    }
    final database = getIt<AppDatabase>();
    Category? feeCategory;
    if (draft.adminFee > 0) {
      feeCategory =
          await (database.select(database.categories)..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.type.equals('expense') &
                    row.name.equals('Biaya admin') &
                    row.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (feeCategory == null) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kategori Biaya Admin belum tersedia di Data Utama.'),
          ),
        );
        return false;
      }
    }
    await database.transaction(() async {
      if (draft.adminFee > 0) {
        if (isEditing && existingTransfer.feeTransactionId != null) {
          await (database.update(database.transactions)
                ..where((t) => t.id.equals(existingTransfer.feeTransactionId!)))
              .write(
                TransactionsCompanion(
                  date: Value(transferDate),
                  amount: Value(-draft.adminFee),
                  accountId: Value(draft.fromAccountId),
                  categoryId: Value(feeCategory!.id),
                  note: Value(
                    'Biaya admin transfer ${_accountLabel(draft.fromAccountId)} ke ${_accountLabel(draft.toAccountId)}',
                  ),
                  updatedAt: Value(now),
                  isDeleted: const Value(false),
                ),
              );
        } else {
          await database.into(database.transactions).insert(
                TransactionsCompanion.insert(
                  id: feeTransactionId!,
                  householdId: AppContext.householdId,
                  type: 'expense',
                  date: transferDate,
                  recordedAt: now,
                  amount: -draft.adminFee,
                  owner: const Value('Keluarga'),
                  categoryId: Value(feeCategory!.id),
                  note: Value(
                    'Biaya admin transfer ${_accountLabel(draft.fromAccountId)} ke ${_accountLabel(draft.toAccountId)}',
                  ),
                  source: const Value('transfer_fee'),
                  accountId: Value(draft.fromAccountId),
                  merchantId: const Value(null),
                  goalId: const Value(null),
                  createdAt: now,
                  updatedAt: Value(now),
                  isDeleted: const Value(false),
                ),
              );
        }
      } else if (isEditing && existingTransfer.feeTransactionId != null) {
        await (database.update(database.transactions)
              ..where((t) => t.id.equals(existingTransfer.feeTransactionId!)))
            .write(
              TransactionsCompanion(
                isDeleted: const Value(true),
                updatedAt: Value(now),
              ),
            );
        feeTransactionId = null;
      }

      if (isEditing) {
        await (database.update(database.transfers)
              ..where((t) => t.id.equals(existingTransfer.id)))
            .write(
              TransfersCompanion(
                date: Value(transferDate),
                amount: Value(draft.amount),
                adminFee: Value(draft.adminFee),
                feeTransactionId: Value(feeTransactionId),
                fromAccountId: Value(draft.fromAccountId),
                toAccountId: Value(draft.toAccountId),
                note: Value(draft.note.isEmpty ? null : draft.note),
                updatedAt: Value(now),
              ),
            );
      } else {
        await database.into(database.transfers).insert(
              TransfersCompanion.insert(
                id: id,
                householdId: AppContext.householdId,
                date: transferDate,
                recordedAt: now,
                amount: draft.amount,
                adminFee: Value(draft.adminFee),
                feeTransactionId: Value(feeTransactionId),
                fromAccountId: draft.fromAccountId,
                toAccountId: draft.toAccountId,
                note: Value(draft.note.isEmpty ? null : draft.note),
                source: const Value('manual'),
                updatedAt: Value(now),
              ),
            );
      }
    });

    if (isEditing) {
      await AuditLogger(database).record(
        action: 'ubah',
        entity: 'transfer',
        oldValue: {
          'id': existingTransfer.id,
          'amount': existingTransfer.amount,
          'admin_fee': existingTransfer.adminFee,
          'from_account_id': existingTransfer.fromAccountId,
          'to_account_id': existingTransfer.toAccountId,
        },
        newValue: {
          'id': id,
          'amount': draft.amount,
          'admin_fee': draft.adminFee,
          'from_account_id': draft.fromAccountId,
          'to_account_id': draft.toAccountId,
        },
      );
    } else {
      await AuditLogger(database).record(
        action: 'tambah',
        entity: 'transfer',
        newValue: {
          'id': id,
          'amount': draft.amount,
          'admin_fee': draft.adminFee,
          'from_account_id': draft.fromAccountId,
          'to_account_id': draft.toAccountId,
        },
      );
    }

    await _loadTransactions();
    if (!mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isEditing
              ? 'Transfer berhasil diperbarui.'
              : 'Transfer berhasil dicatat.',
        ),
      ),
    );
    return true;
  }

  Future<void> _deleteTransfer(Transfer transfer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus transfer?'),
        content: const Text(
          'Transfer ini akan disembunyikan dari riwayat dan saldo rekening akan dihitung ulang. Anda dapat membatalkannya melalui tombol Urungkan di notifikasi bawah.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppCopy.batal),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final database = getIt<AppDatabase>();
    final deletedAt = DateTime.now();
    await (database.update(
      database.transfers,
    )..where((row) => row.id.equals(transfer.id))).write(
      TransfersCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(deletedAt),
      ),
    );
    final feeTransactionId = transfer.feeTransactionId;
    if (feeTransactionId != null && feeTransactionId.isNotEmpty) {
      await (database.update(
        database.transactions,
      )..where((row) => row.id.equals(feeTransactionId))).write(
        TransactionsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(deletedAt),
        ),
      );
    }
    await AuditLogger(database).record(
      action: 'hapus',
      entity: 'transfer',
      oldValue: {
        'id': transfer.id,
        'amount': transfer.amount,
        'from_account_id': transfer.fromAccountId,
        'to_account_id': transfer.toAccountId,
      },
    );
    await _loadTransactions();
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Transfer dihapus.'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Urungkan',
          onPressed: () async {
            await (database.update(
              database.transfers,
            )..where((row) => row.id.equals(transfer.id))).write(
              const TransfersCompanion(
                isDeleted: Value(false),
              ),
            );
            if (feeTransactionId != null && feeTransactionId.isNotEmpty) {
              await (database.update(
                database.transactions,
              )..where((row) => row.id.equals(feeTransactionId))).write(
                const TransactionsCompanion(
                  isDeleted: Value(false),
                ),
              );
            }
            await AuditLogger(database).record(
              action: 'pulihkan',
              entity: 'transfer',
              newValue: {
                'id': transfer.id,
                'amount': transfer.amount,
                'from_account_id': transfer.fromAccountId,
                'to_account_id': transfer.toAccountId,
              },
            );
            await _loadTransactions();
          },
        ),
      ),
    );
  }

  Future<void> _openForm() async {
    await _showNewEntrySheet();
  }

  Future<void> _showNewEntrySheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .55,
        minChildSize: .42,
        maxChildSize: .92,
        builder: (_, controller) => SafeArea(
          child: NewEntrySheetBody(
            controller: controller,
            onSelect: (choice) => Navigator.pop(sheetContext, choice),
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'expense':
        await _openTransactionForm(TransactionType.expense);
      case 'income':
        await _openTransactionForm(TransactionType.income);
      case 'transfer':
        await _openTransfer();
      case 'goal':
        await _openGoalContribution();
      case 'goal_usage':
        await _openGoalContribution(usage: true);
      case 'quick':
        await _openQuickEntry();
      case 'json':
      case 'receipt_json':
        await _openJsonBatch();
    }
  }

  Future<void> _openTransactionForm(TransactionType type) async {
    final drafts = await Navigator.of(context).push<List<TransactionDraft>>(
      MaterialPageRoute(
        builder: (_) => TransactionFormPage(
          initialType: type,
          showFirstTransactionGuide:
              _transactions.isEmpty && type == TransactionType.expense,
        ),
      ),
    );
    if (!mounted || drafts == null || drafts.isEmpty) return;
    await _saveDrafts(drafts);
  }

  Future<bool> _openGoalContribution({
    TransactionWithItems? existing,
    bool usage = false,
    FfmAssistantDraft? assistantDraft,
  }) async {
    final drafts = await Navigator.of(context).push<List<TransactionDraft>>(
      MaterialPageRoute(
        builder: (_) => GoalContributionFormPage(
          existingTransaction: existing,
          usage: usage || existing?.transaction.source == 'goal_usage',
          assistantDraft: assistantDraft,
        ),
      ),
    );
    if (!mounted || drafts == null || drafts.isEmpty) return false;
    if (existing == null) {
      await _saveDrafts(drafts);
    } else {
      await _saveDraft(drafts.first, transactionId: existing.transaction.id);
    }
    return true;
  }

  Future<void> _openQuickEntry() async {
    if (_accounts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tambahkan rekening di Data Utama dulu.')),
      );
      return;
    }
    final drafts = await Navigator.of(context).push<List<TransactionDraft>>(
      MaterialPageRoute(
        builder: (_) => QuickTransactionBatchPage(
          categories: _categories,
          merchants: _merchants,
          accounts: _accounts,
          onSave: _saveBatchDrafts,
        ),
      ),
    );
    if (!mounted || drafts == null || drafts.isEmpty) return;
  }

  Future<List<JsonBudgetOption>> _loadJsonBudgetOptions() async {
    final database = getIt<AppDatabase>();
    final budgets =
        await (database.select(database.envelopeBudgets)
              ..where((row) => row.householdId.equals(AppContext.householdId))
              ..where((row) => row.isActive.equals(true)))
            .get();
    final options = <JsonBudgetOption>[];
    final configuredCategoryIds = <String>{};
    for (final budget in budgets) {
      final categoryIds = <String>[];
      try {
        final decoded = jsonDecode(budget.categoryIdsJson);
        if (decoded is List) {
          categoryIds.addAll(decoded.whereType<String>());
        }
      } catch (_) {
        // Data lama bisa memakai categoryId tunggal.
      }
      if (budget.categoryId != null &&
          !categoryIds.contains(budget.categoryId)) {
        categoryIds.add(budget.categoryId!);
      }
      if (categoryIds.isEmpty) continue;
      configuredCategoryIds.addAll(categoryIds);
      final period = budget.periodType == 'weekly' ? 'Mingguan' : 'Bulanan';
      options.add(
        JsonBudgetOption(
          id: budget.id,
          label:
              '${budget.name} · $period · ${formatTanggalSingkat(budget.startDate)}–${formatTanggalSingkat(budget.endDate)}',
          categoryIds: categoryIds,
        ),
      );
    }
    for (final category in transactionCategoryOptions(_categories, 'expense')) {
      if (configuredCategoryIds.contains(category.id)) continue;
      options.add(
        JsonBudgetOption(
          id: 'category:${category.id}',
          label:
              '${transactionCategoryLabel(_categories, category)} · belum ada target',
          categoryIds: [category.id],
        ),
      );
    }
    return options;
  }

  Future<void> _openJsonBatch() async {
    if (_accounts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tambahkan rekening di Data Utama dulu.')),
      );
      return;
    }
    final budgetOptions = await _loadJsonBudgetOptions();
    if (!mounted) return;
    final result = await Navigator.of(context).push<JsonBatchResult>(
      MaterialPageRoute(
        builder: (_) => JsonTransactionBatchPage(
          categories: _categories,
          merchants: _merchants,
          accounts: _accounts,
          budgetOptions: budgetOptions,
        ),
      ),
    );
    if (!mounted ||
        result == null ||
        (result.drafts.isEmpty && result.transfers.isEmpty)) {
      return;
    }
    await _saveImportedJsonResult(result);
  }

  Future<void> _saveImportedStatementBalance(
    ReceiptBatchImport? statement,
  ) async {
    final closingBalance = statement?.closingBalance;
    if (statement == null || closingBalance == null) return;
    final account = _accounts
        .where(
          (item) =>
              item.id == statement.statementAccountId ||
              (statement.statementAccountName != null &&
                  item.name.toLowerCase() ==
                      statement.statementAccountName!.toLowerCase()),
        )
        .firstOrNull;
    if (account == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Transaksi sudah masuk, tapi saldo akhir belum direkonsiliasi. Pilih rekening yang cocok di Data Utama.',
            ),
          ),
        );
      }
      return;
    }
    await getIt<CreateReconciliationLog>()(
      householdId: AppContext.householdId,
      accountId: account.id,
      actualBalance: closingBalance,
      checkedAt: statement.periodEnd ?? DateTime.now(),
      note: 'Saldo akhir dari impor mutasi JSON eksternal.',
    );
  }

  Future<void> _saveImportedJsonResult(JsonBatchResult result) async {
    final database = getIt<AppDatabase>();
    final now = DateTime.now();
    final entities = <TransactionEntity>[];
    final itemsByTransactionId = <String, List<TransactionItemEntity>>{};
    final transfers = <TransferEntity>[];
    final auditRows = <Map<String, dynamic>>[];

    for (final draft in result.drafts) {
      final id = const Uuid().v4();
      final entity = TransactionEntity(
        id: id,
        householdId: AppContext.householdId,
        date: draft.date,
        amount: draft.amount,
        owner: OwnerLabels.normalizeForStorage(draft.owner),
        categoryId: draft.categoryId,
        note: draft.note.trim().isEmpty ? null : draft.note.trim(),
        source: draft.source,
        accountId: draft.accountId,
        merchantId: draft.merchantId,
        location: draft.location,
        goalId: draft.goalId,
        partyName: draft.partyName,
        receiptRawText: draft.receiptRawText,
        receiptNumber: draft.receiptNumber,
        receiptPaidAmount: draft.receiptPaidAmount,
        receiptChangeAmount: draft.receiptChangeAmount,
        recordedAt: now,
        updatedAt: now,
      );
      entities.add(entity);
      itemsByTransactionId[id] = draft.items
          .map(
            (item) => TransactionItemEntity(
              id: const Uuid().v4(),
              transactionId: id,
              itemName: item.name,
              price: item.price,
              qty: item.qty,
            ),
          )
          .toList();
      auditRows.add({
        'id': id,
        'amount': draft.amount,
        'account_id': draft.accountId,
        'category_id': draft.categoryId,
        'source': draft.source,
      });
    }

    Category? feeCategory;
    final hasAdminFee = result.transfers.any(
      (transfer) => transfer.adminFee > 0,
    );
    if (hasAdminFee) {
      feeCategory =
          await (database.select(database.categories)..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.type.equals('expense') &
                    row.name.equals('Biaya admin') &
                    row.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (feeCategory == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Kategori Biaya admin belum tersedia. Tambahkan di Data Utama dulu.',
              ),
            ),
          );
        }
        return;
      }
    }

    for (final draft in result.transfers) {
      final transferId = const Uuid().v4();
      final feeTransactionId = draft.adminFee > 0 ? const Uuid().v4() : null;
      if (draft.adminFee > 0) {
        final feeEntity = TransactionEntity(
          id: feeTransactionId!,
          householdId: AppContext.householdId,
          date: draft.date,
          amount: -draft.adminFee,
          owner: OwnerLabels.family,
          categoryId: feeCategory!.id,
          note:
              'Biaya admin transfer ${_accountLabel(draft.fromAccountId)} ke ${_accountLabel(draft.toAccountId)}',
          source: 'transfer_fee',
          accountId: draft.fromAccountId,
          merchantId: null,
          location: null,
          goalId: null,
          partyName: null,
          receiptRawText: null,
          receiptNumber: null,
          receiptPaidAmount: null,
          receiptChangeAmount: null,
          recordedAt: now,
          updatedAt: now,
        );
        entities.add(feeEntity);
        itemsByTransactionId[feeEntity.id] = const [];
        auditRows.add({
          'id': feeEntity.id,
          'amount': feeEntity.amount,
          'account_id': feeEntity.accountId,
          'category_id': feeEntity.categoryId,
          'source': feeEntity.source,
        });
      }
      transfers.add(
        TransferEntity(
          id: transferId,
          householdId: AppContext.householdId,
          date: draft.date,
          recordedAt: now,
          amount: draft.amount,
          adminFee: draft.adminFee,
          feeTransactionId: feeTransactionId,
          fromAccountId: draft.fromAccountId,
          toAccountId: draft.toAccountId,
          note: draft.note?.trim().isEmpty == true ? null : draft.note?.trim(),
          source: 'json_bank_statement',
          updatedAt: now,
        ),
      );
      auditRows.add({
        'id': transferId,
        'amount': draft.amount,
        'admin_fee': draft.adminFee,
        'from_account_id': draft.fromAccountId,
        'to_account_id': draft.toAccountId,
        'source': 'json_bank_statement',
      });
    }

    await getIt<SaveMixedTransactionBatch>()(
      entities,
      itemsByTransactionId: itemsByTransactionId,
      transfers: transfers,
    );
    final auditLogger = AuditLogger(database);
    for (final row in auditRows) {
      await auditLogger.record(
        action: 'tambah',
        entity: row['source'] == 'json_bank_statement'
            ? 'transfer'
            : 'transaksi',
        newValue: row,
      );
    }
    await _saveImportedStatementBalance(result.statement);
    await _loadTransactions();
    if (!mounted) return;
    final regularCount = result.drafts.length;
    final feeCount = result.transfers.where((item) => item.adminFee > 0).length;
    final feeText = feeCount > 0 ? ' dan $feeCount biaya admin' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$regularCount transaksi dan ${result.transfers.length} transfer$feeText berhasil dikonfirmasi.',
        ),
      ),
    );
  }

  Future<void> _openEdit(TransactionWithItems entry) async {
    if (entry.transaction.goalId != null) {
      await _openGoalContribution(
        existing: entry,
        usage: entry.transaction.source == 'goal_usage',
      );
      return;
    }
    final drafts = await Navigator.of(context).push<List<TransactionDraft>>(
      MaterialPageRoute(
        builder: (_) => TransactionFormPage(existingTransaction: entry),
      ),
    );
    if (!mounted || drafts == null || drafts.isEmpty) return;
    await _saveDraft(drafts.first, transactionId: entry.transaction.id);
  }

  Future<void> _openDetail(TransactionWithItems entry) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TransactionDetailPage(
          entry: entry,
          categoryLabel: _categoryLabel(entry.transaction.categoryId),
          accountLabel: _accountLabel(entry.transaction.accountId),
          merchantLabel: _merchantLabel(entry.transaction.merchantId),
        ),
      ),
    );
  }

  Future<void> _deleteTransaction(TransactionWithItems entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus transaksi?'),
        content: const Text(
          'Transaksi ini akan disembunyikan dari riwayat. Anda dapat membatalkannya melalui tombol Urungkan di notifikasi bawah.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppCopy.batal),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await getIt<DeleteTransaction>()(
      AppContext.householdId,
      entry.transaction.id,
    );
    await _syncGoalContribution(
      previous: _entityFromRow(entry.transaction),
      nextGoalId: null,
      nextAmount: 0,
      nextSource: null,
    );
    await AuditLogger(getIt<AppDatabase>()).record(
      action: 'hapus',
      entity: 'transaksi',
      oldValue: _auditTransactionValue(_entityFromRow(entry.transaction)),
    );
    await _loadTransactions();
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Transaksi dihapus.'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Urungkan',
          onPressed: () async {
            final database = getIt<AppDatabase>();
            await (database.update(database.transactions)
                  ..where((row) =>
                      row.householdId.equals(AppContext.householdId) &
                      row.id.equals(entry.transaction.id)))
                .write(
              const TransactionsCompanion(
                isArchived: Value(false),
                isDeleted: Value(false),
              ),
            );
            await _syncGoalContribution(
              previous: null,
              nextGoalId: entry.transaction.goalId,
              nextAmount: entry.transaction.amount,
              nextSource: entry.transaction.source,
            );
            await AuditLogger(database).record(
              action: 'pulihkan',
              entity: 'transaksi',
              newValue: _auditTransactionValue(_entityFromRow(entry.transaction)),
            );
            await _loadTransactions();
          },
        ),
      ),
    );
  }

  Future<void> _refreshFts(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      if (mounted) setState(() => _ftsTransactionIds = null);
      return;
    }
    try {
      final escaped = query.replaceAll('"', ' ');
      final rows = await getIt<AppDatabase>()
          .customSelect(
            'SELECT transaction_id FROM transaction_search '
            'WHERE transaction_search MATCH ?',
            variables: [Variable.withString('"$escaped"')],
          )
          .get();
      if (!mounted || rawQuery != _query) return;
      setState(
        () => _ftsTransactionIds = rows
            .map((row) => row.data['transaction_id']?.toString())
            .whereType<String>()
            .toSet(),
      );
    } catch (_) {
      if (mounted && rawQuery == _query) {
        setState(() => _ftsTransactionIds = null);
      }
    }
  }

  List<TransactionWithItems> get _visibleTransactions {
    final query = _query.trim().toLowerCase();
    final now = DateTime.now();
    return _transactions
        .where((entry) {
          final transaction = entry.transaction;
          final matchesType = switch (_typeFilter) {
            'Pemasukan' => transaction.amount >= 0,
            'Pengeluaran' => transaction.amount < 0,
            'Transfer' => false,
            _ => true,
          };
          final matchesMonth =
              !_currentMonthOnly ||
              (transaction.date.year == now.year &&
                  transaction.date.month == now.month);
          final matchesDateRange = _matchesDateRange(transaction.date);
          final matchesAccount =
              _accountFilter == null || transaction.accountId == _accountFilter;
          final matchesCategory =
              _categoryFilter == null ||
              transaction.categoryId == _categoryFilter;
          final matchesMerchant =
              _merchantFilter == null ||
              transaction.merchantId == _merchantFilter;
          final matchesOwner =
              _ownerFilter == null || transaction.owner == _ownerFilter;
          final searchText = [
            _categoryLabel(transaction.categoryId),
            transaction.owner ?? '',
            transaction.note ?? '',
            _merchantLabel(transaction.merchantId),
            _accountLabel(transaction.accountId),
            ...entry.items.map((item) => item.itemName),
            _dateLabel(transaction.date),
          ].join(' ').toLowerCase();
          final matchesFts =
              _ftsTransactionIds == null ||
              _ftsTransactionIds!.contains(transaction.id);
          if (transaction.source == 'transfer') return false;
          return matchesType &&
              matchesMonth &&
              matchesDateRange &&
              matchesAccount &&
              matchesCategory &&
              matchesMerchant &&
              matchesOwner &&
              (query.isEmpty || matchesFts || searchText.contains(query));
        })
        .toList(growable: false);
  }

  List<Transfer> get _visibleTransfers {
    if (_typeFilter == 'Pemasukan' ||
        _typeFilter == 'Pengeluaran' ||
        _merchantFilter != null ||
        _ownerFilter != null) {
      return const [];
    }
    final query = _query.trim().toLowerCase();
    final now = DateTime.now();
    return _transfers
        .where((transfer) {
          final matchesType =
              _typeFilter == 'Transfer' || _typeFilter == 'Semua';
          final matchesMonth =
              !_currentMonthOnly ||
              (transfer.date.year == now.year &&
                  transfer.date.month == now.month);
          final matchesDateRange = _matchesDateRange(transfer.date);
          final matchesAccount =
              _accountFilter == null ||
              transfer.fromAccountId == _accountFilter ||
              transfer.toAccountId == _accountFilter;
          final searchText = [
            _accountLabel(transfer.fromAccountId),
            _accountLabel(transfer.toAccountId),
            transfer.note ?? '',
            _dateLabel(transfer.date),
            transfer.amount.toString(),
          ].join(' ').toLowerCase();
          return matchesType &&
              matchesMonth &&
              matchesDateRange &&
              matchesAccount &&
              (query.isEmpty || searchText.contains(query));
        })
        .toList(growable: false);
  }

  bool _matchesDateRange(DateTime date) {
    if (_startDateFilter != null && date.isBefore(_startDateFilter!)) {
      return false;
    }
    if (_endDateFilter == null) return true;
    final endOfDay = DateTime(
      _endDateFilter!.year,
      _endDateFilter!.month,
      _endDateFilter!.day,
      23,
      59,
      59,
      999,
    );
    return !date.isAfter(endOfDay);
  }

  void _onSearchChanged(String value) {
    if (mounted) setState(() => _query = value);
    unawaited(_refreshFts(value));
  }

  void _openSearch() {
    setState(() => _isSearchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _searchFocusNode.unfocus();
    _searchController.clear();
    _onSearchChanged('');
    if (mounted) setState(() => _isSearchOpen = false);
  }

  Future<void> _showFilterSheet() async {
    final owners = _transactions
        .map((t) => t.transaction.owner)
        .whereType<String>()
        .where((o) => o.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final result = await showModalBottomSheet<TransactionFilter>(
      context: context,
      showDragHandle: true,
      builder: (context) => TransactionFilterSheet(
        typeFilter: _typeFilter,
        currentMonthOnly: _currentMonthOnly,
        accounts: _accounts,
        categories: _categories,
        merchants: _merchants,
        owners: owners,
        accountId: _accountFilter,
        categoryId: _categoryFilter,
        merchantId: _merchantFilter,
        owner: _ownerFilter,
        startDate: _startDateFilter,
        endDate: _endDateFilter,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _typeFilter = result.typeFilter;
      _currentMonthOnly = result.currentMonthOnly;
      _accountFilter = result.accountId;
      _categoryFilter = result.categoryId;
      _merchantFilter = result.merchantId;
      _ownerFilter = result.owner;
      _startDateFilter = result.startDate;
      _endDateFilter = result.endDate;
    });
  }

  Future<void> _saveMetadata(
    String transactionId,
    TransactionDraft draft,
  ) async {
    final database = getIt<AppDatabase>();
    await database.transaction(() async {
      await (database.delete(
        database.transactionTags,
      )..where((table) => table.transactionId.equals(transactionId))).go();
      await (database.delete(
        database.attachments,
      )..where((table) => table.transactionId.equals(transactionId))).go();
      for (final rawTag in draft.tags) {
        final tagName = rawTag.trim().toLowerCase();
        if (tagName.isEmpty) continue;
        final existing =
            await (database.select(database.tags)..where(
                  (table) =>
                      table.householdId.equals(AppContext.householdId) &
                      table.name.equals(tagName) &
                      table.isArchived.equals(false),
                ))
                .getSingleOrNull();
        if (existing == null) continue;
        final tagId = existing.id;
        await database
            .into(database.transactionTags)
            .insert(
              TransactionTagsCompanion.insert(
                transactionId: transactionId,
                tagId: tagId,
              ),
            );
      }
      for (final path in draft.attachmentPaths) {
        await database
            .into(database.attachments)
            .insert(
              AttachmentsCompanion.insert(
                id: const Uuid().v4(),
                transactionId: Value(transactionId),
                path: path,
                createdAt: DateTime.now(),
              ),
            );
      }
    });
  }

  TransactionEntity _entityFromRow(Transaction row) => TransactionEntity(
    id: row.id,
    householdId: row.householdId,
    date: row.date,
    amount: row.amount,
    owner: row.owner ?? OwnerLabels.family,
    categoryId: row.categoryId,
    note: row.note,
    source: row.source ?? 'manual',
    accountId: row.accountId,
    merchantId: row.merchantId,
    location: row.location,
    goalId: row.goalId,
    partyName: row.partyName,
    receiptRawText: row.receiptRawText,
    receiptNumber: row.receiptNumber,
    receiptPaidAmount: row.receiptPaidAmount,
    receiptChangeAmount: row.receiptChangeAmount,
    recordedAt: row.recordedAt,
    updatedAt: row.updatedAt,
  );

  Future<void> _syncGoalContribution({
    required TransactionEntity? previous,
    required String? nextGoalId,
    required int nextAmount,
    required String? nextSource,
  }) async {
    await getIt<SyncGoalBalance>()(
      householdId: AppContext.householdId,
      previous: previous,
      nextGoalId: nextGoalId,
      nextAmount: nextAmount,
      nextSource: nextSource,
    );
  }

  Map<String, Object?> _auditTransactionValue(TransactionEntity transaction) {
    return {
      'id': transaction.id,
      'amount': transaction.amount,
      'owner': transaction.owner,
      'category_id': transaction.categoryId,
      'merchant_id': transaction.merchantId,
      'location': transaction.location,
      'goal_id': transaction.goalId,
      'source': transaction.source,
    };
  }

  Future<void> _saveDrafts(List<TransactionDraft> drafts) async {
    for (final draft in drafts) {
      await _saveDraft(draft, refresh: false, showMessage: false);
    }
    await _loadTransactions();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${drafts.length} transaksi berhasil dicatat.')),
    );
  }

  Future<void> _saveBatchDrafts(List<TransactionDraft> drafts) async {
    final now = DateTime.now();
    final entities = <TransactionEntity>[];
    final itemsByTransactionId = <String, List<TransactionItemEntity>>{};
    final auditRows = <Map<String, dynamic>>[];
    for (final draft in drafts) {
      final id = const Uuid().v4();
      final entity = TransactionEntity(
        id: id,
        householdId: AppContext.householdId,
        date: draft.date,
        amount: draft.amount,
        owner: OwnerLabels.normalizeForStorage(draft.owner),
        categoryId: draft.categoryId,
        note: draft.note.isEmpty ? null : draft.note,
        source: draft.source,
        accountId: draft.accountId,
        merchantId: draft.merchantId,
        location: draft.location,
        goalId: draft.goalId,
        partyName: draft.partyName,
        receiptRawText: draft.receiptRawText,
        receiptNumber: draft.receiptNumber,
        receiptPaidAmount: draft.receiptPaidAmount,
        receiptChangeAmount: draft.receiptChangeAmount,
        recordedAt: now,
        updatedAt: now,
      );
      entities.add(entity);
      itemsByTransactionId[id] = draft.items
          .map(
            (item) => TransactionItemEntity(
              id: const Uuid().v4(),
              transactionId: id,
              itemName: item.name,
              price: item.price,
              qty: item.qty,
            ),
          )
          .toList();
      auditRows.add({
        'id': id,
        'amount': draft.amount,
        'category_id': draft.categoryId,
        'merchant_id': draft.merchantId,
        'account_id': draft.accountId,
        'source': draft.source,
      });
    }
    await getIt<SaveTransactionBatch>()(
      entities,
      itemsByTransactionId: itemsByTransactionId,
    );
    for (final draft in drafts) {
      await _recordPersonalizationCorrections(draft);
    }
    final auditLogger = AuditLogger(getIt<AppDatabase>());
    for (final row in auditRows) {
      await auditLogger.record(
        action: 'tambah',
        entity: 'transaksi',
        newValue: row,
      );
    }
    await _loadTransactions();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${drafts.length} transaksi berhasil dicatat sekaligus.'),
      ),
    );
  }

  Future<void> _saveDraft(
    TransactionDraft draft, {
    String? transactionId,
    bool refresh = true,
    bool showMessage = true,
  }) async {
    final id = transactionId ?? const Uuid().v4();
    final categoryId = draft.categoryId;
    final previous = transactionId == null
        ? null
        : await getIt<GetTransaction>()(AppContext.householdId, transactionId);
    final confirmationTime = DateTime.now();
    final savedTransaction = TransactionEntity(
      id: id,
      householdId: AppContext.householdId,
      date: draft.date,
      amount: draft.amount,
      owner: OwnerLabels.normalizeForStorage(draft.owner),
      categoryId: categoryId,
      note: draft.note.isEmpty ? null : draft.note,
      source: draft.source,
      accountId: draft.accountId,
      merchantId: draft.merchantId,
      location: draft.location,
      goalId: draft.goalId,
      partyName: draft.partyName,
      receiptRawText: draft.receiptRawText,
      receiptNumber: draft.receiptNumber,
      receiptPaidAmount: draft.receiptPaidAmount,
      receiptChangeAmount: draft.receiptChangeAmount,
      recordedAt: transactionId == null
          ? confirmationTime
          : (previous?.transaction.recordedAt ?? confirmationTime),
      updatedAt: confirmationTime,
    );
    await getIt<SaveTransaction>()(
      savedTransaction,
      items: draft.items
          .map(
            (item) => TransactionItemEntity(
              id: const Uuid().v4(),
              transactionId: id,
              itemName: item.name,
              price: item.price,
              qty: item.qty,
            ),
          )
          .toList(),
    );
    await _syncGoalContribution(
      previous: previous == null ? null : _entityFromRow(previous.transaction),
      nextGoalId: savedTransaction.goalId,
      nextAmount: savedTransaction.amount,
      nextSource: savedTransaction.source,
    );
    await _saveMetadata(id, draft);
    await _recordPersonalizationCorrections(draft);
    await AuditLogger(getIt<AppDatabase>()).record(
      action: transactionId == null ? 'tambah' : 'ubah',
      entity: 'transaksi',
      oldValue: previous == null
          ? null
          : _auditTransactionValue(_entityFromRow(previous.transaction)),
      newValue: {
        'id': id,
        'amount': draft.amount,
        'owner': draft.owner,
        'category_id': draft.categoryId,
        'merchant_id': draft.merchantId,
        'location': draft.location,
        'account_id': draft.accountId,
        'goal_id': draft.goalId,
        'source': draft.source,
      },
    );
    if (refresh) await _loadTransactions();
    if (!mounted || !showMessage) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transaksi berhasil dicatat.')),
    );
  }

  Future<void> _recordPersonalizationCorrections(TransactionDraft draft) async {
    final merchant = draft.assistantMerchantName?.trim();
    if (merchant == null || merchant.isEmpty) return;

    final repository = getIt<FfmAssistantPersonalizationRepository>();
    for (final entry in draft.assistantSlmFieldValues.entries) {
      final slmValue = entry.value.trim();
      if (slmValue.isEmpty) continue;
      final finalValue = switch (entry.key) {
        'category' => _categoryLabel(draft.categoryId),
        'account' => _accountLabel(draft.accountId),
        'amount' => draft.amount.toString(),
        _ => null,
      };
      if (finalValue == null || finalValue.isEmpty || finalValue == slmValue) {
        continue;
      }
      await repository.recordCorrection(
        householdId: AppContext.householdId,
        merchantName: merchant,
        fieldName: entry.key,
        slmValue: slmValue,
        correctedValue: finalValue,
      );
    }
    // Agregasi pola agar lapisan Agent (kategori otomatis) bisa membaca
    // InteractionPatterns; sebelumnya hanya dipanggil dari test sehingga
    // tabel pola selalu kosong di production.
    try {
      await repository.recalculatePatterns(AppContext.householdId);
    } on Object {
      // Agregasi bersifat best-effort; penyimpanan transaksi tetap sukses.
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  String _money(int value) => 'Rp ${formatRupiahInput(value.toString())}';

  int get _activeFilterCount {
    var count = 0;
    if (_typeFilter != 'Semua') count++;
    if (_currentMonthOnly) count++;
    if (_accountFilter != null) count++;
    if (_categoryFilter != null) count++;
    if (_merchantFilter != null) count++;
    if (_ownerFilter != null) count++;
    if (_startDateFilter != null && _endDateFilter != null) count++;
    return count;
  }

  Widget _buildActiveFilterChips() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (_typeFilter != 'Semua')
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InputChip(
                  label: Text('Jenis: $_typeFilter'),
                  onDeleted: () => setState(() => _typeFilter = 'Semua'),
                ),
              ),
            if (_currentMonthOnly)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InputChip(
                  label: const Text('Bulan ini'),
                  onDeleted: () => setState(() => _currentMonthOnly = false),
                ),
              ),
            if (_startDateFilter != null && _endDateFilter != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InputChip(
                  label: Text(
                    '${_dateLabel(_startDateFilter!)} - ${_dateLabel(_endDateFilter!)}',
                  ),
                  onDeleted: () => setState(() {
                    _startDateFilter = null;
                    _endDateFilter = null;
                  }),
                ),
              ),
            if (_accountFilter != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InputChip(
                  label: Text('Rekening: ${_accountLabel(_accountFilter)}'),
                  onDeleted: () => setState(() => _accountFilter = null),
                ),
              ),
            if (_categoryFilter != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InputChip(
                  label: Text('Kategori: ${_categoryLabel(_categoryFilter)}'),
                  onDeleted: () => setState(() => _categoryFilter = null),
                ),
              ),
            if (_merchantFilter != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InputChip(
                  label: Text('Toko: ${_merchantLabel(_merchantFilter)}'),
                  onDeleted: () => setState(() => _merchantFilter = null),
                ),
              ),
            if (_ownerFilter != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InputChip(
                  label: Text('Pemilik: $_ownerFilter'),
                  onDeleted: () => setState(() => _ownerFilter = null),
                ),
              ),
            TextButton.icon(
              onPressed: () => setState(() {
                _typeFilter = 'Semua';
                _currentMonthOnly = false;
                _accountFilter = null;
                _categoryFilter = null;
                _merchantFilter = null;
                _ownerFilter = null;
                _startDateFilter = null;
                _endDateFilter = null;
              }),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Reset'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleTransactions = _visibleTransactions;
    final visibleTransfers = _visibleTransfers;
    final timeline =
        <
            ({
              TransactionWithItems? transaction,
              Transfer? transfer,
              DateTime date,
            })
          >[
            ...visibleTransactions.map(
              (entry) => (
                transaction: entry,
                transfer: null,
                date: entry.transaction.date,
              ),
            ),
            ...visibleTransfers.map(
              (transfer) =>
                  (transaction: null, transfer: transfer, date: transfer.date),
            ),
          ]
          ..sort((left, right) => right.date.compareTo(left.date));
    final incomeTotal = visibleTransactions
        .where(
          (entry) =>
              entry.transaction.source != 'transfer' &&
              entry.transaction.amount >= 0,
        )
        .fold<int>(0, (sum, entry) => sum + entry.transaction.amount);
    final expenseTotal = visibleTransactions
        .where(
          (entry) =>
              entry.transaction.source != 'transfer' &&
              entry.transaction.amount < 0,
        )
        .fold<int>(0, (sum, entry) => sum + entry.transaction.amount.abs());
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.transactions,
      dataSummary:
          'Tampil ${visibleTransactions.length} transaksi. Total Masuk: ${_money(incomeTotal)}, Total Keluar: ${_money(expenseTotal)}.',
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: _isSearchOpen ? 0 : null,
          leading: _isSearchOpen
              ? IconButton(
                  tooltip: 'Tutup pencarian',
                  onPressed: _closeSearch,
                  icon: const Icon(Icons.arrow_back),
                )
              : null,
          title: _isSearchOpen
              ? TextField(
                  focusNode: _searchFocusNode,
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Cari transaksi, kategori, toko, atau catatan',
                    border: InputBorder.none,
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Hapus pencarian',
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                )
              : const Text('Transaksi'),
          actions: _isSearchOpen
              ? const [SizedBox(width: 8)]
              : [
                  IconButton(
                    tooltip: 'Cari transaksi',
                    onPressed: _openSearch,
                    icon: const Icon(Icons.search),
                  ),
                  IconButton(
                    tooltip: 'Info Transaksi',
                    onPressed: () => showAppInfoDialog(
                      context,
                      title: 'Cara pakai Transaksi',
                      message: _accounts.isEmpty
                          ? 'Buat rekening di Data Utama dulu. Setelah itu catat pemasukan awal supaya saldo keluarga punya titik awal.'
                          : 'Pemasukan menambah arus kas dan pengeluaran menguranginya. Kamu bisa impor JSON dari LLM, lalu selalu cek dan edit hasilnya sebelum menyimpan.',
                    ),
                    icon: const Icon(Icons.info_outline),
                  ),
                  IconButton(
                    tooltip: 'Saring transaksi',
                    onPressed: _showFilterSheet,
                    icon: Badge(
                      isLabelVisible: _activeFilterCount > 0,
                      label: Text('$_activeFilterCount'),
                      child: const Icon(Icons.tune),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Aksi transaksi lainnya',
                    onSelected: (value) {
                      switch (value) {
                        case 'transfer':
                          _openTransfer();
                        case 'cepat':
                          _openQuickEntry();
                        case 'json':
                          _openJsonBatch();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'transfer',
                        child: ListTile(
                          leading: Icon(Icons.swap_horiz_rounded),
                          title: Text('Pindah saldo'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'cepat',
                        child: ListTile(
                          leading: Icon(Icons.playlist_add_rounded),
                          title: Text('Input banyak transaksi'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'json',
                        child: ListTile(
                          leading: Icon(Icons.auto_awesome_outlined),
                          title: Text('Tempel hasil dari Asisten AI'),
                        ),
                      ),
                    ],
                  ),
                ],
        ),
        body: Column(
          children: [
            if (_activeFilterCount > 0) _buildActiveFilterChips(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 160),
                      children: [
                        AppEmptyState(
                          icon: Icons.error_outline,
                          title: 'Gagal memuat transaksi',
                          message: _errorMessage!,
                          action: FilledButton.icon(
                            onPressed: _loadTransactions,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Coba Lagi'),
                          ),
                        ),
                      ],
                    )
                  : _transactions.isEmpty && _transfers.isEmpty
                  ? ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
                children: [
                  AppEmptyState(
                    icon: _accounts.isEmpty
                        ? Icons.account_balance_wallet_outlined
                        : Icons.receipt_long_outlined,
                    title: _accounts.isEmpty
                        ? 'Rekening belum ada'
                        : 'Belum ada transaksi',
                    message: _accounts.isEmpty
                        ? 'Transaksi membutuhkan tempat uang seperti Tunai, bank, atau dompet digital.'
                        : 'Sebaiknya catat pemasukan awal dulu. Setelah saldo ada, pengeluaran akan terlihat jelas mengurangi saldo keluarga.',
                    action: FilledButton.icon(
                      onPressed: _accounts.isEmpty
                          ? () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const MasterDataPage(),
                                ),
                              );
                              if (mounted) await _loadTransactions();
                            }
                          : _openForm,
                      icon: Icon(
                        _accounts.isEmpty ? Icons.tune_outlined : Icons.add,
                      ),
                      label: Text(
                        _accounts.isEmpty
                            ? 'Buka Data Utama'
                            : AppCopy.tambahTransaksi,
                      ),
                    ),
                  ),
                ],
              )
            : visibleTransactions.isEmpty && visibleTransfers.isEmpty
            ? ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
                children: [
                  const AppHelpBanner(
                    title: 'Tidak ada yang cocok',
                    message: 'Coba ubah kata pencarian atau matikan saringan untuk melihat transaksi lain.',
                    icon: Icons.search_off_outlined,
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
                itemCount: timeline.length + 2,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return TransactionFlowSummary(
                      incomeTotal: incomeTotal,
                      expenseTotal: expenseTotal,
                      transactionCount: visibleTransactions.length,
                      transferCount: visibleTransfers.length,
                    );
                  }
                  if (index == 1) {
                    return AccountBalancesCard(
                      accounts: _accounts,
                      transactions: _transactions,
                      transfers: _transfers,
                      accountTypeLabel: _accountTypeLabel,
                    );
                  }
                  final timelineItem = timeline[index - 2];
                  final transfer = timelineItem.transfer;
                  if (transfer != null) {
                    return TransferHistoryCard(
                      transfer: transfer,
                      fromLabel: _accountLabel(transfer.fromAccountId),
                      toLabel: _accountLabel(transfer.toAccountId),
                      dateLabel: _dateLabel,
                      onEdit: () => _openTransfer(existingTransfer: transfer),
                      onDelete: () => _deleteTransfer(transfer),
                    );
                  }
                  final entry = timelineItem.transaction!;
                  final item = entry.transaction;
                  final isIncome = item.amount >= 0;
                  final isGoalUsage =
                      item.goalId != null && item.source == 'goal_usage';
                  final isGoalContribution =
                      item.goalId != null && !isGoalUsage;
                  final merchantName = _merchantLabel(item.merchantId);
                  final color = isGoalContribution
                      ? AppColors.primary
                      : isGoalUsage
                      ? AppColors.negative
                      : isIncome
                      ? AppColors.positive
                      : AppColors.negative;
                  return AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    color: isIncome
                        ? AppColors.positiveSoft.withValues(alpha: .72)
                        : AppColors.negativeSoft.withValues(alpha: .78),
                    onTap: () => _openDetail(entry),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: color.withValues(alpha: .14),
                          foregroundColor: color,
                          child: Icon(
                            isIncome
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded,
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  AppStatusChip(
                                    label: isGoalContribution
                                        ? 'Isi target'
                                        : isGoalUsage
                                        ? 'Pakai target'
                                        : isIncome
                                        ? 'Uang masuk'
                                        : 'Uang keluar',
                                    color: color,
                                    backgroundColor: color.withValues(
                                      alpha: .14,
                                    ),
                                  ),
                                  if (isDataSusulan(
                                    item.date,
                                    now: item.recordedAt,
                                  ))
                                    AppStatusChip(
                                      label: 'Data susulan',
                                      color: AppColors.warning,
                                      backgroundColor: AppColors.warningSoft,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              Text(
                                merchantName.isNotEmpty
                                    ? merchantName
                                    : isGoalContribution
                                    ? 'Uang terkumpul untuk target'
                                    : isGoalUsage
                                    ? 'Penggunaan dana target'
                                    : _categoryLabel(item.categoryId),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              if (merchantName.isNotEmpty &&
                                  !isGoalContribution &&
                                  !isGoalUsage) ...[
                                Text(
                                  _categoryLabel(item.categoryId),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppColors.inkMuted),
                                ),
                              ],
                              const SizedBox(height: 5),
                              HijriDateText(
                                date: item.date,
                                includeSeconds: false,
                                compact: true,
                                color: AppColors.inkMuted,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              isIncome ? '+' : '−',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: color,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            AppMoneyText(
                              item.amount.abs(),
                              compact: true,
                              color: color,
                            ),
                          ],
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Aksi transaksi',
                          icon: const Icon(Icons.more_vert),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          onSelected: (value) {
                            if (value == 'edit') {
                              _openEdit(entry);
                            } else if (value == 'delete') {
                              _deleteTransaction(entry);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Ubah transaksi'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Hapus transaksi'),
                            ),
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
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'transaction_add_fab',
          onPressed: _openForm,
          icon: const Icon(Icons.add),
          label: const Text(AppCopy.tambah),
        ),
      ),
    );
  }

  String _merchantLabel(String? merchantId) {
    if (merchantId == null) return '';
    return _merchants
            .where((merchant) => merchant.id == merchantId)
            .map((merchant) => merchant.name)
            .firstOrNull ??
        '';
  }

  String _categoryLabel(String? categoryId) {
    for (final category in _categories) {
      if (categoryId != null && category.id == categoryId) return category.name;
    }
    return 'Target uang terkumpul';
  }

  String _accountTypeLabel(String type) {
    return switch (type) {
      'cash' => 'Tunai',
      'bank' => 'Rekening',
      'ewallet' => 'Dompet digital',
      _ => type,
    };
  }

  String _accountLabel(String? accountId) {
    if (accountId == null) return '';
    final account = _accounts.where((item) => item.id == accountId).firstOrNull;
    if (account == null) return '';
    return '${account.name} · ${_accountTypeLabel(account.type)}';
  }

  String _dateLabel(DateTime date) => formatTanggalLengkap(date);
}
