import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/audit_logger.dart';
import '../../activity/data/repositories/activity_repository.dart';
import '../../activity/domain/entities/activity_entity.dart';
import '../../daily_notes/data/daily_note_repository.dart';
import '../../tasks/data/task_repository.dart';
import '../../goal/domain/entities/goal_entity.dart';
import '../../goal/domain/usecases/goal_crud_usecases.dart';
import '../../reminder/data/repositories/reminder_repository.dart';
import '../../reminder/domain/entities/reminder_entity.dart';
import '../../transaction/domain/usecases/transaction_crud_usecases.dart';
import '../domain/ffm_assistant_action_plan.dart';
import '../domain/ffm_assistant_capability_executor.dart';
import 'ffm_assistant_reminder_mutation_service.dart';

class FfmAssistantCapabilityAdapterRegistry {
  FfmAssistantCapabilityAdapterRegistry({
    required AppDatabase database,
    required String householdId,
    DateTime Function()? clock,
    FfmAssistantReminderMutationService? reminderMutations,
  }) : _database = database,
       _householdId = householdId,
       _clock = clock ?? DateTime.now,
       _reminderMutations = reminderMutations;

  final AppDatabase _database;
  final String _householdId;
  final DateTime Function() _clock;
  final FfmAssistantReminderMutationService? _reminderMutations;

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
    'draft.daily_note': _prepareDraft,
    'draft.daily_note_archive': _prepareDailyNoteMutation,
    'draft.task': _prepareDraft,
    'draft.task_update': _prepareTaskMutation,
    'draft.task_complete': _prepareTaskMutation,
    'draft.task_reopen': _prepareTaskMutation,
    'draft.task_archive': _prepareTaskMutation,
    'draft.income': _prepareDraft,
    'draft.expense': _prepareDraft,
    'draft.transfer': _prepareDraft,
    'draft.profile': _prepareDraft,
    'draft.activity': _prepareDraft,
    'draft.reminder': _prepareDraft,
    'draft.master_data': _prepareDraft,
    'draft.goal': _prepareDraft,
    'draft.asset': _prepareDraft,
    'draft.liability': _prepareDraft,
    'draft.receivable': _prepareDraft,
    'draft.budget': _prepareDraft,
    'draft.goal_deposit': _prepareDraft,
    'draft.goal_usage': _prepareDraft,
    'draft.goal_update': _prepareGoalMutation,
    'draft.goal_archive': _prepareGoalMutation,
    'draft.reminder_archive': _prepareReminderMutation,
    'mutate.save_draft': _saveDraft,
    'mutate.update': _updateTransaction,
    'mutate.archive': _archiveMutation,
    'sensitive.delete': _deleteMutation,
    'verify.saved_draft': _verifySavedDraft,
    'verify.transaction_mutation': _verifyTransactionMutation,
    'verify.activity_mutation': _verifyActivityMutation,
    'verify.daily_note_mutation': _verifyDailyNoteMutation,
    'verify.task_mutation': _verifyTaskMutation,
    'verify.goal_mutation': _verifyGoalMutation,
    'verify.reminder_mutation': _verifyReminderMutation,
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
    if (step.parameters['entity'] == 'task') return _updateTask(step);
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
    if (step.parameters['entity'] == 'activity_session') {
      return _archiveActivity(step);
    }
    if (step.parameters['entity'] == 'daily_note') {
      return _archiveDailyNote(step);
    }
    if (step.parameters['entity'] == 'task') return _archiveTask(step);
    return _archiveTransaction(step);
  }

  Future<FfmAssistantCapabilityExecutionResult> _deleteMutation(
    FfmAssistantActionStep step,
  ) {
    if (step.parameters['entity'] == 'activity_session') {
      return _deleteActivity(step);
    }
    return _deleteTransaction(step);
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveTransaction(
    FfmAssistantActionStep step,
  ) => _setTransactionVisibility(step, archive: true);

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
    final session = await _mutableActivityTarget(step);
    if (session == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Aktivitas target tidak ditemukan, sudah diarsipkan, atau masih aktif.',
      );
    }
    final checkpoints = await ActivityRepository(
      _database,
      AuditLogger(_database),
    ).getCheckpoints(session.id);
    final operation = step.parameters['operation']?.toString() ?? 'perubahan';
    final impact = operation == 'delete'
        ? ' Penghapusan akan menghapus ${checkpoints.length} checkpoint dan seluruh catatan aktivitas yang terkait.'
        : '';
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview $operation siap untuk aktivitas “${session.title}”.$impact Belum ada data yang diubah.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _prepareDailyNoteMutation(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null || step.parameters['operation'] != 'archive') {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload arsip Catatan Harian tidak lengkap.',
      );
    }
    final note = await DailyNoteRepository(
      _database,
      AuditLogger(_database),
      clock: _clock,
    ).get(_householdId, targetId);
    if (note == null || note.isArchived) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Catatan Harian target tidak ditemukan atau sudah diarsipkan.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview arsip Catatan Harian “${note.title ?? note.noteDate.toIso8601String().substring(0, 10)}”. Catatan tidak akan dihapus permanen. Belum ada data yang diubah.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveDailyNote(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Catatan Harian belum valid.',
      );
    }
    final archived = await DailyNoteRepository(
      _database,
      AuditLogger(_database),
      clock: _clock,
    ).archive(householdId: _householdId, id: targetId);
    if (archived == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Catatan Harian tidak ditemukan atau sudah diarsipkan.',
      );
    }
    return const FfmAssistantCapabilityExecutionResult.success(
      'Catatan Harian diarsipkan. Hasilnya akan dibaca kembali untuk verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveActivity(
    FfmAssistantActionStep step,
  ) async {
    final session = await _mutableActivityTarget(step);
    if (session == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Aktivitas target tidak ditemukan, sudah diarsipkan, atau masih aktif.',
      );
    }
    await ActivityRepository(
      _database,
      AuditLogger(_database),
    ).archiveSession(_householdId, session.id);
    return const FfmAssistantCapabilityExecutionResult.success(
      'Aktivitas diarsipkan. Hasilnya akan dibaca kembali untuk verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _deleteActivity(
    FfmAssistantActionStep step,
  ) async {
    final session = await _mutableActivityTarget(step);
    if (session == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Aktivitas target tidak ditemukan, sudah diarsipkan, atau masih aktif.',
      );
    }
    await ActivityRepository(
      _database,
      AuditLogger(_database),
    ).deleteSessionPermanently(_householdId, session.id);
    return const FfmAssistantCapabilityExecutionResult.success(
      'Aktivitas dan data turunannya dihapus permanen. Hasilnya akan dibaca kembali untuk verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyActivityMutation(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final operation = step.parameters['operation']?.toString();
    if (targetId == null || operation == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload verifikasi perubahan aktivitas tidak lengkap.',
      );
    }
    final repository = ActivityRepository(_database, AuditLogger(_database));
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
    return const FfmAssistantCapabilityExecutionResult.failure(
      'Jenis perubahan aktivitas tidak dikenal saat verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyDailyNoteMutation(
    FfmAssistantActionStep step,
  ) async {
    final kind = step.parameters['kind']?.toString();
    final repository = DailyNoteRepository(
      _database,
      AuditLogger(_database),
      clock: _clock,
    );
    if (kind == 'dailyNote') {
      final key = step.parameters['_idempotencyKey']?.toString();
      if (key == null || key.isEmpty) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Kunci verifikasi Catatan Harian belum ada.',
        );
      }
      final note = await repository.get(_householdId, _stableId(key));
      return note != null && !note.isArchived
          ? FfmAssistantCapabilityExecutionResult.success(
              'verified: Catatan Harian “${note.title ?? note.noteDate.toIso8601String().substring(0, 10)}” berhasil dibaca kembali dari data lokal.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Catatan Harian belum ditemukan setelah simpan.',
            );
    }
    if (kind == 'dailyNoteArchive') {
      final targetId = _targetId(step);
      final note = targetId == null
          ? null
          : await repository.get(_householdId, targetId);
      return note?.isArchived == true
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Catatan Harian sudah diarsipkan dan tidak tampil pada daftar aktif.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Catatan Harian belum berstatus arsip.',
            );
    }
    return const FfmAssistantCapabilityExecutionResult.failure(
      'Jenis mutasi Catatan Harian tidak dikenal saat verifikasi.',
    );
  }

  TaskRepository get _tasks =>
      TaskRepository(_database, AuditLogger(_database), clock: _clock);

  Future<FfmAssistantCapabilityExecutionResult> _prepareTaskMutation(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final operation = step.parameters['operation']?.toString();
    if (targetId == null ||
        !const {
          'update',
          'complete',
          'reopen',
          'archive',
        }.contains(operation)) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload perubahan Tugas tidak lengkap.',
      );
    }
    final task = await _tasks.get(_householdId, targetId);
    if (task == null || task.isArchived) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Tugas target tidak ditemukan atau sudah diarsipkan.',
      );
    }
    final suffix = switch (operation) {
      'complete' => ' akan ditandai selesai',
      'reopen' => ' akan dibuka kembali',
      'archive' => ' akan diarsipkan tanpa dihapus permanen',
      _ => ' akan diperbarui',
    };
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview Tugas “${task.title}”$suffix. Belum ada data yang diubah.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _updateTask(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final operation = step.parameters['operation']?.toString();
    if (targetId == null || operation == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target atau operasi Tugas belum valid.',
      );
    }
    final before = await _tasks.get(_householdId, targetId);
    if (before == null || before.isArchived) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Tugas target tidak ditemukan atau sudah diarsipkan.',
      );
    }
    if (operation == 'complete') {
      final completed = await _tasks.complete(
        householdId: _householdId,
        id: targetId,
      );
      return completed == null
          ? const FfmAssistantCapabilityExecutionResult.failure(
              'Tugas belum dapat ditandai selesai.',
            )
          : FfmAssistantCapabilityExecutionResult.success(
              completed.isCompleted
                  ? 'Tugas “${completed.title}” ditandai selesai. Hasilnya akan dibaca kembali untuk verifikasi.'
                  : 'alreadyApplied: Tugas sudah berstatus terbuka.',
            );
    }
    if (operation == 'reopen') {
      final reopened = await _tasks.reopen(
        householdId: _householdId,
        id: targetId,
      );
      return reopened == null
          ? const FfmAssistantCapabilityExecutionResult.failure(
              'Tugas belum dapat dibuka kembali.',
            )
          : FfmAssistantCapabilityExecutionResult.success(
              !reopened.isCompleted
                  ? 'Tugas “${reopened.title}” dibuka kembali. Hasilnya akan dibaca kembali untuk verifikasi.'
                  : 'alreadyApplied: Tugas sudah selesai.',
            );
    }
    if (operation == 'update') {
      final title = step.parameters['title']?.toString();
      if (title == null || title.trim().isEmpty) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Judul Tugas baru belum ada.',
        );
      }
      final updated = await _tasks.update(
        householdId: _householdId,
        id: targetId,
        title: title,
        note: step.parameters['note']?.toString(),
        dueDate: _dateParameter(step.parameters['date']),
      );
      return updated == null
          ? const FfmAssistantCapabilityExecutionResult.failure(
              'Tugas belum dapat diperbarui.',
            )
          : FfmAssistantCapabilityExecutionResult.success(
              'Tugas “${updated.title}” diperbarui. Hasilnya akan dibaca kembali untuk verifikasi.',
            );
    }
    return const FfmAssistantCapabilityExecutionResult.failure(
      'Operasi Tugas tidak dikenal.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveTask(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Tugas belum valid.',
      );
    }
    final task = await _tasks.archive(householdId: _householdId, id: targetId);
    return task == null
        ? const FfmAssistantCapabilityExecutionResult.failure(
            'Tugas tidak ditemukan atau sudah diarsipkan.',
          )
        : FfmAssistantCapabilityExecutionResult.success(
            'Tugas “${task.title}” diarsipkan tanpa dihapus permanen. Hasilnya akan dibaca kembali untuk verifikasi.',
          );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyTaskMutation(
    FfmAssistantActionStep step,
  ) async {
    final kind = step.parameters['kind']?.toString();
    if (kind == 'task') {
      final key = step.parameters['_idempotencyKey']?.toString();
      if (key == null || key.isEmpty) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Kunci verifikasi Tugas belum ada.',
        );
      }
      final task = await _tasks.get(_householdId, _stableId(key));
      return task != null && !task.isArchived
          ? FfmAssistantCapabilityExecutionResult.success(
              'verified: Tugas “${task.title}” berhasil dibaca kembali dari data lokal.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Tugas belum ditemukan setelah simpan.',
            );
    }
    final targetId = _targetId(step);
    final operation = step.parameters['operation']?.toString();
    final task = targetId == null
        ? null
        : await _tasks.get(_householdId, targetId);
    if (operation == 'archive') {
      return task?.isArchived == true
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Tugas sudah diarsipkan dan tidak tampil pada daftar aktif.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Tugas belum berstatus arsip.',
            );
    }
    if (operation == 'complete') {
      return task?.isCompleted == true
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Tugas sudah berstatus selesai.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Tugas belum berstatus selesai.',
            );
    }
    if (operation == 'reopen') {
      return task != null && !task.isArchived && !task.isCompleted
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Tugas sudah kembali berstatus terbuka.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Tugas belum kembali terbuka.',
            );
    }
    if (operation == 'update') {
      final title = step.parameters['title']?.toString().trim();
      return task != null && !task.isArchived && task.title == title
          ? FfmAssistantCapabilityExecutionResult.success(
              'verified: Tugas “${task.title}” sudah terbaca kembali dengan judul yang diperbarui.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: perubahan Tugas belum sesuai draft.',
            );
    }
    return const FfmAssistantCapabilityExecutionResult.failure(
      'Jenis mutasi Tugas tidak dikenal saat verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _prepareReminderMutation(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null || step.parameters['operation'] != 'archive') {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload arsip pengingat tidak lengkap.',
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
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview arsip pengingat “${reminder.title}”. Alarm berikutnya akan dibatalkan dan riwayat tetap disimpan. Belum ada data yang diubah.',
    );
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
    if (targetId == null || step.parameters['operation'] != 'archive') {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload verifikasi arsip pengingat tidak lengkap.',
      );
    }
    final reminder = await ReminderRepository(_database)
        .getReminder(_householdId, targetId);
    return reminder != null && !reminder.isActive
        ? FfmAssistantCapabilityExecutionResult.success(
            'verified: pengingat “${reminder.title}” sudah nonaktif dan tidak akan dijadwalkan lagi.',
          )
        : const FfmAssistantCapabilityExecutionResult.failure(
            'Verifikasi gagal: pengingat masih aktif atau tidak ditemukan.',
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

  Future<ActivitySessionEntity?> _mutableActivityTarget(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null) return null;
    final session = await ActivityRepository(
      _database,
      AuditLogger(_database),
    ).getSession(_householdId, targetId);
    if (session == null ||
        session.isArchived ||
        session.status == ActivitySessionStatus.active) {
      return null;
    }
    return session;
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
    if (kind == 'dailyNote') return _saveDailyNote(step, idempotencyKey);
    if (kind == 'task') return _saveTask(step, idempotencyKey);
    if (kind == 'reminder') return _saveReminder(step, idempotencyKey);
    if (kind == 'master_data') return _saveMasterData(step, idempotencyKey);
    if (kind == 'goal') return _saveGoal(step, idempotencyKey);
    if (kind == 'asset') return _saveAsset(step, idempotencyKey);
    if (kind == 'liability') return _saveLiability(step, idempotencyKey);
    if (kind == 'receivable') return _saveReceivable(step, idempotencyKey);
    if (kind == 'budget') return _saveBudget(step, idempotencyKey);
    if (kind == 'goal_deposit')
      return _saveGoalTransaction(step, idempotencyKey, isDeposit: true);
    if (kind == 'goal_usage')
      return _saveGoalTransaction(step, idempotencyKey, isDeposit: false);
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
      recordedAt: _clock(),
      updatedAt: _clock(),
    );
    await SaveTransaction(_database)(entity);
    return FfmAssistantCapabilityExecutionResult.success(
      'Tersimpan satu kali: ${kind == 'income' ? 'pemasukan' : 'pengeluaran'} ${_money(amount)} pada ${date.toIso8601String().substring(0, 10)}.',
    );
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
    if (category == 'rekening') {
      final account =
          await (_database.select(_database.accounts)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
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
      return merchant == null
          ? const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: toko belum ditemukan di data lokal.',
            )
          : FfmAssistantCapabilityExecutionResult.success(
              'verified: toko “${merchant.name}” berhasil dibaca kembali dari data lokal.',
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
        await (_database.select(_database.activitySessions)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isArchived.equals(false),
            ))
            .get();
    if (rows.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada aktivitas yang tercatat.',
      );
    }
    final lines = rows.take(10).map((row) {
      final status = row.status == 'active' ? 'sedang jalan' : 'selesai';
      return '${row.title} (${row.category}) — $status';
    });
    return FfmAssistantCapabilityExecutionResult.success(
      'Aktivitas (${rows.length}): ${lines.join('; ')}.',
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
      'Model lokal Qwen2-VL 2B. Instal via menu Lainnya → Model Asisten Lokal. Fitur ini berjalan 100% offline di perangkat.',
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
    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.activitySessions)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      return previous.title == title.trim()
          ? const FfmAssistantCapabilityExecutionResult.success(
              'alreadyApplied: aktivitas sudah tersimpan sebelumnya.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Idempotency key sudah dipakai oleh aktivitas dengan isi berbeda.',
            );
    }
    await _database
        .into(_database.activitySessions)
        .insert(
          ActivitySessionsCompanion.insert(
            id: id,
            householdId: _householdId,
            title: title.trim(),
            status: const Value('active'),
            startedAt: now,
            createdAt: now,
            updatedAt: Value(now),
          ),
        );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Aktivitas berhasil dimulai.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveDailyNote(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final body =
        step.parameters['body']?.toString() ??
        step.parameters['note']?.toString();
    if (body == null || body.trim().isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Isi Catatan Harian belum diisi.',
      );
    }
    final date = _dateParameter(step.parameters['date']) ?? _clock();
    final note =
        await DailyNoteRepository(
          _database,
          AuditLogger(_database),
          clock: _clock,
        ).create(
          id: _stableId(idempotencyKey),
          householdId: _householdId,
          noteDate: date,
          title: step.parameters['title']?.toString(),
          body: body,
        );
    return FfmAssistantCapabilityExecutionResult.success(
      'Catatan Harian “${note.title ?? note.noteDate.toIso8601String().substring(0, 10)}” disimpan. Hasilnya akan dibaca kembali untuk verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveTask(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final title = step.parameters['title']?.toString();
    if (title == null || title.trim().isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Judul Tugas belum diisi.',
      );
    }
    final task = await _tasks.create(
      id: _stableId(idempotencyKey),
      householdId: _householdId,
      title: title,
      note: step.parameters['note']?.toString(),
      dueDate: _dateParameter(step.parameters['date']),
    );
    return FfmAssistantCapabilityExecutionResult.success(
      'Tugas “${task.title}” disimpan. Hasilnya akan dibaca kembali untuk verifikasi.',
    );
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
      await _database
          .into(_database.accounts)
          .insert(
            AccountsCompanion.insert(
              id: id,
              householdId: _householdId,
              name: title.trim(),
              type: 'tunai',
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
      await _database
          .into(_database.merchants)
          .insert(
            MerchantsCompanion.insert(
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
}
