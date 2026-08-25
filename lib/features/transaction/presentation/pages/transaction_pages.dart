import 'dart:async';

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

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
import '../../data/services/offline_ai_engine_service.dart';
import '../../data/services/receipt_import_service.dart';
import '../../data/services/receipt_import_models.dart';
import '../../data/services/voice_transaction_parser.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/usecases/transaction_crud_usecases.dart';
import 'transaction_detail_page.dart';
import 'receipt_json_import_page.dart';
import '../../../goal/domain/entities/goal_entity.dart';
import '../../../goal/domain/usecases/goal_balance_usecases.dart';
import '../../../goal/presentation/pages/goal_pages.dart';
import '../../../goal/domain/usecases/goal_crud_usecases.dart';
import '../../../recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';
import '../../../liability/presentation/pages/liability_pages.dart';
import '../../../settings/presentation/pages/master_data_page.dart';
import '../../../assistant/data/ffm_assistant_personalization_repository.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../../assistant/presentation/widgets/ffm_agent_status_indicator.dart';

List<Category> _transactionCategoryOptions(
  List<Category> categories,
  String type, {
  String? selectedId,
}) {
  final typed = categories.where((category) => category.type == type).toList();
  final parentIds = typed
      .map((category) => category.parentId)
      .whereType<String>()
      .toSet();
  return typed
      .where(
        (category) =>
            !parentIds.contains(category.id) || category.id == selectedId,
      )
      .toList(growable: false);
}

String _transactionCategoryLabel(
  List<Category> categories,
  Category category, {
  bool markLegacyParent = true,
}) {
  final parent = categories
      .where((item) => item.id == category.parentId)
      .firstOrNull;
  if (parent != null) return '${parent.name} · ${category.name}';
  final hasChildren = categories.any((item) => item.parentId == category.id);
  return hasChildren && markLegacyParent
      ? '${category.name} · kelompok'
      : category.name;
}

class TransactionListPage extends StatefulWidget {
  const TransactionListPage({
    super.key,
    this.assistantDraft,
    this.assistantRequestId = 0,
    this.onOpenAssistant,
  });

  final FfmAssistantDraft? assistantDraft;
  final int assistantRequestId;
  final Future<void> Function()? onOpenAssistant;

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
  var _query = '';
  var _typeFilter = 'Semua';
  var _currentMonthOnly = false;
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
        final drafts = await Navigator.of(context).push<List<TransactionDraft>>(
          MaterialPageRoute(
            builder: (_) => TransactionFormPage(
              initialType: draft.kind == FfmAssistantDraftKind.income
                  ? TransactionType.income
                  : TransactionType.expense,
              initialAmount: draft.amount,
              initialAccountName: draft.toAccountName ?? draft.fromAccountName,
              initialCategoryName: draft.categoryName,
              initialNote: draft.note,
              initialDate: draft.date,
              assistantMerchantName: draft.merchantName,
              assistantSlmFieldValues: draft.slmFieldValues,
            ),
          ),
        );
        if (!mounted || drafts == null || drafts.isEmpty) return;
        await _saveDrafts(drafts);
      case FfmAssistantDraftKind.goalDeposit:
        await _openGoalContribution();
      case FfmAssistantDraftKind.goalUsage:
        await _openGoalContribution(usage: true);
      case FfmAssistantDraftKind.transfer:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Draft transfer ${draft.fromAccountName ?? 'asal belum dipilih'} → ${draft.toAccountName ?? 'tujuan belum dipilih'} sudah terbaca. Cek detailnya sebelum simpan, ya.',
            ),
          ),
        );
        await _openTransfer();
      case FfmAssistantDraftKind.liability:
      case FfmAssistantDraftKind.receivable:
      case FfmAssistantDraftKind.goal:
      case FfmAssistantDraftKind.goalUpdate:
      case FfmAssistantDraftKind.goalArchive:
      case FfmAssistantDraftKind.asset:
      case FfmAssistantDraftKind.budget:
      case FfmAssistantDraftKind.masterData:
      case FfmAssistantDraftKind.reminder:
      case FfmAssistantDraftKind.reminderUpdate:
      case FfmAssistantDraftKind.reminderArchive:
      case FfmAssistantDraftKind.activity:
      case FfmAssistantDraftKind.dailyNote:
      case FfmAssistantDraftKind.dailyNoteArchive:
      case FfmAssistantDraftKind.task:
      case FfmAssistantDraftKind.taskUpdate:
      case FfmAssistantDraftKind.taskComplete:
      case FfmAssistantDraftKind.taskReopen:
      case FfmAssistantDraftKind.taskArchive:
      case FfmAssistantDraftKind.routine:
      case FfmAssistantDraftKind.routineUpdate:
      case FfmAssistantDraftKind.routineMarkComplete:
      case FfmAssistantDraftKind.routineUnmarkComplete:
      case FfmAssistantDraftKind.routineActivate:
      case FfmAssistantDraftKind.routineDeactivate:
      case FfmAssistantDraftKind.routineArchive:
      case FfmAssistantDraftKind.schedule:
      case FfmAssistantDraftKind.scheduleUpdate:
      case FfmAssistantDraftKind.scheduleArchive:
      case FfmAssistantDraftKind.profile:
      case FfmAssistantDraftKind.transactionUpdate:
      case FfmAssistantDraftKind.transactionArchive:
      case FfmAssistantDraftKind.transactionDelete:
      case FfmAssistantDraftKind.activityArchive:
      case FfmAssistantDraftKind.activityDelete:
        return;
    }
  }

  Future<void> _loadTransactions() async {
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
    });
  }

  Future<void> _openTransfer() async {
    if (_accounts.length < 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tambahkan minimal dua rekening di Data Utama dulu.'),
        ),
      );
      return;
    }
    final draft = await showDialog<_TransferDraft>(
      context: context,
      builder: (_) => _TransferFormDialog(accounts: _accounts),
    );
    if (!mounted || draft == null) return;
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
    final id = const Uuid().v4();
    final feeTransactionId = draft.adminFee > 0 ? const Uuid().v4() : null;
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
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kategori Biaya Admin belum tersedia di Data Utama.'),
          ),
        );
        return;
      }
    }
    await database.transaction(() async {
      if (draft.adminFee > 0) {
        await database
            .into(database.transactions)
            .insert(
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
      await database
          .into(database.transfers)
          .insert(
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
    });
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
    await _loadTransactions();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Transfer berhasil dicatat.')));
  }

  Future<void> _deleteTransfer(Transfer transfer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus transfer?'),
        content: const Text(
          'Transfer ini akan disembunyikan dari riwayat dan saldo rekening akan dihitung ulang.',
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
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Transfer dihapus.')));
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
        initialChildSize: .84,
        minChildSize: .55,
        maxChildSize: .96,
        builder: (_, controller) => SafeArea(
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              const Text(
                'Mau mencatat apa?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text(
                'Pilih alurnya dulu. Semua pilihan ada di sini, termasuk Input cepat dan JSON batch.',
              ),
              const SizedBox(height: 16),
              _NewEntryChoiceTile(
                icon: Icons.north_east_rounded,
                color: AppColors.negative,
                title: 'Pengeluaran',
                subtitle: 'Satu uang keluar dari Tunai, Rekening, atau Dompet digital.',
                onTap: () => Navigator.pop(sheetContext, 'expense'),
              ),
              const SizedBox(height: 8),
              _NewEntryChoiceTile(
                icon: Icons.south_west_rounded,
                color: AppColors.positive,
                title: 'Pemasukan',
                subtitle:
                    'Satu uang masuk ke Tunai, Rekening, atau Dompet digital.',
                onTap: () => Navigator.pop(sheetContext, 'income'),
              ),
              const SizedBox(height: 8),
              _NewEntryChoiceTile(
                icon: Icons.flag_outlined,
                color: AppColors.primary,
                title: 'Isi target uang terkumpul',
                subtitle: 'Setor ke target dan pilih tempat uang. Tidak ada kategori belanja.',
                onTap: () => Navigator.pop(sheetContext, 'goal'),
              ),
              const SizedBox(height: 8),
              _NewEntryChoiceTile(
                icon: Icons.outbox_outlined,
                color: AppColors.warning,
                title: 'Pakai dana target',
                subtitle: 'Gunakan dana yang sudah terkumpul tanpa membuat saldo ganda.',
                onTap: () => Navigator.pop(sheetContext, 'goal_usage'),
              ),
              const Divider(height: 28),
              _NewEntryChoiceTile(
                icon: Icons.playlist_add_rounded,
                color: AppColors.primary,
                title: 'Input cepat banyak item',
                subtitle: 'Catat 10+ transaksi manual; tiap baris punya nominal, kategori, tempat uang, jam, dan rincian.',
                onTap: () => Navigator.pop(sheetContext, 'quick'),
              ),
              const SizedBox(height: 8),
              _NewEntryChoiceTile(
                icon: Icons.data_object_rounded,
                color: AppColors.primary,
                title: 'Impor JSON batch dari Gemini',
                subtitle: 'Tempel atau impor JSON untuk mengisi banyak transaksi dan item sekaligus. Semua bisa diedit dulu.',
                onTap: () => Navigator.pop(sheetContext, 'json'),
              ),
              const SizedBox(height: 8),
              _NewEntryChoiceTile(
                icon: Icons.data_object_rounded,
                color: AppColors.primary,
                title: 'Impor JSON nota dari LLM',
                subtitle: 'Tempel atau pilih JSON hasil LLM, lalu cek semua isinya sebelum masuk ke form transaksi.',
                onTap: () => Navigator.pop(sheetContext, 'receipt_json'),
              ),
            ],
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
      case 'goal':
        await _openGoalContribution();
      case 'goal_usage':
        await _openGoalContribution(usage: true);
      case 'quick':
        await _openQuickEntry();
      case 'json':
        await _openJsonBatch();
      case 'receipt_json':
        await _openReceiptJsonImport();
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

  Future<void> _openGoalContribution({
    TransactionWithItems? existing,
    bool usage = false,
  }) async {
    final drafts = await Navigator.of(context).push<List<TransactionDraft>>(
      MaterialPageRoute(
        builder: (_) => GoalContributionFormPage(
          existingTransaction: existing,
          usage: usage || existing?.transaction.source == 'goal_usage',
        ),
      ),
    );
    if (!mounted || drafts == null || drafts.isEmpty) return;
    if (existing == null) {
      await _saveDrafts(drafts);
    } else {
      await _saveDraft(drafts.first, transactionId: existing.transaction.id);
    }
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
          onSaveJsonResult: _saveImportedJsonResult,
          onSaveStatement: _saveImportedStatementBalance,
        ),
      ),
    );
    if (!mounted || drafts == null || drafts.isEmpty) return;
  }

  Future<List<_JsonBudgetOption>> _loadJsonBudgetOptions() async {
    final database = getIt<AppDatabase>();
    final budgets =
        await (database.select(database.envelopeBudgets)
              ..where((row) => row.householdId.equals(AppContext.householdId))
              ..where((row) => row.isActive.equals(true)))
            .get();
    final options = <_JsonBudgetOption>[];
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
        _JsonBudgetOption(
          id: budget.id,
          label:
              '${budget.name} · $period · ${formatTanggalSingkat(budget.startDate)}–${formatTanggalSingkat(budget.endDate)}',
          categoryIds: categoryIds,
        ),
      );
    }
    for (final category in _transactionCategoryOptions(
      _categories,
      'expense',
    )) {
      if (configuredCategoryIds.contains(category.id)) continue;
      options.add(
        _JsonBudgetOption(
          id: 'category:${category.id}',
          label:
              '${_transactionCategoryLabel(_categories, category)} · belum ada target',
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
      note: 'Saldo akhir dari impor mutasi JSON/Gemini.',
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
          note: draft.note.trim().isEmpty ? null : draft.note.trim(),
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

  Future<void> _openReceiptJsonImport() async {
    final isFirstTransaction = _transactions.isEmpty;
    final result = await Navigator.of(context).push<ReceiptOcrResult>(
      MaterialPageRoute(builder: (_) => const ReceiptJsonImportPage()),
    );
    if (!mounted || result == null) return;

    final drafts = await Navigator.of(context).push<List<TransactionDraft>>(
      MaterialPageRoute(
        builder: (_) => TransactionFormPage(
          initialScan: result,
          initialType: TransactionType.expense,
          showFirstTransactionGuide: isFirstTransaction,
        ),
      ),
    );
    if (!mounted || drafts == null || drafts.isEmpty) return;
    await _saveDrafts(drafts);
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
      MaterialPageRoute(builder: (_) => TransactionDetailPage(entry: entry)),
    );
  }

  Future<void> _deleteTransaction(TransactionWithItems entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus transaksi?'),
        content: const Text(
          'Transaksi ini akan disembunyikan dari daftar. Tindakan ini tidak bisa dibatalkan dari aplikasi.',
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
    getIt<FfmAgentStatusController>().working(
      'Menghapus transaksi dan memperbarui konteks asisten...',
    );
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
    getIt<FfmAgentStatusController>().done(
      'Transaksi dihapus; konteks asisten diperbarui.',
    );
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Transaksi dihapus.')));
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
              (query.isEmpty || matchesFts || searchText.contains(query));
        })
        .toList(growable: false);
  }

  List<Transfer> get _visibleTransfers {
    if (_typeFilter == 'Pemasukan' || _typeFilter == 'Pengeluaran') {
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
          final searchText = [
            _accountLabel(transfer.fromAccountId),
            _accountLabel(transfer.toAccountId),
            transfer.note ?? '',
            _dateLabel(transfer.date),
            transfer.amount.toString(),
          ].join(' ').toLowerCase();
          return matchesType &&
              matchesMonth &&
              (query.isEmpty || searchText.contains(query));
        })
        .toList(growable: false);
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
    final result = await showModalBottomSheet<_TransactionFilter>(
      context: context,
      showDragHandle: true,
      builder: (context) => _TransactionFilterSheet(
        typeFilter: _typeFilter,
        currentMonthOnly: _currentMonthOnly,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _typeFilter = result.typeFilter;
      _currentMonthOnly = result.currentMonthOnly;
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
    getIt<FfmAgentStatusController>().working(
      'Menyimpan transaksi dan memperbarui konteks asisten...',
    );
    for (final draft in drafts) {
      await _saveDraft(draft, refresh: false, showMessage: false);
    }
    await _loadTransactions();
    if (!mounted) return;
    getIt<FfmAgentStatusController>().done(
      '${drafts.length} transaksi tersimpan; konteks asisten diperbarui.',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${drafts.length} transaksi berhasil dicatat.')),
    );
  }

  Future<void> _saveBatchDrafts(List<TransactionDraft> drafts) async {
    getIt<FfmAgentStatusController>().working(
      'Menyimpan beberapa transaksi dan memperbarui konteks asisten...',
    );
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
    getIt<FfmAgentStatusController>().done(
      '${drafts.length} transaksi tersimpan; konteks asisten diperbarui.',
    );
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
    getIt<FfmAgentStatusController>().working(
      transactionId == null
          ? 'Menyimpan transaksi dan memperbarui konteks asisten...'
          : 'Memperbarui transaksi dan konteks asisten...',
    );
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
    getIt<FfmAgentStatusController>().done(
      transactionId == null
          ? 'Transaksi tersimpan; konteks asisten diperbarui.'
          : 'Transaksi diperbarui; konteks asisten diperbarui.',
    );
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
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleTransactions = _visibleTransactions;
    final visibleTransfers = _visibleTransfers;
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
                  if (widget.onOpenAssistant != null)
                    IconButton(
                      tooltip: 'Buka Asisten FFM',
                      onPressed: widget.onOpenAssistant,
                      icon: const Icon(Icons.auto_awesome_outlined),
                    ),
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
                    icon: const Icon(Icons.tune),
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
                        case 'receipt_json':
                          _openReceiptJsonImport();
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
                          title: Text('Input cepat'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'json',
                        child: ListTile(
                          leading: Icon(Icons.data_object_rounded),
                          title: Text('Impor JSON'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'receipt_json',
                        child: ListTile(
                          leading: Icon(Icons.data_object_rounded),
                          title: Text('Impor JSON nota'),
                        ),
                      ),
                    ],
                  ),
                ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
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
                itemCount:
                    visibleTransactions.length + visibleTransfers.length + 2,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _TransactionFlowSummary(
                      incomeTotal: incomeTotal,
                      expenseTotal: expenseTotal,
                      transactionCount: visibleTransactions.length,
                      transferCount: visibleTransfers.length,
                    );
                  }
                  if (index == 1) {
                    return _AccountBalancesCard(
                      accounts: _accounts,
                      transactions: _transactions,
                      transfers: _transfers,
                      accountTypeLabel: _accountTypeLabel,
                    );
                  }
                  final transferIndex = index - 2;
                  if (transferIndex >= 0 &&
                      transferIndex < visibleTransfers.length) {
                    final transfer = visibleTransfers[transferIndex];
                    return _TransferHistoryCard(
                      transfer: transfer,
                      fromLabel: _accountLabel(transfer.fromAccountId),
                      toLabel: _accountLabel(transfer.toAccountId),
                      dateLabel: _dateLabel,
                      onDelete: () => _deleteTransfer(transfer),
                    );
                  }
                  final entry =
                      visibleTransactions[transferIndex -
                          visibleTransfers.length];
                  final item = entry.transaction;
                  final isIncome = item.amount >= 0;
                  final isGoalUsage =
                      item.goalId != null && item.source == 'goal_usage';
                  final isGoalContribution =
                      item.goalId != null && !isGoalUsage;
                  final merchantName = _merchantLabel(item.merchantId);
                  final itemSummary = entry.items.isEmpty
                      ? null
                      : entry.items
                            .map((receiptItem) => receiptItem.itemName)
                            .join(', ');
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
                                isGoalContribution
                                    ? 'Uang terkumpul untuk target'
                                    : isGoalUsage
                                    ? 'Penggunaan dana target'
                                    : _categoryLabel(item.categoryId),

                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              if (merchantName.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  merchantName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                              if (_accountLabel(item.accountId).isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.account_balance_wallet_outlined,
                                      size: 14,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        _accountLabel(item.accountId),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (itemSummary != null) ...[
                                const SizedBox(height: 3),
                                Text(
                                  itemSummary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                'Dipakai oleh: ${item.owner}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppColors.inkMuted),
                              ),
                              const SizedBox(height: 2),
                              HijriDateText(
                                date: item.date,
                                includeSeconds: true,
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

class TransactionFormPage extends StatefulWidget {
  const TransactionFormPage({
    super.key,
    this.initialScan,
    this.existingTransaction,
    this.initialType,
    this.initialNote,
    this.initialAmount,
    this.initialAccountName,
    this.initialCategoryName,
    this.initialDate,
    this.assistantMerchantName,
    this.assistantSlmFieldValues = const <String, String>{},
    this.showFirstTransactionGuide = false,
  });

  final ReceiptOcrResult? initialScan;
  final TransactionWithItems? existingTransaction;
  final TransactionType? initialType;
  final String? initialNote;
  final int? initialAmount;
  final String? initialAccountName;
  final String? initialCategoryName;
  final DateTime? initialDate;
  final String? assistantMerchantName;
  final Map<String, String> assistantSlmFieldValues;
  final bool showFirstTransactionGuide;

  @override
  State<TransactionFormPage> createState() => _TransactionFormPageState();
}

class _TransactionFormPageState extends State<TransactionFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _locationController = TextEditingController();
  final _itemNameController = TextEditingController();
  final _itemPriceController = TextEditingController();
  final _tagController = TextEditingController();
  final _speech = SpeechToText();
  final _offlineAi = getIt<OfflineAiEngineService>();

  var _type = TransactionType.expense;
  var _categories = <Category>[];
  var _merchants = <Merchant>[];
  var _masterTags = <Tag>[];
  var _accounts = <Account>[];
  var _parties = <TransactionParty>[];
  String? _categoryId;
  String? _merchantId;
  String? _accountId;
  var _categoriesLoading = true;
  var _partiesLoading = true;
  var _partyName = '';
  var _source = 'manual';
  String? _receiptRawText;
  String? _receiptNumber;
  int? _receiptPaidAmount;
  int? _receiptChangeAmount;
  var _date = DateTime.now();
  var _items = <ReceiptItemDraft>[];
  var _tags = <String>[];
  var _attachmentPaths = <String>[];
  var _listening = false;
  String? _voiceText;
  VoiceTransactionParseResult? _voiceResult;
  int? _selectedAccountBalance;
  var _accountBalanceLoading = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingTransaction;
    _type = widget.initialType ?? TransactionType.expense;
    if (existing != null) {
      _type = existing.transaction.amount >= 0
          ? TransactionType.income
          : TransactionType.expense;
      _categoryId = existing.transaction.categoryId;
      _merchantId = existing.transaction.merchantId;
      _accountId = existing.transaction.accountId;
      _partyName = existing.transaction.partyName ?? '';
      _source = existing.transaction.source ?? 'manual';
      _receiptRawText = existing.transaction.receiptRawText;
      _receiptNumber = existing.transaction.receiptNumber;
      _receiptPaidAmount = existing.transaction.receiptPaidAmount;
      _receiptChangeAmount = existing.transaction.receiptChangeAmount;
      _date = existing.transaction.date;
      _amountController.text = formatRupiahInput(
        existing.transaction.amount.abs().toString(),
      );
      _noteController.text = existing.transaction.note ?? '';
      _locationController.text = existing.transaction.location ?? '';
      _items = existing.items
          .map(
            (item) => ReceiptItemDraft(
              name: item.itemName,
              price: item.price,
              qty: item.qty,
            ),
          )
          .toList();
    }
    if (existing == null && widget.initialNote != null) {
      _noteController.text = widget.initialNote!;
    }
    if (existing == null && widget.initialAmount != null) {
      _amountController.text = formatRupiahInput(
        widget.initialAmount.toString(),
      );
    }
    if (existing == null && widget.initialDate != null) {
      _date = widget.initialDate!;
    }
    _loadCategories();
    _loadMerchants();
    _loadMasterTags();
    _loadAccounts();
    _loadParties();
    if (existing != null) _loadMetadata(existing.transaction.id);
    final scan = widget.initialScan;
    if (scan == null || existing != null) return;

    final total = scan.total ?? scan.itemsTotal;
    if (total > 0) _amountController.text = total.toString();
    if (scan.merchant != null) {
      _noteController.text = 'Toko: ${scan.merchant}';
      _merchantId = _matchMerchant(scan.merchant!);
    }
    _date = scan.date ?? _date;
    _categoryId = scan.categoryId ?? _categoryId;
    if (scan.imagePath != null && scan.imagePath!.isNotEmpty) {
      _attachmentPaths = [scan.imagePath!];
    }
    _partyName = '';
    _source = 'ocr';
    _receiptRawText = scan.rawText.isEmpty ? null : scan.rawText;
    _receiptNumber = scan.receiptNumber;
    _receiptPaidAmount = scan.paidAmount;
    _receiptChangeAmount = scan.changeAmount;

    _items = scan.items
        .map(
          (item) => ReceiptItemDraft(
            name: item.name,
            price: item.price,
            qty: item.quantity,
          ),
        )
        .toList();
  }

  Future<void> _loadParties() async {
    final parties =
        await (getIt<AppDatabase>().select(
                getIt<AppDatabase>().transactionParties,
              )
              ..where(
                (table) =>
                    table.householdId.equals(AppContext.householdId) &
                    table.isArchived.equals(false),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.name)]))
            .get();
    if (!mounted) return;
    setState(() {
      _parties = parties;
      _partiesLoading = false;
    });
  }

  Future<void> _loadAccounts() async {
    final accounts =
        await (getIt<AppDatabase>().select(getIt<AppDatabase>().accounts)
              ..where(
                (table) =>
                    table.householdId.equals(AppContext.householdId) &
                    table.isArchived.equals(false),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.name)]))
            .get();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      final targetName = widget.initialAccountName?.toLowerCase();
      if (_accountId == null && targetName != null) {
        final matches = accounts.where(
          (account) => account.name.toLowerCase() == targetName,
        );
        if (matches.isNotEmpty) _accountId = matches.first.id;
      }
    });
    if (_accountId != null) await _loadSelectedAccountBalance(_accountId);
  }

  Future<void> _loadSelectedAccountBalance(String? accountId) async {
    if (accountId == null) {
      if (mounted) setState(() => _selectedAccountBalance = null);
      return;
    }
    setState(() => _accountBalanceLoading = true);
    var balance = await getIt<GetAccountBookBalance>()(
      AppContext.householdId,
      accountId,
    );
    final existing = widget.existingTransaction;
    if (existing != null && existing.transaction.accountId == accountId) {
      balance -= existing.transaction.amount;
    }
    if (!mounted) return;
    setState(() {
      _selectedAccountBalance = balance;
      _accountBalanceLoading = false;
    });
  }

  Future<void> _loadMerchants() async {
    final merchants =
        await (getIt<AppDatabase>().select(getIt<AppDatabase>().merchants)
              ..where(
                (table) =>
                    table.householdId.equals(AppContext.householdId) &
                    table.isActive.equals(true),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.name)]))
            .get();
    if (!mounted) return;
    setState(() {
      _merchants = merchants;
      final rawMerchant = widget.initialScan?.merchant;
      if (rawMerchant != null && widget.existingTransaction == null) {
        _merchantId = _matchMerchant(rawMerchant);
      }
    });
  }

  Future<void> _loadMasterTags() async {
    final tags =
        await (getIt<AppDatabase>().select(getIt<AppDatabase>().tags)
              ..where(
                (table) =>
                    table.householdId.equals(AppContext.householdId) &
                    table.isArchived.equals(false),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.name)]))
            .get();
    if (!mounted) return;
    setState(() => _masterTags = tags);
  }

  String? _matchMerchant(String rawName) {
    final normalized = rawName.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    if (normalized.isEmpty) return null;
    for (final merchant in _merchants) {
      final candidate = merchant.name.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]'),
        '',
      );
      if (candidate.isNotEmpty &&
          (normalized.contains(candidate) || candidate.contains(normalized))) {
        return merchant.id;
      }
    }
    return null;
  }

  Future<void> _openMasterData() async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const MasterDataPage()));
    if (!mounted) return;
    await Future.wait([
      _loadCategories(),
      _loadMerchants(),
      _loadMasterTags(),
      _loadAccounts(),
      _loadParties(),
    ]);
  }

  String _categoryDisplayName(Category category) =>
      _transactionCategoryLabel(_categories, category);

  Future<void> _loadCategories() async {
    final categories =
        await (getIt<AppDatabase>().select(getIt<AppDatabase>().categories)
              ..where(
                (table) =>
                    table.householdId.equals(AppContext.householdId) &
                    table.isActive.equals(true),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.name)]))
            .get();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      final targetName = widget.initialCategoryName?.toLowerCase();
      if (_categoryId == null && targetName != null) {
        final matches = categories.where(
          (category) =>
              category.type ==
                  (_type == TransactionType.income ? 'income' : 'expense') &&
              category.name.toLowerCase() == targetName,
        );
        if (matches.length == 1) _categoryId = matches.single.id;
      }
      _categoriesLoading = false;
    });
  }

  Future<void> _loadMetadata(String transactionId) async {
    final database = getIt<AppDatabase>();
    final tagRows = await database
        .customSelect(
          'SELECT tags.name FROM tags INNER JOIN transaction_tags '
          'ON tags.id = transaction_tags.tag_id WHERE transaction_tags.transaction_id = ?',
          variables: [Variable.withString(transactionId)],
        )
        .get();
    final attachmentRows = await database
        .customSelect(
          'SELECT file_path FROM attachments WHERE transaction_id = ?',
          variables: [Variable.withString(transactionId)],
        )
        .get();
    if (!mounted) return;
    setState(() {
      _tags = tagRows
          .map((row) => row.data['name']?.toString() ?? '')
          .where((value) => value.isNotEmpty)
          .toList();
      _attachmentPaths = attachmentRows
          .map((row) => row.data['file_path']?.toString() ?? '')
          .where((value) => value.isNotEmpty)
          .toList();
    });
  }

  void _addTag(String value) {
    final allowed = _masterTags
        .map((tag) => tag.name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
    final incoming = value
        .split(',')
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .where((item) => allowed.contains(item))
        .where((item) => !_tags.contains(item))
        .toList();
    if (incoming.isEmpty) {
      if (allowed.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Buat tag di Data Utama dulu kalau mau memakainya.'),
          ),
        );
      }
      return;
    }
    setState(() => _tags = [..._tags, ...incoming]);
    _tagController.clear();
  }

  Future<void> _showTagInfo() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tag transaksi itu buat apa?'),
        content: const Text(
          'Tag adalah penanda tambahan untuk mengelompokkan transaksi lintas kategori. Contohnya wajib, sekolah, kerja, mudik, atau bisa ditunda. Tag tidak mengubah saldo dan tidak menggantikan kategori. Buat dan kelola tag dari Data Utama, lalu pilih tag yang diperlukan di sini.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Oke, paham'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result.isEmpty || !mounted) return;
    final paths = result
        .map((file) => file.path)
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toList();
    if (paths.isEmpty) return;
    setState(() {
      _attachmentPaths = {..._attachmentPaths, ...paths}.toList();
    });
  }

  Future<void> _showVoiceGuide() async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _VoiceInputGuide(isIncome: _type == TransactionType.income),
    );
  }

  Future<void> _startVoiceInput() async {
    if (_listening) {
      if (_offlineAi.isWhisperRecording) {
        await _finishWhisperInput();
      } else {
        await _speech.stop();
        if (mounted) setState(() => _listening = false);
      }
      return;
    }
    setState(() {
      _listening = true;
      _voiceText = null;
    });

    if (_offlineAi.isWhisperReady) {
      try {
        if (await _offlineAi.startWhisperRecording()) return;
      } on Object catch (error) {
        if (mounted) {
          setState(() {
            _listening = false;
            _voiceText = 'Voice Note offline belum bisa dimulai: $error';
          });
        }
        return;
      }
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted || status != 'done') return;
        setState(() => _listening = false);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _listening = false);
      },
    );
    if (!available) {
      if (mounted) {
        setState(() {
          _listening = false;
          _voiceText = 'Pengenalan suara tanpa internet belum tersedia di perangkat ini. Cek izin mikrofon dan bahasa Indonesia di pengaturan HP.';
        });
      }
      return;
    }
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        final text = result.recognizedWords.trim();
        setState(() => _voiceText = text.isEmpty ? null : text);
        if (result.finalResult && text.isNotEmpty) {
          unawaited(_applyVoiceResult(text));
        }
      },
      listenOptions: SpeechListenOptions(
        localeId: 'id_ID',
        listenFor: Duration(seconds: 20),
        pauseFor: Duration(seconds: 3),
        partialResults: false,
        onDevice: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  Future<void> _finishWhisperInput() async {
    try {
      final result = await _offlineAi.stopWhisperRecording();
      final transcript = result.text.trim();
      if (transcript.isEmpty) {
        if (mounted) setState(() => _listening = false);
        return;
      }
      await _applyVoiceResult(transcript);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _listening = false;
        _voiceText = 'Voice Note offline perlu dicoba lagi: $error';
      });
    }
  }

  Future<void> _applyVoiceResult(String transcript) async {
    final parsedMany = VoiceTransactionParser.parseMany(
      transcript,
      _categories,
      merchants: _merchants,
      accounts: _accounts,
      parties: _parties,
      tags: _masterTags,
    );
    if (!mounted || parsedMany.isEmpty) return;
    setState(() {
      _voiceText = transcript;
      _voiceResult = parsedMany.length == 1 ? parsedMany.first : null;
      _listening = false;
    });
    if (parsedMany.length > 1) {
      await _reviewVoiceBatch(parsedMany);
      return;
    }
    await _reviewVoiceResult(parsedMany.first);
  }

  Future<void> _reviewVoiceBatch(
    List<VoiceTransactionParseResult> parsedResults,
  ) async {
    final drafts = await showDialog<List<TransactionDraft>>(
      context: context,
      builder: (_) => _VoiceBatchReviewDialog(
        transcript: _voiceText ?? '',
        results: parsedResults,
        categories: _categories,
        merchants: _merchants,
        accounts: _accounts,
        parties: _parties,
        tagsMaster: _masterTags,
      ),
    );
    if (!mounted || drafts == null || drafts.isEmpty) return;
    Navigator.of(context).pop(drafts);
  }

  Future<void> _reviewVoiceResult(VoiceTransactionParseResult parsed) async {
    final parsedType = parsed.type == VoiceTransactionType.income
        ? TransactionType.income
        : TransactionType.expense;
    final nextType = parsed.hasExplicitType ? parsedType : _type;
    final existingCategory =
        _categoryId != null &&
            _categories.any((category) => category.id == _categoryId)
        ? _categoryId
        : null;
    final selectedCategory = parsed.hasExplicitType
        ? parsed.categoryId ?? existingCategory
        : existingCategory ?? parsed.categoryId;
    final selectedParty =
        parsed.partyName ??
        _partyNameOrEmpty(
          parsed.owner ?? '',
          nextType == TransactionType.income ? 'income_source' : 'used_by',
        );
    final review = await showDialog<_VoiceReviewDraft>(
      context: context,
      builder: (_) => _VoiceReviewDialog(
        transcript: _voiceText ?? parsed.note ?? '',
        type: nextType,
        amount: parsed.hasAmount
            ? parsed.amount
            : parseRupiah(_amountController.text),
        categoryId: selectedCategory,
        merchantId: parsed.merchantId ?? _merchantId,
        accountId: parsed.accountId ?? _accountId,
        partyName: selectedParty,
        note: parsed.note ?? _noteController.text,
        tags: {..._tags, ...parsed.tagNames}.toList(),
        categories: _categories,
        merchants: _merchants,
        accounts: _accounts,
        parties: _parties,
        tagsMaster: _masterTags,
      ),
    );
    if (!mounted || review == null) return;
    setState(() {
      _type = review.type;
      _amountController.text = formatRupiahInput(review.amount.toString());
      _categoryId = review.categoryId;
      _merchantId = review.merchantId;
      _accountId = review.accountId;
      _partyName = review.partyName;
      _noteController.text = review.note;
      _tags = review.tags;
      _source = 'voice';
    });
  }

  String _partyNameOrEmpty(String rawName, String kind) {
    final normalized = rawName.trim().toLowerCase();
    if (normalized.isEmpty) return '';
    final kindsToSearch = kind == 'used_by'
        ? ['used_by', 'husband', 'wife']
        : [kind];
    return _parties
            .where((party) => kindsToSearch.contains(party.kind))
            .where((party) => party.name.trim().toLowerCase() == normalized)
            .map((party) => party.name)
            .firstOrNull ??
        '';
  }

  List<TransactionParty> _partiesOfKind(String kind) =>
      _parties.where((party) => party.kind == kind).toList(growable: false);

  List<TransactionParty> _uniquePartiesByName(
    Iterable<TransactionParty> parties,
  ) {
    final seen = <String>{};
    return parties
        .where((party) {
          final name = party.name.trim().toLowerCase();
          return name.isNotEmpty && seen.add(name);
        })
        .toList(growable: false);
  }

  void _clearVoiceResult() {
    setState(() {
      _voiceText = null;
      _voiceResult = null;
      if (_source == 'voice') _source = 'manual';
    });
  }

  @override
  void dispose() {
    if (_offlineAi.isWhisperRecording) {
      unawaited(_offlineAi.cancelWhisperRecording());
    } else if (_listening) {
      unawaited(_speech.stop());
    }
    _amountController.dispose();
    _noteController.dispose();
    _locationController.dispose();
    _itemNameController.dispose();
    _itemPriceController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate() ||
        _categoryId == null ||
        _accountId == null) {
      if (_accountId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pilih rekening atau dompet dulu supaya arus uangnya jelas.',
            ),
          ),
        );
      }
      return;
    }
    final amount = parseRupiah(_amountController.text);
    Navigator.of(context).pop([
      TransactionDraft(
        type: _type,
        categoryId: _categoryId!,
        owner: OwnerLabels.family,
        date: _date,
        amount: _type == TransactionType.income ? amount : -amount,
        note: _noteController.text.trim(),
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        source: _source,
        merchantId: _merchantId,
        accountId: _accountId,
        goalId: null,
        partyName: _partyName.trim().isEmpty ? null : _partyName.trim(),
        receiptRawText: _receiptRawText,
        receiptNumber: _receiptNumber,
        receiptPaidAmount: _receiptPaidAmount,
        receiptChangeAmount: _receiptChangeAmount,
        items: _items,
        tags: _tags,
        attachmentPaths: _attachmentPaths,
        assistantMerchantName: widget.assistantMerchantName,
        assistantSlmFieldValues: widget.assistantSlmFieldValues,
      ),
    ]);
  }

  Widget _buildAccountBalancePreview({required bool isExpense}) {
    if (_accountBalanceLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: LinearProgressIndicator(minHeight: 3),
      );
    }
    final balance = _selectedAccountBalance;
    if (balance == null) return const SizedBox.shrink();
    final amount = parseRupiah(_amountController.text);
    final after = isExpense ? balance - amount : balance + amount;
    final afterColor = after < 0 ? AppColors.negative : AppColors.positive;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Saldo sekarang'),
                AppMoneyText(balance, compact: true),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_rounded, size: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Saldo setelah disimpan'),
                AppMoneyText(after, compact: true, color: afterColor),
                if (after < 0)
                  Text(
                    'Saldo jadi minus',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.negative,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSelector() {
    if (_accounts.isEmpty) {
      return AppCard(
        color: Theme.of(context).colorScheme.primaryContainer
            .withValues(alpha: .45),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rekening atau dompet belum ada',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Rekening adalah tempat uang berada, misalnya Tunai, BCA, DANA, atau GoPay. Tambahkan dulu di Data Utama sebelum mencatat transaksi.',
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _openMasterData,
                    icon: const Icon(Icons.tune_outlined),
                    label: const Text('Buka Data Utama'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final selectedAccounts = _accounts
        .where((account) => account.id == _accountId)
        .toList(growable: false);
    final isExpense = _type == TransactionType.expense;
    final accountColor = _accountId == null
        ? AppColors.negative
        : AppColors.primary;
    return AppCard(
      color: isExpense
          ? AppColors.negativeSoft.withValues(alpha: .32)
          : AppColors.positiveSoft.withValues(alpha: .45),
      border: BorderSide(color: accountColor, width: 1.6),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_rounded, color: accountColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isExpense
                      ? 'Sumber uang keluar · wajib diisi'
                      : 'Tujuan uang masuk · wajib diisi',
                  style: TextStyle(
                    color: accountColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SearchableDropdown<Account>(
            items: _accounts,
            selectedItem: selectedAccounts.isEmpty
                ? null
                : selectedAccounts.first,
            itemLabel: (account) =>
                '${account.name} · ${_accountTypeLabel(account.type)}',
            itemId: (account) => account.id,
            labelText: isExpense
                ? 'Rekening sumber pengeluaran'
                : 'Rekening tujuan pemasukan',
            helperText: isExpense
                ? 'Pengeluaran akan mengurangi saldo rekening ini.'
                : 'Pemasukan akan menambah saldo rekening ini.',
            searchHintText: 'Cari rekening atau dompet',
            cacheKey: 'transaksi.rekening',
            onChanged: (account) {
              setState(() => _accountId = account?.id);
              _loadSelectedAccountBalance(account?.id);
            },
            validator: (account) =>
                account == null ? 'Pilih rekening atau dompet dulu.' : null,
          ),
          _buildAccountBalancePreview(isExpense: isExpense),
        ],
      ),
    );
  }

  Widget _buildPartySelector({required bool isIncome}) {
    final options = isIncome
        ? _partiesOfKind('income_source')
        : _uniquePartiesByName([
            ..._partiesOfKind('husband'),
            ..._partiesOfKind('wife'),
            ..._partiesOfKind('used_by'),
          ]);
    final label = isIncome ? 'Sumber pemasukan' : 'Dipakai oleh';
    final help = isIncome
        ? 'Pilih sumber uangnya, misalnya gaji atau panen. Saldo tetap gabungan keluarga.'
        : 'Cuma penanda rincian pemakaian. Saldo tetap gabungan keluarga.';
    if (options.isEmpty) {
      return AppCard(
        color: Theme.of(context).colorScheme.primaryContainer
            .withValues(alpha: .45),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.tune_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label belum ada',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isIncome
                        ? 'Tambahkan sumber pemasukan di Data Utama supaya pilihan ini muncul di sini.'
                        : 'Tambahkan rincian pemakai di Data Utama kalau ingin menandainya.',
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _openMasterData,
                    icon: const Icon(Icons.tune_outlined),
                    label: const Text('Buka Data Utama'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final selectedParties = options
        .where((party) => party.name == _partyName)
        .toList(growable: false);
    return SearchableDropdown<TransactionParty>(
      items: options,
      selectedItem: selectedParties.isEmpty ? null : selectedParties.first,
      itemLabel: (party) => party.details?.trim().isNotEmpty == true
          ? '${party.name} · ${party.details}'
          : party.name,
      itemId: (party) => party.name,
      labelText: label,
      helperText: help,
      searchHintText: 'Cari sumber atau pemakai',
      cacheKey: 'transaksi.${isIncome ? 'sumber_pemasukan' : 'dipakai_oleh'}',
      onChanged: (party) => setState(() => _partyName = party?.name ?? ''),
      validator: isIncome
          ? (party) => party == null ? 'Pilih sumber pemasukan dulu.' : null
          : null,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _date,
      helpText: 'Pilih tanggal transaksi',
      cancelText: AppCopy.batal,
      confirmText: AppCopy.selesai,
    );
    if (picked != null) {
      setState(
        () => _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
          _date.second,
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      helpText: 'Pilih jam kejadian',
      cancelText: AppCopy.batal,
      confirmText: AppCopy.selesai,
    );
    if (picked != null) {
      setState(
        () => _date = DateTime(
          _date.year,
          _date.month,
          _date.day,
          picked.hour,
          picked.minute,
          _date.second,
        ),
      );
    }
  }

  void _addItem() {
    final name = _itemNameController.text.trim();
    final price = parseRupiah(_itemPriceController.text);
    if (name.isEmpty || price <= 0) {
      return;
    }
    setState(() {
      _items = [..._items, ReceiptItemDraft(name: name, price: price)];
      _syncAmountFromItems();
      _itemNameController.clear();
      _itemPriceController.clear();
    });
  }

  void _syncAmountFromItems() {
    final total = _items.fold<int>(
      0,
      (sum, item) => sum + (item.price * item.qty).round(),
    );
    if (total > 0) {
      _amountController.text = formatRupiahInput(total.toString());
    }
  }

  Future<void> _editItem(int index) async {
    final edited = await showDialog<ReceiptItemDraft>(
      context: context,
      builder: (_) => _ReceiptItemEditorDialog(item: _items[index]),
    );
    if (!mounted || edited == null) return;
    setState(() {
      _items[index] = edited;
      _syncAmountFromItems();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = _type == TransactionType.income;
    final scheme = Theme.of(context).colorScheme;
    final flowColor = isIncome ? AppColors.positive : AppColors.negative;
    final flowLabel = isIncome ? 'Uang masuk' : 'Uang keluar';
    final categoryOptions = _transactionCategoryOptions(
      _categories,
      isIncome ? 'income' : 'expense',
      selectedId: _categoryId,
    );
    final voiceResult = _voiceResult;
    final voiceCategoryId = voiceResult?.categoryId;
    final voiceCategoryName = voiceCategoryId == null
        ? 'Belum terbaca'
        : _categories
                  .where((category) => category.id == voiceCategoryId)
                  .map((category) => category.name)
                  .firstOrNull ??
              'Belum terbaca';
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.transactions,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.existingTransaction == null
                ? (isIncome ? 'Tambah pemasukan' : 'Tambah pengeluaran')
                : (isIncome ? 'Ubah pemasukan' : 'Ubah pengeluaran'),
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (widget.showFirstTransactionGuide)
                _FirstTransactionGuide(
                  isIncome: isIncome,
                  onOpenLiability: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LiabilityReceivablePage(),
                      ),
                    );
                  },
                ),
              if (widget.showFirstTransactionGuide) const SizedBox(height: 16),
              AppCard(
                color: flowColor.withValues(alpha: isIncome ? .16 : .10),
                border: BorderSide(color: flowColor, width: isIncome ? 2 : 1.4),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isIncome
                              ? Icons.south_west_rounded
                              : Icons.north_east_rounded,
                          color: flowColor,
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                flowLabel,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: flowColor,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              Text(
                                isIncome
                                    ? 'Menambah saldo keluarga'
                                    : 'Mengurangi saldo keluarga',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cara input suara',
                          onPressed: _showVoiceGuide,
                          icon: const Icon(Icons.help_outline_rounded),
                        ),
                        IconButton.filledTonal(
                          tooltip: _listening
                              ? 'Berhenti mendengar'
                              : 'Isi dengan suara',
                          onPressed: _categoriesLoading
                              ? null
                              : _startVoiceInput,
                          icon: Icon(
                            _listening
                                ? Icons.stop_rounded
                                : Icons.mic_none_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _listening
                          ? 'Ngomong sekarang: sebut arah, nominal, dan keperluannya.'
                          : 'Tekan mikrofon, ucapkan satu kalimat pendek, lalu cek hasilnya.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: flowColor.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Jenis transaksi: $flowLabel',
                        style: TextStyle(
                          color: flowColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [RupiahInputFormatter()],
                      decoration: InputDecoration(
                        labelText: 'Nominal $flowLabel',
                        prefixText: 'Rp ',
                        hintText: '0',
                        filled: true,
                        fillColor: scheme.surfaceContainerLowest,
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        final amount = parseRupiah(value ?? '');
                        if (amount <= 0) {
                          return AppCopy.nominalTidakValid;
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_voiceText != null)
                AppCard(
                  color: scheme.primaryContainer.withValues(alpha: .45),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.graphic_eq_rounded, color: scheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _listening
                                  ? 'Lagi mendengarkan…'
                                  : 'Hasil suara: “$_voiceText”',
                            ),
                          ),
                        ],
                      ),
                      if (!_listening && voiceResult != null) ...[
                        const SizedBox(height: 14),
                        const Text(
                          'Cek dulu hasilnya. Data belum tersimpan sampai kamu menekan Simpan.',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        _VoiceResultLine(
                          label: 'Arah transaksi',
                          value: voiceResult.hasExplicitType ? flowLabel : 'Belum disebut — pilih Uang masuk atau Uang keluar',
                          isValid: voiceResult.hasExplicitType,
                        ),
                        _VoiceResultLine(
                          label: 'Nominal',
                          value: voiceResult.hasAmount
                              ? 'Rp ${formatRupiahInput(voiceResult.amount.toString())}'
                              : 'Belum terbaca — isi manual',
                          isValid: voiceResult.hasAmount,
                        ),
                        _VoiceResultLine(
                          label: 'Kategori',
                          value: voiceCategoryName,
                          isValid: voiceResult.categoryId != null,
                        ),
                        _VoiceResultLine(
                          label: 'Dipakai oleh / sumber',
                          value:
                              voiceResult.partyName ??
                              voiceResult.owner ??
                              'Belum diatur',
                          isValid: voiceResult.partyName != null,
                        ),
                        _VoiceResultLine(
                          label: 'Toko / rekening',
                          value:
                              voiceResult.merchantId != null ||
                                  voiceResult.accountId != null
                              ? 'Terbaca dari Data Utama'
                              : 'Belum cocok — pilih manual di editor',
                          isValid:
                              voiceResult.merchantId != null ||
                              voiceResult.accountId != null,
                        ),
                        _VoiceResultLine(
                          label: 'Tag',
                          value: voiceResult.tagNames.isEmpty
                              ? 'Belum ada — boleh ditambahkan'
                              : voiceResult.tagNames
                                    .map((tag) => '#$tag')
                                    .join(', '),
                          isValid: voiceResult.tagNames.isNotEmpty,
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _reviewVoiceResult(voiceResult),
                            icon: const Icon(Icons.edit_note_rounded),
                            label: const Text(
                              'Tinjau dan terapkan ke transaksi',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            TextButton.icon(
                              onPressed: _startVoiceInput,
                              icon: const Icon(Icons.mic_none_rounded),
                              label: const Text('Dengar lagi'),
                            ),
                            TextButton.icon(
                              onPressed: _clearVoiceResult,
                              icon: const Icon(Icons.clear_rounded),
                              label: const Text('Hapus hasil'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              if (_voiceText != null) const SizedBox(height: 12),
              AppSectionHeader(
                title: isIncome
                    ? '1. Lokasi uang masuk'
                    : '1. Lokasi uang keluar',
                helpText: isIncome
                    ? 'Pilih rekening tujuan. Saldo rekening ini akan bertambah setelah disimpan.'
                    : 'Pilih rekening sumber. Saldo rekening ini akan berkurang setelah disimpan.',
              ),
              const SizedBox(height: 8),
              _buildAccountSelector(),
              const SizedBox(height: 16),
              AppSectionHeader(
                title: isIncome
                    ? '2. Kategori pemasukan'
                    : '2. Kategori pengeluaran',
                helpText: isIncome
                    ? 'Contoh: gaji, panen, bonus, atau pemberian.'
                    : 'Contoh: belanja, listrik, BBM, makan, atau biaya admin.',
              ),
              const SizedBox(height: 8),
              if (_categoriesLoading)
                const LinearProgressIndicator()
              else if (categoryOptions.isEmpty)
                AppCard(
                  color: Theme.of(context).colorScheme.errorContainer
                      .withValues(alpha: .45),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.category_outlined,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kategori ${_type == TransactionType.income ? 'pemasukan' : 'pengeluaran'} masih kosong',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Buat kategori ${_type == TransactionType.income ? 'pemasukan' : 'pengeluaran'} dulu supaya transaksi bisa masuk ke laporan dan Anggaran.',
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _openMasterData,
                              icon: const Icon(Icons.add),
                              label: const Text('Buka Data Utama'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                SearchableDropdown(
                  items: categoryOptions,
                  selectedItem: categoryOptions
                      .where((category) => category.id == _categoryId)
                      .firstOrNull,
                  itemLabel: _categoryDisplayName,
                  itemId: (category) => category.id,
                  labelText: 'Kategori uang masuk / keluar',
                  helperText: 'Pilih sendiri. Tidak ada kategori yang dipilih otomatis.',
                  searchHintText: 'Cari kategori transaksi',
                  cacheKey: 'transaksi.kategori',
                  onChanged: (category) {
                    if (category != null) {
                      setState(() => _categoryId = category.id);
                    }
                  },
                  validator: (category) =>
                      category == null ? 'Pilih kategori dulu.' : null,
                ),
              if (_type == TransactionType.expense)
                AppCard(
                  color: Theme.of(context).colorScheme.primaryContainer
                      .withValues(alpha: .45),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Kategori ini akan dihitung otomatis ke pos Anggaran yang sesuai. Target uang terkumpul dicatat lewat menu khusus, bukan di sini.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              AppSectionHeader(
                title: isIncome
                    ? '3. Waktu dan catatan pemasukan'
                    : '3. Rincian tambahan',
                helpText: isIncome
                    ? 'Catat kapan uang diterima dan tambahkan keterangan bila perlu.'
                    : 'Buka bagian ini kalau ingin mengisi toko, lokasi, tanggal, sumber/pemakai, atau catatan.',
              ),
              const SizedBox(height: 4),
              ExpansionTile(
                initiallyExpanded:
                    isIncome ||
                    _merchantId != null ||
                    _locationController.text.trim().isNotEmpty ||
                    _partyName.trim().isNotEmpty,
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                leading: Icon(
                  isIncome ? Icons.event_note_outlined : Icons.tune_outlined,
                ),
                title: Text(
                  isIncome ? 'Atur waktu dan catatan' : 'Buka rincian tambahan',
                ),
                subtitle: Text(
                  isIncome
                      ? 'Tanggal, jam, sumber pemasukan, dan catatan'
                      : 'Toko, lokasi, waktu, sumber/pemakai, dan catatan',
                ),
                children: [
                  if (!isIncome) ...[
                    if (_merchants.isNotEmpty)
                      SearchableDropdown(
                        items: _merchants,
                        selectedItem: _merchants
                            .where((merchant) => merchant.id == _merchantId)
                            .firstOrNull,
                        itemLabel: (merchant) =>
                            merchant.details?.trim().isNotEmpty == true
                            ? '${merchant.name} · ${merchant.details}'
                            : merchant.name,
                        itemId: (merchant) => merchant.id,
                        labelText: 'Toko / tempat',
                        helperText: 'Pilih dari Data Utama agar nama dan rinciannya konsisten.',
                        searchHintText: 'Cari toko atau tempat',
                        cacheKey: 'transaksi.toko',
                        allowClear: true,
                        onChanged: (merchant) =>
                            setState(() => _merchantId = merchant?.id),
                      )
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _openMasterData,
                          icon: const Icon(Icons.tune_rounded),
                          label: const Text('Atur toko di Data Utama'),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _locationController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Lokasi transaksi',
                        hintText: 'Misalnya pasar, rumah, atau kantor',
                        helperText: 'Rekening = tempat uang berada. Lokasi = tempat kejadian.',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('Tanggal kejadian'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_dateLabel(_date)),
                        HijriDateLabel(date: _date),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickDate,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_outlined),
                    title: const Text('Jam kejadian'),
                    subtitle: Text(formatJam(_date)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickTime,
                  ),
                  if (isDataSusulan(_date, now: DateTime.now()))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Tanggal kejadian berbeda dari hari ini. Data ini akan ditandai sebagai susulan.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: AppColors.warning),
                      ),
                    ),
                  if (_partiesLoading)
                    const LinearProgressIndicator()
                  else
                    _buildPartySelector(isIncome: isIncome),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _noteController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: AppCopy.catatanOpsional,
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppSectionHeader(
                title: isIncome
                    ? '4. Opsi tambahan pemasukan (opsional)'
                    : '4. Tag dan lampiran',
                helpText: isIncome
                    ? 'Tag untuk menandai sumber pemasukan. Lampiran untuk bukti penerimaan bila ada.'
                    : 'Tag membantu pencarian dan pengelompokan. Lampiran hanya sebagai bukti transaksi.',
              ),
              const SizedBox(height: 4),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isIncome ? 'Bukti dan penanda' : 'Tag dan lampiran',
                            style: AppTextStyles.labelCaps,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Buka penjelasan Tag',
                          onPressed: _showTagInfo,
                          icon: const Icon(Icons.info_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _masterTags.isEmpty
                          ? 'Belum ada tag. Atur dulu dari Data Utama.'
                          : (isIncome
                                ? 'Opsional. Tag tidak mengubah saldo; lampiran hanya sebagai bukti penerimaan.'
                                : 'Pilih penanda dari Data Utama. Tag tidak mengubah saldo.'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_masterTags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final tag in _masterTags)
                            FilterChip(
                              label: Text('#${tag.name}'),
                              selected: _tags.contains(
                                tag.name.trim().toLowerCase(),
                              ),
                              onSelected: (_) => _addTag(tag.name),
                            ),
                        ],
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: TextButton.icon(
                          onPressed: _openMasterData,
                          icon: const Icon(Icons.tune_rounded),
                          label: const Text('Atur tag di Data Utama'),
                        ),
                      ),
                    if (_tags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final tag in _tags)
                            InputChip(
                              label: Text('#$tag'),
                              onDeleted: () => setState(
                                () => _tags = [..._tags]..remove(tag),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickAttachments,
                      icon: const Icon(Icons.attach_file_rounded),
                      label: Text(
                        isIncome
                            ? 'Tambah bukti penerimaan (foto/PDF)'
                            : 'Tambah foto atau PDF nota',
                      ),
                    ),
                    if (_attachmentPaths.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      for (final path in _attachmentPaths)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.insert_drive_file_outlined),
                          title: Text(
                            path.split(RegExp(r'[/\\\\]')).last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: 'Hapus lampiran',
                            onPressed: () => setState(
                              () =>
                                  _attachmentPaths = [..._attachmentPaths]
                                    ..remove(path),
                            ),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (!isIncome) ...[
                const AppSectionHeader(
                  title: '5. Rincian nota dan banyak item',
                  helpText: 'Pakai bagian ini kalau satu transaksi punya beberapa barang atau detail nota.',
                ),
                const SizedBox(height: 4),
                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Rincian nota',
                              style: AppTextStyles.labelCaps,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _showAddItemSheet,
                            icon: const Icon(Icons.add),
                            label: const Text(AppCopy.tambah),
                          ),
                        ],
                      ),
                      if (_items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Belum ada item nota. Bagian ini boleh dilewati.',
                          ),
                        )
                      else
                        ..._items.map(
                          (item) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.name),
                            subtitle: item.qty == 1
                                ? null
                                : Text('Jumlah ${item.qty.toStringAsFixed(2)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppMoneyText(item.price, compact: true),
                                IconButton(
                                  tooltip: 'Ubah item',
                                  onPressed: () =>
                                      _editItem(_items.indexOf(item)),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Hapus item',
                                  onPressed: () => setState(() {
                                    _items.remove(item);
                                    _syncAmountFromItems();
                                  }),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: Text(
                    widget.existingTransaction == null
                        ? AppCopy.simpanTransaksi
                        : 'Simpan perubahan',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddItemSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tambah item nota',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _itemNameController,
              decoration: const InputDecoration(labelText: 'Nama item'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _itemPriceController,
              keyboardType: TextInputType.number,
              inputFormatters: const [RupiahInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Harga item',
                prefixText: 'Rp ',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                _addItem();
                Navigator.pop(context);
              },
              child: const Text('Tambahkan item'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  String _accountTypeLabel(String type) {
    return switch (type) {
      'cash' => 'Tunai',
      'bank' => 'Rekening',
      'ewallet' => 'Dompet digital',
      _ => type,
    };
  }

  String _dateLabel(DateTime date) => formatTanggalLengkap(date);
}

class _NewEntryChoiceTile extends StatelessWidget {
  const _NewEntryChoiceTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: .16),
                foregroundColor: color,
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class GoalContributionFormPage extends StatefulWidget {
  const GoalContributionFormPage({
    super.key,
    this.existingTransaction,
    this.usage = false,
  });

  final TransactionWithItems? existingTransaction;
  final bool usage;

  @override
  State<GoalContributionFormPage> createState() =>
      _GoalContributionFormPageState();
}

class _GoalContributionFormPageState extends State<GoalContributionFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  var _goals = <GoalEntity>[];
  var _accounts = <Account>[];
  String? _goalId;
  String? _accountId;
  DateTime _date = DateTime.now();
  int? _accountBalance;
  var _goalsLoading = true;
  var _accountsLoading = true;
  var _balanceLoading = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingTransaction;
    if (existing != null) {
      _goalId = existing.transaction.goalId;
      _accountId = existing.transaction.accountId;
      _date = existing.transaction.date;
      _amountController.text = formatRupiahInput(
        existing.transaction.amount.abs().toString(),
      );
      _noteController.text = existing.transaction.note ?? '';
    }
    _loadGoals();
    _loadAccounts();
  }

  bool get _isUsage =>
      widget.usage ||
      widget.existingTransaction?.transaction.source == 'goal_usage';

  Future<void> _loadGoals() async {
    final goals = await getIt<GetGoals>()(AppContext.householdId);
    if (!mounted) return;
    setState(() {
      _goals = goals
          .where(
            (goal) => _isUsage
                ? goal.currentAmount > 0 || goal.id == _goalId
                : goal.currentAmount < goal.targetAmount || goal.id == _goalId,
          )
          .toList(growable: false);
      _goalsLoading = false;
    });
  }

  Future<void> _loadAccounts() async {
    final accounts =
        await (getIt<AppDatabase>().select(getIt<AppDatabase>().accounts)
              ..where(
                (table) =>
                    table.householdId.equals(AppContext.householdId) &
                    table.isArchived.equals(false),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.name)]))
            .get();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _accountsLoading = false;
    });
    await _loadBalance(_accountId);
  }

  Future<void> _loadBalance(String? accountId) async {
    if (accountId == null) {
      if (mounted) setState(() => _accountBalance = null);
      return;
    }
    setState(() => _balanceLoading = true);
    var balance = await getIt<GetAccountBookBalance>()(
      AppContext.householdId,
      accountId,
    );
    final existing = widget.existingTransaction;
    if (existing != null && existing.transaction.accountId == accountId) {
      balance -= existing.transaction.amount;
    }
    if (!mounted) return;
    setState(() {
      _accountBalance = balance;
      _balanceLoading = false;
    });
  }

  Future<void> _openGoalForm() async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const GoalFormPage()));
    if (!mounted) return;
    await _loadGoals();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _date,
      helpText: 'Pilih tanggal alokasi',
      cancelText: AppCopy.batal,
      confirmText: AppCopy.selesai,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _date.hour,
        _date.minute,
        _date.second,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      helpText: 'Pilih jam alokasi',
      cancelText: AppCopy.batal,
      confirmText: AppCopy.selesai,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = DateTime(
        _date.year,
        _date.month,
        _date.day,
        picked.hour,
        picked.minute,
        _date.second,
      );
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final amount = parseRupiah(_amountController.text);
    final goal = _goals.where((item) => item.id == _goalId).firstOrNull;
    if (goal == null || _accountId == null || amount <= 0) return;
    if (_isUsage && amount > goal.currentAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nominal pemakaian melebihi dana target yang tersedia.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop([
      TransactionDraft(
        type: TransactionType.expense,
        categoryId: _isUsage ? goal.categoryId : null,
        owner: OwnerLabels.family,
        date: _date,
        amount: -amount,
        note: _noteController.text.trim(),
        source: _isUsage ? 'goal_usage' : 'goal_contribution',
        accountId: _accountId,
        goalId: goal.id,
        items: const [],
      ),
    ]);
  }

  Widget _buildBalancePreview() {
    if (_balanceLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: LinearProgressIndicator(minHeight: 3),
      );
    }
    final balance = _accountBalance;
    if (balance == null) return const SizedBox.shrink();
    final amount = parseRupiah(_amountController.text);
    final after = balance - amount;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Saldo sebelum alokasi'),
                AppMoneyText(balance, compact: true),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_rounded, size: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Saldo setelah alokasi'),
                AppMoneyText(
                  after,
                  compact: true,
                  color: after < 0 ? AppColors.negative : AppColors.positive,
                ),
                if (after < 0)
                  Text(
                    'Saldo jadi minus',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.negative,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedGoal = _goals.where((goal) => goal.id == _goalId).firstOrNull;
    final amount = parseRupiah(_amountController.text);
    final projected = selectedGoal == null
        ? null
        : selectedGoal.currentAmount + (_isUsage ? -amount : amount);
    final progress = selectedGoal == null || selectedGoal.targetAmount <= 0
        ? 0.0
        : (selectedGoal.currentAmount / selectedGoal.targetAmount).clamp(
            0.0,
            1.0,
          );
    final projectedProgress =
        selectedGoal == null || selectedGoal.targetAmount <= 0
        ? 0.0
        : (projected! / selectedGoal.targetAmount).clamp(0.0, 1.0);
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.transactions,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isUsage
                ? (widget.existingTransaction == null
                      ? 'Pakai dana target'
                      : 'Ubah pemakaian target')
                : (widget.existingTransaction == null
                      ? 'Isi target uang terkumpul'
                      : 'Ubah isi target'),
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              AppCard(
                color: AppColors.primarySoft.withValues(alpha: .55),
                border: BorderSide(color: AppColors.primary, width: 1.5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isUsage
                          ? 'Pakai dana target'
                          : 'Isi target tanpa kategori',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isUsage
                          ? 'Pilih target, tempat uang, dan nominal yang mau dipakai. Saldo rekening berkurang sekali dan saldo target ikut berkurang.'
                          : 'Pilih target, tempat uang, dan nominal alokasi. Ini bukan transaksi belanja, jadi tidak perlu memilih kategori.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppSectionHeader(
                title: '1. Target tujuan',
                helpText: _isUsage
                    ? 'Pilih target yang dananya mau dipakai.'
                    : 'Tentukan target yang ingin kamu tambah progresnya.',
              ),
              const SizedBox(height: 8),
              if (_goalsLoading)
                const LinearProgressIndicator()
              else if (_goals.isEmpty)
                AppCard(
                  color: Theme.of(context).colorScheme.primaryContainer
                      .withValues(alpha: .45),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Belum ada target aktif',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Buat target dulu, misalnya dana darurat, sekolah, atau kebutuhan tertentu.',
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _openGoalForm,
                        icon: const Icon(Icons.add),
                        label: const Text('Buat target sekarang'),
                      ),
                    ],
                  ),
                )
              else ...[
                DropdownButtonFormField<String>(
                  initialValue: _goalId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _isUsage
                        ? 'Target yang dipakai · wajib dipilih'
                        : 'Target uang terkumpul · wajib dipilih',
                    helperText: 'Target tidak mengubah saldo keluarga menjadi saldo kedua.',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                  items: _goals
                      .map(
                        (goal) => DropdownMenuItem<String>(
                          value: goal.id,
                          child: Text(
                            goal.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => setState(() => _goalId = value),
                  validator: (value) =>
                      value == null ? 'Pilih target dulu.' : null,
                ),
                if (selectedGoal != null) ...[
                  const SizedBox(height: 12),
                  AppCard(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Progres ${selectedGoal.name}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: progress),
                        const SizedBox(height: 6),
                        Text(
                          '${formatRupiahInput(selectedGoal.currentAmount.toString())} dari ${formatRupiahInput(selectedGoal.targetAmount.toString())} · ${(progress * 100).round()}%',
                        ),
                        if (amount > 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            '${_isUsage ? 'Setelah dipakai' : 'Setelah disimpan'}: ${formatRupiahInput(projected!.toString())} · ${(projectedProgress * 100).round()}%',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 18),
              AppSectionHeader(
                title: '2. Tempat uang',
                helpText: _isUsage
                    ? 'Pilih rekening atau cash tempat dana target benar-benar dipakai.'
                    : 'Pilih tempat uang yang dipakai untuk alokasi target: tunai, bank, atau dompet digital.',
              ),
              const SizedBox(height: 8),
              if (_accountsLoading)
                const LinearProgressIndicator()
              else if (_accounts.isEmpty)
                const Text('Tambahkan rekening atau tunai di Data Utama dulu.')
              else
                AppCard(
                  color: AppColors.negativeSoft.withValues(alpha: .28),
                  border: const BorderSide(
                    color: AppColors.negative,
                    width: 1.4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tempat uang yang dipakai · wajib dipilih',
                        style: TextStyle(
                          color: AppColors.negative,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SearchableDropdown<Account>(
                        items: _accounts,
                        selectedItem: _accounts
                            .where((account) => account.id == _accountId)
                            .firstOrNull,
                        itemLabel: (account) => account.name,
                        itemId: (account) => account.id,
                        labelText: 'Ambil uang dari',
                        helperText: _isUsage
                            ? 'Saldo tempat uang ini berkurang satu kali; progres target ikut berkurang satu kali.'
                            : 'Saldo tempat uang ini berkurang satu kali; progres target bertambah satu kali.',
                        searchHintText: 'Cari rekening atau dompet',
                        cacheKey: 'target.tempat_uang',
                        onChanged: (account) {
                          setState(() => _accountId = account?.id);
                          _loadBalance(account?.id);
                        },
                        validator: (account) => account == null
                            ? 'Pilih rekening sumber dulu.'
                            : null,
                      ),
                      _buildBalancePreview(),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              AppSectionHeader(
                title: '3. Isi nominal alokasi',
                helpText: _isUsage
                    ? 'Masukkan jumlah dana target yang mau dipakai.'
                    : 'Masukkan jumlah uang yang mau ditambahkan ke target.',
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: const [RupiahInputFormatter()],
                decoration: InputDecoration(
                  labelText: _isUsage
                      ? 'Nominal yang dipakai · wajib diisi'
                      : 'Nominal yang dialokasikan · wajib diisi',
                  prefixText: 'Rp ',
                  hintText: '0',
                  helperText: _isUsage
                      ? 'Nominal ini mengurangi rekening sumber dan mengurangi progres target.'
                      : 'Nominal ini mengurangi rekening sumber dan menambah progres target.',
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) => parseRupiah(value ?? '') <= 0
                    ? (_isUsage
                          ? 'Isi nominal pemakaian dulu.'
                          : 'Isi nominal alokasi dulu.')
                    : null,
              ),
              const SizedBox(height: 18),
              AppSectionHeader(
                title: '4. Waktu dan catatan',
                helpText:
                    'Tanggal bisa diubah kalau alokasi dicatat belakangan.',
              ),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Tanggal kejadian alokasi'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatTanggalLengkap(_date)),
                    HijriDateLabel(date: _date),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickDate,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('Jam kejadian alokasi'),
                subtitle: Text(formatJam(_date)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickTime,
              ),
              TextFormField(
                controller: _noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Catatan target · opsional',
                  hintText: 'Contoh: sisihan dari pemasukan minggu ini',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _goals.isEmpty || _accounts.isEmpty ? null : _save,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Simpan alokasi target'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum TransactionType { income, expense }

class TransactionDraft {
  const TransactionDraft({
    required this.type,
    required this.categoryId,
    required this.owner,
    required this.date,
    required this.amount,
    required this.note,
    this.location,
    this.source = 'manual',
    this.merchantId,
    this.accountId,
    this.goalId,
    this.partyName,
    this.receiptRawText,
    this.receiptNumber,
    this.receiptPaidAmount,
    this.receiptChangeAmount,
    required this.items,
    this.tags = const [],
    this.attachmentPaths = const [],
    this.assistantMerchantName,
    this.assistantSlmFieldValues = const <String, String>{},
  });

  final TransactionType type;
  final String? categoryId;
  final String owner;
  final DateTime date;
  final int amount;
  final String note;
  final String? location;
  final String source;
  final String? merchantId;
  final String? accountId;
  final String? goalId;
  final String? partyName;
  final String? receiptRawText;
  final String? receiptNumber;
  final int? receiptPaidAmount;
  final int? receiptChangeAmount;
  final List<ReceiptItemDraft> items;
  final List<String> tags;
  final List<String> attachmentPaths;
  final String? assistantMerchantName;
  final Map<String, String> assistantSlmFieldValues;
}

class ReceiptItemDraft {
  const ReceiptItemDraft({
    required this.name,
    required this.price,
    this.qty = 1,
  });

  final String name;
  final int price;
  final double qty;
}

class _TransactionFilter {
  const _TransactionFilter({
    required this.typeFilter,
    required this.currentMonthOnly,
  });

  final String typeFilter;
  final bool currentMonthOnly;
}

class _TransactionFilterSheet extends StatefulWidget {
  const _TransactionFilterSheet({
    required this.typeFilter,
    required this.currentMonthOnly,
  });

  final String typeFilter;
  final bool currentMonthOnly;

  @override
  State<_TransactionFilterSheet> createState() =>
      _TransactionFilterSheetState();
}

class _TransactionFilterSheetState extends State<_TransactionFilterSheet> {
  late String _typeFilter;
  late bool _currentMonthOnly;

  @override
  void initState() {
    super.initState();
    _typeFilter = widget.typeFilter;
    _currentMonthOnly = widget.currentMonthOnly;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saring transaksi',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Text('Jenis', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Semua', label: Text('Semua')),
              ButtonSegment(value: 'Pemasukan', label: Text('Pemasukan')),
              ButtonSegment(value: 'Pengeluaran', label: Text('Pengeluaran')),
              ButtonSegment(value: 'Transfer', label: Text('Transfer')),
            ],
            selected: {_typeFilter},
            onSelectionChanged: (value) {
              setState(() => _typeFilter = value.first);
            },
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bulan berjalan saja'),
            value: _currentMonthOnly,
            onChanged: (value) => setState(() => _currentMonthOnly = value),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(
                    context,
                    const _TransactionFilter(
                      typeFilter: 'Semua',
                      currentMonthOnly: false,
                    ),
                  ),
                  child: const Text('Reset'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    _TransactionFilter(
                      typeFilter: _typeFilter,
                      currentMonthOnly: _currentMonthOnly,
                    ),
                  ),
                  child: const Text('Terapkan'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransferDraft {
  const _TransferDraft({
    required this.fromAccountId,
    required this.toAccountId,
    required this.amount,
    required this.adminFee,
    required this.date,
    required this.note,
  });

  final String fromAccountId;
  final String toAccountId;
  final int amount;
  final int adminFee;
  final DateTime date;
  final String note;
}

class _TransferFormDialog extends StatefulWidget {
  const _TransferFormDialog({required this.accounts});

  final List<Account> accounts;

  @override
  State<_TransferFormDialog> createState() => _TransferFormDialogState();
}

class _TransferFormDialogState extends State<_TransferFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _adminFeeController = TextEditingController();
  final _noteController = TextEditingController();
  late String? _fromAccountId;
  late String? _toAccountId;
  var _date = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fromAccountId = widget.accounts.firstOrNull?.id;
    _toAccountId = widget.accounts.length > 1 ? widget.accounts[1].id : null;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _adminFeeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _accountLabel(Account account) {
    final type = switch (account.type) {
      'cash' => 'Tunai',
      'bank' => 'Rekening',
      'ewallet' => 'Dompet digital',
      _ => account.type,
    };
    return '${account.name} · $type';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _date,
      helpText: 'Pilih tanggal transfer',
      cancelText: AppCopy.batal,
      confirmText: 'Pakai tanggal ini',
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_fromAccountId == null || _toAccountId == null) return;
    if (_fromAccountId == _toAccountId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rekening asal dan tujuan harus beda.')),
      );
      return;
    }
    final amount = parseRupiah(_amountController.text);
    if (amount <= 0) return;
    Navigator.of(context).pop(
      _TransferDraft(
        fromAccountId: _fromAccountId!,
        toAccountId: _toAccountId!,
        amount: amount,
        adminFee: parseRupiah(_adminFeeController.text),
        date: _date,
        note: _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.swap_horiz_rounded),
          SizedBox(width: 8),
          Text('Transfer saldo antar tempat'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Pindahkan saldo dari Rekening, Tunai, atau Dompet digital ke tempat lain. Transfer tidak dihitung sebagai pemasukan atau pengeluaran.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                SearchableDropdown(
                  items: widget.accounts,
                  selectedItem: widget.accounts
                      .where((account) => account.id == _fromAccountId)
                      .firstOrNull,
                  itemLabel: _accountLabel,
                  itemId: (account) => account.id,
                  labelText: 'Dari tempat uang',
                  searchHintText: 'Cari rekening, tunai, atau dompet',
                  cacheKey: 'transfer.tempat_asal',
                  onChanged: (account) =>
                      setState(() => _fromAccountId = account?.id),
                  validator: (account) =>
                      account == null ? 'Pilih rekening asal.' : null,
                ),
                const SizedBox(height: 12),
                SearchableDropdown(
                  items: widget.accounts,
                  selectedItem: widget.accounts
                      .where((account) => account.id == _toAccountId)
                      .firstOrNull,
                  itemLabel: _accountLabel,
                  itemId: (account) => account.id,
                  labelText: 'Ke tempat uang',
                  searchHintText: 'Cari rekening, tunai, atau dompet',
                  cacheKey: 'transfer.tempat_tujuan',
                  onChanged: (account) =>
                      setState(() => _toAccountId = account?.id),
                  validator: (account) =>
                      account == null ? 'Pilih rekening tujuan.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Nominal yang dipindahkan',
                    prefixText: 'Rp ',
                    helperText:
                        'Contoh: 250.000. Ini yang masuk ke rekening tujuan.',
                  ),
                  validator: (value) => parseRupiah(value ?? '') <= 0
                      ? 'Nominal harus lebih dari nol.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _adminFeeController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Biaya admin (opsional)',
                    prefixText: 'Rp ',
                    helperText:
                        'Dipisahkan sebagai pengeluaran dari rekening asal.',
                  ),
                  validator: (value) => parseRupiah(value ?? '') < 0
                      ? 'Biaya admin tidak boleh negatif.'
                      : null,
                ),
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Tanggal'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                      ),
                      HijriDateLabel(date: _date),
                    ],
                  ),
                  trailing: TextButton(
                    onPressed: _pickDate,
                    child: const Text('Ganti'),
                  ),
                ),
                TextFormField(
                  controller: _noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppCopy.batal),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.swap_horiz_rounded),
          label: const Text('Simpan transfer'),
        ),
      ],
    );
  }
}

class _TransferHistoryCard extends StatelessWidget {
  const _TransferHistoryCard({
    required this.transfer,
    required this.fromLabel,
    required this.toLabel,
    required this.dateLabel,
    required this.onDelete,
  });

  final Transfer transfer;
  final String fromLabel;
  final String toLabel;
  final String Function(DateTime) dateLabel;
  final VoidCallback onDelete;

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
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('Hapus transfer')),
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

class _AccountBalancesCard extends StatelessWidget {
  const _AccountBalancesCard({
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
                'Transfer ikut dihitung',
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

class _TransactionFlowSummary extends StatelessWidget {
  const _TransactionFlowSummary({
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
                child: _TransactionFlowTile(
                  label: 'Pemasukan',
                  amount: incomeTotal,
                  color: AppColors.positive,
                  icon: Icons.south_west_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TransactionFlowTile(
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

class _TransactionFlowTile extends StatelessWidget {
  const _TransactionFlowTile({
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

class _ReceiptItemEditorDialog extends StatefulWidget {
  const _ReceiptItemEditorDialog({required this.item});

  final ReceiptItemDraft item;

  @override
  State<_ReceiptItemEditorDialog> createState() =>
      _ReceiptItemEditorDialogState();
}

class _ReceiptItemEditorDialogState extends State<_ReceiptItemEditorDialog> {
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

class _VoiceBatchRowDraft {
  _VoiceBatchRowDraft(VoiceTransactionParseResult result)
    : type = result.type == VoiceTransactionType.income
          ? TransactionType.income
          : TransactionType.expense,
      categoryId = result.categoryId,
      merchantId = result.merchantId,
      accountId = result.accountId,
      partyName = result.partyName ?? '',
      amountController = TextEditingController(
        text: result.hasAmount
            ? formatRupiahInput(result.amount.toString())
            : '',
      ),
      partyController = TextEditingController(text: result.partyName ?? ''),
      noteController = TextEditingController(text: result.note ?? ''),
      tagsController = TextEditingController(text: result.tagNames.join(', '));

  _VoiceBatchRowDraft.empty()
    : this(
        const VoiceTransactionParseResult(
          amount: 0,
          type: VoiceTransactionType.expense,
          owner: '',
          hasExplicitType: false,
          hasAmount: false,
          note: '',
        ),
      );

  TransactionType type;
  String? categoryId;
  String? merchantId;
  String? accountId;
  String partyName;
  final TextEditingController amountController;
  final TextEditingController partyController;
  final TextEditingController noteController;
  final TextEditingController tagsController;

  List<String> get tags => tagsController.text
      .split(',')
      .map((tag) => tag.trim().replaceFirst(RegExp(r'^#'), ''))
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList(growable: false);

  void dispose() {
    amountController.dispose();
    partyController.dispose();
    noteController.dispose();
    tagsController.dispose();
  }
}

class _VoiceBatchReviewDialog extends StatefulWidget {
  const _VoiceBatchReviewDialog({
    required this.transcript,
    required this.results,
    required this.categories,
    required this.merchants,
    required this.accounts,
    required this.parties,
    required this.tagsMaster,
  });

  final String transcript;
  final List<VoiceTransactionParseResult> results;
  final List<Category> categories;
  final List<Merchant> merchants;
  final List<Account> accounts;
  final List<TransactionParty> parties;
  final List<Tag> tagsMaster;

  @override
  State<_VoiceBatchReviewDialog> createState() =>
      _VoiceBatchReviewDialogState();
}

class _VoiceBatchReviewDialogState extends State<_VoiceBatchReviewDialog> {
  late final List<_VoiceBatchRowDraft> _rows;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _rows = widget.results.map(_VoiceBatchRowDraft.new).toList();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  List<Category> _categoriesFor(_VoiceBatchRowDraft row) =>
      _transactionCategoryOptions(
        widget.categories,
        row.type == TransactionType.income ? 'income' : 'expense',
        selectedId: row.categoryId,
      );

  List<TransactionParty> _partiesFor(_VoiceBatchRowDraft row) {
    if (row.type == TransactionType.income) {
      return widget.parties
          .where((party) => party.kind == 'income_source')
          .toList(growable: false);
    }
    final seen = <String>{};
    return [
          ...widget.parties.where((party) => party.kind == 'husband'),
          ...widget.parties.where((party) => party.kind == 'wife'),
          ...widget.parties.where((party) => party.kind == 'used_by'),
        ]
        .where((party) {
          final name = party.name.trim().toLowerCase();
          return name.isNotEmpty && seen.add(name);
        })
        .toList(growable: false);
  }

  String _categoryLabel(Category category) =>
      _transactionCategoryLabel(widget.categories, category);

  String _accountLabel(Account account) {
    final type = switch (account.type) {
      'cash' => 'Tunai',
      'bank' => 'Rekening',
      'ewallet' => 'Dompet digital',
      _ => account.type,
    };
    return '${account.name} · $type';
  }

  void _changeType(_VoiceBatchRowDraft row, TransactionType type) {
    setState(() {
      row.type = type;
      if (!_categoriesFor(row).any((item) => item.id == row.categoryId)) {
        row.categoryId = null;
      }
      final partyNames = _partiesFor(row).map((party) => party.name).toSet();
      if (row.partyName.isNotEmpty && !partyNames.contains(row.partyName)) {
        row.partyName = '';
        row.partyController.clear();
      }
    });
  }

  void _addRow() {
    setState(() => _rows.add(_VoiceBatchRowDraft.empty()));
  }

  void _removeRow(int index) {
    if (_rows.length == 1) return;
    final row = _rows.removeAt(index);
    row.dispose();
    setState(() {});
  }

  String? _validateRows() {
    for (var index = 0; index < _rows.length; index++) {
      final row = _rows[index];
      if (parseRupiah(row.amountController.text) <= 0) {
        return 'Transaksi ${index + 1}: nominal belum valid.';
      }
      if (row.categoryId == null) {
        return 'Transaksi ${index + 1}: kategori belum dipilih dari Data Utama.';
      }
      if (row.accountId == null) {
        return 'Transaksi ${index + 1}: rekening atau dompet belum dipilih.';
      }
      if (row.type == TransactionType.income &&
          row.partyController.text.trim().isEmpty) {
        return 'Transaksi ${index + 1}: sumber pemasukan belum diisi.';
      }
    }
    return null;
  }

  void _saveAll() {
    final error = _validateRows();
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    final drafts = _rows
        .map(
          (row) => TransactionDraft(
            type: row.type,
            categoryId: row.categoryId!,
            owner: row.partyController.text.trim(),
            date: DateTime.now(),
            amount: row.type == TransactionType.income
                ? parseRupiah(row.amountController.text)
                : -parseRupiah(row.amountController.text),
            note: row.noteController.text.trim(),
            source: 'voice',
            merchantId: row.merchantId,
            accountId: row.accountId,
            items: const [],
            tags: row.tags,
          ),
        )
        .toList(growable: false);
    Navigator.of(context).pop(drafts);
  }

  Widget _buildRow(BuildContext context, int index, _VoiceBatchRowDraft row) {
    final scheme = Theme.of(context).colorScheme;
    final categories = _categoriesFor(row);
    final parties = _partiesFor(row);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: scheme.primaryContainer,
                  child: Text('${index + 1}'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Transaksi ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (_rows.length > 1)
                  IconButton(
                    tooltip: 'Hapus baris ini',
                    onPressed: () => _removeRow(index),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<TransactionType>(
              initialValue: row.type,
              decoration: const InputDecoration(labelText: 'Jenis transaksi'),
              items: const [
                DropdownMenuItem(
                  value: TransactionType.expense,
                  child: Text('Uang keluar'),
                ),
                DropdownMenuItem(
                  value: TransactionType.income,
                  child: Text('Uang masuk'),
                ),
              ],
              onChanged: (value) {
                if (value != null) _changeType(row, value);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: row.amountController,
              keyboardType: TextInputType.number,
              inputFormatters: const [RupiahInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Nominal',
                prefixText: 'Rp ',
                helperText: 'Bisa ketik angka atau koreksi hasil terbilang.',
              ),
            ),
            const SizedBox(height: 10),
            if (categories.isEmpty)
              const Text('Kategori belum ada. Tambahkan dulu di Data Utama.')
            else
              DropdownButtonFormField<String>(
                initialValue:
                    categories.any((category) => category.id == row.categoryId)
                    ? row.categoryId
                    : null,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: categories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category.id,
                        child: Text(_categoryLabel(category)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => row.categoryId = value),
              ),
            const SizedBox(height: 10),
            if (widget.accounts.isEmpty)
              const AppCard(
                padding: EdgeInsets.all(10),
                child: Text(
                  'Rekening atau dompet belum ada. Tutup dulu, tambahkan dari Data Utama, lalu rekam ulang Voice Note.',
                ),
              )
            else
              DropdownButtonFormField<String>(
                initialValue:
                    widget.accounts.any(
                      (account) => account.id == row.accountId,
                    )
                    ? row.accountId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Rekening atau dompet',
                  helperText: 'Tempat uang masuk atau keluar.',
                ),
                items: widget.accounts
                    .map(
                      (account) => DropdownMenuItem<String>(
                        value: account.id,
                        child: Text(_accountLabel(account)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => row.accountId = value),
              ),
            if (widget.merchants.isNotEmpty) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue:
                    widget.merchants.any(
                      (merchant) => merchant.id == row.merchantId,
                    )
                    ? row.merchantId
                    : null,
                decoration: const InputDecoration(labelText: 'Toko / tempat'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Belum dipilih'),
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
            ],
            const SizedBox(height: 10),
            TextField(
              controller: row.partyController,
              onChanged: (value) => row.partyName = value,
              decoration: InputDecoration(
                labelText: row.type == TransactionType.income
                    ? 'Sumber pemasukan'
                    : 'Dipakai oleh',
                helperText: parties.isEmpty
                    ? 'Bisa diisi manual; lebih rapi kalau dibuat di Data Utama.'
                    : 'Pilih saran di bawah atau ubah manual.',
              ),
            ),
            if (parties.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: parties
                    .map(
                      (party) => InputChip(
                        label: Text(party.name),
                        selected: row.partyController.text == party.name,
                        onPressed: () => setState(() {
                          row.partyController.text = party.name;
                          row.partyName = party.name;
                        }),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: row.noteController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Catatan'),
            ),
            const SizedBox(height: 10),
            if (widget.tagsMaster.isEmpty)
              const Text('Tag belum tersedia. Tambahkan dulu dari Data Utama.')
            else ...[
              const Text('Tag dari Data Utama'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: widget.tagsMaster.map((tag) {
                  final selected = row.tags.any(
                    (current) =>
                        current.toLowerCase() == tag.name.toLowerCase(),
                  );
                  return FilterChip(
                    label: Text('#${tag.name}'),
                    selected: selected,
                    onSelected: (_) {
                      final next = [...row.tags];
                      if (selected) {
                        next.removeWhere(
                          (current) =>
                              current.toLowerCase() == tag.name.toLowerCase(),
                        );
                      } else {
                        next.add(tag.name);
                      }
                      row.tagsController.text = next.join(', ');
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.table_rows_outlined),
          SizedBox(width: 10),
          Expanded(child: Text('Cek banyak transaksi')),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: MediaQuery.sizeOf(context).height * .72,
        child: ListView(
          children: [
            Text(
              'Voice Note berhasil dipecah menjadi ${_rows.length} draf. Kolom kosong bisa kamu isi manual. Tidak ada yang disimpan sebelum tombol Simpan semua ditekan.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            if (widget.transcript.trim().isNotEmpty)
              AppCard(
                color: Theme.of(context).colorScheme.primaryContainer
                    .withValues(alpha: .4),
                child: Text('“${widget.transcript}”'),
              ),
            const SizedBox(height: 12),
            if (_errorText != null)
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 4),
            ..._rows.asMap().entries.map(
              (entry) => _buildRow(context, entry.key, entry.value),
            ),
            OutlinedButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add),
              label: const Text('Tambah transaksi manual'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppCopy.batal),
        ),
        FilledButton.icon(
          onPressed: _saveAll,
          icon: const Icon(Icons.save_outlined),
          label: Text('Simpan semua (${_rows.length})'),
        ),
      ],
    );
  }
}

class _VoiceReviewDraft {
  const _VoiceReviewDraft({
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.merchantId,
    required this.accountId,
    required this.partyName,
    required this.note,
    required this.tags,
  });

  final TransactionType type;
  final int amount;
  final String? categoryId;
  final String? merchantId;
  final String? accountId;
  final String partyName;
  final String note;
  final List<String> tags;
}

class _VoiceReviewDialog extends StatefulWidget {
  const _VoiceReviewDialog({
    required this.transcript,
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.merchantId,
    required this.accountId,
    required this.partyName,
    required this.note,
    required this.tags,
    required this.categories,
    required this.merchants,
    required this.accounts,
    required this.parties,
    required this.tagsMaster,
  });

  final String transcript;
  final TransactionType type;
  final int amount;
  final String? categoryId;
  final String? merchantId;
  final String? accountId;
  final String partyName;
  final String note;
  final List<String> tags;
  final List<Category> categories;
  final List<Merchant> merchants;
  final List<Account> accounts;
  final List<TransactionParty> parties;
  final List<Tag> tagsMaster;

  @override
  State<_VoiceReviewDialog> createState() => _VoiceReviewDialogState();
}

class _VoiceReviewDialogState extends State<_VoiceReviewDialog> {
  late TransactionType _type;
  late String? _categoryId;
  late String? _merchantId;
  late String? _accountId;
  late String _partyName;
  late List<String> _tags;
  late final TextEditingController _amountController;
  late final TextEditingController _partyController;
  late final TextEditingController _noteController;
  late final TextEditingController _tagController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _type = widget.type;
    _categoryId = widget.categoryId;
    _merchantId = widget.merchantId;
    _accountId = widget.accountId;
    _partyName = widget.partyName;
    _tags = [...widget.tags];
    _amountController = TextEditingController(
      text: widget.amount > 0
          ? formatRupiahInput(widget.amount.toString())
          : '',
    );
    _partyController = TextEditingController(text: _partyName);
    _noteController = TextEditingController(text: widget.note);
    _tagController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _partyController.dispose();
    _noteController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  List<Category> get _availableCategories => _transactionCategoryOptions(
    widget.categories,
    _type == TransactionType.income ? 'income' : 'expense',
    selectedId: _categoryId,
  );

  List<TransactionParty> get _availableParties {
    if (_type == TransactionType.income) {
      return widget.parties
          .where((party) => party.kind == 'income_source')
          .toList(growable: false);
    }
    final seen = <String>{};
    return [
          ...widget.parties.where((party) => party.kind == 'husband'),
          ...widget.parties.where((party) => party.kind == 'wife'),
          ...widget.parties.where((party) => party.kind == 'used_by'),
        ]
        .where((party) {
          final name = party.name.trim().toLowerCase();
          return name.isNotEmpty && seen.add(name);
        })
        .toList(growable: false);
  }

  void _changeType(TransactionType type) {
    setState(() {
      _type = type;
      if (!_availableCategories.any((category) => category.id == _categoryId)) {
        _categoryId = null;
      }
      if (!_availableParties.any((party) => party.name == _partyName)) {
        _partyName = '';
        _partyController.clear();
      }
    });
  }

  void _addTag(String rawTag) {
    final tag = rawTag.trim().replaceFirst(RegExp(r'^#'), '');
    if (tag.isEmpty) return;
    final existingIndex = _tags.indexWhere(
      (current) => current.toLowerCase() == tag.toLowerCase(),
    );
    setState(() {
      if (existingIndex >= 0) {
        _tags = [..._tags]..removeAt(existingIndex);
      } else {
        _tags = [..._tags, tag];
      }
      _tagController.clear();
    });
  }

  void _save() {
    final amount = parseRupiah(_amountController.text);
    final needsParty = _type == TransactionType.income;
    if (amount <= 0) {
      setState(() => _errorText = 'Nominal belum valid. Isi nominal dulu.');
      return;
    }
    if (_categoryId == null) {
      setState(
        () => _errorText = 'Kategori belum dipilih. Pilih dari Data Utama.',
      );
      return;
    }
    if (needsParty && _partyName.trim().isEmpty) {
      setState(
        () => _errorText = 'Sumber pemasukan belum dipilih dari Data Utama.',
      );
      return;
    }
    Navigator.of(context).pop(
      _VoiceReviewDraft(
        type: _type,
        amount: amount,
        categoryId: _categoryId,
        merchantId: _merchantId,
        accountId: _accountId,
        partyName: _partyName.trim(),
        note: _noteController.text.trim(),
        tags: _tags,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = _type == TransactionType.income;
    final categoryItems = _availableCategories;
    final partyItems = _availableParties;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.fact_check_outlined),
          SizedBox(width: 10),
          Expanded(child: Text('Cek hasil Voice Note')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ini masih draf. Periksa dan edit dulu sebelum diterapkan ke formulir transaksi.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('“${widget.transcript}”'),
            ),
            const SizedBox(height: 16),
            SegmentedButton<TransactionType>(
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Uang keluar'),
                  icon: Icon(Icons.north_east_rounded),
                ),
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Uang masuk'),
                  icon: Icon(Icons.south_west_rounded),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (value) => _changeType(value.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: const [RupiahInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Nominal',
                prefixText: 'Rp ',
              ),
            ),
            const SizedBox(height: 12),
            if (categoryItems.isEmpty)
              _VoiceReviewWarning(
                icon: Icons.category_outlined,
                text:
                    'Kategori ${isIncome ? 'pemasukan' : 'pengeluaran'} belum ada. Buat dulu di Data Utama.',
              )
            else
              DropdownButtonFormField<String>(
                initialValue:
                    categoryItems.any((item) => item.id == _categoryId)
                    ? _categoryId
                    : null,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: categoryItems
                    .map(
                      (category) => DropdownMenuItem<String>(
                        value: category.id,
                        child: Text(
                          _transactionCategoryLabel(
                            widget.categories,
                            category,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _categoryId = value),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: widget.accounts.any((item) => item.id == _accountId)
                  ? _accountId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Rekening / tempat uang',
                helperText: 'Opsional. Pilih dari Data Utama.',
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Belum dipilih'),
                ),
                ...widget.accounts.map(
                  (account) => DropdownMenuItem<String?>(
                    value: account.id,
                    child: Text(account.name),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _accountId = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue:
                  widget.merchants.any((item) => item.id == _merchantId)
                  ? _merchantId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Toko / tempat',
                helperText: 'Opsional. Pilih dari Data Utama.',
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Belum dipilih'),
                ),
                ...widget.merchants.map(
                  (merchant) => DropdownMenuItem<String?>(
                    value: merchant.id,
                    child: Text(merchant.name),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _merchantId = value),
            ),
            const SizedBox(height: 12),
            if (partyItems.isEmpty)
              _VoiceReviewWarning(
                icon: Icons.person_outline_rounded,
                text: isIncome
                    ? 'Sumber pemasukan belum ada. Buat dulu di Data Utama.'
                    : 'Dipakai oleh belum ada. Bagian ini boleh dilewati.',
              )
            else
              DropdownButtonFormField<String>(
                initialValue: partyItems.any((item) => item.name == _partyName)
                    ? _partyName
                    : null,
                decoration: InputDecoration(
                  labelText: isIncome ? 'Sumber pemasukan' : 'Dipakai oleh',
                  helperText: isIncome
                      ? 'Wajib untuk pemasukan. Pilih dari Data Utama.'
                      : 'Opsional, cuma untuk rincian pemakaian.',
                ),
                items: partyItems
                    .map(
                      (party) => DropdownMenuItem<String>(
                        value: party.name,
                        child: Text(party.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _partyName = value ?? ''),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Catatan transaksi',
                helperText: 'Boleh diedit supaya maksud ucapan lebih jelas.',
              ),
            ),
            const SizedBox(height: 12),
            if (widget.tagsMaster.isEmpty)
              const Text('Tag belum tersedia. Tambahkan dulu dari Data Utama.')
            else ...[
              const Text('Pilih tag dari Data Utama'),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final tag in widget.tagsMaster)
                    FilterChip(
                      label: Text('#${tag.name}'),
                      selected: _tags.any(
                        (current) =>
                            current.toLowerCase() == tag.name.toLowerCase(),
                      ),
                      onSelected: (_) => _addTag(tag.name),
                    ),
                ],
              ),
            ],
            if (_tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final tag in _tags)
                    InputChip(
                      label: Text('#$tag'),
                      onDeleted: () =>
                          setState(() => _tags = [..._tags]..remove(tag)),
                    ),
                ],
              ),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorText!,
                style: TextStyle(
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Rincian nota seperti nama barang dan harga item bisa ditambahkan setelah hasil ini diterapkan ke formulir.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Terapkan ke form'),
        ),
      ],
    );
  }
}

class _VoiceReviewWarning extends StatelessWidget {
  const _VoiceReviewWarning({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _VoiceInputGuide extends StatelessWidget {
  const _VoiceInputGuide({required this.isIncome});

  final bool isIncome;

  @override
  Widget build(BuildContext context) {
    final example = isIncome
        ? '“Uang masuk, gaji, tiga juta, untuk Keluarga.”'
        : '“Uang keluar, beli makan, lima puluh ribu, untuk Anak.”';
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.menu_book_outlined, color: AppColors.primary),
          SizedBox(width: 10),
          Expanded(child: Text('Cara pakai input suara')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Suara diproses langsung di HP tanpa internet. Kalau model Whisper sudah diimpor, tombol memakai Whisper lokal. Kalau belum, aplikasi memakai pengenalan suara offline dari perangkat. Hasilnya cuma isian sementara, jadi tetap wajib dicek sebelum disimpan.',
            ),
            const SizedBox(height: 12),
            _VoiceGuideStep(
              number: '1',
              title: 'Pilih arah transaksi',
              description: isIncome
                  ? 'Pastikan pilihan Uang masuk aktif.'
                  : 'Pastikan pilihan Uang keluar aktif.',
            ),
            _VoiceGuideStep(
              number: '2',
              title: 'Tekan ikon mikrofon',
              description: 'Tunggu sampai tulisan berubah menjadi sedang mendengar, lalu ucapkan satu kalimat pendek.',
            ),
            _VoiceGuideStep(
              number: '3',
              title: 'Ucapkan dengan urutan ini',
              description: 'Arah transaksi, keperluan, nominal, lalu rincian Keluarga, Istri, atau Anak bila perlu.',
            ),
            const SizedBox(height: 8),
            Text(
              'Contoh: $example',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Setelah selesai, aplikasi membuka editor pratinjau. Cek arah, nominal, kategori, rekening, toko, sumber/pemakai, tag, dan catatan sebelum menerapkan hasil ke formulir. Pada mode Whisper, tekan ikon mikrofon sekali lagi untuk berhenti; mode perangkat bisa berhenti otomatis setelah jeda singkat.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Oke, ngerti'),
        ),
      ],
    );
  }
}

class _VoiceGuideStep extends StatelessWidget {
  const _VoiceGuideStep({
    required this.number,
    required this.title,
    required this.description,
  });

  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: AppColors.primary,
            child: Text(
              number,
              style: const TextStyle(
                color: AppColors.onPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: '$title. ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: description),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceResultLine extends StatelessWidget {
  const _VoiceResultLine({
    required this.label,
    required this.value,
    required this.isValid,
  });

  final String label;
  final String value;
  final bool isValid;

  @override
  Widget build(BuildContext context) {
    final color = isValid ? AppColors.positive : AppColors.warning;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isValid ? Icons.check_circle_outline : Icons.help_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FirstTransactionGuide extends StatelessWidget {
  const _FirstTransactionGuide({
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

class _JsonTransactionItem {
  _JsonTransactionItem({String name = '', double quantity = 1, int price = 0})
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

class _JsonTransactionRow {
  _JsonTransactionRow({
    required this.type,
    required this.date,
    String? time,
    int? amount,
    String? merchantName,
    String? partyName,
    String? note,
    String? categoryId,
    String? accountId,
    String? budgetId,
    List<ReceiptOcrItem> items = const [],
  }) : categoryId = categoryId,
       accountId = accountId,
       budgetId = budgetId,
       amountController = TextEditingController(
         text: amount != null && amount > 0
             ? formatRupiahInput(amount.toString())
             : '',
       ),
       time = _mergeTime(date, time),
       merchantController = TextEditingController(text: merchantName ?? ''),
       partyController = TextEditingController(text: partyName ?? ''),
       noteController = TextEditingController(text: note ?? ''),
       items = items
           .map(
             (item) => _JsonTransactionItem(
               name: item.name,
               quantity: item.quantity,
               price: item.price,
             ),
           )
           .toList();

  TransactionType type;
  DateTime date;
  DateTime time;
  String? categoryId;
  String? accountId;
  String? budgetId;
  final TextEditingController amountController;
  final TextEditingController merchantController;
  final TextEditingController partyController;
  final TextEditingController noteController;
  final List<_JsonTransactionItem> items;

  int get itemsTotal => items.fold(0, (sum, item) => sum + item.total);

  void dispose() {
    amountController.dispose();
    merchantController.dispose();
    partyController.dispose();
    noteController.dispose();
    for (final item in items) {
      item.dispose();
    }
  }

  static DateTime _mergeTime(DateTime date, String? raw) {
    if (raw == null || raw.trim().isEmpty) return date;
    final parts = raw.split(':');
    final hour = int.tryParse(parts.first) ?? date.hour;
    final minute = parts.length > 1
        ? int.tryParse(parts[1]) ?? date.minute
        : date.minute;
    final second = parts.length > 2
        ? int.tryParse(parts[2]) ?? date.second
        : date.second;
    return DateTime(date.year, date.month, date.day, hour, minute, second);
  }
}

class _JsonTransferRow {
  _JsonTransferRow({
    required this.date,
    String? time,
    int? amount,
    int? adminFee,
    this.fromAccountId,
    this.toAccountId,
    String? note,
  }) : time = _JsonTransactionRow._mergeTime(date, time),
       amountController = TextEditingController(
         text: amount != null && amount > 0
             ? formatRupiahInput(amount.toString())
             : '',
       ),
       adminFeeController = TextEditingController(
         text: adminFee != null && adminFee > 0
             ? formatRupiahInput(adminFee.toString())
             : '',
       ),
       noteController = TextEditingController(text: note ?? '');

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

class _JsonBudgetOption {
  const _JsonBudgetOption({
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
    required this.note,
  });

  final DateTime date;
  final int amount;
  final int adminFee;
  final String fromAccountId;
  final String toAccountId;
  final String note;
}

class JsonBatchResult {
  const JsonBatchResult({
    required this.drafts,
    this.transfers = const [],
    this.statement,
  });

  final List<TransactionDraft> drafts;
  final List<JsonTransferDraft> transfers;
  final ReceiptBatchImport? statement;
}

class JsonTransactionBatchPage extends StatefulWidget {
  const JsonTransactionBatchPage({
    super.key,
    required this.categories,
    required this.merchants,
    required this.accounts,
    this.budgetOptions = const [],
  });

  final List<Category> categories;
  final List<Merchant> merchants;
  final List<Account> accounts;
  final List<_JsonBudgetOption> budgetOptions;

  @override
  State<JsonTransactionBatchPage> createState() =>
      _JsonTransactionBatchPageState();
}

class _JsonTransactionBatchPageState extends State<JsonTransactionBatchPage> {
  final _jsonController = TextEditingController();
  final _rows = <_JsonTransactionRow>[];
  final _transferRows = <_JsonTransferRow>[];
  List<String> _warnings = const [];
  ReceiptBatchImport? _statementImport;
  var _showJsonBox = false;
  var _loading = false;

  @override
  void initState() {
    super.initState();
    _rows.add(_newRow());
  }

  _JsonTransactionRow _newRow({
    TransactionType type = TransactionType.expense,
    DateTime? date,
    String? time,
    int? amount,
    String? merchant,
    String? categoryId,
    String? accountId,
    String? budgetId,
    String? partyName,
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
    return _JsonTransactionRow(
      type: effectiveType,
      date: date ?? DateTime.now(),
      time: time,
      amount: amount,
      merchantName: merchant,
      partyName: partyName,
      note: note,
      categoryId: validCategory,
      accountId: validAccount,
      budgetId: selectedBudget?.id,
      items: items,
    );
  }

  _JsonBudgetOption? _findBudgetOption(String? idOrName) {
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

  _JsonBudgetOption? _findBudgetByName(String? name) {
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

  _JsonBudgetOption? _selectedBudget(_JsonTransactionRow row) => widget
      .budgetOptions
      .where((option) => option.id == row.budgetId)
      .firstOrNull;

  _JsonTransferRow _newTransferRow({
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
    return _JsonTransferRow(
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
      _transactionCategoryOptions(
        widget.categories,
        type == TransactionType.income ? 'income' : 'expense',
        selectedId: selectedId,
      );

  String _categoryLabel(Category category) =>
      _transactionCategoryLabel(widget.categories, category);

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
    _showMessage('Template JSON batch sudah disalin.');
  }

  Future<void> _copyPrompt() async {
    await Clipboard.setData(
      ClipboardData(text: ReceiptImportService.buildGeminiBatchPrompt()),
    );
    _showMessage('Prompt JSON batch untuk banyak transaksi sudah disalin.');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _addRow() => setState(() => _rows.add(_newRow()));

  void _changeType(_JsonTransactionRow row, TransactionType type) {
    final categories = _categoryOptions(type);
    setState(() {
      row.type = type;
      row.categoryId = categories.firstOrNull?.id;
      if (type == TransactionType.income) row.budgetId = null;
    });
  }

  Future<void> _pickDate(_JsonTransactionRow row) async {
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

  Future<void> _pickTime(_JsonTransactionRow row) async {
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
          source: 'json_batch',
          accountId: row.accountId,
          merchantId: widget.merchants
              .where(
                (merchant) =>
                    merchant.name.toLowerCase() ==
                    row.merchantController.text.trim().toLowerCase(),
              )
              .firstOrNull
              ?.id,
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
        title: const Text('JSON & Input banyak transaksi'),
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
          const AppHelpBanner(
            title: 'Satu halaman untuk banyak transaksi',
            message: 'Tempel JSON dari Gemini atau isi manual. Satu transaksi bisa punya banyak rincian item. Semua hasil masih draft sampai kamu menekan Pakai semua draft.',
            icon: Icons.data_object_rounded,
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Tempel JSON batch di sini',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Bisa memuat pemasukan dan pengeluaran dari screenshot mutasi rekening sekaligus. Setelah dimuat, semuanya masih bisa diedit.',
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _copyPrompt,
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Salin instruksi untuk JSON batch'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _copyTemplate,
                      icon: const Icon(Icons.data_object_outlined),
                      label: const Text('Salin contoh format'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pasteFromClipboard,
                      icon: const Icon(Icons.content_paste_go_outlined),
                      label: const Text('Tempel JSON batch'),
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
                      labelText: 'JSON batch',
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

  Widget _buildJsonTransferRow(int index, _JsonTransferRow row) {
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

  Widget _buildJsonRow(int index, _JsonTransactionRow row) {
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
                      setState(() => row.items.add(_JsonTransactionItem())),
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
    _JsonTransactionRow row,
    int index,
    _JsonTransactionItem item,
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

/// Form manual untuk mencatat beberapa transaksi dalam satu hari.
/// Setiap baris tetap menjadi transaksi terpisah agar saldo, anggaran, dan
/// analisa tidak kehilangan konteks kategori maupun rekening.
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
  final Future<void> Function(ReceiptBatchImport statement)? onSaveStatement;

  @override
  State<QuickTransactionBatchPage> createState() =>
      _QuickTransactionBatchPageState();
}

class _QuickTransactionRow {
  _QuickTransactionRow({
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
  final items = <_JsonTransactionItem>[];

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

class _QuickTransactionBatchPageState extends State<QuickTransactionBatchPage> {
  final _formKey = GlobalKey<FormState>();
  final _rows = <_QuickTransactionRow>[];
  late DateTime _day;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _day = DateTime.now();
    _rows.add(_newRow());
  }

  _QuickTransactionRow _newRow({
    TransactionType type = TransactionType.expense,
  }) {
    final categoryOptions = _categoryOptions(type);
    return _QuickTransactionRow(
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
    return _transactionCategoryOptions(
      widget.categories,
      type == TransactionType.income ? 'income' : 'expense',
      selectedId: selectedId,
    );
  }

  String _categoryLabel(Category category) {
    return _transactionCategoryLabel(widget.categories, category);
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

  Future<void> _pickTime(_QuickTransactionRow row) async {
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

  void _changeType(_QuickTransactionRow row, TransactionType type) {
    setState(() {
      row.type = type;
      row.categoryId = _categoryOptions(type).firstOrNull?.id;
    });
  }

  Future<void> _openJsonBatch() async {
    final result = await Navigator.of(context).push<JsonBatchResult>(
      MaterialPageRoute(
        builder: (_) => JsonTransactionBatchPage(
          categories: widget.categories,
          merchants: widget.merchants,
          accounts: widget.accounts,
        ),
      ),
    );
    if (!mounted ||
        result == null ||
        (result.drafts.isEmpty && result.transfers.isEmpty)) {
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.onSaveJsonResult != null) {
        await widget.onSaveJsonResult!(result);
      } else {
        await widget.onSave(result.drafts);
        if (result.statement != null) {
          await widget.onSaveStatement?.call(result.statement!);
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(result.drafts);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
        title: const Text('Input Cepat'),
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
            AppHelpBanner(
              title: 'Catat banyak transaksi sekaligus',
              message: 'Pilih satu tanggal kejadian untuk hari ini, lalu isi setiap baris. Jam tiap transaksi bisa dibedakan. Waktu input sistem tetap dicatat saat kamu menekan Simpan semua.',
              icon: Icons.playlist_add_check_rounded,
            ),
            const SizedBox(height: 12),
            AppCard(
              color: Theme.of(context).colorScheme.primaryContainer,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mau input lewat JSON batch?',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Bisa. Tempel JSON batch untuk 10+ transaksi sekaligus, lengkap dengan rincian barang, lalu edit sebelum dipakai.',
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _saving ? null : _openJsonBatch,
                    icon: const Icon(Icons.data_object_rounded),
                    label: const Text('Buka JSON/Gemini batch'),
                  ),
                ],
              ),
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

  Widget _buildRow(int index, _QuickTransactionRow row) {
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
                      setState(() => row.items.add(_JsonTransactionItem())),
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
    _QuickTransactionRow row,
    int index,
    _JsonTransactionItem item,
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
