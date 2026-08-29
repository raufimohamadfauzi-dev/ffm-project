import 'package:drift/drift.dart';

// ... (imports remain)

import '../../../core/database/app_database.dart';
import '../../../core/database/audit_logger.dart';
import '../../budget/data/budget_repository.dart';
import '../../activity/data/repositories/activity_repository.dart';
import '../../activity/domain/entities/activity_entity.dart';
import '../../asset/domain/entities/asset_entity.dart';
import '../../asset/domain/usecases/asset_crud_usecases.dart';
import '../../settings/data/category_repository.dart';
import '../../settings/data/account_repository.dart';
import '../../settings/data/income_source_repository.dart';
import '../../settings/data/merchant_repository.dart';
import '../../settings/data/tag_repository.dart';
// ...
import '../../goal/domain/entities/goal_entity.dart';
import '../../goal/domain/usecases/goal_crud_usecases.dart';
import '../../liability/domain/entities/liability_entity.dart';
import '../../liability/domain/usecases/liability_crud_usecases.dart';
import '../../receivable/domain/entities/receivable_entity.dart';
import '../../receivable/domain/usecases/receivable_crud_usecases.dart';
import '../../recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';
import '../../reminder/data/repositories/reminder_repository.dart';
import '../../reminder/domain/entities/reminder_entity.dart';
import '../../transaction/domain/usecases/transaction_crud_usecases.dart';
import '../domain/ffm_assistant_action_plan.dart';
import '../domain/ffm_assistant_capability_executor.dart';
import 'ffm_assistant_reminder_mutation_service.dart';
import 'ffm_activity_habit_learner.dart';
import 'ffm_assistant_personalization_repository.dart';

class FfmAssistantCapabilityAdapterRegistry {
  FfmAssistantCapabilityAdapterRegistry({
    required this._database,
    required this._householdId,
    DateTime Function()? clock,
    this._reminderMutations,
    this._habitLearner,
    this._personalization,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final String _householdId;
  final DateTime Function() _clock;
  final FfmAssistantReminderMutationService? _reminderMutations;
  final FfmActivityHabitLearner? _habitLearner;
  final FfmAssistantPersonalizationRepository? _personalization;

  Map<String, FfmAssistantCapabilityHandler> get handlers => {
    'read.summary': _readSummary,
    'read.transactions': _readTransactions,
    'read.accounts': _readAccounts,
    'read.categories': _readCategories,
    'read.analysis': _readAnalysis,
    'read.activity': _readActivity,
    'read.budget': _readBudget,
    'read.goals': _readGoals,
    'read.assets': _readAssets,
    'read.liabilities': _readLiabilities,
    'read.receivable': _readReceivable,
    'read.recurring': _readRecurring,
    'read.reminders': _readReminders,
    'read.model_status': _readModelStatus,
    'draft.transaction_update': _prepareTransactionMutation,
    'draft.transaction_archive': _prepareTransactionMutation,
    'draft.transaction_delete': _prepareTransactionMutation,
    'draft.activity_archive': _prepareActivityMutation,
    'draft.activity_delete': _prepareActivityMutation,
    'draft.activity_finish': _prepareActivityMutation,
    'draft.activity_update': _prepareActivityMutation,
    'draft.activity_edit': _prepareActivityMutation,
    'draft.task_update': _prepareActivityMutation,
    'draft.task_complete': _prepareActivityMutation,
    'draft.task_reopen': _prepareActivityMutation,
    'draft.task_archive': _prepareActivityMutation,
    'draft.routine_update': _prepareActivityMutation,
    'draft.routine_mark_complete': _prepareActivityMutation,
    'draft.routine_unmark_complete': _prepareActivityMutation,
    'draft.routine_activate': _prepareActivityMutation,
    'draft.routine_deactivate': _prepareActivityMutation,
    'draft.routine_archive': _prepareActivityMutation,
    'draft.schedule_update': _prepareActivityMutation,
    'draft.schedule_archive': _prepareActivityMutation,
    'draft.daily_note': _prepareDraft,
    'draft.task': _prepareDraft,
    'draft.routine': _prepareDraft,
    'draft.schedule': _prepareDraft,
    'draft.income': _prepareDraft,
    'draft.expense': _prepareDraft,
    'draft.transfer': _prepareDraft,
    'draft.profile': _prepareDraft,
    'draft.activity': _prepareDraft,
    'draft.reminder': _prepareDraft,
    'draft.master_data': _prepareDraft,
    'draft.merchant_update': _prepareMerchantMutation,
    'draft.merchant_archive': _prepareMerchantMutation,
    'draft.merchant_delete': _prepareMerchantMutation,
    'draft.tag_update': _prepareTagMutation,
    'draft.tag_archive': _prepareTagMutation,
    'draft.tag_delete': _prepareTagMutation,
    'draft.income_source_update': _prepareIncomeSourceMutation,
    'draft.income_source_archive': _prepareIncomeSourceMutation,
    'draft.income_source_delete': _prepareIncomeSourceMutation,
    'draft.category_update': _prepareCategoryMutation,
    'draft.category_archive': _prepareCategoryMutation,
    'draft.category_delete': _prepareCategoryMutation,
    'draft.account_update': _prepareAccountMutation,
    'draft.account_archive': _prepareAccountMutation,
    'draft.account_delete': _prepareAccountMutation,
    'draft.goal': _prepareDraft,
    'draft.asset': _prepareDraft,
    'draft.asset_update': _prepareAssetMutation,
    'draft.asset_archive': _prepareAssetMutation,
    'draft.liability': _prepareDraft,
    'draft.liability_update': _prepareLiabilityMutation,
    'draft.liability_archive': _prepareLiabilityMutation,
    'draft.receivable': _prepareDraft,
    'draft.receivable_update': _prepareReceivableMutation,
    'draft.receivable_archive': _prepareReceivableMutation,
    'draft.recurring_transaction_update': _prepareRecurringTransactionMutation,
    'draft.recurring_transaction_archive': _prepareRecurringTransactionMutation,
    'draft.budget': _prepareDraft,
    'draft.budget_update': _prepareBudgetMutation,
    'draft.budget_archive': _prepareBudgetMutation,
    'draft.goal_deposit': _prepareDraft,
    'draft.goal_usage': _prepareDraft,
    'draft.goal_update': _prepareGoalMutation,
    'draft.goal_archive': _prepareGoalMutation,
    'draft.reminder_update': _prepareReminderMutation,
    'draft.reminder_archive': _prepareReminderMutation,
    'mutate.save_draft': _saveDraft,
    'mutate.update': _updateTransaction,
    'mutate.archive': _archiveMutation,
    'sensitive.delete': _deleteMutation,
    'verify.saved_draft': _verifySavedDraft,
    'verify.transaction_mutation': _verifyTransactionMutation,
    'verify.activity_mutation': _verifyActivityMutation,
    'verify.daily_note_mutation': _verifyActivityMutation,
    'verify.task_mutation': _verifyActivityMutation,
    'verify.routine_mutation': _verifyActivityMutation,
    'verify.schedule_mutation': _verifyActivityMutation,
    'verify.asset_mutation': _verifyAssetMutation,
    'verify.goal_mutation': _verifyGoalMutation,
    'verify.reminder_mutation': _verifyReminderMutation,
    'verify.liability_mutation': _verifyLiabilityMutation,
    'verify.receivable_mutation': _verifyReceivableMutation,
    'verify.recurring_transaction_mutation':
        _verifyRecurringTransactionMutation,
    'verify.merchant_mutation': _verifyMerchantMutation,
    'verify.tag_mutation': _verifyTagMutation,
    'verify.income_source_mutation': _verifyIncomeSourceMutation,
    'verify.category_mutation': _verifyCategoryMutation,
    'verify.account_mutation': _verifyAccountMutation,
    'verify.budget_mutation': _verifyBudgetMutation,
  };

  Future<FfmAssistantCapabilityExecutionResult> _readSummary(
    FfmAssistantActionStep step,
  ) async {
    final now = _clock();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    final rows =
        await (_database.select(_database.transactions)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isArchived.equals(false) &
                  row.isDeleted.equals(false),
            ))
            .get();
    var income = 0;
    var expense = 0;
    var count = 0;
    for (final row in rows) {
      if (row.date.isBefore(start) || !row.date.isBefore(end)) continue;
      if (row.type == 'income') {
        income += row.amount.abs();
        count++;
      } else if (row.type == 'expense') {
        expense += row.amount.abs();
        count++;
      }
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Ringkasan bulan ini: $count transaksi, pemasukan ${_money(income)}, pengeluaran ${_money(expense)}. Transfer tidak dihitung sebagai pemasukan/pengeluaran.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _readTransactions(
    FfmAssistantActionStep step,
  ) async {
    final rows =
        await (_database.select(_database.transactions)
              ..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.isArchived.equals(false) &
                    row.isDeleted.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.date)]))
            .get();
    final filtered = rows
        .where(_matchesTransaction(step.parameters))
        .take(20)
        .toList();
    if (filtered.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Tidak ada transaksi yang cocok pada data lokal.',
      );
    }
    final lines = filtered.map((row) {
      final kind = row.type == 'income' ? 'Pemasukan' : 'Pengeluaran';
      return '$kind ${_money(row.amount.abs())} pada ${row.date.toIso8601String().substring(0, 10)}';
    });
    return FfmAssistantCapabilityExecutionResult.success(
      'Ditemukan ${filtered.length} transaksi (maksimal 20 ditampilkan): ${lines.join('; ')}',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _readAccounts(
    FfmAssistantActionStep step,
  ) async {
    final rows =
        await (_database.select(_database.accounts)
              ..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.isActive.equals(true) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .get();
    if (rows.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada rekening aktif.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Rekening aktif (${rows.length}): ${rows.map((row) => row.name).join(', ')}.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _readCategories(
    FfmAssistantActionStep step,
  ) async {
    final rows =
        await (_database.select(_database.categories)
              ..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.isActive.equals(true),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .get();
    if (rows.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada kategori aktif.',
      );
    }
    final grouped = <String, List<String>>{};
    for (final row in rows) {
      (grouped[row.type] ??= <String>[]).add(row.name);
    }
    final parts = grouped.entries
        .map((entry) => '${entry.key}: ${entry.value.join(', ')}')
        .join('; ');
    return FfmAssistantCapabilityExecutionResult.success(
      'Kategori aktif (${rows.length}): $parts.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _prepareDraft(
    FfmAssistantActionStep step,
  ) async {
    final kind = step.parameters['kind']?.toString();
    if (kind == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Draft mutation belum memiliki jenis.',
      );
    }
    final needsAmount = switch (kind) {
      'profile' ||
      'activity' ||
      'dailyNote' ||
      'task' ||
      'routine' ||
      'schedule' ||
      'reminder' ||
      'master_data' => false,
      _ => true,
    };

    if (!needsAmount) {
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview siap untuk $kind. Belum ada data yang disimpan.',
      );
    }

    final amount = _positiveInt(step.parameters['amount']);
    if (amount == null || amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Draft mutation belum memiliki nominal yang valid.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview siap untuk $kind sebesar ${_money(amount)}. Belum ada data yang disimpan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _prepareTransactionMutation(
    FfmAssistantActionStep step,
  ) async {
    final target = await _activeTransactionTarget(step);
    if (target == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Transaksi target tidak ditemukan, sudah diarsipkan, atau tidak lagi aktif.',
      );
    }
    final operation = step.parameters['operation']?.toString() ?? 'perubahan';
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview $operation siap untuk transaksi ${_money(target.transaction.amount.abs())} pada ${target.transaction.date.toIso8601String().substring(0, 10)}. Belum ada data yang diubah.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _updateTransaction(
    FfmAssistantActionStep step,
  ) async {
    if (step.parameters['entity'] == 'goal') return _updateGoal(step);
    if (step.parameters['entity'] == 'activity_session' ||
        step.parameters['entity'] == 'task' ||
        step.parameters['entity'] == 'daily_note' ||
        step.parameters['entity'] == 'schedule_entry') {
      return _updateActivity(step);
    }
    if (step.parameters['entity'] == 'daily_routine') {
      return _prepareDraft(step);
    }
    if (step.parameters['entity'] == 'reminder') {
      return _updateReminder(step);
    }
    if (step.parameters['entity'] == 'asset') return _updateAsset(step);
    if (step.parameters['entity'] == 'liability') return _updateLiability(step);
    if (step.parameters['entity'] == 'receivable') {
      return _updateReceivable(step);
    }
    if (step.parameters['entity'] == 'recurring_transaction') {
      return _updateRecurringTransaction(step);
    }
    if (step.parameters['entity'] == 'merchant') {
      return _updateMerchant(step);
    }
    if (step.parameters['entity'] == 'tag') return _updateTag(step);
    if (step.parameters['entity'] == 'income_source') {
      return _updateIncomeSource(step);
    }
    if (step.parameters['entity'] == 'category') return _updateCategory(step);
    if (step.parameters['entity'] == 'account') return _updateAccount(step);
    if (step.parameters['entity'] == 'budget') return _updateBudget(step);
    final target = await _activeTransactionTarget(step);
    if (target == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Transaksi target tidak ditemukan atau sudah tidak aktif.',
      );
    }
    if (target.transaction.goalId != null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Transaksi yang terkait target keuangan harus diubah lewat form transaksi agar kontribusi target ikut disinkronkan.',
      );
    }
    final amount = _positiveInt(step.parameters['amount']);
    if (amount == null || amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nominal perubahan transaksi belum valid.',
      );
    }
    final signedAmount = target.transaction.type == 'income' ? amount : -amount;
    if (target.transaction.amount == signedAmount) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'alreadyApplied: nominal transaksi sudah sesuai dengan draft perubahan.',
      );
    }
    final now = _clock();
    await SaveTransaction(_database)(
      TransactionEntity(
        id: target.transaction.id,
        householdId: target.transaction.householdId,
        date: target.transaction.date,
        amount: signedAmount,
        owner: target.transaction.owner,
        categoryId: target.transaction.categoryId,
        note: target.transaction.note,
        source: target.transaction.source,
        sourceId: target.transaction.sourceId,
        recurringTransactionId: target.transaction.recurringTransactionId,
        accountId: target.transaction.accountId,
        merchantId: target.transaction.merchantId,
        location: target.transaction.location,
        goalId: target.transaction.goalId,
        partyName: target.transaction.partyName,
        receiptRawText: target.transaction.receiptRawText,
        receiptNumber: target.transaction.receiptNumber,
        receiptPaidAmount: target.transaction.receiptPaidAmount,
        receiptChangeAmount: target.transaction.receiptChangeAmount,
        recordedAt: target.transaction.recordedAt,
        updatedAt: now,
      ),
      items: [
        for (final item in target.items)
          TransactionItemEntity(
            id: item.id,
            transactionId: item.transactionId,
            itemName: item.itemName,
            price: item.price,
            qty: item.qty,
          ),
      ],
    );
    await AuditLogger(_database).record(
      action: 'ubah',
      entity: 'transaksi',
      householdId: _householdId,
      oldValue: _transactionAuditValue(target.transaction),
      newValue: {
        ..._transactionAuditValue(target.transaction),
        'amount': signedAmount,
      },
    );
    return FfmAssistantCapabilityExecutionResult.success(
      'Transaksi diperbarui ke ${_money(amount)}. Hasilnya akan dibaca kembali untuk verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveMutation(
    FfmAssistantActionStep step,
  ) {
    if (step.parameters['entity'] == 'reminder') return _archiveReminder(step);
    if (step.parameters['entity'] == 'goal') return _archiveGoal(step);
    if (step.parameters['entity'] == 'activity_session' ||
        step.parameters['entity'] == 'task' ||
        step.parameters['entity'] == 'daily_note' ||
        step.parameters['entity'] == 'daily_routine' ||
        step.parameters['entity'] == 'schedule_entry') {
      return _archiveActivity(step);
    }
    if (step.parameters['entity'] == 'asset') return _archiveAsset(step);
    if (step.parameters['entity'] == 'liability') {
      return _archiveLiability(step);
    }
    if (step.parameters['entity'] == 'receivable') {
      return _archiveReceivable(step);
    }
    if (step.parameters['entity'] == 'recurring_transaction') {
      return _archiveRecurringTransaction(step);
    }
    if (step.parameters['entity'] == 'merchant') {
      return _archiveMerchant(step);
    }
    if (step.parameters['entity'] == 'tag') {
      return _archiveTag(step);
    }
    if (step.parameters['entity'] == 'income_source') {
      return _archiveIncomeSource(step);
    }
    if (step.parameters['entity'] == 'category') {
      return _archiveCategory(step);
    }
    if (step.parameters['entity'] == 'account') {
      return _archiveAccount(step);
    }
    if (step.parameters['entity'] == 'budget') {
      return _archiveBudget(step);
    }
    return _archiveTransaction(step);
  }

  Future<FfmAssistantCapabilityExecutionResult> _deleteMutation(
    FfmAssistantActionStep step,
  ) {
    if (step.parameters['entity'] == 'activity_session' ||
        step.parameters['entity'] == 'task' ||
        step.parameters['entity'] == 'daily_note' ||
        step.parameters['entity'] == 'schedule_entry') {
      return _deleteActivity(step);
    }
    if (step.parameters['entity'] == 'account') {
      return _deleteAccount(step);
    }
    if (step.parameters['entity'] == 'category') {
      return _deleteCategory(step);
    }
    if (step.parameters['entity'] == 'tag') {
      return _deleteTag(step);
    }
    if (step.parameters['entity'] == 'merchant') {
      return _deleteMerchant(step);
    }
    if (step.parameters['entity'] == 'income_source') {
      return _deleteIncomeSource(step);
    }
    return _deleteTransaction(step);
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveTransaction(
    FfmAssistantActionStep step,
  ) => _setTransactionVisibility(step, archive: true);

  Future<FfmAssistantCapabilityExecutionResult> _prepareLiabilityMutation(
    FfmAssistantActionStep step,
  ) async {
    final target = await _liabilityById(_targetId(step));
    if (target == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Hutang target tidak ditemukan atau sudah diarsipkan.',
      );
    }
    if (step.parameters['operation'] == 'archive') {
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview arsip Hutang "${target.name}" tanpa hapus permanen, pembayaran, atau transaksi.',
      );
    }
    final title = step.parameters['title']?.toString().trim();
    return title == null || title.isEmpty
        ? const FfmAssistantCapabilityExecutionResult.failure(
            'Nama Hutang baru belum valid.',
          )
        : FfmAssistantCapabilityExecutionResult.success(
            'Preview perubahan metadata Hutang “${target.name}” menjadi “$title”. Nilai pokok dan sisa Hutang dipertahankan.',
          );
  }

  Future<FfmAssistantCapabilityExecutionResult> _updateLiability(
    FfmAssistantActionStep step,
  ) async {
    final before = await _liabilityById(_targetId(step));
    final title = step.parameters['title']?.toString().trim();
    if (before == null || title == null || title.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target atau nama Hutang belum valid.',
      );
    }
    if (before.name == title) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'alreadyApplied: metadata Hutang sudah sesuai draft.',
      );
    }
    await SaveLiability(_database)(
      LiabilityEntity(
        id: before.id,
        householdId: before.householdId,
        name: title,
        originalAmount: before.originalAmount,
        remainingBalance: before.remainingBalance,
        monthlyInstallment: before.monthlyInstallment,
        interestRate: before.interestRate,
        startDate: before.startDate,
        dueDate: before.dueDate,
        updatedAt: _clock(),
        note: before.note,
      ),
    );
    return FfmAssistantCapabilityExecutionResult.success(
      'Metadata Hutang diperbarui tanpa pembayaran atau transaksi. Hasilnya akan dibaca kembali.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveLiability(
    FfmAssistantActionStep step,
  ) async {
    final target = await _liabilityById(_targetId(step));
    if (target == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Hutang target tidak ditemukan atau sudah diarsipkan.',
      );
    }
    await DeleteLiability(_database)(_householdId, target.id);
    return FfmAssistantCapabilityExecutionResult.success(
      'Hutang “${target.name}” diarsipkan tanpa hapus permanen.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyLiabilityMutation(
    FfmAssistantActionStep step,
  ) async {
    final id = _targetId(step);
    if (id == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Hutang belum valid.',
      );
    }
    final row =
        await (_database.select(_database.liabilities)..where(
              (r) => r.householdId.equals(_householdId) & r.id.equals(id),
            ))
            .getSingleOrNull();
    if (step.parameters['operation'] == 'archive') {
      return row?.isActive == false
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Hutang sudah diarsipkan secara lunak.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Hutang masih aktif.',
            );
    }
    final title = step.parameters['title']?.toString().trim();
    return row != null && row.isActive && row.name == title
        ? FfmAssistantCapabilityExecutionResult.success(
            'verified: metadata Hutang sudah dibaca kembali tanpa mengubah nilai pokok atau sisa Hutang.',
          )
        : const FfmAssistantCapabilityExecutionResult.failure(
            'Verifikasi gagal: metadata Hutang belum sesuai draft.',
          );
  }

  Future<LiabilityEntity?> _liabilityById(String? id) async {
    if (id == null) return null;
    final all = await GetLiabilities(_database)(_householdId);
    for (final item in all) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<FfmAssistantCapabilityExecutionResult> _prepareReceivableMutation(
    FfmAssistantActionStep step,
  ) async {
    final target = await _receivableById(_targetId(step));
    if (target == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Piutang target tidak ditemukan atau sudah diarsipkan.',
      );
    }
    if (step.parameters['operation'] == 'archive') {
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview arsip Piutang “${target.name}” tanpa hapus permanen, penagihan, pembayaran, atau transaksi.',
      );
    }
    final title = step.parameters['title']?.toString().trim();
    if (title == null || title.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama Piutang baru belum valid.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview perubahan metadata Piutang “${target.name}” menjadi “$title”. Nilai pokok dan sisa Piutang dipertahankan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _updateReceivable(
    FfmAssistantActionStep step,
  ) async {
    final before = await _receivableById(_targetId(step));
    final title = step.parameters['title']?.toString().trim();
    if (before == null || title == null || title.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target atau nama Piutang belum valid.',
      );
    }
    if (before.name == title) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'alreadyApplied: metadata Piutang sudah sesuai draft.',
      );
    }
    await SaveReceivable(_database)(
      ReceivableEntity(
        id: before.id,
        householdId: before.householdId,
        name: title,
        originalAmount: before.originalAmount,
        remainingBalance: before.remainingBalance,
        monthlyInstallment: before.monthlyInstallment,
        interestRate: before.interestRate,
        startDate: before.startDate,
        dueDate: before.dueDate,
        updatedAt: _clock(),
        note: before.note,
      ),
    );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Metadata Piutang diperbarui tanpa penagihan, pembayaran, atau transaksi. Hasilnya akan dibaca kembali.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveReceivable(
    FfmAssistantActionStep step,
  ) async {
    final target = await _receivableById(_targetId(step));
    if (target == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Piutang target tidak ditemukan atau sudah diarsipkan.',
      );
    }
    await DeleteReceivable(_database)(_householdId, target.id);
    return FfmAssistantCapabilityExecutionResult.success(
      'Piutang “${target.name}” diarsipkan tanpa hapus permanen.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyReceivableMutation(
    FfmAssistantActionStep step,
  ) async {
    final id = _targetId(step);
    if (id == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Piutang belum valid.',
      );
    }
    final row =
        await (_database.select(_database.receivables)..where(
              (r) => r.householdId.equals(_householdId) & r.id.equals(id),
            ))
            .getSingleOrNull();
    if (step.parameters['operation'] == 'archive') {
      return row?.isActive == false
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Piutang sudah diarsipkan secara lunak.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Piutang masih aktif.',
            );
    }
    final title = step.parameters['title']?.toString().trim();
    return row != null && row.isActive && row.name == title
        ? const FfmAssistantCapabilityExecutionResult.success(
            'verified: metadata Piutang sudah dibaca kembali tanpa mengubah nilai pokok atau sisa Piutang.',
          )
        : const FfmAssistantCapabilityExecutionResult.failure(
            'Verifikasi gagal: metadata Piutang belum sesuai draft.',
          );
  }

  Future<ReceivableEntity?> _receivableById(String? id) async {
    if (id == null) return null;
    final all = await GetReceivables(_database)(_householdId);
    for (final item in all) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<FfmAssistantCapabilityExecutionResult>
  _prepareRecurringTransactionMutation(FfmAssistantActionStep step) async {
    final target = await _recurringTransactionById(_targetId(step));
    if (target == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Jadwal Transaksi Berkala target tidak ditemukan atau sudah dinonaktifkan.',
      );
    }
    if (step.parameters['operation'] == 'archive') {
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview penonaktifan jadwal “${target.name}” tanpa menjalankan jadwal, mengubah riwayat, atau membuat transaksi.',
      );
    }
    final metadataField = step.parameters['metadataField']?.toString();
    final value = metadataField == 'note'
        ? step.parameters['note']?.toString().trim()
        : step.parameters['title']?.toString().trim();
    if (value == null || value.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nilai metadata Transaksi Berkala baru belum valid.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview perubahan ${metadataField == 'note' ? 'catatan' : 'nama'} jadwal “${target.name}”. Nominal, rekening, kategori, jadwal, dan mode kalkulasi dipertahankan; jadwal tidak akan dijalankan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _updateRecurringTransaction(
    FfmAssistantActionStep step,
  ) async {
    final before = await _recurringTransactionById(_targetId(step));
    final title = step.parameters['title']?.toString().trim();
    final metadataField = step.parameters['metadataField']?.toString();
    final nextNote = metadataField == 'note'
        ? step.parameters['note']?.toString().trim()
        : before?.note;
    if (before == null ||
        title == null ||
        title.isEmpty ||
        (metadataField == 'note' && (nextNote == null || nextNote.isEmpty))) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target atau metadata Transaksi Berkala belum valid.',
      );
    }
    if (before.name == title && before.note == nextNote) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'alreadyApplied: metadata Transaksi Berkala sudah sesuai draft.',
      );
    }
    await UpdateRecurringTransaction(_database)(
      id: before.id,
      householdId: before.householdId,
      name: title,
      type: before.type,
      amount: before.amount,
      startDate: before.startDate,
      periodType: before.periodType,
      categoryId: before.categoryId,
      accountId: before.accountId,
      sourceId: before.sourceId,
      note: nextNote,
      endDate: before.endDate,
      calcMode: before.calcMode,
      ratePercent: before.ratePercent,
    );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Metadata Transaksi Berkala diperbarui tanpa menjalankan jadwal atau membuat transaksi. Hasilnya akan dibaca kembali.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveRecurringTransaction(
    FfmAssistantActionStep step,
  ) async {
    final target = await _recurringTransactionById(_targetId(step));
    if (target == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Jadwal Transaksi Berkala target tidak ditemukan atau sudah dinonaktifkan.',
      );
    }
    await ArchiveRecurringTransaction(_database)(_householdId, target.id);
    return FfmAssistantCapabilityExecutionResult.success(
      'Jadwal Transaksi Berkala “${target.name}” dinonaktifkan tanpa mengubah riwayat atau transaksi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult>
  _verifyRecurringTransactionMutation(FfmAssistantActionStep step) async {
    final id = _targetId(step);
    if (id == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Transaksi Berkala belum valid.',
      );
    }
    final row =
        await (_database.select(_database.recurringTransactions)..where(
              (r) => r.householdId.equals(_householdId) & r.id.equals(id),
            ))
            .getSingleOrNull();
    if (step.parameters['operation'] == 'archive') {
      return row?.isActive == false
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: jadwal Transaksi Berkala sudah dinonaktifkan secara lunak.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: jadwal Transaksi Berkala masih aktif.',
            );
    }
    final title = step.parameters['title']?.toString().trim();
    final metadataField = step.parameters['metadataField']?.toString();
    final expectedNote = metadataField == 'note'
        ? step.parameters['note']?.toString().trim()
        : row?.note;
    return row != null &&
            row.isActive &&
            row.name == title &&
            row.note == expectedNote
        ? const FfmAssistantCapabilityExecutionResult.success(
            'verified: metadata Transaksi Berkala sudah dibaca kembali tanpa menjalankan jadwal atau mengubah transaksi.',
          )
        : const FfmAssistantCapabilityExecutionResult.failure(
            'Verifikasi gagal: metadata Transaksi Berkala belum sesuai draft.',
          );
  }

  Future<RecurringTransaction?> _recurringTransactionById(String? id) async {
    if (id == null) return null;
    final all = await GetRecurringTransactions(_database)(_householdId);
    for (final item in all) {
      if (item.id == id) return item;
    }
    return null;
  }

  MerchantRepository get _merchants =>
      MerchantRepository(_database, AuditLogger(_database), clock: _clock);

  Future<FfmAssistantCapabilityExecutionResult> _prepareMerchantMutation(
    FfmAssistantActionStep step,
  ) async {
    final target = await _merchantById(_targetId(step));
    if (target == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Toko/Tempat target tidak ditemukan atau sudah diarsipkan.',
      );
    }
    if (step.parameters['operation'] == 'archive') {
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview arsip Toko/Tempat \u201c${target.name}\u201d. Data tidak akan muncul di transaksi baru dan transaksi historis tetap utuh.',
      );
    }
    if (step.parameters['operation'] == 'delete') {
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview hapus permanen Toko/Tempat \u201c${target.name}\u201d. Data akan dihapus total dari database. Tindakan ini tidak dapat dibatalkan.',
      );
    }
    final metadataField = step.parameters['metadataField']?.toString();
    final value = metadataField == 'details'
        ? step.parameters['note']?.toString().trim()
        : step.parameters['title']?.toString().trim();
    if (value == null || value.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nilai metadata Toko/Tempat baru belum valid.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview perubahan ${metadataField == 'details' ? 'keterangan' : 'nama'} Toko/Tempat “${target.name}”. Transaksi historis tidak akan diubah.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _updateMerchant(
    FfmAssistantActionStep step,
  ) async {
    final before = await _merchantById(_targetId(step));
    final title = step.parameters['title']?.toString().trim();
    final metadataField = step.parameters['metadataField']?.toString();
    final nextDetails = metadataField == 'details'
        ? step.parameters['note']?.toString().trim()
        : before?.details;
    if (before == null ||
        title == null ||
        title.isEmpty ||
        (metadataField == 'details' &&
            (nextDetails == null || nextDetails.isEmpty))) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target atau metadata Toko/Tempat belum valid.',
      );
    }
    if (before.name == title && before.details == nextDetails) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'alreadyApplied: metadata Toko/Tempat sudah sesuai draft.',
      );
    }
    await _merchants.update(
      householdId: _householdId,
      id: before.id,
      name: title,
      details: nextDetails,
    );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Metadata Toko/Tempat diperbarui tanpa mengubah transaksi historis. Hasilnya akan dibaca kembali.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveMerchant(
    FfmAssistantActionStep step,
  ) async {
    final target = await _merchantById(_targetId(step));
    if (target == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Toko/Tempat target tidak ditemukan atau sudah diarsipkan.',
      );
    }
    await _merchants.archive(householdId: _householdId, id: target.id);
    return FfmAssistantCapabilityExecutionResult.success(
      'Toko/Tempat “${target.name}” diarsipkan lunak tanpa mengubah transaksi historis.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyMerchantMutation(
    FfmAssistantActionStep step,
  ) async {
    final id = _targetId(step);
    if (id == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Toko/Tempat belum valid.',
      );
    }
    final row = await _merchants.get(_householdId, id);
    if (step.parameters['operation'] == 'archive') {
      return row?.isActive == false
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Toko/Tempat sudah diarsipkan secara lunak.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Toko/Tempat masih aktif.',
            );
    }
    if (step.parameters['operation'] == 'delete') {
      return row == null
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Toko/Tempat sudah tidak ditemukan di database lokal.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Toko/Tempat masih ditemukan setelah penghapusan.',
            );
    }
    final title = step.parameters['title']?.toString().trim();
    final metadataField = step.parameters['metadataField']?.toString();
    final expectedDetails = metadataField == 'details'
        ? step.parameters['note']?.toString().trim()
        : row?.details;
    return row != null &&
            row.isActive &&
            row.name == title &&
            row.details == expectedDetails
        ? const FfmAssistantCapabilityExecutionResult.success(
            'verified: metadata Toko/Tempat sudah dibaca kembali tanpa mengubah transaksi historis.',
          )
        : const FfmAssistantCapabilityExecutionResult.failure(
            'Verifikasi gagal: metadata Toko/Tempat belum sesuai draft.',
          );
  }

  Future<Merchant?> _merchantById(String? id) async {
    if (id == null) return null;
    final all = await _merchants.readActive(_householdId);
    for (final item in all) {
      if (item.id == id) return item;
    }
    return null;
  }

  TagRepository get _tags =>
      TagRepository(_database, AuditLogger(_database), clock: _clock);

  Future<FfmAssistantCapabilityExecutionResult> _prepareTagMutation(
    FfmAssistantActionStep step,
  ) async {
    final target = await _tagById(_targetId(step));
    if (target == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Tag target tidak ditemukan atau sudah diarsipkan.',
      );
    }
    if (step.parameters['operation'] == 'archive') {
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview arsip Tag \u201c${target.name}\u201d. Relasi Tag pada transaksi historis tidak akan diubah.',
      );
    }
    if (step.parameters['operation'] == 'delete') {
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview hapus permanen Tag \u201c${target.name}\u201d. Data akan dihapus total dari database. Tindakan ini tidak dapat dibatalkan.',
      );
    }
    final title = step.parameters['title']?.toString().trim();
    if (title == null || title.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama Tag baru belum valid.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview perubahan nama Tag “${target.name}” menjadi “$title”. Relasi Tag pada transaksi tidak akan diubah.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _updateTag(
    FfmAssistantActionStep step,
  ) async {
    final before = await _tagById(_targetId(step));
    final title = step.parameters['title']?.toString().trim();
    if (before == null || title == null || title.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target atau nama Tag belum valid.',
      );
    }
    if (before.name == title) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'alreadyApplied: nama Tag sudah sesuai draft.',
      );
    }
    await _tags.update(householdId: _householdId, id: before.id, name: title);
    return const FfmAssistantCapabilityExecutionResult.success(
      'Nama Tag diperbarui tanpa mengubah relasi Tag pada transaksi. Hasilnya akan dibaca kembali.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveTag(
    FfmAssistantActionStep step,
  ) async {
    final target = await _tagById(_targetId(step));
    if (target == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Tag target tidak ditemukan atau sudah diarsipkan.',
      );
    }
    await _tags.archive(householdId: _householdId, id: target.id);
    return FfmAssistantCapabilityExecutionResult.success(
      'Tag “${target.name}” diarsipkan lunak tanpa mengubah relasi Tag pada transaksi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyTagMutation(
    FfmAssistantActionStep step,
  ) async {
    final id = _targetId(step);
    if (id == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Tag belum valid.',
      );
    }
    final row = await _tags.get(_householdId, id);
    if (step.parameters['operation'] == 'archive') {
      return row?.isArchived == true
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Tag sudah diarsipkan secara lunak.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Tag masih aktif.',
            );
    }
    if (step.parameters['operation'] == 'delete') {
      return row == null
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Tag sudah tidak ditemukan di database lokal.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Tag masih ditemukan setelah penghapusan.',
            );
    }
    final title = step.parameters['title']?.toString().trim();
    return row != null && !row.isArchived && row.name == title
        ? const FfmAssistantCapabilityExecutionResult.success(
            'verified: nama Tag sudah dibaca kembali tanpa mengubah relasi transaksi.',
          )
        : const FfmAssistantCapabilityExecutionResult.failure(
            'Verifikasi gagal: nama Tag belum sesuai draft.',
          );
  }

  Future<Tag?> _tagById(String? id) async {
    if (id == null) return null;
    final all = await _tags.readActive(_householdId);
    for (final item in all) {
      if (item.id == id) return item;
    }
    return null;
  }

  IncomeSourceRepository get _incomeSources =>
      IncomeSourceRepository(_database, AuditLogger(_database), clock: _clock);

  Future<FfmAssistantCapabilityExecutionResult> _prepareIncomeSourceMutation(
    FfmAssistantActionStep step,
  ) async {
    final target = await _incomeSourceById(_targetId(step));
    if (target == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Sumber Pemasukan target tidak ditemukan atau sudah diarsipkan.',
      );
    }
    if (step.parameters['operation'] == 'archive') {
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview arsip Sumber Pemasukan \u201c${target.name}\u201d. sourceId transaksi historis tidak akan diubah.',
      );
    }
    if (step.parameters['operation'] == 'delete') {
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview hapus permanen Sumber Pemasukan \u201c${target.name}\u201d. Data akan dihapus total dari database. Tindakan ini tidak dapat dibatalkan.',
      );
    }
    final metadataField = step.parameters['metadataField']?.toString();
    final value = metadataField == 'details'
        ? step.parameters['note']?.toString().trim()
        : step.parameters['title']?.toString().trim();
    if (value == null || value.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nilai metadata Sumber Pemasukan baru belum valid.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview perubahan ${metadataField == 'details' ? 'keterangan' : 'nama'} Sumber Pemasukan “${target.name}”. sourceId transaksi tidak akan diubah.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _updateIncomeSource(
    FfmAssistantActionStep step,
  ) async {
    final before = await _incomeSourceById(_targetId(step));
    final title = step.parameters['title']?.toString().trim();
    final metadataField = step.parameters['metadataField']?.toString();
    final nextDetails = metadataField == 'details'
        ? step.parameters['note']?.toString().trim()
        : before?.details;
    if (before == null ||
        title == null ||
        title.isEmpty ||
        (metadataField == 'details' &&
            (nextDetails == null || nextDetails.isEmpty))) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target atau metadata Sumber Pemasukan belum valid.',
      );
    }
    if (before.name == title && before.details == nextDetails) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'alreadyApplied: metadata Sumber Pemasukan sudah sesuai draft.',
      );
    }
    await _incomeSources.update(
      householdId: _householdId,
      id: before.id,
      name: title,
      details: nextDetails,
    );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Metadata Sumber Pemasukan diperbarui tanpa mengubah sourceId transaksi. Hasilnya akan dibaca kembali.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveIncomeSource(
    FfmAssistantActionStep step,
  ) async {
    final target = await _incomeSourceById(_targetId(step));
    if (target == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Sumber Pemasukan target tidak ditemukan atau sudah diarsipkan.',
      );
    }
    await _incomeSources.archive(householdId: _householdId, id: target.id);
    return FfmAssistantCapabilityExecutionResult.success(
      'Sumber Pemasukan “${target.name}” diarsipkan lunak tanpa mengubah sourceId transaksi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyIncomeSourceMutation(
    FfmAssistantActionStep step,
  ) async {
    final id = _targetId(step);
    if (id == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Sumber Pemasukan belum valid.',
      );
    }
    final row = await _incomeSources.get(_householdId, id);
    if (step.parameters['operation'] == 'archive') {
      return row?.isArchived == true
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Sumber Pemasukan sudah diarsipkan secara lunak.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Sumber Pemasukan masih aktif.',
            );
    }
    if (step.parameters['operation'] == 'delete') {
      return row == null
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Sumber Pemasukan sudah tidak ditemukan di database lokal.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Sumber Pemasukan masih ditemukan setelah penghapusan.',
            );
    }
    final title = step.parameters['title']?.toString().trim();
    final metadataField = step.parameters['metadataField']?.toString();
    final expectedDetails = metadataField == 'details'
        ? step.parameters['note']?.toString().trim()
        : row?.details;
    return row != null &&
            !row.isArchived &&
            row.name == title &&
            row.details == expectedDetails &&
            row.kind == IncomeSourceRepository.kind &&
            row.role == IncomeSourceRepository.role
        ? const FfmAssistantCapabilityExecutionResult.success(
            'verified: metadata Sumber Pemasukan sudah dibaca kembali tanpa mengubah sourceId transaksi.',
          )
        : const FfmAssistantCapabilityExecutionResult.failure(
            'Verifikasi gagal: metadata Sumber Pemasukan belum sesuai draft.',
          );
  }

  Future<TransactionParty?> _incomeSourceById(String? id) async {
    if (id == null) return null;
    final all = await _incomeSources.readActive(_householdId);
    for (final item in all) {
      if (item.id == id) return item;
    }
    return null;
  }

  CategoryRepository get _categories =>
      CategoryRepository(_database, AuditLogger(_database), clock: _clock);

  Future<FfmAssistantCapabilityExecutionResult> _prepareCategoryMutation(
    FfmAssistantActionStep step,
  ) async {
    final target = await _categoryById(_targetId(step));
    if (target == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Kategori target tidak ditemukan atau sudah diarsipkan.',
      );
    }
    if (step.parameters['operation'] == 'archive') {
      final block = await _categories.archiveBlockReason(
        householdId: _householdId,
        id: target.id,
      );
      if (block != null) {
        return FfmAssistantCapabilityExecutionResult.failure(
          'Arsip Kategori tidak dapat disiapkan: $block',
        );
      }
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview arsip Kategori \u201c${target.name}\u201d. Guard subkategori, transaksi berkala, Target Keuangan, dan Anggaran aktif sudah lolos.',
      );
    }
    if (step.parameters['operation'] == 'delete') {
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview hapus permanen Kategori \u201c${target.name}\u201d. Data akan dihapus total dari database. Tindakan ini tidak dapat dibatalkan.',
      );
    }
    final title = step.parameters['title']?.toString().trim();
    if (title == null || title.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama Kategori baru belum valid.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview perubahan nama Kategori “${target.name}” menjadi “$title”. Tipe, hierarki, periode Anggaran, dan relasi data tidak akan diubah.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _updateCategory(
    FfmAssistantActionStep step,
  ) async {
    final before = await _categoryById(_targetId(step));
    final title = step.parameters['title']?.toString().trim();
    if (before == null || title == null || title.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target atau nama Kategori belum valid.',
      );
    }
    if (before.name == title) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'alreadyApplied: nama Kategori sudah sesuai draft.',
      );
    }
    await _categories.updateName(
      householdId: _householdId,
      id: before.id,
      name: title,
    );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Nama Kategori diperbarui tanpa mengubah tipe, hierarki, periode Anggaran, atau relasi kategori. Hasilnya akan dibaca kembali.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveCategory(
    FfmAssistantActionStep step,
  ) async {
    final target = await _categoryById(_targetId(step));
    if (target == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Kategori target tidak ditemukan atau sudah diarsipkan.',
      );
    }
    final block = await _categories.archiveBlockReason(
      householdId: _householdId,
      id: target.id,
    );
    if (block != null) {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Arsip Kategori ditolak: $block',
      );
    }
    await _categories.archive(householdId: _householdId, id: target.id);
    return FfmAssistantCapabilityExecutionResult.success(
      'Kategori “${target.name}” diarsipkan lunak setelah seluruh guard dependensi lolos.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyCategoryMutation(
    FfmAssistantActionStep step,
  ) async {
    final id = _targetId(step);
    if (id == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Kategori belum valid.',
      );
    }
    final row = await _categories.get(_householdId, id);
    final preservesProtectedFields =
        row != null &&
        row.type == step.parameters['protectedType'] &&
        (row.parentId ?? '') == step.parameters['protectedParentId'] &&
        row.defaultBudgetPeriod ==
            step.parameters['protectedDefaultBudgetPeriod'];
    if (step.parameters['operation'] == 'archive') {
      return row != null && !row.isActive && preservesProtectedFields
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Kategori sudah diarsipkan lunak dan field terlindungi tetap sama.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: arsip atau field terlindungi Kategori tidak sesuai.',
            );
    }
    if (step.parameters['operation'] == 'delete') {
      return row == null
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Kategori sudah tidak ditemukan di database lokal.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Kategori masih ditemukan setelah penghapusan.',
            );
    }
    final title = step.parameters['title']?.toString().trim();
    return row != null &&
            row.isActive &&
            row.name == title &&
            preservesProtectedFields
        ? const FfmAssistantCapabilityExecutionResult.success(
            'verified: nama Kategori dibaca kembali dan field terlindungi tetap sama.',
          )
        : const FfmAssistantCapabilityExecutionResult.failure(
            'Verifikasi gagal: nama atau field terlindungi Kategori tidak sesuai draft.',
          );
  }

  Future<Category?> _categoryById(String? id) async {
    if (id == null) return null;
    final all = await _categories.readActive(_householdId);
    for (final item in all) {
      if (item.id == id) return item;
    }
    return null;
  }

  AccountRepository get _accounts =>
      AccountRepository(_database, AuditLogger(_database), clock: _clock);

  Future<FfmAssistantCapabilityExecutionResult> _prepareAccountMutation(
    FfmAssistantActionStep step,
  ) async {
    final target = await _accountById(_targetId(step));
    if (target == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Rekening target tidak ditemukan, sudah diarsipkan, atau tidak aktif.',
      );
    }
    if (step.parameters['operation'] == 'archive') {
      final block = await _accounts.archiveBlockReason(
        householdId: _householdId,
        id: target.id,
      );
      if (block != null) {
        return FfmAssistantCapabilityExecutionResult.failure(
          'Arsip Rekening tidak dapat disiapkan: $block',
        );
      }
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview arsip Rekening \u201c${target.name}\u201d. Guard transaksi, transfer, transaksi berkala, dan rekonsiliasi sudah lolos. Saldo awal, tipe, status aktif, dan seluruh referensi keuangan tidak akan diubah.',
      );
    }
    if (step.parameters['operation'] == 'delete') {
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview hapus permanen Rekening \u201c${target.name}\u201d. Data akan dihapus total dari database. Tindakan ini tidak dapat dibatalkan.',
      );
    }
    final title = step.parameters['title']?.toString().trim();
    if (title == null || title.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama Rekening baru belum valid.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview perubahan nama Rekening “${target.name}” menjadi “$title”. Saldo awal, tipe, status aktif, dan seluruh referensi keuangan tidak akan diubah.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _updateAccount(
    FfmAssistantActionStep step,
  ) async {
    final before = await _accountById(_targetId(step));
    final title = step.parameters['title']?.toString().trim();
    if (before == null || title == null || title.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target atau nama Rekening belum valid.',
      );
    }
    if (before.name == title) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'alreadyApplied: nama Rekening sudah sesuai draft.',
      );
    }
    await _accounts.updateName(
      householdId: _householdId,
      id: before.id,
      name: title,
    );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Nama Rekening diperbarui tanpa mengubah saldo awal, tipe, status, atau referensi keuangan. Hasilnya akan dibaca kembali.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveAccount(
    FfmAssistantActionStep step,
  ) async {
    final target = await _accountById(_targetId(step));
    if (target == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Rekening target tidak ditemukan, sudah diarsipkan, atau tidak aktif.',
      );
    }
    final block = await _accounts.archiveBlockReason(
      householdId: _householdId,
      id: target.id,
    );
    if (block != null) {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Arsip Rekening ditolak: $block',
      );
    }
    try {
      await _accounts.archive(householdId: _householdId, id: target.id);
    } on StateError catch (error) {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Arsip Rekening ditolak: ${error.message}',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Rekening “${target.name}” diarsipkan lunak setelah seluruh guard referensi lolos.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyAccountMutation(
    FfmAssistantActionStep step,
  ) async {
    final id = _targetId(step);
    if (id == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Rekening belum valid.',
      );
    }
    final row = await _accounts.get(_householdId, id);
    final preservesProtectedFields =
        row != null &&
        row.id == step.parameters['protectedId'] &&
        row.householdId == step.parameters['protectedHouseholdId'] &&
        row.type == step.parameters['protectedType'] &&
        row.openingBalance ==
            int.tryParse(
              step.parameters['protectedOpeningBalance']?.toString() ?? '',
            ) &&
        row.isActive ==
            (step.parameters['protectedIsActive']?.toString() == 'true') &&
        row.createdAt.toIso8601String() ==
            step.parameters['protectedCreatedAt'];
    if (step.parameters['operation'] == 'archive') {
      return row != null &&
              row.isArchived &&
              preservesProtectedFields &&
              row.isArchived ==
                  (step.parameters['protectedArchiveResult']?.toString() ==
                      'true')
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Rekening sudah diarsipkan lunak dan field terlindungi tetap sama.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: arsip atau field terlindungi Rekening tidak sesuai.',
            );
    }
    if (step.parameters['operation'] == 'delete') {
      return row == null
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Rekening sudah tidak ditemukan di database lokal.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Rekening masih ditemukan setelah penghapusan.',
            );
    }
    final title = step.parameters['title']?.toString().trim();
    return row != null &&
            !row.isArchived &&
            row.name == title &&
            preservesProtectedFields
        ? const FfmAssistantCapabilityExecutionResult.success(
            'verified: nama Rekening dibaca kembali dan field terlindungi tetap sama.',
          )
        : const FfmAssistantCapabilityExecutionResult.failure(
            'Verifikasi gagal: nama atau field terlindungi Rekening tidak sesuai draft.',
          );
  }

  Future<Account?> _accountById(String? id) async {
    if (id == null) return null;
    final all = await _accounts.readActive(_householdId);
    for (final item in all) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<FfmAssistantCapabilityExecutionResult> _deleteTransaction(
    FfmAssistantActionStep step,
  ) => _setTransactionVisibility(step, archive: false);

  Future<FfmAssistantCapabilityExecutionResult> _setTransactionVisibility(
    FfmAssistantActionStep step, {
    required bool archive,
  }) async {
    final targetId = _targetId(step);
    if (targetId == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload belum memiliki transaksi target yang valid.',
      );
    }
    final current = await GetTransaction(_database)(_householdId, targetId);
    if (current == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Transaksi target tidak ditemukan.',
      );
    }
    if (archive &&
        current.transaction.isArchived &&
        !current.transaction.isDeleted) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'alreadyApplied: transaksi sudah diarsipkan.',
      );
    }
    if (!archive && current.transaction.isDeleted) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'alreadyApplied: transaksi sudah dihapus dari daftar aktif.',
      );
    }
    if (current.transaction.goalId != null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Transaksi yang terkait target keuangan harus dikelola dari form transaksi agar kontribusi target ikut disinkronkan.',
      );
    }
    if (archive) {
      await ArchiveTransaction(_database)(_householdId, targetId);
    } else {
      await DeleteTransaction(_database)(_householdId, targetId);
    }
    await AuditLogger(_database).record(
      action: archive ? 'arsip' : 'hapus',
      entity: 'transaksi',
      householdId: _householdId,
      oldValue: _transactionAuditValue(current.transaction),
      newValue: {
        ..._transactionAuditValue(current.transaction),
        'isArchived': true,
        if (!archive) 'isDeleted': true,
      },
    );
    return FfmAssistantCapabilityExecutionResult.success(
      archive
          ? 'Transaksi diarsipkan. Hasilnya akan dibaca kembali untuk verifikasi.'
          : 'Transaksi dihapus dari daftar aktif. Jejak audit tetap tersimpan secara lokal.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _prepareActivityMutation(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target aktivitas belum valid.',
      );
    }
    final repository = ActivityRepository(_database, AuditLogger(_database));
    final session = await repository.getSession(_householdId, targetId);
    if (session == null || session.isArchived) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Aktivitas target tidak ditemukan atau sudah diarsipkan.',
      );
    }

    final operation = step.parameters['operation']?.toString() ?? 'perubahan';
    final suffix = switch (operation) {
      'complete' || 'finish' => ' akan ditandai selesai',
      'reopen' => ' akan dibuka kembali',
      'archive' => ' akan diarsipkan tanpa dihapus permanen',
      'delete' => ' akan dihapus permanen beserta data turunannya',
      'update' || 'checkpoint' => ' akan ditambahkan checkpoint/catatan',
      'edit' => ' akan diedit judul/kategorinya',
      _ => ' akan diperbarui',
    };

    return FfmAssistantCapabilityExecutionResult.success(
      'Preview ${session.kind.name} “${session.title}”$suffix. Belum ada data yang diubah.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _updateActivity(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final operation = step.parameters['operation']?.toString();
    if (targetId == null || operation == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target atau operasi aktivitas belum valid.',
      );
    }

    final repository = ActivityRepository(_database, AuditLogger(_database));
    final current = await repository.getSession(_householdId, targetId);
    if (current == null || current.isArchived) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Aktivitas tidak ditemukan atau sudah diarsipkan.',
      );
    }

    final now = _clock();
    if (operation == 'complete' || operation == 'finish') {
      await repository.saveSession(
        current.copyWith(
          isCompleted: true,
          status: ActivitySessionStatus.completed,
          endedAt: now,
          updatedAt: now,
        ),
      );
      return FfmAssistantCapabilityExecutionResult.success(
        'Aktivitas "${current.title}" ditandai selesai.',
      );
    }

    if (operation == 'reopen') {
      await repository.saveSession(
        current.copyWith(
          isCompleted: false,
          status: ActivitySessionStatus.active,
          endedAt: null,
          updatedAt: now,
        ),
      );
      return FfmAssistantCapabilityExecutionResult.success(
        'Aktivitas "${current.title}" dibuka kembali.',
      );
    }

    if (operation == 'update' || operation == 'checkpoint') {
      final label = step.parameters['label']?.toString();
      if (label != null && label.isNotEmpty) {
        final place = step.parameters['place']?.toString();
        final note = step.parameters['note']?.toString();
        final checkpoint = ActivityCheckpointEntity(
          id: 'checkpoint-${now.microsecondsSinceEpoch}',
          sessionId: targetId,
          label: label,
          place: place,
          note: note,
          occurredAt: now,
          sequence: 0,
          createdAt: now,
        );
        await repository.saveCheckpoint(checkpoint);
        return FfmAssistantCapabilityExecutionResult.success(
          'Checkpoint "$label" ditambahkan ke aktivitas "${current.title}".',
        );
      }
    }

    if (operation == 'edit') {
      final title = step.parameters['title']?.toString() ?? current.title;
      final notes = step.parameters['note']?.toString() ?? current.notes;
      final category =
          step.parameters['category']?.toString() ?? current.category;
      final dueDate = _dateParameter(
        step.parameters['dueDate'] ?? step.parameters['date'],
      );
      final scheduledAt = _dateParameter(step.parameters['scheduledAt']);

      await repository.saveSession(
        current.copyWith(
          title: title,
          notes: notes,
          category: category,
          dueDate: dueDate ?? current.dueDate,
          scheduledAt: scheduledAt ?? current.scheduledAt,
          updatedAt: now,
        ),
      );
      return FfmAssistantCapabilityExecutionResult.success(
        'Aktivitas "${current.title}" diperbarui.',
      );
    }

    return const FfmAssistantCapabilityExecutionResult.failure(
      'Operasi aktivitas tidak dikenal.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveActivity(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target aktivitas belum valid.',
      );
    }
    final repository = ActivityRepository(_database, AuditLogger(_database));
    final current = await repository.getSession(_householdId, targetId);
    if (current == null || current.isArchived) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Aktivitas tidak ditemukan atau sudah diarsipkan.',
      );
    }
    if (current.status == ActivitySessionStatus.active) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Aktivitas yang masih berjalan harus diselesaikan sebelum diarsipkan.',
      );
    }
    await repository.archiveSession(_householdId, targetId);
    return const FfmAssistantCapabilityExecutionResult.success(
      'Aktivitas diarsipkan. Hasilnya akan dibaca kembali untuk verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _deleteActivity(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target aktivitas belum valid.',
      );
    }
    final repository = ActivityRepository(_database, AuditLogger(_database));
    final current = await repository.getSession(_householdId, targetId);
    if (current == null || current.isArchived) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Aktivitas tidak ditemukan atau sudah diarsipkan.',
      );
    }
    if (current.status == ActivitySessionStatus.active) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Aktivitas yang masih berjalan harus diselesaikan sebelum dihapus permanen.',
      );
    }
    await repository.deleteSessionPermanently(_householdId, targetId);
    return const FfmAssistantCapabilityExecutionResult.success(
      'Aktivitas dan data turunannya dihapus permanen. Hasilnya akan dibaca kembali untuk verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _deleteAccount(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Rekening belum valid.',
      );
    }
    final account = await (_database.select(_database.accounts)
          ..where((r) => r.id.equals(targetId)))
        .getSingleOrNull();
    if (account == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Rekening tidak ditemukan.',
      );
    }
    await (_database.delete(_database.accounts)
          ..where((r) => r.id.equals(targetId)))
        .go();
    return FfmAssistantCapabilityExecutionResult.success(
      'Rekening "${account.name}" dihapus permanen dari database.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _deleteCategory(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Kategori belum valid.',
      );
    }
    final category = await (_database.select(_database.categories)
          ..where((r) => r.id.equals(targetId)))
        .getSingleOrNull();
    if (category == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Kategori tidak ditemukan.',
      );
    }
    await (_database.delete(_database.categories)
          ..where((r) => r.id.equals(targetId)))
        .go();
    return FfmAssistantCapabilityExecutionResult.success(
      'Kategori "${category.name}" dihapus permanen dari database.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _deleteTag(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Tag belum valid.',
      );
    }
    final tag = await (_database.select(_database.tags)
          ..where((r) => r.id.equals(targetId)))
        .getSingleOrNull();
    if (tag == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Tag tidak ditemukan.',
      );
    }
    await (_database.delete(_database.tags)
          ..where((r) => r.id.equals(targetId)))
        .go();
    return FfmAssistantCapabilityExecutionResult.success(
      'Tag "${tag.name}" dihapus permanen dari database.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _deleteMerchant(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Toko/Tempat belum valid.',
      );
    }
    final merchant = await (_database.select(_database.merchants)
          ..where((r) => r.id.equals(targetId)))
        .getSingleOrNull();
    if (merchant == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Toko/Tempat tidak ditemukan.',
      );
    }
    await (_database.delete(_database.merchants)
          ..where((r) => r.id.equals(targetId)))
        .go();
    return FfmAssistantCapabilityExecutionResult.success(
      'Toko/Tempat "${merchant.name}" dihapus permanen dari database.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _deleteIncomeSource(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Sumber Pemasukan belum valid.',
      );
    }
    final source = await (_database.select(_database.transactionParties)
          ..where((r) => r.id.equals(targetId)))
        .getSingleOrNull();
    if (source == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Sumber Pemasukan tidak ditemukan.',
      );
    }
    await (_database.delete(_database.transactionParties)
          ..where((r) => r.id.equals(targetId)))
        .go();
    return FfmAssistantCapabilityExecutionResult.success(
      'Sumber Pemasukan "${source.name}" dihapus permanen dari database.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyActivityMutation(
    FfmAssistantActionStep step,
  ) async {
    final kind = step.parameters['kind']?.toString();
    final repository = ActivityRepository(_database, AuditLogger(_database));

    if (kind != null &&
        const {'activity', 'task', 'dailyNote', 'schedule'}.contains(kind)) {
      final key = step.parameters['_idempotencyKey']?.toString();
      if (key == null || key.isEmpty) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Kunci verifikasi aktivitas belum ada.',
        );
      }
      final session = await repository.getSession(_householdId, _stableId(key));
      return session != null && !session.isArchived
          ? FfmAssistantCapabilityExecutionResult.success(
              'verified: aktivitas “${session.title}” (${session.kind.name}) berhasil dibaca kembali dari data lokal.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: aktivitas belum ditemukan setelah simpan.',
            );
    }

    final targetId = _targetId(step);
    final operation = step.parameters['operation']?.toString();
    if (targetId == null || operation == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload verifikasi perubahan aktivitas tidak lengkap.',
      );
    }

    final session = await repository.getSession(_householdId, targetId);
    if (operation == 'archive') {
      return session?.isArchived == true
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: aktivitas sudah diarsipkan dan tidak tampil pada daftar aktif.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: aktivitas belum berstatus arsip.',
            );
    }
    if (operation == 'delete') {
      return session == null
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: aktivitas beserta data turunan yang terkait sudah tidak ditemukan di database lokal.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: aktivitas masih ditemukan setelah penghapusan.',
            );
    }
    if (operation == 'complete') {
      return session?.isCompleted == true
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: aktivitas sudah berstatus selesai.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: aktivitas belum berstatus selesai.',
            );
    }
    if (operation == 'reopen') {
      return session != null && !session.isArchived && !session.isCompleted
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: aktivitas sudah kembali berstatus aktif.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: aktivitas belum kembali aktif.',
            );
    }
    if (operation == 'update') {
      final title = step.parameters['title']?.toString().trim();
      return session != null && !session.isArchived && session.title == title
          ? FfmAssistantCapabilityExecutionResult.success(
              'verified: aktivitas “${session.title}” sudah terbaca kembali dengan data yang diperbarui.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: perubahan aktivitas belum sesuai draft.',
            );
    }

    return const FfmAssistantCapabilityExecutionResult.failure(
      'Jenis perubahan aktivitas tidak dikenal saat verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _prepareAssetMutation(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final operation = step.parameters['operation']?.toString();
    if (targetId == null || !const {'update', 'archive'}.contains(operation)) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload perubahan Aset tidak lengkap.',
      );
    }
    final asset = await _assetById(targetId);
    if (asset == null || asset.isArchived) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Aset target tidak ditemukan atau sudah diarsipkan.',
      );
    }
    if (operation == 'archive') {
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview arsip aset “${asset.name}”. Aset hanya akan disembunyikan dari daftar aktif; tidak ada transaksi atau saldo yang diubah.',
      );
    }
    final title = step.parameters['title']?.toString().trim();
    final value = _nonNegativeInt(step.parameters['amount']);
    if (title == null || title.isEmpty || value == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama atau nilai baru Aset belum valid.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview perubahan aset “${asset.name}” menjadi “$title” bernilai ${_money(value)}. Tidak ada transaksi atau saldo yang diubah.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _updateAsset(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final title = step.parameters['title']?.toString();
    final value = _nonNegativeInt(step.parameters['amount']);
    if (targetId == null ||
        title == null ||
        title.trim().isEmpty ||
        value == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target, nama, atau nilai Aset belum valid.',
      );
    }
    final before = await _assetById(targetId);
    if (before == null || before.isArchived) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Aset target tidak ditemukan atau sudah diarsipkan.',
      );
    }
    final assetType = step.parameters['assetType']?.toString().trim();
    final placement = step.parameters['placement']?.toString().trim();
    final next = AssetEntity(
      id: before.id,
      householdId: before.householdId,
      name: title,
      assetType: assetType == null || assetType.isEmpty
          ? before.assetType
          : assetType,
      value: value,
      placement: placement == null || placement.isEmpty
          ? before.placement
          : placement,
      note: step.parameters['note']?.toString() ?? before.note,
      createdAt: before.createdAt,
      updatedAt: _clock(),
      isArchived: false,
    );
    if (next.name == before.name &&
        next.value == before.value &&
        next.assetType == before.assetType &&
        next.placement == before.placement &&
        next.note == before.note) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'alreadyApplied: Aset sudah sesuai dengan draft perubahan.',
      );
    }
    await SaveAsset(_database)(next);
    return FfmAssistantCapabilityExecutionResult.success(
      'Aset “${next.name}” diperbarui tanpa membuat transaksi atau saldo. Hasilnya akan dibaca kembali untuk verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveAsset(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Aset belum valid.',
      );
    }
    final asset = await _assetById(targetId);
    if (asset == null || asset.isArchived) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Aset tidak ditemukan atau sudah diarsipkan.',
      );
    }
    await ArchiveAsset(_database)(_householdId, targetId);
    return FfmAssistantCapabilityExecutionResult.success(
      'Aset “${asset.name}” diarsipkan tanpa hapus permanen. Tidak ada transaksi atau saldo yang diubah. Hasilnya akan dibaca kembali untuk verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyAssetMutation(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final operation = step.parameters['operation']?.toString();
    final asset = targetId == null ? null : await _assetById(targetId);
    if (operation == 'archive') {
      return asset?.isArchived == true
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Aset sudah diarsipkan dan tidak tampil pada daftar aktif.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Aset belum berstatus arsip.',
            );
    }
    final title = step.parameters['title']?.toString().trim();
    final value = _nonNegativeInt(step.parameters['amount']);
    return asset != null &&
            !asset.isArchived &&
            title != null &&
            asset.name == title &&
            value != null &&
            asset.value == value
        ? FfmAssistantCapabilityExecutionResult.success(
            'verified: Aset “${asset.name}” sudah dibaca kembali sesuai draft.',
          )
        : const FfmAssistantCapabilityExecutionResult.failure(
            'Verifikasi gagal: perubahan Aset belum sesuai draft.',
          );
  }

  Future<AssetEntity?> _assetById(String id) async {
    final row =
        await (_database.select(_database.assets)..where(
              (item) =>
                  item.householdId.equals(_householdId) & item.id.equals(id),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : AssetEntity(
            id: row.id,
            householdId: row.householdId,
            name: row.name,
            assetType: row.assetType,
            value: row.value,
            placement: row.placement,
            note: row.note,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            isArchived: row.isArchived,
          );
  }

  Future<FfmAssistantCapabilityExecutionResult> _prepareReminderMutation(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final operation = step.parameters['operation']?.toString();
    if (targetId == null || !const {'update', 'archive'}.contains(operation)) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload perubahan pengingat tidak lengkap.',
      );
    }
    if (_reminderMutations == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Layanan jadwal pengingat belum siap. Pengingat belum diubah.',
      );
    }
    final reminder = await ReminderRepository(_database)
        .getReminder(_householdId, targetId);
    if (reminder == null || !reminder.isActive) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Pengingat tidak ditemukan atau sudah nonaktif.',
      );
    }
    if (operation == 'archive') {
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview arsip pengingat “${reminder.title}”. Alarm berikutnya akan dibatalkan dan riwayat tetap disimpan. Belum ada data yang diubah.',
      );
    }
    final title = step.parameters['title']?.toString().trim();
    final scheduledAt = _dateParameter(step.parameters['scheduledAt']);
    if (title == null || title.isEmpty || scheduledAt == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Judul atau waktu baru pengingat belum valid.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview perubahan pengingat “${reminder.title}” menjadi “$title” pada ${scheduledAt.toIso8601String().substring(0, 16)}. Pola berulang, suara, snooze, dan identitas notifikasi tetap dipertahankan. Belum ada data yang diubah.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _updateReminder(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final reminderMutations = _reminderMutations;
    final title = step.parameters['title']?.toString();
    final scheduledAt = _dateParameter(step.parameters['scheduledAt']);
    if (targetId == null ||
        reminderMutations == null ||
        title == null ||
        scheduledAt == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Layanan, target, judul, atau waktu pengingat belum siap.',
      );
    }
    final previous = await ReminderRepository(_database)
        .getReminder(_householdId, targetId);
    if (previous == null || !previous.isActive) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Pengingat tidak ditemukan atau sudah nonaktif.',
      );
    }
    try {
      final updated = await reminderMutations.updateTitleAndScheduledAt(
        previous: previous,
        title: title,
        note: step.parameters['note']?.toString(),
        scheduledAt: scheduledAt,
      );
      if (updated.title == previous.title &&
          updated.note == previous.note &&
          updated.scheduledAt == previous.scheduledAt) {
        return const FfmAssistantCapabilityExecutionResult.success(
          'alreadyApplied: pengingat sudah sesuai dengan draft perubahan.',
        );
      }
      return FfmAssistantCapabilityExecutionResult.success(
        'Pengingat “${updated.title}” diperbarui dan dijadwalkan ulang. Pola berulang, suara, snooze, dan identitas notifikasi tetap dipertahankan. Hasilnya akan dibaca kembali untuk verifikasi.',
      );
    } on Object {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Pengingat belum dapat diperbarui karena izin atau jadwal notifikasi belum siap.',
      );
    }
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveReminder(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final reminderMutations = _reminderMutations;
    if (targetId == null || reminderMutations == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Layanan atau target pengingat belum siap.',
      );
    }
    final reminder = await ReminderRepository(_database)
        .getReminder(_householdId, targetId);
    if (reminder == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Pengingat tidak ditemukan.',
      );
    }
    if (!reminder.isActive) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'alreadyApplied: pengingat sudah nonaktif.',
      );
    }
    try {
      await reminderMutations.archive(reminder);
    } on Object {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Pengingat belum dapat diarsipkan karena jadwal notifikasi belum siap.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Pengingat “${reminder.title}” dinonaktifkan. Hasilnya akan dibaca kembali untuk verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyReminderMutation(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final operation = step.parameters['operation']?.toString();
    if (targetId == null || !const {'update', 'archive'}.contains(operation)) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload verifikasi perubahan pengingat tidak lengkap.',
      );
    }
    final reminder = await ReminderRepository(_database)
        .getReminder(_householdId, targetId);
    if (operation == 'archive') {
      return reminder != null && !reminder.isActive
          ? FfmAssistantCapabilityExecutionResult.success(
              'verified: pengingat “${reminder.title}” sudah nonaktif dan tidak akan dijadwalkan lagi.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: pengingat masih aktif atau tidak ditemukan.',
            );
    }
    final title = step.parameters['title']?.toString().trim();
    final scheduledAt = _dateParameter(step.parameters['scheduledAt']);
    return reminder != null &&
            reminder.isActive &&
            title != null &&
            reminder.title == title &&
            scheduledAt != null &&
            reminder.scheduledAt == scheduledAt
        ? FfmAssistantCapabilityExecutionResult.success(
            'verified: pengingat “${reminder.title}” sudah dibaca kembali sesuai draft tanpa mengubah pola, suara, atau identitas notifikasi.',
          )
        : const FfmAssistantCapabilityExecutionResult.failure(
            'Verifikasi gagal: perubahan pengingat belum sesuai draft.',
          );
  }

  Future<FfmAssistantCapabilityExecutionResult> _prepareBudgetMutation(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final operation = step.parameters['operation']?.toString();
    if (targetId == null || (operation != 'update' && operation != 'archive')) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload perubahan Anggaran tidak lengkap.',
      );
    }
    final repository = BudgetRepository(
      _database,
      AuditLogger(_database),
      clock: _clock,
    );
    final eligibility = await repository.mutationEligibilityReason(
      householdId: _householdId,
      id: targetId,
    );
    if (eligibility != null) {
      return FfmAssistantCapabilityExecutionResult.failure(eligibility);
    }
    final snapshot = await repository.snapshot(
      householdId: _householdId,
      id: targetId,
    );
    if (snapshot == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Pos Anggaran tidak ditemukan.',
      );
    }
    if (operation == 'archive') {
      final block = await repository.archiveBlockReason(
        householdId: _householdId,
        id: targetId,
      );
      return block == null
          ? FfmAssistantCapabilityExecutionResult.success(
              'Preview arsip “${snapshot.budget.name}”: belum ada transaksi pemakaian atau transfer alokasi. Tidak ada data yang diubah.',
            )
          : FfmAssistantCapabilityExecutionResult.failure(block);
    }
    final amount = _positiveInt(step.parameters['amount']);
    if (amount == null || amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Batas Anggaran baru belum valid.',
      );
    }
    final remainingAfter = snapshot.remainingFor(amount);
    if (remainingAfter < 0) {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Batas baru membuat sisa Anggaran negatif (${_money(remainingAfter.abs())} di bawah nol). Pengeluaran dan transfer tidak diubah.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview “${snapshot.budget.name}”: batas ${_money(snapshot.budget.allocated)} menjadi ${_money(amount)}; rollover ${_money(snapshot.budget.rollover)}, transfer masuk ${_money(snapshot.transferredIn)}, transfer keluar ${_money(snapshot.transferredOut)}, pengeluaran ${_money(snapshot.spent)}, sisa ${_money(snapshot.remaining)} menjadi ${_money(remainingAfter)}. Tidak ada transaksi atau transfer yang dibuat.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _updateBudget(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final allocated = _positiveInt(step.parameters['amount']);
    if (targetId == null || allocated == null || allocated <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target atau batas Anggaran baru belum valid.',
      );
    }
    final repository = BudgetRepository(
      _database,
      AuditLogger(_database),
      clock: _clock,
    );
    try {
      final updated = await repository.updateAllocated(
        householdId: _householdId,
        id: targetId,
        allocated: allocated,
      );
      if (updated == null) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Pos Anggaran tidak ditemukan atau sudah tidak aktif.',
        );
      }
      return FfmAssistantCapabilityExecutionResult.success(
        'Batas Anggaran “${updated.budget.name}” diperbarui menjadi ${_money(allocated)}. Hasilnya akan dibaca kembali; transaksi dan transfer tidak diubah.',
      );
    } on StateError catch (error) {
      return FfmAssistantCapabilityExecutionResult.failure(error.message);
    }
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveBudget(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Anggaran untuk diarsipkan belum valid.',
      );
    }
    final repository = BudgetRepository(
      _database,
      AuditLogger(_database),
      clock: _clock,
    );
    try {
      final archived = await repository.archive(
        householdId: _householdId,
        id: targetId,
      );
      if (archived == null) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Pos Anggaran tidak ditemukan atau sudah tidak aktif.',
        );
      }
      return FfmAssistantCapabilityExecutionResult.success(
        'Pos Anggaran “${archived.budget.name}” diarsipkan lunak. Tidak ada transaksi atau transfer yang diubah.',
      );
    } on StateError catch (error) {
      return FfmAssistantCapabilityExecutionResult.failure(error.message);
    }
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyBudgetMutation(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final operation = step.parameters['operation']?.toString();
    if (targetId == null || (operation != 'update' && operation != 'archive')) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload verifikasi Anggaran tidak lengkap.',
      );
    }
    final snapshot = await BudgetRepository(
      _database,
      AuditLogger(_database),
      clock: _clock,
    ).snapshot(householdId: _householdId, id: targetId);
    if (snapshot == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Readback gagal: pos Anggaran tidak ditemukan.',
      );
    }
    final budget = snapshot.budget;
    final protected =
        budget.id == step.parameters['protectedId']?.toString() &&
        budget.householdId ==
            step.parameters['protectedHouseholdId']?.toString() &&
        budget.name == step.parameters['protectedName']?.toString() &&
        (budget.categoryId ?? '') ==
            step.parameters['protectedCategoryId']?.toString() &&
        budget.categoryIdsJson ==
            step.parameters['protectedCategoryIdsJson']?.toString() &&
        (budget.month ?? '') == step.parameters['protectedMonth']?.toString() &&
        budget.periodType ==
            step.parameters['protectedPeriodType']?.toString() &&
        budget.startDate.toIso8601String() ==
            step.parameters['protectedStartDate']?.toString() &&
        budget.endDate.toIso8601String() ==
            step.parameters['protectedEndDate']?.toString() &&
        budget.rollover.toString() ==
            step.parameters['protectedRollover']?.toString() &&
        budget.alertPercent.toString() ==
            step.parameters['protectedAlertPercent']?.toString() &&
        budget.createdAt.toIso8601String() ==
            step.parameters['protectedCreatedAt']?.toString();
    if (!protected) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Readback gagal: ada field Anggaran terlindungi yang berubah.',
      );
    }
    if (operation == 'update') {
      final amount = _positiveInt(step.parameters['amount']);
      return amount != null &&
              budget.isActive &&
              budget.allocated == amount &&
              snapshot.remaining >= 0
          ? FfmAssistantCapabilityExecutionResult.success(
              'verified: batas “${budget.name}” terbaca kembali ${_money(amount)} dengan sisa ${_money(snapshot.remaining)}; field terlindungi, transaksi, dan transfer tetap utuh.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: batas atau sisa Anggaran belum sesuai kontrak.',
            );
    }
    return !budget.isActive &&
            step.parameters['protectedIsActive']?.toString() == 'true'
        ? FfmAssistantCapabilityExecutionResult.success(
            'verified: pos “${budget.name}” diarsipkan lunak dan field lain terbaca kembali utuh.',
          )
        : const FfmAssistantCapabilityExecutionResult.failure(
            'Verifikasi gagal: arsip Anggaran belum sesuai kontrak.',
          );
  }

  Future<FfmAssistantCapabilityExecutionResult> _prepareGoalMutation(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final operation = step.parameters['operation']?.toString();
    if (targetId == null || (operation != 'update' && operation != 'archive')) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload perubahan target tidak lengkap.',
      );
    }
    final goal = await GetGoal(_database)(_householdId, targetId);
    if (goal == null || !goal.isActive) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target keuangan tidak ditemukan atau sudah diarsipkan.',
      );
    }
    if (operation == 'update') {
      final amount = _positiveInt(step.parameters['amount']);
      if (amount == null || amount <= 0) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Nominal target baru belum valid.',
        );
      }
      if (amount < goal.currentAmount) {
        return FfmAssistantCapabilityExecutionResult.failure(
          'Nominal target baru tidak boleh lebih kecil dari progres saat ini ${_money(goal.currentAmount)}.',
        );
      }
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview perubahan target “${goal.name}” dari ${_money(goal.targetAmount)} menjadi ${_money(amount)}. Belum ada data yang diubah.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview arsip target “${goal.name}”. Progres ${_money(goal.currentAmount)} tetap tersimpan dalam data lokal, tetapi target tidak lagi aktif. Belum ada data yang diubah.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _updateGoal(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final amount = _positiveInt(step.parameters['amount']);
    if (targetId == null || amount == null || amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target atau nominal perubahan belum valid.',
      );
    }
    final goal = await GetGoal(_database)(_householdId, targetId);
    if (goal == null || !goal.isActive) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target keuangan tidak ditemukan atau sudah diarsipkan.',
      );
    }
    if (amount < goal.currentAmount) {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Nominal target baru tidak boleh lebih kecil dari progres saat ini ${_money(goal.currentAmount)}.',
      );
    }
    if (amount == goal.targetAmount) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'alreadyApplied: nominal target sudah sesuai dengan draft perubahan.',
      );
    }
    await SaveGoal(_database)(
      GoalEntity(
        id: goal.id,
        householdId: goal.householdId,
        name: goal.name,
        targetAmount: amount,
        currentAmount: goal.currentAmount,
        targetDate: goal.targetDate,
        categoryId: goal.categoryId,
        isActive: goal.isActive,
        createdAt: goal.createdAt,
      ),
    );
    return FfmAssistantCapabilityExecutionResult.success(
      'Target “${goal.name}” diperbarui menjadi ${_money(amount)}. Hasilnya akan dibaca kembali untuk verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveGoal(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target keuangan yang akan diarsipkan belum valid.',
      );
    }
    final goal = await GetGoal(_database)(_householdId, targetId);
    if (goal == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target keuangan tidak ditemukan.',
      );
    }
    if (!goal.isActive) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'alreadyApplied: target keuangan sudah diarsipkan.',
      );
    }
    await DeleteGoal(_database)(_householdId, targetId);
    return FfmAssistantCapabilityExecutionResult.success(
      'Target “${goal.name}” diarsipkan. Hasilnya akan dibaca kembali untuk verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyGoalMutation(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final operation = step.parameters['operation']?.toString();
    if (targetId == null || operation == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload verifikasi perubahan target tidak lengkap.',
      );
    }
    final goal = await GetGoal(_database)(_householdId, targetId);
    if (operation == 'update') {
      final amount = _positiveInt(step.parameters['amount']);
      return goal != null &&
              goal.isActive &&
              amount != null &&
              goal.targetAmount == amount
          ? FfmAssistantCapabilityExecutionResult.success(
              'verified: target “${goal.name}” terbaca kembali dengan nominal ${_money(amount)}.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: nominal target belum sesuai dengan draft perubahan.',
            );
    }
    if (operation == 'archive') {
      return goal != null && !goal.isActive
          ? FfmAssistantCapabilityExecutionResult.success(
              'verified: target “${goal.name}” sudah diarsipkan dan tidak tampil pada daftar aktif.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: target masih aktif atau tidak ditemukan setelah arsip.',
            );
    }
    return const FfmAssistantCapabilityExecutionResult.failure(
      'Jenis perubahan target tidak dikenal saat verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyTransactionMutation(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final operation = step.parameters['operation']?.toString();
    if (targetId == null || operation == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload verifikasi perubahan transaksi tidak lengkap.',
      );
    }
    final transaction = await GetTransaction(_database)(_householdId, targetId);
    if (transaction == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Transaksi tidak ditemukan saat verifikasi.',
      );
    }
    if (operation == 'update') {
      final amount = _positiveInt(step.parameters['amount']);
      final expected = transaction.transaction.type == 'income'
          ? amount
          : amount == null
          ? null
          : -amount;
      if (expected == null || transaction.transaction.amount != expected) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Verifikasi gagal: nominal transaksi tidak sesuai dengan draft.',
        );
      }
      return FfmAssistantCapabilityExecutionResult.success(
        'verified: perubahan transaksi ${_money(expected.abs())} sudah terbaca kembali dari database lokal.',
      );
    }
    if (operation == 'archive') {
      return transaction.transaction.isArchived &&
              !transaction.transaction.isDeleted
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: transaksi sudah diarsipkan dan tidak tampil pada daftar aktif.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: transaksi belum berstatus arsip.',
            );
    }
    if (operation == 'delete') {
      return transaction.transaction.isArchived &&
              transaction.transaction.isDeleted
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: transaksi sudah dihapus dari daftar aktif dan jejak audit tetap lokal.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: transaksi belum berstatus dihapus.',
            );
    }
    return const FfmAssistantCapabilityExecutionResult.failure(
      'Jenis perubahan transaksi tidak dikenal saat verifikasi.',
    );
  }

  Future<dynamic> _activeTransactionTarget(FfmAssistantActionStep step) async {
    final targetId = _targetId(step);
    if (targetId == null) return null;
    final target = await GetTransaction(_database)(_householdId, targetId);
    if (target == null ||
        target.transaction.isArchived ||
        target.transaction.isDeleted) {
      return null;
    }
    return target;
  }

  String? _targetId(FfmAssistantActionStep step) {
    final targetId = step.parameters['targetId']?.toString().trim();
    return targetId == null || targetId.isEmpty ? null : targetId;
  }

  Map<String, Object?> _transactionAuditValue(dynamic transaction) => {
    'id': transaction.id,
    'amount': transaction.amount,
    'date': transaction.date.toIso8601String(),
    'type': transaction.type,
    'note': transaction.note,
    'isArchived': transaction.isArchived,
    'isDeleted': transaction.isDeleted,
  };

  Future<FfmAssistantCapabilityExecutionResult> _saveDraft(
    FfmAssistantActionStep step,
  ) async {
    final kind = step.parameters['kind']?.toString();
    final idempotencyKey = step.parameters['_idempotencyKey']?.toString();
    if (kind == null || idempotencyKey == null || idempotencyKey.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload mutation tidak memiliki kind atau idempotency key.',
      );
    }
    if (kind == 'transfer') return _saveTransfer(step, idempotencyKey);
    if (kind == 'profile') return _saveProfile(step, idempotencyKey);
    if (kind == 'activity') return _saveActivity(step, idempotencyKey);
    if (kind == 'dailyNote') return _saveActivity(step, idempotencyKey);
    if (kind == 'task') return _saveActivity(step, idempotencyKey);
    if (kind == 'routine') return _saveActivity(step, idempotencyKey);
    if (kind == 'schedule') return _saveActivity(step, idempotencyKey);
    if (kind == 'reminder') return _saveReminder(step, idempotencyKey);
    if (kind == 'master_data') return _saveMasterData(step, idempotencyKey);
    if (kind == 'goal') return _saveGoal(step, idempotencyKey);
    if (kind == 'asset') return _saveAsset(step, idempotencyKey);
    if (kind == 'liability') return _saveLiability(step, idempotencyKey);
    if (kind == 'receivable') return _saveReceivable(step, idempotencyKey);
    if (kind == 'budget') {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Pembuatan Anggaran oleh Agent tidak diizinkan. Buat pos Anggaran secara manual, atau ubah batas satu pos yang sudah ada melalui draft khusus.',
      );
    }
    if (kind == 'goal_deposit') {
      return _saveGoalTransaction(step, idempotencyKey, isDeposit: true);
    }
    if (kind == 'goal_usage') {
      return _saveGoalTransaction(step, idempotencyKey, isDeposit: false);
    }
    if (kind != 'income' && kind != 'expense') {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Mutation draft $kind belum memiliki adapter aman.',
      );
    }
    final amount = _positiveInt(step.parameters['amount']);
    if (amount == null || amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nominal harus lebih besar dari nol.',
      );
    }
    final accountName =
        (kind == 'income'
                ? step.parameters['toAccount']
                : step.parameters['fromAccount'])
            ?.toString()
            .trim();
    final account = await _findAccount(accountName);
    if (account == null) {
      return FfmAssistantCapabilityExecutionResult.failure(
        accountName == null || accountName.isEmpty
            ? 'Rekening untuk draft belum disebutkan.'
            : 'Rekening "$accountName" tidak ditemukan atau tidak unik.',
      );
    }
    final categoryName = step.parameters['category']?.toString().trim();
    final category = await _findCategory(categoryName, kind);
    if (categoryName != null && categoryName.isNotEmpty && category == null) {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Kategori "$categoryName" tidak ditemukan atau tidak unik.',
      );
    }
    final id = _stableId(idempotencyKey);
    final previous = await GetTransaction(_database)(_householdId, id);
    if (previous != null) {
      final expectedAmount = kind == 'income' ? amount : -amount;
      if (previous.transaction.amount == expectedAmount &&
          previous.transaction.accountId == account.id) {
        return FfmAssistantCapabilityExecutionResult.success(
          'alreadyApplied: transaksi ${kind == 'income' ? 'pemasukan' : 'pengeluaran'} sudah tersimpan.',
        );
      }
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Idempotency key sudah dipakai oleh transaksi dengan isi berbeda.',
      );
    }
    final date = _dateParameter(step.parameters['date']) ?? _clock();
    final note = step.parameters['note']?.toString().trim();
    final party = step.parameters['party']?.toString().trim();
    final linkedActivityId = step.parameters['linkedActivityId']?.toString();
    final entity = TransactionEntity(
      id: id,
      householdId: _householdId,
      date: date,
      amount: kind == 'income' ? amount : -amount,
      owner: 'Keluarga',
      categoryId: category?.id,
      note: note == null || note.isEmpty ? null : note,
      source: 'assistant_orchestrator',
      accountId: account.id,
      partyName: party == null || party.isEmpty ? null : party,
      linkedActivityId: linkedActivityId,
      recordedAt: _clock(),
      updatedAt: _clock(),
    );
    await SaveTransaction(_database)(entity);
    await _recordDraftCorrections(
      parameters: step.parameters,
      finalCategory: categoryName,
      finalAccount: accountName,
      finalAmount: amount,
    );
    return FfmAssistantCapabilityExecutionResult.success(
      'Tersimpan satu kali: ${kind == 'income' ? 'pemasukan' : 'pengeluaran'} ${_money(amount)} pada ${date.toIso8601String().substring(0, 10)}.',
    );
  }

  /// Merekam koreksi user terhadap tebakan awal (SLM/rule) pada draft
  /// transaksi ber-merchant, lalu mengagregasi pola agar lapisan Agent
  /// kategori otomatis semakin akurat. Best-effort: gagal tidak membatalkan
  /// penyimpanan transaksi.
  Future<void> _recordDraftCorrections({
    required Map<String, Object?> parameters,
    required String? finalCategory,
    required String? finalAccount,
    required int finalAmount,
  }) async {
    final personalization = _personalization;
    if (personalization == null) return;
    try {
      final merchant = parameters['assistantMerchantName']?.toString().trim();
      if (merchant == null || merchant.isEmpty) return;
      final guessesRaw = parameters['assistantSlmFieldValues'];
      final guesses = guessesRaw is Map
          ? guessesRaw.map((k, v) => MapEntry('$k', '$v'))
          : const <String, String>{};

      Future<void> record(
        String field,
        String? guess,
        String? corrected,
      ) async {
        final safeGuess = guess?.trim() ?? '';
        final safeCorrected = corrected?.trim() ?? '';
        if (safeGuess.isEmpty || safeCorrected.isEmpty) return;
        if (safeGuess.toLowerCase() == safeCorrected.toLowerCase()) return;
        await personalization.recordCorrection(
          householdId: _householdId,
          merchantName: merchant,
          fieldName: field,
          slmValue: safeGuess,
          correctedValue: safeCorrected,
        );
      }

      await record('category', guesses['category'], finalCategory);
      await record('account', guesses['account'], finalAccount);
      final guessAmount = guesses['amount']?.trim();
      if (guessAmount != null && guessAmount.isNotEmpty && finalAmount > 0) {
        final parsedGuess = int.tryParse(
          guessAmount.replaceAll(RegExp(r'[^0-9]'), ''),
        );
        if (parsedGuess != null && parsedGuess != finalAmount) {
          await record('amount', guessAmount, '$finalAmount');
        }
      }
      await personalization.recalculatePatterns(_householdId);
    } on Object {
      // Pembelajaran tidak boleh menggagalkan penyimpanan.
    }
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveTransfer(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final amount = _positiveInt(step.parameters['amount']);
    final fromName = step.parameters['fromAccount']?.toString().trim();
    final toName = step.parameters['toAccount']?.toString().trim();
    if (amount == null || amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nominal transfer harus lebih besar dari nol.',
      );
    }
    final from = await _findAccount(fromName);
    final to = await _findAccount(toName);
    if (from == null || to == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Rekening asal dan tujuan harus ditemukan secara unik.',
      );
    }
    if (from.id == to.id) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Rekening asal dan tujuan tidak boleh sama.',
      );
    }
    final transferId = _stableId(idempotencyKey);
    final existing =
        await (_database.select(_database.transfers)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.id.equals(transferId),
            ))
            .getSingleOrNull();
    if (existing != null) {
      if (existing.amount == amount &&
          existing.fromAccountId == from.id &&
          existing.toAccountId == to.id) {
        return const FfmAssistantCapabilityExecutionResult.success(
          'alreadyApplied: transfer sudah tersimpan.',
        );
      }
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Idempotency key sudah dipakai oleh transfer dengan isi berbeda.',
      );
    }
    final fee = _positiveInt(step.parameters['adminFee']) ?? 0;
    final now = _clock();
    final feeId = fee > 0 ? '$transferId-fee' : null;
    final feeCategory = fee > 0
        ? await _findCategory('Biaya admin', 'expense')
        : null;
    if (fee > 0 && feeCategory == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Kategori Biaya admin belum tersedia.',
      );
    }
    final transfer = TransferEntity(
      id: transferId,
      householdId: _householdId,
      date: _dateParameter(step.parameters['date']) ?? now,
      recordedAt: now,
      amount: amount,
      adminFee: fee,
      feeTransactionId: feeId,
      fromAccountId: from.id,
      toAccountId: to.id,
      note: step.parameters['note']?.toString().trim(),
      source: 'assistant_orchestrator',
      updatedAt: now,
    );
    final entities = <TransactionEntity>[];
    if (fee > 0) {
      entities.add(
        TransactionEntity(
          id: feeId!,
          householdId: _householdId,
          date: transfer.date,
          amount: -fee,
          owner: 'Keluarga',
          categoryId: feeCategory!.id,
          note: 'Biaya admin transfer ${from.name} ke ${to.name}',
          source: 'transfer_fee',
          accountId: from.id,
          recordedAt: now,
          updatedAt: now,
        ),
      );
    }
    await SaveMixedTransactionBatch(_database)(
      entities,
      itemsByTransactionId: const {},
      transfers: [transfer],
    );
    return FfmAssistantCapabilityExecutionResult.success(
      'Tersimpan satu kali: transfer ${_money(amount)} dari ${from.name} ke ${to.name}.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifySavedDraft(
    FfmAssistantActionStep step,
  ) async {
    final kind = step.parameters['kind']?.toString();
    final key = step.parameters['_idempotencyKey']?.toString();
    if (kind == null || key == null || key.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload verifikasi tidak lengkap.',
      );
    }
    final id = _stableId(key);
    if (kind == 'transfer') {
      final transfer =
          await (_database.select(_database.transfers)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      return transfer == null
          ? const FfmAssistantCapabilityExecutionResult.failure(
              'Transfer belum ditemukan saat verifikasi.',
            )
          : FfmAssistantCapabilityExecutionResult.success(
              'verified: transfer ${transfer.amount} berhasil dibaca kembali dari database lokal.',
            );
    }
    if (kind == 'profile') return _verifyProfileSaved();
    if (kind == 'activity') {
      final activity =
          await (_database.select(_database.activitySessions)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      return activity == null
          ? const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: aktivitas belum ditemukan di data lokal.',
            )
          : FfmAssistantCapabilityExecutionResult.success(
              'verified: aktivitas “${activity.title}” berhasil dibaca kembali dari data lokal.',
            );
    }
    if (kind == 'reminder') {
      final reminder =
          await (_database.select(_database.reminders)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      return reminder == null
          ? const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: pengingat belum ditemukan di data lokal.',
            )
          : FfmAssistantCapabilityExecutionResult.success(
              'verified: pengingat “${reminder.title}” berhasil dibaca kembali dari data lokal.',
            );
    }
    if (kind == 'master_data') {
      return _verifyMasterDataSaved(step, id);
    }
    if (kind == 'goal') {
      final goal =
          await (_database.select(_database.goals)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      return goal == null
          ? const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: target keuangan belum ditemukan di data lokal.',
            )
          : FfmAssistantCapabilityExecutionResult.success(
              'verified: target “${goal.name}” berhasil dibaca kembali dari data lokal.',
            );
    }
    if (kind == 'asset') {
      final asset =
          await (_database.select(_database.assets)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      return asset == null
          ? const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: aset belum ditemukan di data lokal.',
            )
          : FfmAssistantCapabilityExecutionResult.success(
              'verified: aset “${asset.name}” berhasil dibaca kembali dari data lokal.',
            );
    }
    if (kind == 'liability') {
      final liability =
          await (_database.select(_database.liabilities)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      return liability == null
          ? const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: hutang belum ditemukan di data lokal.',
            )
          : FfmAssistantCapabilityExecutionResult.success(
              'verified: hutang “${liability.name}” berhasil dibaca kembali dari data lokal.',
            );
    }
    if (kind == 'receivable') {
      final receivable =
          await (_database.select(_database.receivables)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      return receivable == null
          ? const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: piutang belum ditemukan di data lokal.',
            )
          : FfmAssistantCapabilityExecutionResult.success(
              'verified: piutang “${receivable.name}” berhasil dibaca kembali dari data lokal.',
            );
    }
    if (kind == 'budget') {
      final budget =
          await (_database.select(_database.envelopeBudgets)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      return budget == null
          ? const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: anggaran belum ditemukan di data lokal.',
            )
          : FfmAssistantCapabilityExecutionResult.success(
              'verified: anggaran “${budget.name}” berhasil dibaca kembali dari data lokal.',
            );
    }
    final transaction = await GetTransaction(_database)(_householdId, id);
    return transaction == null
        ? const FfmAssistantCapabilityExecutionResult.failure(
            'Verifikasi gagal: transaksi hasil draft belum ditemukan di data lokal.',
          )
        : FfmAssistantCapabilityExecutionResult.success(
            'verified: transaksi ${transaction.transaction.amount} berhasil dibaca kembali dari database lokal.',
          );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyProfileSaved() async {
    final preferences = await (_database.select(
      _database.userPreferences,
    )..where((row) => row.householdId.equals(_householdId))).get();
    const profileKeys = <String>{
      'profile_name',
      'profile_occupation',
      'profile_routine',
      'profile_goals',
    };
    final exists = preferences.any(
      (item) => profileKeys.contains(item.preferenceKey),
    );
    return exists
        ? const FfmAssistantCapabilityExecutionResult.success(
            'verified: setidaknya satu preferensi profil berhasil dibaca kembali dari data lokal.',
          )
        : const FfmAssistantCapabilityExecutionResult.failure(
            'Verifikasi gagal: preferensi profil belum ditemukan di data lokal.',
          );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyMasterDataSaved(
    FfmAssistantActionStep step,
    String id,
  ) async {
    final category = step.parameters['category']?.toString();
    final operation = step.parameters['operation']?.toString();
    if (category == 'rekening') {
      final account =
          await (_database.select(_database.accounts)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      if (operation == 'delete') {
        return account == null
            ? const FfmAssistantCapabilityExecutionResult.success(
                'verified: rekening sudah tidak ditemukan di database lokal.',
              )
            : const FfmAssistantCapabilityExecutionResult.failure(
                'Verifikasi gagal: rekening masih ditemukan setelah penghapusan.',
              );
      }
      return account == null
          ? const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: rekening belum ditemukan di data lokal.',
            )
          : FfmAssistantCapabilityExecutionResult.success(
              'verified: rekening “${account.name}” berhasil dibaca kembali dari data lokal.',
            );
    }
    if (category == 'toko') {
      final merchant =
          await (_database.select(_database.merchants)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      if (operation == 'delete') {
        return merchant == null
            ? const FfmAssistantCapabilityExecutionResult.success(
                'verified: toko sudah tidak ditemukan di database lokal.',
              )
            : const FfmAssistantCapabilityExecutionResult.failure(
                'Verifikasi gagal: toko masih ditemukan setelah penghapusan.',
              );
      }
      return merchant == null
          ? const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: toko belum ditemukan di data lokal.',
            )
          : FfmAssistantCapabilityExecutionResult.success(
              'verified: toko "${merchant.name}" berhasil dibaca kembali dari data lokal.',
            );
    }
    if (category == 'kategori' || category == 'sumber_pemasukan') {
      final cat =
          await (_database.select(_database.categories)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      if (operation == 'delete') {
        return cat == null
            ? const FfmAssistantCapabilityExecutionResult.success(
                'verified: kategori sudah tidak ditemukan di database lokal.',
              )
            : const FfmAssistantCapabilityExecutionResult.failure(
                'Verifikasi gagal: kategori masih ditemukan setelah penghapusan.',
              );
      }
      return cat == null
          ? const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: kategori belum ditemukan di data lokal.',
            )
          : FfmAssistantCapabilityExecutionResult.success(
              'verified: kategori "${cat.name}" berhasil dibaca kembali dari data lokal.',
            );
    }
    if (category == 'tag') {
      final tag =
          await (_database.select(_database.tags)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      if (operation == 'delete') {
        return tag == null
            ? const FfmAssistantCapabilityExecutionResult.success(
                'verified: tag sudah tidak ditemukan di database lokal.',
              )
            : const FfmAssistantCapabilityExecutionResult.failure(
                'Verifikasi gagal: tag masih ditemukan setelah penghapusan.',
              );
      }
      return tag == null
          ? const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: tag belum ditemukan di data lokal.',
            )
          : FfmAssistantCapabilityExecutionResult.success(
              'verified: tag "${tag.name}" berhasil dibaca kembali dari data lokal.',
            );
    }
    return const FfmAssistantCapabilityExecutionResult.failure(
      'Verifikasi gagal: jenis Data Utama hasil draft tidak dikenali.',
    );
  }

  Future<dynamic> _findAccount(String? name) async {
    if (name == null || name.isEmpty) return null;
    final rows =
        await (_database.select(_database.accounts)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isActive.equals(true) &
                  row.isArchived.equals(false) &
                  row.name.equals(name),
            ))
            .get();
    return rows.length == 1 ? rows.single : null;
  }

  Future<dynamic> _findCategory(String? name, String type) async {
    if (name == null || name.isEmpty) return null;
    final rows =
        await (_database.select(_database.categories)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isActive.equals(true) &
                  row.name.equals(name) &
                  row.type.equals(type),
            ))
            .get();
    return rows.length == 1 ? rows.single : null;
  }

  int? _positiveInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) {
      return int.tryParse(value.replaceAll(RegExp(r'[^0-9-]'), ''));
    }
    return null;
  }

  int? _nonNegativeInt(Object? value) {
    final parsed = _positiveInt(value);
    return parsed == null || parsed < 0 ? null : parsed;
  }

  String _stableId(String key) {
    var hash = 2166136261;
    for (final codeUnit in key.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return 'assistant-${hash.toRadixString(16)}';
  }

  Future<FfmAssistantCapabilityExecutionResult> _readAnalysis(
    FfmAssistantActionStep step,
  ) async {
    final summary = await _readSummary(step);
    return FfmAssistantCapabilityExecutionResult.success(
      'Analisa lokal berdasarkan data yang tersedia. ${summary.message} Gunakan halaman Analisa untuk grafik dan rincian lengkap.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _readActivity(
    FfmAssistantActionStep step,
  ) async {
    final rows =
        await (_database.select(_database.activitySessions)
              ..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.startedAt)]))
            .get();

    if (rows.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada aktivitas, tugas, atau catatan yang tercatat.',
      );
    }

    final active = rows.where((r) => r.status == 'active').toList();
    final recent = rows.where((r) => r.status != 'active').take(5).toList();

    final buffer = StringBuffer();
    if (active.isNotEmpty) {
      buffer.writeln('Aktivitas Aktif (${active.length}):');
      for (final row in active) {
        final parentText = row.parentSessionId != null
            ? ' (di dalam ${row.parentSessionId})'
            : '';
        buffer.writeln(
          '  - ${row.title} [${row.kind}] dimulai ${_dateTime(row.startedAt)}$parentText',
        );
      }
    }

    if (recent.isNotEmpty) {
      buffer.writeln('Riwayat Terbaru:');
      for (final row in recent) {
        final timeText = row.kind == 'task' && row.isCompleted
            ? 'Selesai ${_dateTime(row.endedAt ?? row.startedAt)}'
            : 'Tercatat ${_dateTime(row.startedAt)}';
        buffer.writeln('  - ${row.title} [${row.kind}]: $timeText');
      }
    }

    return FfmAssistantCapabilityExecutionResult.success(
      buffer.toString().trim(),
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _readBudget(
    FfmAssistantActionStep step,
  ) async {
    final rows =
        await (_database.select(_database.envelopeBudgets)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    if (rows.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada anggaran yang dibuat.',
      );
    }
    final lines = rows.take(10).map((row) {
      return '${row.name}: anggaran $_money(row.allocated)';
    });
    return FfmAssistantCapabilityExecutionResult.success(
      'Anggaran (${rows.length}): ${lines.join('; ')}.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _readGoals(
    FfmAssistantActionStep step,
  ) async {
    final rows =
        await (_database.select(_database.goals)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    if (rows.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada target keuangan.',
      );
    }
    final lines = rows.take(10).map((row) {
      final progress = row.targetAmount > 0
          ? '${((row.currentAmount / row.targetAmount) * 100).toStringAsFixed(0)}%'
          : '0%';
      return '${row.name}: ${_money(row.currentAmount)} dari ${_money(row.targetAmount)} ($progress)';
    });
    return FfmAssistantCapabilityExecutionResult.success(
      'Target (${rows.length}): ${lines.join('; ')}.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _readAssets(
    FfmAssistantActionStep step,
  ) async {
    final rows =
        await (_database.select(_database.assets)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isArchived.equals(false),
            ))
            .get();
    if (rows.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada aset yang tercatat.',
      );
    }
    final lines = rows.take(10).map((row) {
      return '${row.name} (${row.assetType}): $_money(row.value)';
    });
    return FfmAssistantCapabilityExecutionResult.success(
      'Aset (${rows.length}): ${lines.join('; ')}.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _readLiabilities(
    FfmAssistantActionStep step,
  ) async {
    final liabilities =
        await (_database.select(_database.liabilities)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final receivables =
        await (_database.select(_database.receivables)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    if (liabilities.isEmpty && receivables.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada hutang atau piutang yang tercatat.',
      );
    }
    final parts = <String>[];
    if (liabilities.isNotEmpty) {
      final lines = liabilities.take(5).map((row) {
        return '${row.name}: sisa ${_money(row.remainingBalance)}';
      });
      parts.add('Hutang (${liabilities.length}): ${lines.join('; ')}');
    }
    if (receivables.isNotEmpty) {
      final lines = receivables.take(5).map((row) {
        return '${row.name}: sisa ${_money(row.remainingBalance)}';
      });
      parts.add('Piutang (${receivables.length}): ${lines.join('; ')}');
    }
    return FfmAssistantCapabilityExecutionResult.success(parts.join('. '));
  }

  Future<FfmAssistantCapabilityExecutionResult> _readReceivable(
    FfmAssistantActionStep step,
  ) async {
    final rows =
        await (_database.select(_database.receivables)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    if (rows.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada piutang yang tercatat.',
      );
    }
    final lines = rows.take(10).map((row) {
      return '${row.name}: sisa ${_money(row.remainingBalance)}';
    });
    return FfmAssistantCapabilityExecutionResult.success(
      'Piutang (${rows.length}): ${lines.join('; ')}.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _readRecurring(
    FfmAssistantActionStep step,
  ) async {
    final rows =
        await (_database.select(_database.recurringTransactions)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    if (rows.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada transaksi berkala.',
      );
    }
    final lines = rows.take(10).map((row) {
      return '${row.name}: ${_money(row.amount)} (${row.periodType})';
    });
    return FfmAssistantCapabilityExecutionResult.success(
      'Transaksi berkala (${rows.length}): ${lines.join('; ')}.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _readReminders(
    FfmAssistantActionStep step,
  ) async {
    final rows =
        await (_database.select(_database.reminders)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    if (rows.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada pengingat aktif.',
      );
    }
    final lines = rows.take(10).map((row) {
      final date = row.scheduledAt.toIso8601String().substring(0, 10);
      return '${row.title} pada $date';
    });
    return FfmAssistantCapabilityExecutionResult.success(
      'Pengingat aktif (${rows.length}): ${lines.join('; ')}.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _readModelStatus(
    FfmAssistantActionStep step,
  ) async {
    return FfmAssistantCapabilityExecutionResult.success(
      'Status Gemini Cloud dikelola dari Dashboard Intelligence. Provider hanya aktif setelah API key dan model diuji berhasil.',
    );
  }

  bool Function(dynamic) _matchesTransaction(Map<String, Object?> parameters) {
    final from = _dateParameter(parameters['dateFrom']);
    final to = _dateParameter(parameters['dateTo']);
    final query = parameters['query']?.toString().trim().toLowerCase();
    return (row) {
      if (from != null && row.date.isBefore(from)) return false;
      if (to != null && !row.date.isBefore(to)) return false;
      if (query == null || query.isEmpty) return true;
      final haystack = '${row.note ?? ''} ${row.partyName ?? ''}'.toLowerCase();
      return haystack.contains(query);
    };
  }

  DateTime? _dateParameter(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  bool? _boolParameter(Object? value) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'true' => true,
      'false' => false,
      _ => null,
    };
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveProfile(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final note = step.parameters['note']?.toString() ?? '';
    final formValues = <String, String>{};
    final parts = note.split('\n');
    for (final part in parts) {
      final colon = part.indexOf(':');
      if (colon > 0) {
        final key = part.substring(0, colon).trim();
        final val = part.substring(colon + 1).trim();
        if (key.isNotEmpty && val.isNotEmpty) {
          formValues[key] = val;
        }
      }
    }

    final name = formValues['Nama'] ?? formValues['Panggilan'];
    final occupation = formValues['Pekerjaan'] ?? formValues['Peran'];
    final routine = formValues['Rutinitas'] ?? formValues['Kegiatan'];
    final goals = formValues['Tujuan'] ?? formValues['Prioritas'];

    if (name == null &&
        occupation == null &&
        routine == null &&
        goals == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Format profil tidak valid atau kosong. Harus berisi key: value seperti "Nama: Rudi".',
      );
    }

    await _database.transaction(() async {
      Future<void> save(String key, String? val) async {
        if (val != null && val.isNotEmpty) {
          await _database
              .into(_database.userPreferences)
              .insertOnConflictUpdate(
                UserPreferencesCompanion.insert(
                  id: 'pref-$key',
                  householdId: _householdId,
                  preferenceKey: key,
                  preferenceValue: val,
                  updatedAt: _clock(),
                ),
              );
        }
      }

      await save('profile_name', name);
      await save('profile_occupation', occupation);
      await save('profile_routine', routine);
      await save('profile_goals', goals);
    });

    return const FfmAssistantCapabilityExecutionResult.success(
      'Profil personalisasi berhasil disimpan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveActivity(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final title = step.parameters['title']?.toString();
    if (title == null || title.trim().isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama aktivitas belum diisi.',
      );
    }

    final kindParam =
        step.parameters['kind']?.toString() ??
        (step.capabilityId.contains('task')
            ? 'task'
            : step.capabilityId.contains('daily_note')
            ? 'note'
            : step.capabilityId.contains('schedule')
            ? 'event'
            : 'timer');
    final activityKind = ActivityKind.fromValue(kindParam);

    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.activitySessions)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();

    if (previous != null) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'alreadyApplied: aktivitas sudah tersimpan sebelumnya.',
      );
    }

    final categoryName =
        step.parameters['category']?.toString().trim() ?? 'Lainnya';
    final category = await _findCategory(categoryName, 'activity');
    if (category == null) {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Kategori aktivitas "$categoryName" tidak ditemukan atau tidak aktif di Data Utama.',
      );
    }
    final parentId = step.parameters['parentSessionId']?.toString();
    final notes =
        step.parameters['note']?.toString() ??
        step.parameters['body']?.toString();
    final dueDate = _dateParameter(
      step.parameters['dueDate'] ?? step.parameters['date'],
    );
    final scheduledAt = _dateParameter(step.parameters['scheduledAt']);
    final isAllDay = _boolParameter(step.parameters['isAllDay']) ?? false;

    await _database
        .into(_database.activitySessions)
        .insert(
          ActivitySessionsCompanion.insert(
            id: id,
            householdId: _householdId,
            title: title.trim(),
            parentSessionId: Value(parentId),
            categoryId: Value(category.id),
            category: Value(category.name),
            kind: Value(activityKind.value),
            startedAt: now,
            dueDate: Value(dueDate),
            scheduledAt: Value(scheduledAt),
            isAllDay: Value(isAllDay),
            status:
                (activityKind == ActivityKind.timer ||
                    activityKind == ActivityKind.task)
                ? const Value('active')
                : const Value('completed'),
            isCompleted: Value(
              activityKind != ActivityKind.timer &&
                  activityKind != ActivityKind.task,
            ),
            notes: Value(notes),
            createdAt: now,
            updatedAt: Value(now),
          ),
        );

    await _observeActivityHabit(title, now);
    return FfmAssistantCapabilityExecutionResult.success(
      'Aktivitas “${title.trim()}” (${activityKind.name}) berhasil disimpan.',
    );
  }

  Future<void> _observeActivityHabit(String title, DateTime occurredAt) async {
    try {
      await _habitLearner?.recordActivityObservation(
        title: title,
        occurredAt: occurredAt,
      );
    } on Object {
      // Observasi kebiasaan bersifat best-effort.
    }
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveReminder(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final title = step.parameters['title']?.toString();
    final dateStr = step.parameters['date']?.toString();
    if (title == null || title.trim().isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Judul pengingat belum diisi.',
      );
    }
    final date = _dateParameter(dateStr);
    if (date == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Waktu pengingat tidak valid.',
      );
    }
    if (!date.isAfter(_clock())) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Waktu pengingat harus masih di masa depan.',
      );
    }
    final reminderMutations = _reminderMutations;
    if (reminderMutations == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Layanan jadwal pengingat belum siap. Pengingat belum disimpan.',
      );
    }
    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.reminders)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      return previous.title == title.trim() && previous.scheduledAt == date
          ? const FfmAssistantCapabilityExecutionResult.success(
              'alreadyApplied: pengingat sudah tersimpan sebelumnya.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Idempotency key sudah dipakai oleh pengingat dengan isi berbeda.',
            );
    }
    try {
      await reminderMutations.save(
        ReminderEntity(
          id: id,
          householdId: _householdId,
          title: title.trim(),
          note: step.parameters['note']?.toString(),
          scheduledAt: date,
          recurrenceType: ReminderRecurrenceType.once,
          weekdays: const [],
          notificationId: id.hashCode.abs(),
          createdAt: now,
        ),
      );
    } on Object {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Pengingat belum disimpan karena izin atau jadwal notifikasi belum siap.',
      );
    }
    return const FfmAssistantCapabilityExecutionResult.success(
      'Pengingat berhasil disimpan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveMasterData(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final title = step.parameters['title']?.toString();
    final category = step.parameters['category']?.toString();
    if (title == null || title.trim().isEmpty || category == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama atau jenis data utama belum diisi.',
      );
    }
    final now = _clock();
    final id = _stableId(idempotencyKey);
    final formValues = step.parameters;

    if (category == 'rekening') {
      final previous =
          await (_database.select(_database.accounts)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      if (previous != null) {
        return previous.name == title.trim()
            ? const FfmAssistantCapabilityExecutionResult.success(
                'alreadyApplied: rekening sudah tersimpan.',
              )
            : const FfmAssistantCapabilityExecutionResult.failure(
                'Idempotency key sudah dipakai oleh rekening dengan isi berbeda.',
              );
      }
      final accountType = formValues['accountType']?.toString() ?? 'cash';
      final type = switch (accountType) {
        'cash' || 'tunai' => 'tunai',
        'bank' => 'bank',
        'ewallet' || 'e-wallet' || 'dompet digital' => 'ewallet',
        _ => 'tunai',
      };
      final openingBalance = int.tryParse(
            formValues['openingBalance']?.toString() ?? '0',
          ) ??
          0;
      await _database
          .into(_database.accounts)
          .insert(
            AccountsCompanion.insert(
              id: id,
              householdId: _householdId,
              name: title.trim(),
              type: type,
              openingBalance: Value(openingBalance),
              createdAt: now,
            ),
          );
    } else if (category == 'toko') {
      final previous =
          await (_database.select(_database.merchants)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      if (previous != null) {
        return previous.name == title.trim()
            ? const FfmAssistantCapabilityExecutionResult.success(
                'alreadyApplied: toko sudah tersimpan.',
              )
            : const FfmAssistantCapabilityExecutionResult.failure(
                'Idempotency key sudah dipakai oleh toko dengan isi berbeda.',
              );
      }
      final details = formValues['details']?.toString();
      await _database
          .into(_database.merchants)
          .insert(
            MerchantsCompanion.insert(
              id: id,
              householdId: _householdId,
              name: title.trim(),
              details: Value(details),
              createdAt: now,
            ),
          );
    } else if (category == 'kategori' || category == 'sumber_pemasukan') {
      final previous =
          await (_database.select(_database.categories)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      if (previous != null) {
        return previous.name == title.trim()
            ? const FfmAssistantCapabilityExecutionResult.success(
                'alreadyApplied: kategori sudah tersimpan.',
              )
            : const FfmAssistantCapabilityExecutionResult.failure(
                'Idempotency key sudah dipakai oleh kategori dengan isi berbeda.',
              );
      }
      final type = category == 'sumber_pemasukan'
          ? 'income'
          : (formValues['type']?.toString() == 'income' ? 'income' : 'expense');
      final period = formValues['defaultBudgetPeriod']?.toString() ?? 'none';
      final budgetPeriod = switch (period) {
        'weekly' || 'mingguan' => 'weekly',
        'monthly' || 'bulanan' => 'monthly',
        _ => 'none',
      };
      await _database
          .into(_database.categories)
          .insert(
            CategoriesCompanion.insert(
              id: id,
              householdId: _householdId,
              name: title.trim(),
              type: type,
              defaultBudgetPeriod: Value(budgetPeriod),
              createdAt: now,
            ),
          );
    } else if (category == 'tag') {
      final previous =
          await (_database.select(_database.tags)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      if (previous != null) {
        return previous.name == title.trim()
            ? const FfmAssistantCapabilityExecutionResult.success(
                'alreadyApplied: tag sudah tersimpan.',
              )
            : const FfmAssistantCapabilityExecutionResult.failure(
                'Idempotency key sudah dipakai oleh tag dengan isi berbeda.',
              );
      }
      await _database
          .into(_database.tags)
          .insert(
            TagsCompanion.insert(
              id: id,
              householdId: _householdId,
              name: title.trim(),
              createdAt: now,
            ),
          );
    } else {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Pembuatan data utama jenis $category belum didukung.',
      );
    }

    return const FfmAssistantCapabilityExecutionResult.success(
      'Data utama berhasil disimpan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveGoal(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final title = step.parameters['title']?.toString();
    final amount = _positiveInt(step.parameters['amount']);
    final dateStr = step.parameters['date']?.toString();
    if (title == null ||
        title.trim().isEmpty ||
        amount == null ||
        amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama atau nominal target belum diisi dengan benar.',
      );
    }
    final date =
        _dateParameter(dateStr) ?? _clock().add(const Duration(days: 30));
    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.goals)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      return previous.name == title.trim() && previous.targetAmount == amount
          ? const FfmAssistantCapabilityExecutionResult.success(
              'alreadyApplied: target sudah tersimpan.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Idempotency key sudah dipakai oleh target dengan isi berbeda.',
            );
    }
    await _database
        .into(_database.goals)
        .insert(
          GoalsCompanion.insert(
            id: id,
            householdId: _householdId,
            name: title.trim(),
            targetAmount: amount,
            targetDate: Value(date),
            createdAt: now,
          ),
        );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Target berhasil disimpan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveAsset(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final title = step.parameters['title']?.toString();
    final amount = _positiveInt(step.parameters['amount']);
    if (title == null ||
        title.trim().isEmpty ||
        amount == null ||
        amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama atau nilai aset belum diisi dengan benar.',
      );
    }
    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.assets)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      return previous.name == title.trim() && previous.value == amount
          ? const FfmAssistantCapabilityExecutionResult.success(
              'alreadyApplied: aset sudah tersimpan.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Idempotency key sudah dipakai oleh aset dengan isi berbeda.',
            );
    }
    await _database
        .into(_database.assets)
        .insert(
          AssetsCompanion.insert(
            id: id,
            householdId: _householdId,
            name: title.trim(),
            assetType: 'Aset Lancar',
            value: Value(amount),
            createdAt: now,
            updatedAt: Value(now),
          ),
        );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Aset berhasil disimpan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveLiability(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final title = step.parameters['title']?.toString() ?? 'Hutang';
    final party = step.parameters['party']?.toString();
    final amount = _positiveInt(step.parameters['amount']);
    if (party == null ||
        party.trim().isEmpty ||
        amount == null ||
        amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama pihak atau nominal hutang belum diisi dengan benar.',
      );
    }
    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.liabilities)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      final expectedName = '${title.trim()} - ${party.trim()}';
      return previous.name == expectedName && previous.originalAmount == amount
          ? const FfmAssistantCapabilityExecutionResult.success(
              'alreadyApplied: hutang sudah tersimpan.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Idempotency key sudah dipakai oleh hutang dengan isi berbeda.',
            );
    }
    await _database
        .into(_database.liabilities)
        .insert(
          LiabilitiesCompanion.insert(
            id: id,
            householdId: _householdId,
            name: '${title.trim()} - ${party.trim()}',
            originalAmount: amount,
            remainingBalance: amount,
            startDate: now,
            createdAt: now,
          ),
        );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Hutang berhasil disimpan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveReceivable(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final title = step.parameters['title']?.toString() ?? 'Piutang';
    final party = step.parameters['party']?.toString();
    final amount = _positiveInt(step.parameters['amount']);
    if (party == null ||
        party.trim().isEmpty ||
        amount == null ||
        amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama pihak atau nominal piutang belum diisi dengan benar.',
      );
    }
    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.receivables)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      final expectedName = '${title.trim()} - ${party.trim()}';
      return previous.name == expectedName && previous.originalAmount == amount
          ? const FfmAssistantCapabilityExecutionResult.success(
              'alreadyApplied: piutang sudah tersimpan.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Idempotency key sudah dipakai oleh piutang dengan isi berbeda.',
            );
    }
    await _database
        .into(_database.receivables)
        .insert(
          ReceivablesCompanion.insert(
            id: id,
            householdId: _householdId,
            name: '${title.trim()} - ${party.trim()}',
            originalAmount: amount,
            remainingBalance: amount,
            startDate: now,
            createdAt: now,
          ),
        );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Piutang berhasil disimpan.',
    );
  }

  // ignore: unused_element
  Future<FfmAssistantCapabilityExecutionResult> _saveBudget(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final amount = _positiveInt(step.parameters['amount']);
    if (amount == null || amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nominal anggaran belum diisi dengan benar.',
      );
    }
    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.envelopeBudgets)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      return previous.allocated == amount
          ? const FfmAssistantCapabilityExecutionResult.success(
              'alreadyApplied: anggaran sudah tersimpan.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Idempotency key sudah dipakai oleh anggaran dengan isi berbeda.',
            );
    }
    await _database
        .into(_database.envelopeBudgets)
        .insert(
          EnvelopeBudgetsCompanion.insert(
            id: id,
            householdId: _householdId,
            name: 'Anggaran Asisten',
            periodType: const Value('monthly'),
            allocated: Value(amount),
            startDate: DateTime(now.year, now.month, 1),
            endDate: DateTime(now.year, now.month + 1, 0),
            createdAt: now,
            updatedAt: Value(now),
          ),
        );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Anggaran berhasil disimpan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveGoalTransaction(
    FfmAssistantActionStep step,
    String idempotencyKey, {
    required bool isDeposit,
  }) async {
    final amount = _positiveInt(step.parameters['amount']);
    final goalName = step.parameters['goal']?.toString();
    if (amount == null || amount <= 0 || goalName == null || goalName.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nominal atau nama target belum diisi.',
      );
    }
    final goal =
        await (_database.select(_database.goals)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.name.equals(goalName),
            ))
            .getSingleOrNull();
    if (goal == null) {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Target keuangan "$goalName" tidak ditemukan.',
      );
    }
    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.transactions)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Transaksi target sudah tersimpan.',
      );
    }

    await _database.transaction(() async {
      await _database
          .into(_database.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: id,
              householdId: _householdId,
              type: isDeposit ? 'expense' : 'income',
              date: now,
              recordedAt: now,
              amount: amount,
              owner: const Value('Keluarga'),
              note: Value(step.parameters['note']?.toString()),
              source: const Value('manual'),
              goalId: Value(goal.id),
              createdAt: now,
              updatedAt: Value(now),
              isDeleted: const Value(false),
            ),
          );

      final newAmount = isDeposit
          ? goal.currentAmount + amount
          : goal.currentAmount - amount;

      await (_database.update(_database.goals)
            ..where((row) => row.id.equals(goal.id)))
          .write(GoalsCompanion(currentAmount: Value(newAmount)));
    });

    return const FfmAssistantCapabilityExecutionResult.success(
      'Transaksi target berhasil disimpan.',
    );
  }

  String _money(int value) {
    final digits = value.toString();
    final buffer = StringBuffer('Rp');
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }

  String _dateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }
}
