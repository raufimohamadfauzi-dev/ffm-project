import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:drift/drift.dart';

// ... (imports remain)

import '../../../core/database/app_database.dart';
import '../../../core/database/audit_logger.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/app_theme_controller.dart';
import '../../hijri/domain/hijri_calendar_service.dart';
import '../../advisor/data/cash_flow_profile_repository.dart';
import '../../advisor/domain/entities/cash_flow_profile_models.dart';
import '../../budget/data/budget_repository.dart';
import '../../activity/data/repositories/activity_repository.dart';
import '../../activity/domain/entities/activity_entity.dart';
import '../../audit/data/repositories/audit_log_repository.dart';
import '../../asset/domain/entities/asset_entity.dart';
import '../../asset/domain/usecases/asset_crud_usecases.dart';
import '../../asset/data/repositories/market_news_cache_repository.dart';
import '../../asset/data/services/market_news_radar_service.dart';
import '../../settings/data/category_repository.dart';
import '../../settings/data/account_repository.dart';
import '../../settings/data/income_source_repository.dart';
import '../../settings/data/merchant_repository.dart';
import '../../settings/data/tag_repository.dart';
import '../../settings/data/utility_meter_repository.dart';
import '../../settings/data/vehicle_repository.dart';
import '../../settings/domain/entities/vehicle_models.dart';
// ...
import '../../goal/domain/entities/goal_entity.dart';
import '../../goal/domain/usecases/goal_crud_usecases.dart';
import '../../liability/domain/entities/liability_entity.dart';
import '../../liability/domain/usecases/liability_crud_usecases.dart';
import '../../liability/domain/usecases/process_debt_payment.dart';
import '../../receivable/domain/entities/receivable_entity.dart';
import '../../receivable/domain/usecases/receivable_crud_usecases.dart';
import '../../recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';
import '../../reminder/data/repositories/reminder_repository.dart';
import '../../reminder/domain/entities/reminder_entity.dart';
import '../../transaction/domain/usecases/transaction_crud_usecases.dart';
import '../domain/ffm_assistant_reference_resolver.dart';
import 'ffm_assistant_database_reference_resolver.dart';
import 'telegram_delivery_repository.dart';
import 'telegram_config_repository.dart';
import 'ffm_assistant_autonomy_trigger_service.dart';
import '../domain/ffm_assistant_action_plan.dart';
import '../domain/ffm_assistant_capability_executor.dart';
import '../domain/entities/autonomous_activity_models.dart';
import 'ffm_assistant_reminder_mutation_service.dart';
import 'ffm_activity_habit_learner.dart';
import 'ffm_assistant_personalization_repository.dart';
import 'autonomous_activity_repository.dart';
import 'ffm_assistant_financial_snapshot_service.dart';
import 'ffm_assistant_autonomy_repository.dart';
import 'ffm_assistant_monitoring_job_service.dart';
import 'ffm_assistant_goal_evidence_evaluator.dart';
import 'ffm_assistant_chat_history_repository.dart';
import '../domain/ffm_assistant_monitoring_job.dart';

class FfmAssistantCapabilityAdapterRegistry {
  FfmAssistantCapabilityAdapterRegistry({
    required AppDatabase database,
    required String householdId,
    DateTime Function()? clock,
    FfmAssistantReminderMutationService? reminderMutations,
    FfmActivityHabitLearner? habitLearner,
    FfmAssistantPersonalizationRepository? personalization,
    AppThemeController? themeController,
    SaveTransaction? saveTransaction,
    SaveMixedTransactionBatch? saveMixedTransactionBatch,
  }) : _database = database, // ignore: prefer_initializing_formals
       _householdId = householdId, // ignore: prefer_initializing_formals
       _clock = clock ?? DateTime.now,
       // ignore: prefer_initializing_formals
       _reminderMutations = reminderMutations,
       // ignore: prefer_initializing_formals
       _habitLearner = habitLearner,
       // ignore: prefer_initializing_formals
       _personalization = personalization,
       // ignore: prefer_initializing_formals
       _themeController = themeController,
       _saveTransaction =
           saveTransaction ??
           (getIt.isRegistered<SaveTransaction>()
               ? getIt<SaveTransaction>()
               // Fallback: konstruksi manual dengan Telegram deps dari getIt jika tersedia,
               // sehingga kebijakan notifikasi Telegram tetap berlaku di semua jalur.
               : SaveTransaction(
                   database,
                   telegramDeliveryRepository:
                       getIt.isRegistered<TelegramDeliveryRepository>()
                       ? getIt<TelegramDeliveryRepository>()
                       : null,
                   telegramConfigRepository:
                       getIt.isRegistered<TelegramConfigRepository>()
                       ? getIt<TelegramConfigRepository>()
                       : null,
                   autonomyTrigger:
                       getIt.isRegistered<FfmAssistantAutonomyTriggerService>()
                       ? getIt<FfmAssistantAutonomyTriggerService>()
                       : null,
                 )),
       _saveMixedTransactionBatch =
           saveMixedTransactionBatch ??
           (getIt.isRegistered<SaveMixedTransactionBatch>()
               ? getIt<SaveMixedTransactionBatch>()
               : SaveMixedTransactionBatch(
                   database,
                   telegramDeliveryRepository:
                       getIt.isRegistered<TelegramDeliveryRepository>()
                       ? getIt<TelegramDeliveryRepository>()
                       : null,
                   telegramConfigRepository:
                       getIt.isRegistered<TelegramConfigRepository>()
                       ? getIt<TelegramConfigRepository>()
                       : null,
                   autonomyTrigger:
                       getIt.isRegistered<FfmAssistantAutonomyTriggerService>()
                       ? getIt<FfmAssistantAutonomyTriggerService>()
                       : null,
                 ));

  final AppDatabase _database;
  final String _householdId;
  final DateTime Function() _clock;
  final FfmAssistantReminderMutationService? _reminderMutations;
  final FfmActivityHabitLearner? _habitLearner;
  final FfmAssistantPersonalizationRepository? _personalization;
  final AppThemeController? _themeController;
  final SaveTransaction _saveTransaction;
  final SaveMixedTransactionBatch _saveMixedTransactionBatch;

  FfmAssistantDatabaseReferenceResolver get _references =>
      FfmAssistantDatabaseReferenceResolver(
        database: _database,
        householdId: _householdId,
      );

  Map<String, FfmAssistantCapabilityHandler> get handlers => {
    'read.summary': _readSummary,
    'read.transactions': _readTransactions,
    'read.accounts': _readAccounts,
    'read.categories': _readCategories,
    'read.analysis': _readAnalysis,
    'read.activity': _readActivity,
    'read.dailyNotes': _readDailyNotes,
    'read.activityLog': _readActivityLog,
    'read.audit': _readActivityLog,
    'read.electricity': _readElectricity,
    'read.budget': _readBudget,
    'read.goals': _readGoals,
    'read.assets': _readAssets,
    'read.liabilities': _readLiabilities,
    'read.receivable': _readReceivable,
    'read.recurring': _readRecurring,
    'read.reminders': _readReminders,
    'read.model_status': _readModelStatus,
    'read.schema': _readSchema,
    'read.tables': _readSchema,
    'system.set_theme': _setTheme,
    'system.set_hijri_adjustment': _setHijriAdjustment,
    'market.refresh': _refreshMarket,
    'draft.transaction_update': _prepareTransactionMutation,
    'draft.transaction_archive': _prepareTransactionMutation,
    'draft.transaction_delete': _prepareTransactionMutation,
    'draft.activity_archive': _prepareActivityMutation,
    'draft.activity_delete': _prepareActivityMutation,
    'draft.activity_finish': _prepareActivityMutation,
    'draft.activity_update': _prepareActivityMutation,
    'draft.activity_edit': _prepareActivityMutation,
    'draft.daily_note_archive': _prepareDailyNoteMutation,
    'draft.daily_note_update': _prepareDailyNoteMutation,
    'draft.daily_note_restore': _prepareDailyNoteMutation,
    'draft.daily_note_delete': _prepareDailyNoteMutation,
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
    'draft.meter_reading': _prepareDraft,
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
    'draft.liability_payment': _prepareDebtPayment,
    'draft.liability_update': _prepareLiabilityMutation,
    'draft.liability_archive': _prepareLiabilityMutation,
    'draft.receivable': _prepareDraft,
    'draft.receivable_payment': _prepareDebtPayment,
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
    'draft.reminder_complete': _prepareReminderMutation,
    'mutate.save_draft': _saveDraft,
    'mutate.debt_payment': _processDebtPaymentMutation,
    'mutate.update': _updateTransaction,
    'mutate.archive': _archiveMutation,
    'mutate.complete': _completeMutation,
    'sensitive.delete': _deleteMutation,
    'verify.saved_draft': _verifySavedDraft,
    'verify.debt_payment': _verifyDebtPayment,
    'verify.transaction_mutation': _verifyTransactionMutation,
    'verify.activity_mutation': _verifyActivityMutation,
    'verify.daily_note_mutation': _verifyDailyNoteMutation,
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
    'read.monitoring_jobs': _readMonitoringJobs,
    'read.monitoring_evaluation': _evaluateMonitoring,
    'read.goal_evidence_evaluation': _evaluateGoalEvidence,
    'read.history_search': _searchChatHistory,
    'mutate.monitoring_job_save': _saveMonitoringJob,
    'mutate.monitoring_job_pause': _pauseMonitoringJob,
    'mutate.monitoring_job_resume': _resumeMonitoringJob,
    'mutate.monitoring_job_cancel': _cancelMonitoringJob,
    'verify.monitoring_job': _verifyMonitoringJob,
  };

  FfmAssistantMonitoringJobService get _monitoringService =>
      FfmAssistantMonitoringJobService(
        database: _database,
        autonomyRepository: FfmAssistantAutonomyRepository(_database),
        clock: _clock,
      );

  Future<FfmAssistantCapabilityExecutionResult> _readMonitoringJobs(
    FfmAssistantActionStep step,
  ) async {
    final jobs = await _monitoringService.listJobs(_householdId);
    if (jobs.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada jadwal pemantauan otonom yang dibuat.',
      );
    }
    final buffer = StringBuffer()
      ..writeln('Daftar Jadwal Pemantauan Aktif (${jobs.length}):');
    for (final job in jobs) {
      final nextRunStr = job.nextRunAt != null
          ? '${job.nextRunAt!.day}/${job.nextRunAt!.month}/${job.nextRunAt!.year} jam ${job.targetTimeMinutes ~/ 60}:${(job.targetTimeMinutes % 60).toString().padLeft(2, '0')}'
          : 'Belum dijadwalkan';
      buffer.writeln(
        '• [${job.status.label}] ${job.title} (${job.cadence.label}) - Next run: $nextRunStr',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      buffer.toString().trim(),
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _evaluateMonitoring(
    FfmAssistantActionStep step,
  ) async {
    final jobId = step.parameters['jobId']?.toString();
    if (jobId != null && jobId.isNotEmpty) {
      final report = await _monitoringService.runJobNow(jobId);
      return FfmAssistantCapabilityExecutionResult.success(report.content);
    }
    final dummyJob = FfmAssistantMonitoringJob.create(
      householdId: _householdId,
      preset: FfmAssistantMonitoringPreset.weeklyEvaluation,
      now: _clock(),
    );
    final report = await _monitoringService.executeEvaluation(
      dummyJob,
      now: _clock(),
    );
    return FfmAssistantCapabilityExecutionResult.success(report.content);
  }

  Future<FfmAssistantCapabilityExecutionResult> _evaluateGoalEvidence(
    FfmAssistantActionStep step,
  ) async {
    final evaluator = FfmAssistantGoalEvidenceEvaluator(
      database: _database,
      clock: _clock,
    );
    final goalId = step.parameters['goalId']?.toString();
    if (goalId != null && goalId.isNotEmpty) {
      final report = await evaluator.evaluateGoal(goalId, now: _clock());
      if (report == null) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Target keuangan tidak ditemukan.',
        );
      }
      return FfmAssistantCapabilityExecutionResult.success(
        report.toSummaryText(),
      );
    }

    final reports = await evaluator.evaluateAllGoals(
      _householdId,
      now: _clock(),
    );
    if (reports.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Tidak ada target keuangan aktif yang dapat dievaluasi.',
      );
    }
    final buffer = StringBuffer()
      ..writeln(
        'Evaluasi Progres Target Keuangan Berdasarkan Arus Kas Riil:\n',
      );
    for (final r in reports) {
      buffer.writeln(r.toSummaryText());
      buffer.writeln('---');
    }
    return FfmAssistantCapabilityExecutionResult.success(
      buffer.toString().trim(),
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _searchChatHistory(
    FfmAssistantActionStep step,
  ) async {
    final query = step.parameters['query']?.toString() ?? '';
    if (query.trim().isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Kata kunci pencarian riwayat obrolan tidak boleh kosong.',
      );
    }
    final historyRepo = FfmAssistantChatHistoryRepository();
    final matches = await historyRepo.search(query: query);

    if (matches.isEmpty) {
      return FfmAssistantCapabilityExecutionResult.success(
        'Tidak ditemukan riwayat obrolan yang menyebut "$query".',
      );
    }

    final buffer = StringBuffer()
      ..writeln('Riwayat Percakapan Terdahulu Terkait "$query":');
    for (final m in matches.take(5)) {
      final role = m.isUser ? 'User' : 'Asisten';
      final snippet = m.text.length > 120
          ? '${m.text.substring(0, 120)}...'
          : m.text;
      buffer.writeln('• [$role - ${m.conversationTitle}]: $snippet');
    }
    return FfmAssistantCapabilityExecutionResult.success(
      buffer.toString().trim(),
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveMonitoringJob(
    FfmAssistantActionStep step,
  ) async {
    final presetName =
        step.parameters['preset']?.toString() ?? 'weeklyEvaluation';
    final cadenceName = step.parameters['cadence']?.toString() ?? 'weekly';
    final targetTimeMinutes =
        int.tryParse(step.parameters['targetTimeMinutes']?.toString() ?? '') ??
        540;
    final targetDay = int.tryParse(
      step.parameters['targetDay']?.toString() ?? '',
    );
    final categoryFilter = step.parameters['categoryFilter']?.toString();
    final title = step.parameters['title']?.toString();

    final preset = FfmAssistantMonitoringPreset.values.firstWhere(
      (p) => p.name == presetName,
      orElse: () => FfmAssistantMonitoringPreset.weeklyEvaluation,
    );
    final cadence = FfmAssistantJobCadence.values.firstWhere(
      (c) => c.name == cadenceName,
      orElse: () => FfmAssistantJobCadence.weekly,
    );

    final job = FfmAssistantMonitoringJob.create(
      householdId: _householdId,
      preset: preset,
      title: title,
      cadence: cadence,
      targetTimeMinutes: targetTimeMinutes,
      targetDay: targetDay,
      categoryFilter: categoryFilter,
      now: _clock(),
    );

    final saved = await _monitoringService.createJob(job);
    if (saved == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Gagal menyimpan jadwal pemantauan.',
      );
    }

    return FfmAssistantCapabilityExecutionResult.success(
      'Jadwal pemantauan "${saved.title}" berhasil disimpan dan aktif.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _pauseMonitoringJob(
    FfmAssistantActionStep step,
  ) async {
    final jobId = step.parameters['jobId']?.toString();
    if (jobId == null || jobId.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Job ID monitoring diperlukan untuk menjeda.',
      );
    }
    final ok = await _monitoringService.pauseJob(jobId);
    return ok
        ? const FfmAssistantCapabilityExecutionResult.success(
            'Jadwal pemantauan berhasil dijeda.',
          )
        : const FfmAssistantCapabilityExecutionResult.failure(
            'Gagal menjeda jadwal pemantauan.',
          );
  }

  Future<FfmAssistantCapabilityExecutionResult> _resumeMonitoringJob(
    FfmAssistantActionStep step,
  ) async {
    final jobId = step.parameters['jobId']?.toString();
    if (jobId == null || jobId.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Job ID monitoring diperlukan untuk melanjutkan.',
      );
    }
    final ok = await _monitoringService.resumeJob(jobId);
    return ok
        ? const FfmAssistantCapabilityExecutionResult.success(
            'Jadwal pemantauan berhasil diaktifkan kembali.',
          )
        : const FfmAssistantCapabilityExecutionResult.failure(
            'Gagal mengaktifkan jadwal pemantauan.',
          );
  }

  Future<FfmAssistantCapabilityExecutionResult> _cancelMonitoringJob(
    FfmAssistantActionStep step,
  ) async {
    final jobId = step.parameters['jobId']?.toString();
    if (jobId == null || jobId.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Job ID monitoring diperlukan untuk membatalkan.',
      );
    }
    final ok = await _monitoringService.cancelJob(jobId);
    return ok
        ? const FfmAssistantCapabilityExecutionResult.success(
            'Jadwal pemantauan berhasil dibatalkan.',
          )
        : const FfmAssistantCapabilityExecutionResult.failure(
            'Gagal membatalkan jadwal pemantauan.',
          );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyMonitoringJob(
    FfmAssistantActionStep step,
  ) async {
    final jobId = step.parameters['jobId']?.toString();
    if (jobId == null || jobId.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Job ID diperlukan untuk verifikasi.',
      );
    }
    final job = await _monitoringService.jobById(jobId);
    if (job == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Jadwal pemantauan tidak ditemukan.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Status jadwal pemantauan "${job.title}": ${job.status.label}.',
    );
  }

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

  Future<FfmAssistantCapabilityExecutionResult> _readSchema(
    FfmAssistantActionStep step,
  ) async {
    final snapshotService = FfmAssistantFinancialSnapshotService(_database);
    final schema = await snapshotService.buildSchemaContext(
      householdId: _householdId,
    );
    return FfmAssistantCapabilityExecutionResult.success(schema);
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
      'master_data' ||
      'masterData' => false,
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
    if (step.parameters['entity'] == 'daily_note') {
      return _updateDailyNote(step);
    }
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
    await _saveTransaction(
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
    if (step.parameters['entity'] == 'daily_note') {
      return _archiveDailyNote(step);
    }
    if (step.parameters['entity'] == 'activity_session' ||
        step.parameters['entity'] == 'task' ||
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

  Future<FfmAssistantCapabilityExecutionResult> _completeMutation(
    FfmAssistantActionStep step,
  ) {
    if (step.parameters['entity'] == 'reminder') {
      return _completeReminder(step);
    }
    if (step.parameters['entity'] == 'task' ||
        step.parameters['entity'] == 'activity_session' ||
        step.parameters['entity'] == 'daily_routine') {
      return _updateActivity(step);
    }
    return _updateTransaction(step);
  }

  Future<FfmAssistantCapabilityExecutionResult> _deleteMutation(
    FfmAssistantActionStep step,
  ) {
    if (step.parameters['entity'] == 'daily_note') {
      return _deleteDailyNote(step);
    }
    if (step.parameters['entity'] == 'activity_session' ||
        step.parameters['entity'] == 'task' ||
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

  Future<FfmAssistantCapabilityExecutionResult> _updateDailyNote(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final operation = step.parameters['operation']?.toString();
    if (targetId == null || operation == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target atau operasi Catatan Harian belum valid.',
      );
    }
    final repository = ActivityRepository(_database, AuditLogger(_database));
    final note = await (_database.select(_database.dailyNotes)..where(
          (row) => row.householdId.equals(_householdId) & row.id.equals(targetId),
        ))
        .getSingleOrNull();
    if (note == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Catatan Harian tidak ditemukan.',
      );
    }
    if (operation == 'restore') {
      if (!note.isArchived) {
        return const FfmAssistantCapabilityExecutionResult.success(
          'alreadyApplied: Catatan Harian sudah aktif.',
        );
      }
      await repository.restoreDailyNote(_householdId, targetId);
      return const FfmAssistantCapabilityExecutionResult.success(
        'Catatan Harian dipulihkan. Hasilnya akan dibaca kembali untuk verifikasi.',
      );
    }
    if (operation == 'priority') {
      final priority = int.tryParse(step.parameters['priority']?.toString() ?? '0') ?? 0;
      await (_database.update(_database.dailyNotes)..where(
            (row) => row.householdId.equals(_householdId) & row.id.equals(targetId),
          ))
          .write(
            DailyNotesCompanion(
              priority: Value(priority.clamp(0, 1)),
              updatedAt: Value(_clock()),
            ),
          );
      return const FfmAssistantCapabilityExecutionResult.success(
        'Prioritas Catatan Harian diperbarui. Hasilnya akan dibaca kembali untuk verifikasi.',
      );
    }
    if (operation != 'edit') {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Operasi Catatan Harian tidak dikenal.',
      );
    }
    final tags = await (_database.select(_database.dailyNoteTags)..where(
          (row) => row.dailyNoteId.equals(targetId),
        ))
        .get();
    await repository.saveDailyNote(
      id: targetId,
      householdId: _householdId,
      noteDate: _dateParameter(step.parameters['date']) ?? note.noteDate,
      title: step.parameters['title']?.toString() ?? note.title,
      body: step.parameters['body']?.toString() ?? note.body,
      treatmentType: step.parameters['treatmentType']?.toString() ?? note.treatmentType,
      priority: note.priority,
      tagIds: tags.map((item) => item.tagId).toList(growable: false),
      createdAt: note.createdAt,
      updatedAt: _clock(),
    );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Catatan Harian diperbarui. Hasilnya akan dibaca kembali untuk verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _archiveTransaction(
    FfmAssistantActionStep step,
  ) => _setTransactionVisibility(step, archive: true);

  Future<FfmAssistantCapabilityExecutionResult> _prepareDebtPayment(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final entity = step.parameters['entity']?.toString();
    final amount = _positiveInt(step.parameters['amount']);
    if (entity == 'liability') {
      final target = await _liabilityById(targetId);
      if (target == null) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Hutang target tidak ditemukan atau sudah diarsipkan.',
        );
      }
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview pembayaran Hutang “${target.name}” sebesar ${_money(amount ?? target.remainingBalance)}. Setelah disetujui, saldo Hutang akan berkurang dan transaksi kas akan dicatat bila rekening tersedia.',
      );
    }
    if (entity == 'receivable') {
      final target = await _receivableById(targetId);
      if (target == null) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Piutang target tidak ditemukan atau sudah diarsipkan.',
        );
      }
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview penerimaan Piutang “${target.name}” sebesar ${_money(amount ?? target.remainingBalance)}. Setelah disetujui, saldo Piutang akan berkurang dan transaksi kas akan dicatat bila rekening tersedia.',
      );
    }
    return const FfmAssistantCapabilityExecutionResult.failure(
      'Jenis target pembayaran hutang/piutang belum valid.',
    );
  }

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

  Future<FfmAssistantCapabilityExecutionResult> _processDebtPaymentMutation(
    FfmAssistantActionStep step,
  ) async {
    final entity = step.parameters['entity']?.toString();
    final targetId = _targetId(step);
    final amount = _positiveInt(step.parameters['amount']);
    if (entity == null || targetId == null || amount == null || amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload pembayaran hutang/piutang tidak lengkap atau nominalnya tidak valid.',
      );
    }
    final accountId = step.parameters['accountId']?.toString().trim();
    final date = _dateParameter(step.parameters['date']) ?? _clock();
    final note = step.parameters['note']?.toString().trim();
    final isLiability = entity == 'liability';
    final String targetIdVal;
    final String targetNameVal;
    if (isLiability) {
      final item = await _liabilityById(targetId);
      if (item == null) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Target hutang tidak ditemukan atau sudah tidak aktif.',
        );
      }
      targetIdVal = item.id;
      targetNameVal = item.name;
    } else {
      final item = await _receivableById(targetId);
      if (item == null) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Target piutang tidak ditemukan atau sudah tidak aktif.',
        );
      }
      targetIdVal = item.id;
      targetNameVal = item.name;
    }
    final normalizedAccountId = accountId == null || accountId.isEmpty
        ? null
        : accountId;
    final idempotencyKey = step.parameters['_idempotencyKey']?.toString();
    late final int result;
    try {
      result = await ProcessDebtPayment(_database).call(
        householdId: _householdId,
        targetId: targetIdVal,
        targetName: targetNameVal,
        isLiability: isLiability,
        amount: amount,
        date: date,
        accountId: normalizedAccountId,
        note: note,
        recordCashTransaction: normalizedAccountId != null,
        idempotencyKey: idempotencyKey == null || idempotencyKey.isEmpty
            ? null
            : _stableId(idempotencyKey),
      );
    } on Object catch (error) {
      return FfmAssistantCapabilityExecutionResult.failure(error.toString());
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Tersimpan satu kali: ${isLiability ? 'pembayaran hutang' : 'penerimaan piutang'} ${_money(amount)} untuk $targetNameVal. Saldo baru: ${_money(result)}.',
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

  Future<FfmAssistantCapabilityExecutionResult> _verifyDebtPayment(
    FfmAssistantActionStep step,
  ) async {
    final entity = step.parameters['entity']?.toString();
    final targetId = _targetId(step);
    if (entity == null || targetId == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target pembayaran hutang/piutang belum valid untuk verifikasi.',
      );
    }
    final source = entity == 'liability'
        ? 'liability_payment'
        : 'receivable_payment';
    final expectedAmount = _positiveInt(step.parameters['amount']);
    final expectedDate = _dateParameter(step.parameters['date']);
    final expectedAccount = step.parameters['accountId']?.toString().trim();
    final tx =
        await (_database.select(_database.transactions)
              ..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.source.equals(source) &
                    row.sourceId.equals(targetId),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.recordedAt)]))
            .getSingleOrNull();
    if (tx == null) {
      final row = entity == 'liability'
          ? await (_database.select(_database.liabilities)..where(
                  (r) =>
                      r.householdId.equals(_householdId) &
                      r.id.equals(targetId),
                ))
                .getSingleOrNull()
          : await (_database.select(_database.receivables)..where(
                  (r) =>
                      r.householdId.equals(_householdId) &
                      r.id.equals(targetId),
                ))
                .getSingleOrNull();
      return row != null && row is Liability || row is Receivable
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: target hutang/piutang masih ada dan siap untuk ditinjau ulang.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: pembayaran tidak terlihat di transaksi atau target tidak valid.',
            );
    }
    final payloadMatches =
        (expectedAmount == null || tx.amount.abs() == expectedAmount) &&
        (expectedDate == null || tx.date == expectedDate) &&
        (expectedAccount == null ||
            expectedAccount.isEmpty ||
            tx.accountId == expectedAccount) &&
        tx.sourceId == targetId;
    return payloadMatches
        ? FfmAssistantCapabilityExecutionResult.success(
            'verified: ${entity == 'liability' ? 'pembayaran hutang' : 'penerimaan piutang'} sudah dibaca kembali dari transaksi lokal.',
          )
        : const FfmAssistantCapabilityExecutionResult.failure(
            'Verifikasi gagal: nominal transaksi pembayaran tidak sesuai draft.',
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
    final operation = step.parameters['operation']?.toString() ?? 'perubahan';
    if (session == null || (session.isArchived && operation != 'reopen')) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Aktivitas target tidak ditemukan atau sudah diarsipkan.',
      );
    }

    final suffix = switch (operation) {
      'complete' || 'finish' => ' akan ditandai selesai',
      'reopen' => ' akan dibuka kembali',
      'archive' => ' akan diarsipkan tanpa dihapus permanen',
      'delete' => ' akan dihapus permanen beserta data turunannya',
      'update' || 'checkpoint' => ' akan ditambahkan checkpoint/catatan',
      'checkpoint_edit' => ' akan mengubah checkpoint',
      'checkpoint_delete' => ' akan menghapus checkpoint',
      'edit' => ' akan diedit judul/kategorinya',
      _ => ' akan diperbarui',
    };

    return FfmAssistantCapabilityExecutionResult.success(
      'Preview ${session.kind.name} “${session.title}”$suffix. Belum ada data yang diubah.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _prepareDailyNoteMutation(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Catatan Harian belum valid.',
      );
    }
    final note = await (_database.select(_database.dailyNotes)..where(
          (row) => row.householdId.equals(_householdId) & row.id.equals(targetId),
        ))
        .getSingleOrNull();
    if (note == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Catatan Harian target tidak ditemukan.',
      );
    }
    final operation = step.parameters['operation']?.toString() ?? 'archive';
    if (operation == 'archive' && note.isArchived) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Catatan Harian sudah diarsipkan.',
      );
    }
    final action = switch (operation) {
      'restore' => 'dipulihkan',
      'edit' => 'diedit',
      'delete' => 'dihapus permanen',
      _ => 'diarsipkan',
    };
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview Catatan Harian "${note.title ?? note.body}" akan $action. Belum ada data yang diubah.',
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
    if (current == null || (current.isArchived && operation != 'reopen')) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Aktivitas tidak ditemukan atau sudah diarsipkan.',
      );
    }

    if (operation == 'reopen' && current.status != ActivitySessionStatus.completed) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Hanya aktivitas selesai yang dapat dibuka kembali.',
      );
    }

    if (operation == 'reopen' && current.isArchived) {
      await repository.restoreSession(_householdId, targetId);
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
          isArchived: false,
          updatedAt: now,
        ),
      );
      return FfmAssistantCapabilityExecutionResult.success(
        'Aktivitas "${current.title}" dibuka kembali.',
      );
    }

    if (operation == 'priority') {
      final priority = int.tryParse(step.parameters['priority']?.toString() ?? '0') ?? 0;
      await repository.saveSession(
        current.copyWith(priority: priority.clamp(0, 1), updatedAt: now),
      );
      return FfmAssistantCapabilityExecutionResult.success(
        priority == 1
            ? 'Aktivitas "${current.title}" ditandai prioritas.'
            : 'Prioritas aktivitas "${current.title}" dihapus.',
      );
    }

    if (operation == 'update' || operation == 'checkpoint') {
      final label = step.parameters['label']?.toString();
      if (label != null && label.isNotEmpty) {
        final place = step.parameters['place']?.toString();
        final note = step.parameters['note']?.toString();
        final checkpoint = ActivityCheckpointEntity(
          id: 'checkpoint-${now.microsecondsSinceEpoch}-${const Uuid().v4().substring(0, 8)}',
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

    if (operation == 'checkpoint_edit' || operation == 'checkpoint_delete') {
      final checkpointId = step.parameters['checkpointId']?.toString();
      if (checkpointId == null || checkpointId.isEmpty) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Checkpoint target belum valid.',
        );
      }
      final checkpoints = await repository.getCheckpoints(targetId);
      final checkpoint = checkpoints.where((item) => item.id == checkpointId).firstOrNull;
      if (checkpoint == null) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Checkpoint target tidak ditemukan pada aktivitas tersebut.',
        );
      }
      if (operation == 'checkpoint_delete') {
        await repository.deleteCheckpoint(checkpointId);
        return const FfmAssistantCapabilityExecutionResult.success(
          'Checkpoint dihapus. Hasilnya akan dibaca kembali untuk verifikasi.',
        );
      }
      final label = step.parameters['label']?.toString().trim();
      if (label == null || label.isEmpty) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Label checkpoint baru belum valid.',
        );
      }
      await repository.saveCheckpoint(checkpoint.copyWith(label: label));
      return FfmAssistantCapabilityExecutionResult.success(
        'Checkpoint diubah menjadi "$label". Hasilnya akan dibaca kembali untuk verifikasi.',
      );
    }

    if (operation == 'edit') {
      final title = step.parameters['title']?.toString() ?? current.title;
      final notes = step.parameters['note']?.toString() ?? current.notes;
      final requestedCategory = step.parameters['category']?.toString().trim();
      var category = current.category;
      var categoryId = current.categoryId;
      if (requestedCategory != null &&
          requestedCategory.isNotEmpty &&
          requestedCategory != current.category) {
        final matches = await _database
            .customSelect(
              'SELECT id, name FROM categories '
              'WHERE household_id = ? AND type = ? AND is_active = 1 '
              'AND lower(name) = ?',
              variables: [
                Variable.withString(_householdId),
                Variable.withString('activity'),
                Variable.withString(requestedCategory.toLowerCase()),
              ],
            )
            .get();
        if (matches.length != 1) {
          return FfmAssistantCapabilityExecutionResult.failure(
            'Kategori aktivitas "$requestedCategory" tidak ditemukan secara unik di Data Utama.',
          );
        }
        category = matches.single.read<String>('name');
        categoryId = matches.single.read<String>('id');
      }
      final dueDate = _dateParameter(
        step.parameters['dueDate'] ?? step.parameters['date'],
      );
      final scheduledAt = _dateParameter(step.parameters['scheduledAt']);

      await repository.saveSession(
        current.copyWith(
          title: title,
          notes: notes,
          category: category,
          categoryId: categoryId,
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

  Future<FfmAssistantCapabilityExecutionResult> _archiveDailyNote(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Catatan Harian belum valid.',
      );
    }
    final repository = ActivityRepository(_database, AuditLogger(_database));
    final note = await (_database.select(_database.dailyNotes)..where(
          (row) => row.householdId.equals(_householdId) & row.id.equals(targetId),
        ))
        .getSingleOrNull();
    if (note == null || note.isArchived) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Catatan Harian tidak ditemukan atau sudah diarsipkan.',
      );
    }
    await repository.archiveDailyNote(_householdId, targetId);
    return const FfmAssistantCapabilityExecutionResult.success(
      'Catatan Harian diarsipkan. Hasilnya akan dibaca kembali untuk verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _deleteDailyNote(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    if (targetId == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target Catatan Harian belum valid.',
      );
    }
    final note = await (_database.select(_database.dailyNotes)..where(
          (row) => row.householdId.equals(_householdId) & row.id.equals(targetId),
        ))
        .getSingleOrNull();
    if (note == null || note.isArchived) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Catatan Harian tidak ditemukan atau sudah diarsipkan.',
      );
    }
    await ActivityRepository(_database, AuditLogger(_database))
        .deleteDailyNotePermanently(_householdId, targetId);
    return const FfmAssistantCapabilityExecutionResult.success(
      'Catatan Harian dihapus permanen. Hasilnya akan dibaca kembali untuk verifikasi.',
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
    final account = await (_database.select(
      _database.accounts,
    )..where((r) => r.id.equals(targetId))).getSingleOrNull();
    if (account == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Rekening tidak ditemukan.',
      );
    }
    await (_database.delete(
      _database.accounts,
    )..where((r) => r.id.equals(targetId))).go();
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
    final category = await (_database.select(
      _database.categories,
    )..where((r) => r.id.equals(targetId))).getSingleOrNull();
    if (category == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Kategori tidak ditemukan.',
      );
    }
    await (_database.delete(
      _database.categories,
    )..where((r) => r.id.equals(targetId))).go();
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
    final tag = await (_database.select(
      _database.tags,
    )..where((r) => r.id.equals(targetId))).getSingleOrNull();
    if (tag == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Tag tidak ditemukan.',
      );
    }
    await (_database.delete(
      _database.tags,
    )..where((r) => r.id.equals(targetId))).go();
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
    final merchant = await (_database.select(
      _database.merchants,
    )..where((r) => r.id.equals(targetId))).getSingleOrNull();
    if (merchant == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Toko/Tempat tidak ditemukan.',
      );
    }
    await (_database.delete(
      _database.merchants,
    )..where((r) => r.id.equals(targetId))).go();
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
    final source = await (_database.select(
      _database.transactionParties,
    )..where((r) => r.id.equals(targetId))).getSingleOrNull();
    if (source == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Sumber Pemasukan tidak ditemukan.',
      );
    }
    await (_database.delete(
      _database.transactionParties,
    )..where((r) => r.id.equals(targetId))).go();
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
    if (operation == 'complete' || operation == 'finish') {
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
        if (operation == 'priority') {
          final priority = int.tryParse(step.parameters['priority']?.toString() ?? '0') ?? 0;
          return session != null && session.priority == priority
              ? const FfmAssistantCapabilityExecutionResult.success(
                  'verified: prioritas aktivitas sudah diperbarui.',
                )
              : const FfmAssistantCapabilityExecutionResult.failure(
                  'Verifikasi gagal: prioritas aktivitas belum sesuai.',
                );
        }
    if (operation == 'update' || operation == 'checkpoint') {
      final label = step.parameters['label']?.toString().trim();
      if (session == null ||
          session.isArchived ||
          label == null ||
          label.isEmpty) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Verifikasi gagal: checkpoint aktivitas belum valid.',
        );
      }
      final checkpoints = await repository.getCheckpoints(targetId);
      return checkpoints.any((checkpoint) => checkpoint.label == label)
          ? FfmAssistantCapabilityExecutionResult.success(
              'verified: checkpoint "$label" sudah terbaca kembali pada aktivitas “${session.title}”.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: checkpoint aktivitas belum tersimpan.',
            );
    }
    if (operation == 'checkpoint_delete' || operation == 'checkpoint_edit') {
      final checkpointId = step.parameters['checkpointId']?.toString();
      final checkpoints = checkpointId == null
          ? const <ActivityCheckpointEntity>[]
          : await repository.getCheckpoints(targetId);
      final exists = checkpoints.any((item) => item.id == checkpointId);
      if (operation == 'checkpoint_delete') {
        return !exists
            ? const FfmAssistantCapabilityExecutionResult.success(
                'verified: checkpoint sudah tidak ditemukan pada aktivitas.',
              )
            : const FfmAssistantCapabilityExecutionResult.failure(
                'Verifikasi gagal: checkpoint masih ditemukan.',
              );
      }
      final label = step.parameters['label']?.toString().trim();
      return exists &&
              label != null &&
              checkpoints.any((item) => item.id == checkpointId && item.label == label)
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: checkpoint sudah diperbarui.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: perubahan checkpoint belum terbaca.',
            );
    }
    if (operation == 'edit') {
      final title = step.parameters['title']?.toString().trim();
      final category = step.parameters['category']?.toString().trim();
      final note = step.parameters['note']?.toString();
      final isVerified =
          session != null &&
          !session.isArchived &&
          (title == null || title.isEmpty || session.title == title) &&
          (category == null ||
              category.isEmpty ||
              session.category.toLowerCase() == category.toLowerCase()) &&
          (note == null || session.notes == note);
      return isVerified
          ? FfmAssistantCapabilityExecutionResult.success(
              'verified: aktivitas “${session.title}” sudah terbaca kembali dengan perubahan draft.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: perubahan aktivitas belum sesuai draft.',
            );
    }

    return const FfmAssistantCapabilityExecutionResult.failure(
      'Jenis perubahan aktivitas tidak dikenal saat verifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyDailyNoteMutation(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final operation = step.parameters['operation']?.toString();
    if (targetId != null &&
      (operation == 'restore' ||
        operation == 'edit' ||
        operation == 'delete' ||
        operation == 'priority')) {
      final note = await (_database.select(_database.dailyNotes)..where(
            (row) => row.householdId.equals(_householdId) & row.id.equals(targetId),
          ))
          .getSingleOrNull();
      if (operation == 'delete') {
        return note == null
            ? const FfmAssistantCapabilityExecutionResult.success(
                'verified: Catatan Harian sudah tidak ditemukan setelah penghapusan.',
              )
            : const FfmAssistantCapabilityExecutionResult.failure(
                'Verifikasi gagal: Catatan Harian masih ditemukan.',
              );
      }
      if (operation == 'restore') {
        return note?.isArchived == false
            ? const FfmAssistantCapabilityExecutionResult.success(
                'verified: Catatan Harian sudah dipulihkan.',
              )
            : const FfmAssistantCapabilityExecutionResult.failure(
                'Verifikasi gagal: Catatan Harian belum dipulihkan.',
              );
      }
      if (operation == 'priority') {
        final priority = int.tryParse(step.parameters['priority']?.toString() ?? '0') ?? 0;
        return note != null && note.priority == priority
            ? const FfmAssistantCapabilityExecutionResult.success(
                'verified: prioritas Catatan Harian sudah diperbarui.',
              )
            : const FfmAssistantCapabilityExecutionResult.failure(
                'Verifikasi gagal: prioritas Catatan Harian belum sesuai.',
              );
      }
      final body = step.parameters['body']?.toString();
      final title = step.parameters['title']?.toString();
      return note != null &&
              !note.isArchived &&
              (body == null || note.body == body) &&
              (title == null || note.title == title)
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Catatan Harian sudah diperbarui.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: perubahan Catatan Harian belum terbaca.',
            );
    }
    if (targetId != null && operation == 'archive') {
      final note = await (_database.select(_database.dailyNotes)..where(
            (row) => row.householdId.equals(_householdId) & row.id.equals(targetId),
          ))
          .getSingleOrNull();
      return note?.isArchived == true
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Catatan Harian sudah diarsipkan.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Catatan Harian belum berstatus arsip.',
            );
    }
    final key = step.parameters['_idempotencyKey']?.toString();
    if (key == null || key.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Kunci verifikasi Catatan Harian belum ada.',
      );
    }
    final note =
        await (_database.select(_database.dailyNotes)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.id.equals(_stableId(key)) &
                  row.isArchived.equals(false),
            ))
            .getSingleOrNull();
    return note == null
        ? const FfmAssistantCapabilityExecutionResult.failure(
            'Verifikasi gagal: Catatan Harian belum ditemukan setelah simpan.',
          )
        : FfmAssistantCapabilityExecutionResult.success(
            'verified: Catatan Harian berhasil dibaca kembali dari data lokal.',
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
    if (targetId == null ||
        !const {'update', 'archive', 'complete'}.contains(operation)) {
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
    if (operation == 'complete') {
      final isRecurring = reminder.recurrenceType != ReminderRecurrenceType.once;
      final extra = isRecurring
          ? 'Occurrence periode ini akan ditandai selesai dan jadwal berikutnya tetap aktif.'
          : 'Pengingat akan ditandai selesai.';
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview penyelesaian pengingat “${reminder.title}”. $extra Belum ada data yang diubah.',
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
      final modeRaw = step.parameters['mode']?.toString();
      final mode = modeRaw == null ? null : ReminderModeX.fromStorage(modeRaw);
      final soundUri = step.parameters['soundUri']?.toString();
      final soundName = step.parameters['soundName']?.toString();
      final rawRecurrence =
          (step.parameters['recurrence'] ?? step.parameters['recurrenceType'])
              ?.toString()
              .toLowerCase();
      final recurrenceType = switch (rawRecurrence) {
        'daily' || 'harian' => ReminderRecurrenceType.daily,
        'weekly' || 'mingguan' => ReminderRecurrenceType.weekly,
        'monthly' || 'bulanan' => ReminderRecurrenceType.monthly,
        'yearly' || 'tahunan' => ReminderRecurrenceType.yearly,
        'once' || 'sekali' => ReminderRecurrenceType.once,
        'hijri_monthly' ||
        'hijriah' ||
        'bulanan hijriah' => ReminderRecurrenceType.hijriMonthly,
        _ => null,
      };

      final updated = await reminderMutations.updateTitleAndScheduledAt(
        previous: previous,
        title: title,
        note: step.parameters['note']?.toString(),
        scheduledAt: scheduledAt,
        mode: mode,
        soundUri: soundUri,
        soundName: soundName,
        recurrenceType: recurrenceType,
      );
      if (updated.title == previous.title &&
          updated.note == previous.note &&
          updated.scheduledAt == previous.scheduledAt &&
          updated.mode == previous.mode &&
          updated.soundUri == previous.soundUri &&
          updated.recurrenceType == previous.recurrenceType) {
        return const FfmAssistantCapabilityExecutionResult.success(
          'alreadyApplied: pengingat sudah sesuai dengan draft perubahan.',
        );
      }
      return FfmAssistantCapabilityExecutionResult.success(
        'Pengingat “${updated.title}” diperbarui dan dijadwalkan ulang. Mode: ${updated.mode.label}. Hasilnya akan dibaca kembali untuk verifikasi.',
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

  Future<FfmAssistantCapabilityExecutionResult> _completeReminder(
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
        'alreadyApplied: pengingat sudah selesai atau nonaktif.',
      );
    }
    try {
      await reminderMutations.complete(reminder);
    } on Object {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Pengingat belum dapat diselesaikan karena status jadwal belum siap.',
      );
    }
    final recurrenceInfo = reminder.recurrenceType != ReminderRecurrenceType.once
        ? ' Jadwal occurrence berikutnya tetap aktif.'
        : '';
    return FfmAssistantCapabilityExecutionResult.success(
      'Pengingat “${reminder.title}” berhasil diselesaikan.$recurrenceInfo Hasilnya akan diverifikasi.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyReminderMutation(
    FfmAssistantActionStep step,
  ) async {
    final targetId = _targetId(step);
    final operation = step.parameters['operation']?.toString();
    if (targetId == null ||
        !const {'update', 'archive', 'complete'}.contains(operation)) {
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
    if (operation == 'complete') {
      if (reminder == null) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Verifikasi gagal: pengingat tidak ditemukan.',
        );
      }
      final isOnce = reminder.recurrenceType == ReminderRecurrenceType.once;
      if (isOnce && reminder.isActive) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Verifikasi gagal: pengingat sekali jalan masih aktif.',
        );
      }
      return FfmAssistantCapabilityExecutionResult.success(
        'verified: pengingat “${reminder.title}” telah berhasil diselesaikan.',
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
    if (operation == null && targetId == null) {
      final key = step.parameters['_idempotencyKey']?.toString();
      if (key == null || key.isEmpty) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Kunci verifikasi pembuatan Anggaran belum ada.',
        );
      }
      final budget =
          await (_database.select(_database.envelopeBudgets)..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.id.equals(_stableId(key)),
              ))
              .getSingleOrNull();
      final amount = _positiveInt(step.parameters['amount']);
      final expectedCategoryIds = _budgetCategoryIds(step.parameters);
      final expectedStart = _dateParameter(
        step.parameters['startDate'] ?? step.parameters['date'],
      );
      final expectedEnd = _dateParameter(step.parameters['endDate']);
      final expectedAlert =
          _nonNegativeInt(step.parameters['alertPercent']) ?? 80;
      final expectedRollover =
          _nonNegativeInt(step.parameters['rollover']) ?? 0;
      final expectedNote = step.parameters['note']?.toString().trim();
      return budget != null &&
              budget.householdId == _householdId &&
              budget.name == step.parameters['title']?.toString().trim() &&
              budget.allocated == amount &&
              budget.periodType ==
                  (step.parameters['periodType']?.toString() ?? 'monthly') &&
              (expectedCategoryIds == null ||
                  budget.categoryIdsJson == jsonEncode(expectedCategoryIds)) &&
              (expectedStart == null || budget.startDate == expectedStart) &&
              (expectedEnd == null || budget.endDate == expectedEnd) &&
              budget.alertPercent == expectedAlert &&
              budget.rollover == expectedRollover &&
              (expectedNote == null ||
                  budget.note == (expectedNote.isEmpty ? null : expectedNote))
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: Anggaran baru berhasil dibaca kembali dari data lokal.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: Anggaran baru belum sesuai draft.',
            );
    }
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

  List<String>? _budgetCategoryIds(Map<String, Object?> parameters) {
    final raw = parameters['categoryIdsJson'];
    if (raw is! String || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    } on FormatException {
      return null;
    }
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
    final operation = step.parameters['operation']?.toString();
    final kind = step.parameters['kind']?.toString();
    final key = step.parameters['_idempotencyKey']?.toString();
    final targetId =
        _targetId(step) ??
        (kind == 'goal' && key != null ? _stableId(key) : null);
    if (kind == 'goal_deposit' || kind == 'goal_usage') {
      final transactionId = _stableId(
        step.parameters['_idempotencyKey']?.toString() ?? '',
      );
      final transaction =
          await (_database.select(_database.transactions)..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.id.equals(transactionId),
              ))
              .getSingleOrNull();
      final goalId = step.parameters['goalId']?.toString();
      final accountId = step.parameters['accountId']?.toString();
      final amount = _positiveInt(step.parameters['amount']);
      final date = _dateParameter(step.parameters['date']);
      final expectedSource = kind == 'goal_deposit'
          ? 'goal_contribution'
          : 'goal_usage';
      final valid =
          transaction != null &&
          amount != null &&
          transaction.amount == -amount &&
          transaction.source == expectedSource &&
          (goalId == null || transaction.goalId == goalId) &&
          (accountId == null || transaction.accountId == accountId) &&
          (date == null || transaction.date == date);
      return valid
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: transaksi target, rekening, tanggal, dan nominal terbaca kembali dari database.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: transaksi target tidak sesuai dengan draft.',
            );
    }
    if (kind == 'goal') {
      final goal = targetId == null
          ? null
          : await GetGoal(_database)(_householdId, targetId);
      final amount = _positiveInt(step.parameters['amount']);
      final date = _dateParameter(step.parameters['date']) ??
          _clock().add(const Duration(days: 30));
      final categoryId = step.parameters['categoryId']?.toString();
      final note = step.parameters['note']?.toString().trim();
      final valid =
          goal != null &&
          goal.name == step.parameters['title']?.toString().trim() &&
          goal.targetAmount == amount &&
          goal.targetDate == date &&
          (categoryId == null || goal.categoryId == categoryId) &&
          (note == null || goal.note == (note.isEmpty ? null : note));
      return valid
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: target, nominal, batas waktu, dan kategori terbaca kembali dari database.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: target baru tidak sesuai dengan draft.',
            );
    }
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
    if (kind == 'dailyNote') return _saveDailyNote(step, idempotencyKey);
    if (kind == 'task') return _saveActivity(step, idempotencyKey);
    if (kind == 'routine') return _saveActivity(step, idempotencyKey);
    if (kind == 'schedule') return _saveActivity(step, idempotencyKey);
    if (kind == 'reminder') return _saveReminder(step, idempotencyKey);
    if (kind == 'master_data' || kind == 'masterData') {
      return _saveMasterData(step, idempotencyKey);
    }
    if (kind == 'goal') return _saveGoal(step, idempotencyKey);
    if (kind == 'asset') return _saveAsset(step, idempotencyKey);
    if (kind == 'liability') return _saveLiability(step, idempotencyKey);
    if (kind == 'receivable') return _saveReceivable(step, idempotencyKey);
    if (kind == 'cash_flow_profile' ||
        kind == 'cycle' ||
        kind == 'cashFlowProfile' ||
        kind == 'agrotrack') {
      return _saveCashFlowProfile(step, idempotencyKey);
    }
    if (kind == 'budget') {
      return _saveBudget(step, idempotencyKey);
    }
    if (kind == 'meterReading') {
      return _saveMeterReading(step, idempotencyKey);
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
    // merchantName = nama merchant untuk lookup dan transaksi. Didukung dari
    // tiga sumber: field eksplisit 'merchant'/'merchantName', atau field
    // metadata learning 'assistantMerchantName' (diisi oleh planner).
    // Jika merchant tidak ditemukan di DB dan 'newMerchant' tidak disebutkan,
    // transaksi disimpan tanpa merchant (assistantMerchantName tetap dipakai
    // untuk merekam koreksi user via _recordDraftCorrections).
    final merchantName =
        step.parameters['merchant']?.toString().trim() ??
        step.parameters['merchantName']?.toString().trim() ??
        step.parameters['assistantMerchantName']?.toString().trim();
    final merchant = await _findMerchant(merchantName);
    final newMerchantName = _singleName(step.parameters['newMerchant']);
    final generatedMerchantId = newMerchantName == null
        ? null
        : _stableId('$idempotencyKey:merchant:$newMerchantName');
    if (merchant != null &&
        newMerchantName != null &&
        merchant.id != generatedMerchantId) {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Toko sudah ada; draft tidak perlu membuat toko baru.',
      );
    }
    if (merchant == null && newMerchantName != null) {
      // newMerchant disebutkan: nama HARUS cocok dengan merchantName
      if (merchantName == null ||
          merchantName.isEmpty ||
          newMerchantName != merchantName) {
        return FfmAssistantCapabilityExecutionResult.failure(
          'Nama toko baru pada draft harus sama persis dengan nama toko transaksi.',
        );
      }
    }
    // assistantMerchantName may be an unresolved learning hint. Only an
    // existing merchant or an explicitly approved newMerchant becomes an FK.
    final tagNames = _csvValues(step.parameters['tags']);
    final existingTags = await _findTags(tagNames);
    final tags = <dynamic>[];
    final missingTagNames = <String>{};
    final newTagNames = _csvValues(step.parameters['newTags']).toSet();
    if (!tagNames.toSet().containsAll(newTagNames)) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Tag baru harus termasuk dalam daftar tag transaksi.',
      );
    }
    for (final tagName in tagNames) {
      final resolution = FfmAssistantReferenceResolver.resolve(
        tagName,
        existingTags,
        (tag) => tag.name as String,
      );
      if (resolution.status == FfmAssistantReferenceStatus.ambiguous) {
        return FfmAssistantCapabilityExecutionResult.failure(
          'Tag "$tagName" ambigu: ditemukan lebih dari satu tag dengan nama yang sama.',
        );
      }
      if (resolution.isResolved) {
        if (newTagNames.contains(tagName) &&
            resolution.value.id != _stableId('$idempotencyKey:tag:$tagName')) {
          return FfmAssistantCapabilityExecutionResult.failure(
            'Tag "$tagName" sudah ada; draft tidak perlu membuat tag baru.',
          );
        }
        tags.add(resolution.value);
      } else {
        if (!newTagNames.contains(tagName)) {
          return FfmAssistantCapabilityExecutionResult.failure(
            'Tag "$tagName" tidak ditemukan. Tandai sebagai tag baru untuk membuatnya.',
          );
        }
        missingTagNames.add(tagName);
      }
    }
    final date = _dateParameter(step.parameters['date']) ?? _clock();
    final note = step.parameters['note']?.toString().trim();
    // Kolom disamakan dengan form transaksi + database: pihak tunggal
    // (party / incomeSource / partyName), lokasi, dan field nota.
    final party = step.parameters['party']?.toString().trim().isNotEmpty == true
        ? step.parameters['party']?.toString().trim()
        : step.parameters['incomeSource']?.toString().trim().isNotEmpty == true
        ? step.parameters['incomeSource']?.toString().trim()
        : step.parameters['partyName']?.toString().trim();
    final location = step.parameters['location']?.toString().trim();
    final receiptNumber = step.parameters['receiptNumber']?.toString().trim();
    final receiptPaidAmount = _positiveInt(
      step.parameters['receiptPaidAmount'],
    );
    final receiptChangeAmount = _positiveInt(
      step.parameters['receiptChangeAmount'],
    );
    final receiptRawText = step.parameters['receiptRawText']?.toString();
    final linkedActivityId = step.parameters['linkedActivityId']?.toString();
    final items = _transactionItemsFromJson(
      step.parameters['itemsJson'],
      idempotencyKey,
    );
    if (items == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Rincian item struk tidak valid. Periksa nama, harga, dan jumlah item.',
      );
    }
    final receiptIssue = _validateReceiptTotals(
      amount: amount,
      items: items,
      tax: _nonNegativeInt(step.parameters['tax']),
      discount: _nonNegativeInt(step.parameters['discount']),
      paidAmount: _nonNegativeInt(step.parameters['receiptPaidAmount']),
      changeAmount: _nonNegativeInt(step.parameters['receiptChangeAmount']),
    );
    if (receiptIssue != null) {
      return FfmAssistantCapabilityExecutionResult.failure(receiptIssue);
    }
    final attachmentPaths = _attachmentPaths(
      step.parameters['attachmentPathsJson'],
    );
    if (attachmentPaths == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Daftar attachment tidak valid. Semua path harus berupa teks non-kosong.',
      );
    }
    String? merchantId = merchant?.id ?? generatedMerchantId;
    final tagIds = <String>{for (final tag in tags) tag.id};
    tagIds.addAll(
      missingTagNames.map((name) => _stableId('$idempotencyKey:tag:$name')),
    );
    final previous = await GetTransaction(_database)(_householdId, id);
    if (previous != null) {
      final matches = await _transactionMatchesDraft(
        step: step,
        kind: kind,
        transaction: previous,
        accountId: account.id,
        categoryId: category?.id,
        merchantId: merchantId,
        tagIds: tagIds,
        items: items,
        attachmentPaths: attachmentPaths,
      );
      return matches
          ? FfmAssistantCapabilityExecutionResult.success(
              'alreadyApplied: transaksi ${kind == 'income' ? 'pemasukan' : 'pengeluaran'} sudah tersimpan.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Idempotency key sudah dipakai oleh transaksi dengan isi berbeda.',
            );
    }
    try {
      await _database.transaction(() async {
        if (newMerchantName != null) {
          merchantId = generatedMerchantId;
          await _database
              .into(_database.merchants)
              .insert(
                MerchantsCompanion.insert(
                  id: merchantId!,
                  householdId: _householdId,
                  name: newMerchantName,
                  createdAt: _clock(),
                ),
              );
        }
        for (final tagName in missingTagNames) {
          final tagId = _stableId('$idempotencyKey:tag:$tagName');
          await _database
              .into(_database.tags)
              .insert(
                TagsCompanion.insert(
                  id: tagId,
                  householdId: _householdId,
                  name: tagName,
                  createdAt: _clock(),
                ),
              );
          tagIds.add(tagId);
        }
        final entity = TransactionEntity(
          id: id,
          householdId: _householdId,
          date: date,
          amount: kind == 'income' ? amount : -amount,
          owner: 'Keluarga',
          categoryId: category?.id,
          note: note == null || note.isEmpty ? null : note,
          source:
              step.parameters['source']?.toString().trim().isNotEmpty == true
              ? step.parameters['source']!.toString().trim()
              : 'assistant_orchestrator',
          sourceId: step.parameters['sourceId']?.toString(),
          recurringTransactionId: step.parameters['recurringTransactionId']
              ?.toString(),
          accountId: account.id,
          merchantId: merchantId,
          location: location == null || location.isEmpty ? null : location,
          partyName: party == null || party.isEmpty ? null : party,
          receiptRawText: receiptRawText == null || receiptRawText.isEmpty
              ? null
              : receiptRawText,
          receiptNumber: receiptNumber == null || receiptNumber.isEmpty
              ? null
              : receiptNumber,
          receiptPaidAmount: receiptPaidAmount,
          receiptChangeAmount: receiptChangeAmount,
          tax: _nonNegativeInt(step.parameters['tax']),
          discount: _nonNegativeInt(step.parameters['discount']),
          linkedActivityId: linkedActivityId,
          recordedAt: _clock(),
          updatedAt: _clock(),
        );
        await _saveTransaction(entity, items: items);
        await (_database.delete(
          _database.transactionTags,
        )..where((row) => row.transactionId.equals(id))).go();
        for (final tagId in tagIds) {
          await _database
              .into(_database.transactionTags)
              .insert(
                TransactionTagsCompanion.insert(
                  transactionId: id,
                  tagId: tagId,
                ),
              );
        }
        for (var index = 0; index < attachmentPaths.length; index++) {
          await _database
              .into(_database.attachments)
              .insert(
                AttachmentsCompanion.insert(
                  id: _stableId('$idempotencyKey:attachment:$index'),
                  transactionId: Value(id),
                  path: attachmentPaths[index],
                  createdAt: _clock(),
                ),
              );
        }

        // Eksekusi proposal utility meter (PLN) setelah transaksi berhasil disimpan
        await _executeUtilityProposal(step.parameters, transactionId: id);

        // Eksekusi proposal fuel log (BBM) setelah transaksi berhasil disimpan
        await _executeFuelProposal(step.parameters);
      });
    } on StateError catch (error) {
      return FfmAssistantCapabilityExecutionResult.failure(error.message);
    }
    await _recordDraftCorrections(
      parameters: step.parameters,
      finalCategory: categoryName,
      finalAccount: accountName,
      finalAmount: amount,
    );

    var autoResolveNote = '';
    if (kind == 'expense') {
      final resolved = await _autoResolveMatchingReminders(
        note: note,
        categoryName: categoryName,
        merchantName: merchantName,
        partyName: party,
        amount: amount,
      );
      if (resolved != null) {
        autoResolveNote = resolved;
      }
    }

    final metadata = step.parameters['metadata'];
    final isUtilityPurchase = metadata is Map &&
        metadata['utilityProposal'] is Map;
    final utilityNote = isUtilityPurchase
        ? ' ⚡ Pembelian token listrik berhasil dicatat ke Token Listrik.'
        : '';

    return FfmAssistantCapabilityExecutionResult.success(
      'Tersimpan satu kali: ${kind == 'income' ? 'pemasukan' : 'pengeluaran'} ${_money(amount)} pada ${date.toIso8601String().substring(0, 10)}.$utilityNote$autoResolveNote',
    );
  }

  /// Pilar 4 (Poin 2): Auto-resolve pengingat yang cocok jika transaksi pengeluaran dicatat lebih awal
  Future<String?> _autoResolveMatchingReminders({
    String? note,
    String? categoryName,
    String? merchantName,
    String? partyName,
    int? amount,
  }) async {
    final reminderMutations = _reminderMutations;
    if (reminderMutations == null) return null;

    final keywords = <String>{
      if (note != null) ...note.toLowerCase().split(RegExp(r'\s+')),
      if (categoryName != null) ...categoryName.toLowerCase().split(RegExp(r'\s+')),
      if (merchantName != null) ...merchantName.toLowerCase().split(RegExp(r'\s+')),
      if (partyName != null) ...partyName.toLowerCase().split(RegExp(r'\s+')),
    }.where((k) => k.length >= 3 && !const {'pengeluaran', 'bayar', 'beli', 'transaksi', 'biaya', 'pada', 'untuk'}.contains(k)).toSet();

    if (keywords.isEmpty) return null;

    final now = _clock();
    final lookAheadLimit = now.add(const Duration(days: 14));

    final activeReminders = await (_database.select(_database.reminders)
          ..where((row) =>
              row.householdId.equals(_householdId) &
              row.isActive.equals(true) &
              row.scheduledAt.isBiggerOrEqualValue(now.subtract(const Duration(days: 1))) &
              row.scheduledAt.isSmallerOrEqualValue(lookAheadLimit)))
        .get();

    for (final reminder in activeReminders) {
      final titleLower = reminder.title.toLowerCase();
      final matches = keywords.any((kw) => titleLower.contains(kw));
      if (matches) {
        final reminderEntity = await ReminderRepository(_database)
            .getReminder(_householdId, reminder.id);
        if (reminderEntity != null && reminderEntity.isActive) {
          try {
            await reminderMutations.complete(reminderEntity);
            return ' Pengingat “${reminder.title}” otomatis ditandai selesai.';
          } catch (_) {
            // Non-blocking auto resolve
          }
        }
      }
    }
    return null;
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveMeterReading(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final metadata = step.parameters['metadata'];
    final proposal = metadata is Map ? metadata['meterReadingProposal'] : null;
    final readingKwh = (proposal is Map && proposal['readingKwh'] is num)
        ? (proposal['readingKwh'] as num).toDouble()
        : double.tryParse(step.parameters['readingKwh']?.toString() ?? '');
    final meterId = (proposal is Map ? proposal['meterId']?.toString() : null) ??
        step.parameters['meterId']?.toString();

    if (readingKwh == null || readingKwh < 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Angka pembacaan kWh tidak valid.',
      );
    }
    if (meterId == null || meterId.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Target meteran listrik belum ditentukan.',
      );
    }

    final repo = UtilityMeterRepository(_database);
    final recordedAt = _dateParameter(proposal is Map ? proposal['recordedAt'] : null) ??
        _dateParameter(step.parameters['date']) ??
        _clock();
    final note = (proposal is Map ? proposal['note']?.toString() : null) ??
        step.parameters['note']?.toString();
    final meterName = proposal is Map ? proposal['meterName']?.toString() ?? 'meteran' : 'meteran';

    await repo.recordMeterReading(
      householdId: _householdId,
      meterId: meterId,
      readingKwh: readingKwh,
      recordedAt: recordedAt,
      source: 'assistant_chat',
      note: note,
    );

    return FfmAssistantCapabilityExecutionResult.success(
      'Pembacaan ${readingKwh.toStringAsFixed(2)} kWh untuk $meterName berhasil disimpan.',
    );
  }

  /// Eksekusi proposal utility meter (PLN) setelah transaksi berhasil disimpan
  Future<void> _executeUtilityProposal(
    Map<String, Object?> parameters, {
    String? transactionId,
  }) async {
    final metadataRaw = parameters['metadata'];
    if (metadataRaw is! Map) return;
    final proposal = metadataRaw['utilityProposal'];
    if (proposal is! Map) return;
    if (transactionId == null || transactionId.isEmpty) {
      throw StateError('Transaksi wajib tersedia untuk riwayat token listrik.');
    }
    if (!getIt.isRegistered<UtilityMeterRepository>()) {
      throw StateError('Penyimpanan listrik belum tersedia.');
    }
    await getIt<UtilityMeterRepository>().recordLinkedPurchase(
      householdId: _householdId,
      transactionId: transactionId,
      proposal: proposal,
    );
  }

  /// Eksekusi proposal fuel log (BBM) setelah transaksi berhasil disimpan
  Future<void> _executeFuelProposal(Map<String, Object?> parameters) async {
    try {
      final metadataRaw = parameters['metadata'];
      if (metadataRaw is! Map) return;

      final fuelProposal = metadataRaw['fuelProposal'];
      if (fuelProposal is! Map) return;

      final vehicleId = fuelProposal['vehicleId']?.toString();
      if (vehicleId == null || vehicleId.isEmpty) return;

      // Import vehicle repository secara lazy
      if (!getIt.isRegistered<VehicleRepository>()) return;
      final vehicleRepo = getIt<VehicleRepository>();

      final timestampStr = fuelProposal['timestamp']?.toString();
      final timestamp = timestampStr != null
          ? DateTime.tryParse(timestampStr)
          : _clock();

      final liters = (fuelProposal['liters'] as num?)?.toDouble() ?? 0.0;
      final totalAmount =
          (fuelProposal['totalAmount'] as num?)?.toDouble() ?? 0.0;

      if (liters > 0 && totalAmount > 0) {
        final fuelLogId = 'fuel_${Uuid().v4()}';
        await vehicleRepo.addFuelLog(
          householdId: _householdId,
          vehicleId: vehicleId,
          fuelLog: FuelLogEntry(
            id: fuelLogId,
            date: timestamp ?? _clock(),
            liters: liters,
            totalAmount: totalAmount,
            fuelType: fuelProposal['fuelType']?.toString() ?? 'Pertalite',
            spbuLocation: fuelProposal['spbuLocation']?.toString() ?? 'SPBU',
          ),
        );

        // Catat aktivitas otonom jika tersedia
        if (getIt.isRegistered<AutonomousActivityRepository>()) {
          final activityRepo = getIt<AutonomousActivityRepository>();
          await activityRepo.recordActivity(
            AutonomousActivityRecord(
              id: 'act_${Uuid().v4()}_fuel',
              householdId: _householdId,
              title: 'Pencatatan BBM (${fuelProposal['vehicleName']})',
              description:
                  'Mencatat pengisian ${liters}L ${fuelProposal['fuelType']} seharga Rp ${totalAmount.toInt()} untuk ${fuelProposal['plateNumber']}.',
              activityType: AutonomousActivityType.fuelLog,
              occurredAt: timestamp ?? _clock(),
              payload: {
                'vehicleId': vehicleId,
                'logId': fuelLogId,
                'liters': liters,
                'totalAmount': totalAmount,
              },
            ),
          );
        }
      }
    } on Object {
      // Best-effort: gagal tidak membatalkan transaksi utama
    }
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
    final fee = _nonNegativeInt(step.parameters['adminFee']);
    if (step.parameters['adminFee'] != null && fee == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Biaya admin tidak boleh negatif atau tidak valid.',
      );
    }
    final effectiveFee = fee ?? 0;
    final now = _clock();
    final date = _dateParameter(step.parameters['date']) ?? now;
    final note = _nullableText(step.parameters['note']);
    final source =
        _nullableText(step.parameters['source']) ?? 'assistant_orchestrator';
    final feeId = effectiveFee > 0 ? '$transferId-fee' : null;
    final feeCategory = effectiveFee > 0
        ? await _findCategory('Biaya admin', 'expense')
        : null;
    if (effectiveFee > 0 && feeCategory == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Kategori Biaya admin belum tersedia.',
      );
    }
    final existing =
        await (_database.select(_database.transfers)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.id.equals(transferId),
            ))
            .getSingleOrNull();
    if (existing != null) {
      final feeTransaction = feeId == null
          ? null
          : await (_database.select(_database.transactions)..where(
                  (row) =>
                      row.householdId.equals(_householdId) &
                      row.id.equals(feeId),
                ))
                .getSingleOrNull();
      final matches =
          existing.amount == amount &&
          existing.fromAccountId == from.id &&
          existing.toAccountId == to.id &&
          existing.adminFee == effectiveFee &&
          existing.date == date &&
          existing.note == note &&
          existing.source == source &&
          existing.feeTransactionId == feeId &&
          (effectiveFee == 0 ||
              feeTransaction != null &&
                  feeTransaction.amount == -effectiveFee &&
                  feeTransaction.accountId == from.id &&
                  feeTransaction.categoryId == feeCategory.id &&
                  feeTransaction.date == date &&
                  feeTransaction.note ==
                      'Biaya admin transfer ${from.name} ke ${to.name}' &&
                  feeTransaction.source == 'transfer_fee');
      if (matches) {
        return const FfmAssistantCapabilityExecutionResult.success(
          'alreadyApplied: transfer sudah tersimpan.',
        );
      }
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Idempotency key sudah dipakai oleh transfer dengan isi berbeda.',
      );
    }
    final balance = await GetAccountBookBalance(_database)(
      _householdId,
      from.id,
      asOf: date,
    );
    if (balance < amount + effectiveFee) {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Saldo ${from.name} tidak mencukupi untuk transfer dan biaya admin.',
      );
    }
    final transfer = TransferEntity(
      id: transferId,
      householdId: _householdId,
      date: date,
      recordedAt: now,
      amount: amount,
      adminFee: effectiveFee,
      feeTransactionId: feeId,
      fromAccountId: from.id,
      toAccountId: to.id,
      note: note,
      source: source,
      updatedAt: now,
    );
    final entities = <TransactionEntity>[];
    if (effectiveFee > 0) {
      entities.add(
        TransactionEntity(
          id: feeId!,
          householdId: _householdId,
          date: transfer.date,
          amount: -effectiveFee,
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
    await _saveMixedTransactionBatch(
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
      final expectedAmount = _positiveInt(step.parameters['amount']);
      final expectedFee = _nonNegativeInt(step.parameters['adminFee']) ?? 0;
      final expectedDate = _dateParameter(step.parameters['date']);
      final expectedFrom = await _findAccount(
        step.parameters['fromAccount']?.toString().trim(),
      );
      final expectedTo = await _findAccount(
        step.parameters['toAccount']?.toString().trim(),
      );
      final expectedSource =
          _nullableText(step.parameters['source']) ?? 'assistant_orchestrator';
      final expectedNote = _nullableText(step.parameters['note']);
      final expectedFeeCategory = expectedFee == 0
          ? null
          : await _findCategory('Biaya admin', 'expense');
      final feeTransaction = transfer?.feeTransactionId == null
          ? null
          : await (_database.select(_database.transactions)..where(
                  (row) =>
                      row.householdId.equals(_householdId) &
                      row.id.equals(transfer!.feeTransactionId!),
                ))
                .getSingleOrNull();
      final matches =
          transfer != null &&
          expectedAmount != null &&
          expectedFrom != null &&
          expectedTo != null &&
          transfer.amount == expectedAmount &&
          transfer.fromAccountId == expectedFrom.id &&
          transfer.toAccountId == expectedTo.id &&
          transfer.adminFee == expectedFee &&
          transfer.note == expectedNote &&
          transfer.source == expectedSource &&
          (expectedDate == null || transfer.date == expectedDate) &&
          (expectedFee == 0
              ? transfer.feeTransactionId == null
              : feeTransaction != null &&
                    expectedFeeCategory != null &&
                    feeTransaction.amount == -expectedFee &&
                    feeTransaction.accountId == expectedFrom.id &&
                    feeTransaction.categoryId == expectedFeeCategory.id &&
                    feeTransaction.date == transfer.date &&
                    feeTransaction.note ==
                        'Biaya admin transfer ${expectedFrom.name} ke ${expectedTo.name}' &&
                    feeTransaction.source == 'transfer_fee');
      return !matches
          ? const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: transfer belum ditemukan atau field-nya berbeda.',
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
    if (kind == 'cash_flow_profile' ||
        kind == 'cycle' ||
        kind == 'cashFlowProfile' ||
        kind == 'agrotrack') {
      return _verifyCashFlowProfileSaved(id);
    }
    if (kind == 'master_data' || kind == 'masterData') {
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
    if (transaction == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Verifikasi gagal: transaksi hasil draft belum ditemukan di data lokal.',
      );
    }
    if (kind != 'income' && kind != 'expense') {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Verifikasi gagal: jenis transaksi hasil draft tidak didukung.',
      );
    }
    final account = await _findAccount(
      (kind == 'income'
              ? step.parameters['toAccount']
              : step.parameters['fromAccount'])
          ?.toString()
          .trim(),
    );
    final categoryName = step.parameters['category']?.toString().trim();
    final category = await _findCategory(categoryName, kind);
    final merchantName =
        step.parameters['merchant']?.toString().trim() ??
        step.parameters['merchantName']?.toString().trim() ??
        step.parameters['assistantMerchantName']?.toString().trim();
    final merchant = await _findMerchant(merchantName);
    final tagNames = _csvValues(step.parameters['tags']);
    final tags = await _findTags(tagNames);
    final items = _transactionItemsFromJson(step.parameters['itemsJson'], key);
    final attachmentPaths = _attachmentPaths(
      step.parameters['attachmentPathsJson'],
    );
    if (account == null ||
        categoryName != null && categoryName.isNotEmpty && category == null ||
        step.parameters['newMerchant'] != null && merchant == null ||
        tags.length != tagNames.length ||
        items == null ||
        attachmentPaths == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Verifikasi gagal: referensi atau relasi draft tidak dapat di-resolve ulang.',
      );
    }
    final matches = await _transactionMatchesDraft(
      step: step,
      kind: kind,
      transaction: transaction,
      accountId: account.id,
      categoryId: category?.id,
      merchantId: merchant?.id,
      tagIds: tags.map<String>((tag) => tag.id as String).toSet(),
      items: items,
      attachmentPaths: attachmentPaths,
    );
    return !matches
        ? const FfmAssistantCapabilityExecutionResult.failure(
            'Verifikasi gagal: transaksi terbaca tetapi field canonical berbeda.',
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
    if (category == 'sumber_pemasukan') {
      final source =
          await (_database.select(_database.transactionParties)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      if (operation == 'delete') {
        return source == null
            ? const FfmAssistantCapabilityExecutionResult.success(
                'verified: sumber pemasukan sudah tidak ditemukan di database lokal.',
              )
            : const FfmAssistantCapabilityExecutionResult.failure(
                'Verifikasi gagal: sumber pemasukan masih ditemukan setelah penghapusan.',
              );
      }
      return source != null &&
              !source.isArchived &&
              source.name == step.parameters['title']?.toString().trim() &&
              source.kind == IncomeSourceRepository.kind &&
              source.role == IncomeSourceRepository.role
          ? const FfmAssistantCapabilityExecutionResult.success(
              'verified: sumber pemasukan canonical berhasil dibaca kembali dari database lokal.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Verifikasi gagal: sumber pemasukan belum sesuai row canonical.',
            );
    }
    if (category == 'kategori') {
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
    return (await _references.account(name)).value;
  }

  Future<dynamic> _findCategory(String? name, String type) async {
    return (await _references.category(name, type: type)).value;
  }

  Future<dynamic> _findMerchant(String? name) async {
    return (await _references.merchant(name)).value;
  }

  Future<List<dynamic>> _findTags(List<String> names) async {
    if (names.isEmpty) return const [];
    final rows =
        await (_database.select(_database.tags)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isArchived.equals(false),
            ))
            .get();
    final wanted = names.map((name) => name.toLowerCase()).toSet();
    return rows
        .where((row) => wanted.contains(row.name.toLowerCase()))
        .toList(growable: false);
  }

  List<String> _csvValues(Object? value) {
    if (value is! String) return const [];
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  String? _singleName(Object? value) {
    final names = _csvValues(value);
    return names.length == 1 ? names.single : null;
  }

  bool _sameNames(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);

  bool _sameIntList(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
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

  List<String>? _attachmentPaths(Object? value) {
    if (value == null) return const [];
    if (value is! String || value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List || decoded.length > 20) return null;
      final paths = <String>[];
      for (final entry in decoded) {
        if (entry is! String || entry.trim().isEmpty) return null;
        paths.add(entry.trim());
      }
      return paths;
    } on Object {
      return null;
    }
  }

  String? _nullableText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  Future<bool> _transactionMatchesDraft({
    required FfmAssistantActionStep step,
    required String kind,
    required dynamic transaction,
    required String accountId,
    required String? categoryId,
    required String? merchantId,
    required Set<String> tagIds,
    required List<TransactionItemEntity> items,
    required List<String> attachmentPaths,
  }) async {
    final row = transaction.transaction;
    final amount = _positiveInt(step.parameters['amount']);
    if (amount == null) return false;
    final expectedAmount = kind == 'income' ? amount : -amount;
    final expectedDate = _dateParameter(step.parameters['date']);
    final expectedSource =
        _nullableText(step.parameters['source']) ?? 'assistant_orchestrator';
    final party =
        _nullableText(step.parameters['party']) ??
        _nullableText(step.parameters['incomeSource']) ??
        _nullableText(step.parameters['partyName']);
    if (row.type != kind ||
        row.amount != expectedAmount ||
        row.accountId != accountId ||
        row.categoryId != categoryId ||
        row.merchantId != merchantId ||
        expectedDate != null && row.date != expectedDate ||
        row.note != _nullableText(step.parameters['note']) ||
        row.source != expectedSource ||
        row.sourceId != _nullableText(step.parameters['sourceId']) ||
        row.recurringTransactionId !=
            _nullableText(step.parameters['recurringTransactionId']) ||
        row.linkedActivityId !=
            _nullableText(step.parameters['linkedActivityId']) ||
        row.location != _nullableText(step.parameters['location']) ||
        row.partyName != party ||
        row.receiptRawText !=
            _nullableText(step.parameters['receiptRawText']) ||
        row.receiptNumber != _nullableText(step.parameters['receiptNumber']) ||
        row.receiptPaidAmount !=
            _nonNegativeInt(step.parameters['receiptPaidAmount']) ||
        row.receiptChangeAmount !=
            _nonNegativeInt(step.parameters['receiptChangeAmount']) ||
        row.tax != _nonNegativeInt(step.parameters['tax']) ||
        row.discount != _nonNegativeInt(step.parameters['discount'])) {
      return false;
    }

    final persistedItems = transaction.items as List<TransactionItem>;
    if (persistedItems.length != items.length) return false;
    final expectedItems = {
      for (final item in items)
        item.id:
            '${item.itemName}|${item.price}|${item.qty}|${(item.price * item.qty).round()}',
    };
    for (final item in persistedItems) {
      if (expectedItems[item.id] !=
          '${item.itemName}|${item.price}|${item.qty}|${item.amount}') {
        return false;
      }
    }

    final persistedTags = await (_database.select(
      _database.transactionTags,
    )..where((link) => link.transactionId.equals(row.id))).get();
    if (!_sameNames(persistedTags.map((link) => link.tagId).toSet(), tagIds)) {
      return false;
    }
    final persistedAttachments = await (_database.select(
      _database.attachments,
    )..where((attachment) => attachment.transactionId.equals(row.id))).get();
    if (persistedAttachments.length != attachmentPaths.length) return false;
    for (var index = 0; index < attachmentPaths.length; index++) {
      final expectedId = _stableId(
        '${step.parameters['_idempotencyKey']}:attachment:$index',
      );
      final matches = persistedAttachments.any(
        (attachment) =>
            attachment.id == expectedId &&
            attachment.path == attachmentPaths[index],
      );
      if (!matches) return false;
    }
    return true;
  }

  /// Item nota draft asisten disamakan dengan kolom transaction_items.
  /// Format sama dengan form: itemsJson list of {name/itemName, price, qty}.
  List<TransactionItemEntity>? _transactionItemsFromJson(
    Object? raw,
    String idempotencyKey,
  ) {
    if (raw is! String || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final items = <TransactionItemEntity>[];
      var index = 0;
      for (final entry in decoded) {
        if (entry is! Map) return null;
        final name =
            entry['name']?.toString() ?? entry['itemName']?.toString() ?? '';
        if (name.trim().isEmpty) return null;
        final price = int.tryParse(entry['price']?.toString() ?? '0');
        if (price == null || price < 0) return null;
        final qty = double.tryParse(
          entry['qty']?.toString() ?? entry['quantity']?.toString() ?? '1',
        );
        if (qty == null || qty <= 0) return null;
        final lineTotal = entry['lineTotal'] ?? entry['amount'];
        if (lineTotal != null) {
          final parsedLineTotal = int.tryParse(lineTotal.toString());
          if (parsedLineTotal == null ||
              parsedLineTotal < 0 ||
              parsedLineTotal != (price * qty).round()) {
            return null;
          }
        }
        items.add(
          TransactionItemEntity(
            id: _stableId('$idempotencyKey:item:$index:$name'),
            transactionId: _stableId(idempotencyKey),
            itemName: name.trim(),
            price: price,
            qty: qty,
          ),
        );
        index++;
      }
      return items;
    } on Object {
      return null;
    }
  }

  String? _validateReceiptTotals({
    required int amount,
    required List<TransactionItemEntity> items,
    required int? tax,
    required int? discount,
    required int? paidAmount,
    required int? changeAmount,
  }) {
    if (tax != null && tax < 0 || discount != null && discount < 0) {
      return 'Pajak dan diskon tidak boleh negatif.';
    }
    if ((tax != null || discount != null) && items.isEmpty) {
      return 'Pajak atau diskon harus disertai rincian item agar total dapat diverifikasi.';
    }
    if (tax != null && discount != null && tax - discount < 0) {
      return 'Pajak dan diskon menghasilkan total negatif.';
    }
    if (items.isNotEmpty) {
      final subtotal = items.fold<double>(
        0,
        (sum, item) => sum + item.price * item.qty,
      );
      final expected = subtotal.round() + (tax ?? 0) - (discount ?? 0);
      if (expected != amount) {
        return 'Total struk tidak cocok: rincian item menghasilkan ${_money(expected)}, tetapi nominal draft ${_money(amount)}.';
      }
    }
    if (paidAmount != null && paidAmount < 0 ||
        changeAmount != null && changeAmount < 0) {
      return 'Nominal dibayar dan kembalian tidak boleh negatif.';
    }
    if (changeAmount != null && paidAmount == null) {
      return 'Nominal dibayar wajib diisi jika kembalian diberikan.';
    }
    if (paidAmount != null &&
        changeAmount != null &&
        (changeAmount > paidAmount || paidAmount - changeAmount != amount)) {
      return 'Nominal dibayar dikurangi kembalian tidak sama dengan total transaksi.';
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
        await (_database.select(_database.activitySessions)
              ..where(
                (row) =>
                  row.householdId.equals(_householdId),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.startedAt)]))
            .get();

    final includeArchived = step.parameters['archived']?.toString() == 'true';
    final status = step.parameters['status']?.toString();
    final kind = step.parameters['kind']?.toString();
    final category = step.parameters['category']?.toString().toLowerCase();
    final query = step.parameters['query']?.toString().toLowerCase();
    final dateFrom = DateTime.tryParse(step.parameters['dateFrom']?.toString() ?? '');
    final dateTo = DateTime.tryParse(step.parameters['dateTo']?.toString() ?? '');
    final filtered = rows.where((row) {
      if (!includeArchived && row.isArchived) return false;
      if (status != null && status.isNotEmpty && row.status != status) return false;
      if (kind != null && kind.isNotEmpty && row.kind != kind) return false;
      if (category != null && category.isNotEmpty && row.category.toLowerCase() != category) return false;
      if (query != null && query.isNotEmpty &&
          !'${row.title} ${row.notes ?? ''}'.toLowerCase().contains(query)) {
        return false;
      }
      if (dateFrom != null && row.startedAt.isBefore(dateFrom)) return false;
      if (dateTo != null && row.startedAt.isAfter(dateTo)) return false;
      return true;
    }).toList(growable: false);
    final limit = (int.tryParse(step.parameters['limit']?.toString() ?? '') ?? 10)
        .clamp(1, 50);
    final visible = filtered.take(limit).toList(growable: false);
    if (visible.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada aktivitas, tugas, atau catatan yang tercatat.',
      );
    }

    final active = visible.where((r) => r.status == 'active').toList();
    final recent = visible.where((r) => r.status != 'active').toList();

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
        if (step.parameters['includeCheckpoints']?.toString() == 'true') {
          final checkpoints = await ActivityRepository(
            _database,
            AuditLogger(_database),
          ).getCheckpoints(row.id);
          for (final checkpoint in checkpoints) {
            buffer.writeln('    checkpoint: ${checkpoint.label}');
          }
        }
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

  Future<FfmAssistantCapabilityExecutionResult> _readDailyNotes(
    FfmAssistantActionStep step,
  ) async {
    final rows =
        await (_database.select(_database.dailyNotes)
              ..where(
                (row) =>
                    row.householdId.equals(_householdId),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.noteDate)])
              ..limit(50))
            .get();
    final includeArchived = step.parameters['archived']?.toString() == 'true';
    final query = step.parameters['query']?.toString().toLowerCase();
    final dateFrom = DateTime.tryParse(step.parameters['dateFrom']?.toString() ?? '');
    final dateTo = DateTime.tryParse(step.parameters['dateTo']?.toString() ?? '');
    final limit = (int.tryParse(step.parameters['limit']?.toString() ?? '') ?? 10)
        .clamp(1, 50);
    final visible = rows.where((row) {
      if (!includeArchived && row.isArchived) return false;
      if (dateFrom != null && row.noteDate.isBefore(dateFrom)) return false;
      if (dateTo != null && row.noteDate.isAfter(dateTo)) return false;
      if (query != null && query.isNotEmpty &&
          !'${row.title ?? ''} ${row.body}'.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).take(limit).toList(growable: false);
    if (visible.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada Catatan Harian yang tersimpan.',
      );
    }
    final lines = visible.map((row) {
      final title = row.title?.trim();
      final label = title == null || title.isEmpty ? row.body : '$title: ${row.body}';
      return '- ${row.noteDate.toIso8601String().substring(0, 10)} $label';
    }).join('\n');
    return FfmAssistantCapabilityExecutionResult.success(
      'Catatan Harian terbaru:\n$lines',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _readActivityLog(
    FfmAssistantActionStep step,
  ) async {
    final action = step.parameters['action']?.toString();
    final entity = step.parameters['entity']?.toString();
    final search = step.parameters['search']?.toString();
    final limit = int.tryParse(step.parameters['limit']?.toString() ?? '') ?? 20;
    final offset = int.tryParse(step.parameters['offset']?.toString() ?? '') ?? 0;
    final from = DateTime.tryParse(step.parameters['dateFrom']?.toString() ?? '');
    final to = DateTime.tryParse(step.parameters['dateTo']?.toString() ?? '');
    final logs = await SqliteAuditLogRepository(_database).getLogs(
      householdId: _householdId,
      action: action,
      entity: entity,
      from: from,
      to: to,
      search: search,
      limit: limit,
      offset: offset,
    );
    if (logs.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada log aktivitas yang cocok.',
      );
    }
    final lines = logs.map((log) {
      final date = log.timestamp.toIso8601String().replaceFirst('T', ' ');
      return '- $date: ${log.action} ${log.entity}';
    }).join('\n');
    return FfmAssistantCapabilityExecutionResult.success(
      'Log Aktivitas terbaru:\n$lines',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _readElectricity(
    FfmAssistantActionStep step,
  ) async {
    final repo = UtilityMeterRepository(_database);
    final meters = await repo.getAllMeters(_householdId);
    final history = await repo.getPurchaseHistory(_householdId, limit: 8);

    if (meters.isEmpty && history.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada meteran listrik atau riwayat pembelian token yang tercatat.',
      );
    }

    final buffer = StringBuffer();
    if (meters.isNotEmpty) {
      buffer.writeln('Meteran Listrik Terdaftar (${meters.length}):');
      String? highestSpenderName;
      int highestCost = 0;
      for (final meter in meters) {
        final summary = await repo.summarizeUsage(_householdId, meterId: meter.id);
        final burnRate = await repo.calculateBurnRate(_householdId, meter.id);
        final latestReading = await repo.getLatestReading(_householdId, meter.id);
        if (summary.totalCost > highestCost) {
          highestCost = summary.totalCost;
          highestSpenderName = meter.name;
        }

        final burnRateStr = burnRate != null
            ? '; konsumsi: ~${burnRate.dailyKwh.toStringAsFixed(2)} kWh/hari'
              '${burnRate.daysRemaining != null ? " (sisa ~${burnRate.daysRemaining} hari)" : ""}'
            : '';
        final readingStr = latestReading != null
            ? '; pembacaan fisik: ${latestReading.readingKwh.toStringAsFixed(2)} kWh'
            : '';
        final lastToken = meter.lastTokenNumber != null && meter.lastTokenNumber!.isNotEmpty
            ? meter.lastTokenNumber!
            : 'belum ada';

        buffer.writeln(
          '• ${meter.name} (${meter.formattedMeterNumber}): total beli Rp${summary.totalCost} '
          '(${summary.totalCreditedKwh.toStringAsFixed(2)} kWh dari ${summary.purchaseCount}x beli)$readingStr$burnRateStr; '
          'token terakhir: $lastToken',
        );
      }
      if (meters.length > 1 && highestSpenderName != null && highestCost > 0) {
        buffer.writeln(
          'Perbandingan: Properti dengan pengeluaran listrik tertinggi adalah $highestSpenderName (Rp$highestCost).',
        );
      }
    }

    if (history.isNotEmpty) {
      buffer.writeln('Riwayat Pembelian Token Terbaru:');
      for (final row in history.take(5)) {
        final kwh = row.creditedKwh == null
            ? ''
            : ' • ${row.creditedKwh!.toStringAsFixed(2)} kWh';
        final meterObj = meters.where((m) => m.id == row.meterId || m.meterNumber == row.meterNumber).firstOrNull;
        final nameLabel = meterObj != null ? ' (${meterObj.name})' : '';
        buffer.writeln(
          '• ${row.meterNumber}$nameLabel — Rp${row.amount}$kwh • ${_dateTime(row.purchasedAt)}',
        );
      }
    }

    return FfmAssistantCapabilityExecutionResult.success(
      buffer.toString().trim(),
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _readBudget(
    FfmAssistantActionStep step,
  ) async {
    final period = step.parameters['period']?.toString().trim();
    const periodTypes = {
      'weekly',
      'biweekly',
      'monthly',
      'bimonthly',
      'fourmonthly',
      'fivemonthly',
      'nonrecurring',
    };
    if (period != null && period.isNotEmpty && !periodTypes.contains(period)) {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Periode Anggaran "$period" tidak didukung. Gunakan mingguan, dua mingguan, bulanan, atau tidak rutin.',
      );
    }
    final requestedCategory = step.parameters['category']?.toString().trim();
    String? categoryId;
    if (requestedCategory != null && requestedCategory.isNotEmpty) {
      final categories =
          await (_database.select(_database.categories)..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.isActive.equals(true) &
                    row.type.equals('expense'),
              ))
              .get();
      final matches = categories
          .where(
            (category) =>
                category.id == requestedCategory ||
                category.name.toLowerCase() == requestedCategory.toLowerCase(),
          )
          .toList(growable: false);
      if (matches.length != 1) {
        return FfmAssistantCapabilityExecutionResult.failure(
          matches.isEmpty
              ? 'Kategori pengeluaran "$requestedCategory" tidak ditemukan.'
              : 'Kategori "$requestedCategory" tidak unik. Sebut nama kategori yang lebih spesifik.',
        );
      }
      categoryId = matches.single.id;
    }
    final snapshots =
        await BudgetRepository(
          _database,
          AuditLogger(_database),
          clock: _clock,
        ).readSnapshots(
          householdId: _householdId,
          now: _clock(),
          periodType: period?.isEmpty ?? true ? null : period,
          categoryId: categoryId,
          budgetId: step.parameters['budgetId']?.toString().trim(),
        );
    if (snapshots.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada anggaran aktif yang sesuai pada periode berjalan.',
      );
    }
    final lines = snapshots.map((snapshot) {
      return '${snapshot.budget.name}: batas ${_money(snapshot.allocated)}, '
          'pakai ${_money(snapshot.spent)}, sisa ${_money(snapshot.remaining)} '
          '(${(snapshot.progress * 100).round()}%, ${snapshot.status}).';
    });
    return FfmAssistantCapabilityExecutionResult.success(
      'Anggaran (${snapshots.length}): ${lines.join(' ')}',
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
    rows.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final dayNames = ['', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    final lines = rows.take(10).map((row) {
      final local = row.scheduledAt.toLocal();
      final date =
          '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
      final time =
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      final recurrence = switch (row.recurrenceType) {
        'daily' => ' (harian)',
        'weekly' => ' (mingguan)',
        _ => '',
      };
      var info = '${row.title} pada $date $time$recurrence';
      if (row.recurrenceType == 'weekly') {
        try {
          final wj = row.weekdaysJson;
          if (wj.isNotEmpty && wj != '[]') {
            final days = wj
                .replaceAll('[', '')
                .replaceAll(']', '')
                .split(',')
                .map((s) => int.tryParse(s.trim()))
                .whereType<int>()
                .map((d) => (d >= 1 && d <= 7) ? dayNames[d] : '$d')
                .join(',');
            if (days.isNotEmpty) info += ' hari=$days';
          }
        } on Object {
          // Abaikan.
        }
      }
      if (row.note != null && row.note!.trim().isNotEmpty) {
        info += ' catatan=${row.note!.trim()}';
      }
      return info;
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

  Future<FfmAssistantCapabilityExecutionResult> _setTheme(
    FfmAssistantActionStep step,
  ) async {
    final theme = step.parameters['theme']?.toString() ?? 'system';
    if (_themeController != null) {
      await _themeController.setByName(theme);
    }
    final modeLabel = switch (theme.toLowerCase()) {
      'dark' => 'mode gelap 🌙',
      'light' => 'mode terang ☀️',
      _ => 'mode ikuti sistem 📱',
    };
    return FfmAssistantCapabilityExecutionResult.success(
      'Tampilan aplikasi berhasil diubah ke $modeLabel.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _setHijriAdjustment(
    FfmAssistantActionStep step,
  ) async {
    final raw = step.parameters['adjustment']?.toString() ?? '0';
    final adjustment = int.tryParse(raw) ?? 0;
    if (adjustment < -2 || adjustment > 2) {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Offset Hijriah hanya bisa -2 s/d +2 hari.',
      );
    }
    final calendarService = getIt<HijriCalendarService>();
    final settings = await calendarService.getSettings(_householdId);
    await calendarService.saveSettings(
      householdId: _householdId,
      method: settings.method,
      region: settings.region,
      dayAdjustment: adjustment,
      timezone: settings.timezone,
    );
    final label = adjustment == 0
        ? 'standar (0 hari)'
        : '${adjustment > 0 ? "+" : ""}$adjustment hari';
    return FfmAssistantCapabilityExecutionResult.success(
      'Tanggal Hijriah berhasil dikoreksi ke $label. Seluruh tanggal Islam di aplikasi sudah menyesuaikan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _refreshMarket(
    FfmAssistantActionStep step,
  ) async {
    final service = getIt<MarketNewsRadarService>();
    final cache = getIt<MarketNewsCacheRepository>();
    final prices = await service.fetchMarketPrices();
    await cache.savePriceSnapshot(prices);
    final news = await service.fetchCuratedNews();
    if (!news.every((item) => item.isFallback)) {
      await cache.saveNewsItems(news);
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Berita dan valas sudah disegarkan. Sumber online: ${news.length} berita, kurs ${prices.isOfflineCache ? 'fallback' : 'terverifikasi'}.',
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

    try {
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
    } on StateError catch (error) {
      return FfmAssistantCapabilityExecutionResult.failure(error.message);
    }

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
    final requestedMode = ActivityMode.tryParse(
      (step.parameters['activityMode'] ?? step.parameters['mode'])?.toString(),
    );
    final effectiveMode =
        requestedMode ?? ActivityMode.defaultForKind(activityKind);
    if (effectiveMode == ActivityMode.history) {
      // Catatan kejadian memiliki sumber data kanonis sendiri. Permintaan lama
      // berjenis activity+history tetap diterima, tetapi tidak lagi membuat
      // sesi aktivitas semu yang tampil berbeda di UI.
      return _saveDailyNote(step, idempotencyKey);
    }

    final now = _clock();
    final id = _stableId(idempotencyKey);
    final categoryName =
        step.parameters['category']?.toString().trim() ?? 'Lainnya';
    final directCategory = await _findCategory(categoryName, 'activity');
    var category = directCategory;
    if (category == null) {
      category = await _findCategory('Lainnya', 'activity');
      if (category == null) {
        final allActivityCategories = await (_database.select(_database.categories)
              ..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.type.equals('activity') &
                    row.isActive.equals(true),
              ))
            .get();
        category = allActivityCategories.firstOrNull;
      }
    }
    final categoryId = category?.id as String?;
    final resolvedCategoryName =
        directCategory != null ? (directCategory.name as String) : categoryName;
    final parentId = step.parameters['parentSessionId']?.toString();
    if (parentId != null && parentId.trim().isNotEmpty) {
      final parentResolution = await _references.activity(parentId);
      final parent = parentResolution.value;
      if (parentResolution.status != FfmAssistantReferenceStatus.resolved ||
          parent == null ||
          parent.status != ActivitySessionStatus.active.value) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Aktivitas induk tidak ditemukan, tidak unik, atau sudah tidak aktif.',
        );
      }
    }
    final notes =
        step.parameters['note']?.toString() ??
        step.parameters['body']?.toString();
    final dueDate = _dateParameter(
      step.parameters['dueDate'] ?? step.parameters['date'],
    );
    final scheduledAt = _dateParameter(step.parameters['scheduledAt']);
    final isAllDay = _boolParameter(step.parameters['isAllDay']) ?? false;
    final startNow =
        _boolParameter(step.parameters['startNow']) ??
        scheduledAt == null || !scheduledAt.isAfter(now);
    final occurredAt = effectiveMode == ActivityMode.timeTracking && !startNow
        ? scheduledAt!
        : effectiveMode == ActivityMode.timeTracking
        ? now
        : dueDate ?? now;
    final activityGroupId = step.parameters['activityGroupId']?.toString();
    final subjectType = step.parameters['subjectType']?.toString();
    final subjectId = step.parameters['subjectId']?.toString();

    final previous = await (_database.select(
      _database.activitySessions,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (previous != null) {
      if (previous.householdId != _householdId) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Idempotency key sudah terikat pada household lain.',
        );
      }
      final same =
          previous.title == title.trim() &&
          previous.categoryId == categoryId &&
          previous.kind == activityKind.value &&
          previous.mode == effectiveMode.value &&
          previous.parentSessionId == parentId &&
          previous.startedAt == occurredAt &&
          previous.notes == notes;
      if (!same) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Idempotency key sudah dipakai oleh aktivitas dengan isi berbeda.',
        );
      }
      return const FfmAssistantCapabilityExecutionResult.success(
        'alreadyApplied: aktivitas sudah tersimpan sebelumnya.',
      );
    }

    await _database
        .into(_database.activitySessions)
        .insert(
          ActivitySessionsCompanion.insert(
            id: id,
            householdId: _householdId,
            title: title.trim(),
            parentSessionId: Value(parentId),
            categoryId: Value(categoryId),
            category: Value(resolvedCategoryName),
            kind: Value(activityKind.value),
            mode: Value(effectiveMode.value),
            activityGroupId: Value(activityGroupId),
            subjectType: Value(subjectType),
            subjectId: Value(subjectId),
            startedAt: occurredAt,
            dueDate: Value(dueDate),
            scheduledAt: Value(scheduledAt),
            isAllDay: Value(isAllDay),
            status: (effectiveMode == ActivityMode.timeTracking)
                ? const Value('active')
                : const Value('completed'),
            isCompleted: Value(effectiveMode != ActivityMode.timeTracking),
            notes: Value(notes),
            createdAt: now,
            updatedAt: Value(now),
          ),
        );

    await _observeActivityHabit(title, occurredAt);
    return FfmAssistantCapabilityExecutionResult.success(
      'Aktivitas “${title.trim()}” (${activityKind.name}) berhasil disimpan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveDailyNote(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final body =
        (step.parameters['body'] ??
                step.parameters['note'] ??
                step.parameters['title'])
            ?.toString()
            .trim();
    if (body == null || body.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Isi Catatan Harian belum diisi.',
      );
    }
    final tagNames = _csvValues(
      step.parameters['tags'] ??
          step.parameters['tag'] ??
          step.parameters['lahan'],
    );
    final tags = tagNames.isEmpty
        ? const <dynamic>[]
        : await _findTags(tagNames);
    // Relax validation: allow proceeding even if some tags don't exist
    // The editor should handle tag creation, but we should not block execution
    // if tags are missing from master data
    final id = _stableId(idempotencyKey);
    final existing = await (_database.select(
      _database.dailyNotes,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (existing != null) {
      if (existing.householdId != _householdId) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Idempotency key sudah terikat pada household lain.',
        );
      }
      return existing.body == body
          ? const FfmAssistantCapabilityExecutionResult.success(
              'alreadyApplied: Catatan Harian sudah tersimpan.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Idempotency key sudah dipakai oleh Catatan Harian berbeda.',
            );
    }
    final now = _clock();
    final noteDate = _dateParameter(step.parameters['date']) ?? now;
    await _database.transaction(() async {
      await _database
          .into(_database.dailyNotes)
          .insert(
            DailyNotesCompanion.insert(
              id: id,
              householdId: _householdId,
              noteDate: noteDate,
              title: Value(step.parameters['title']?.toString().trim()),
              body: body,
              treatmentType: Value(
                step.parameters['treatmentType']
                    ?.toString()
                    .trim()
                    .toLowerCase(),
              ),
              createdAt: now,
              updatedAt: Value(now),
            ),
          );
      await _database.batch((batch) {
        batch.insertAll(
          _database.dailyNoteTags,
          tags
              .map(
                (tag) => DailyNoteTagsCompanion.insert(
                  dailyNoteId: id,
                  tagId: tag.id as String,
                ),
              )
              .toList(growable: false),
        );
      });
    });
    return const FfmAssistantCapabilityExecutionResult.success(
      'Catatan Harian berhasil disimpan.',
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
    try {
      final rawRecurrence =
          (step.parameters['recurrence'] ?? step.parameters['recurrenceType'])
              ?.toString()
              .toLowerCase();
      final recurrenceType = switch (rawRecurrence) {
        'daily' || 'harian' => ReminderRecurrenceType.daily,
        'weekly' || 'mingguan' => ReminderRecurrenceType.weekly,
        'monthly' || 'bulanan' => ReminderRecurrenceType.monthly,
        'yearly' || 'tahunan' => ReminderRecurrenceType.yearly,
        'hijri_monthly' ||
        'hijriah' ||
        'bulanan hijriah' => ReminderRecurrenceType.hijriMonthly,
        _ => ReminderRecurrenceType.once,
      };

      final weekdaysRaw = step.parameters['weekdays'];
      final List<int> parsedWeekdays = weekdaysRaw is List
          ? weekdaysRaw
                .map((e) => int.tryParse(e.toString()))
                .whereType<int>()
                .toList()
          : weekdaysRaw is String
          ? weekdaysRaw
                .split(',')
                .map((e) => int.tryParse(e.trim()))
                .whereType<int>()
                .toList()
          : const [];
      final List<int> weekdays =
          (recurrenceType == ReminderRecurrenceType.weekly &&
              parsedWeekdays.isEmpty)
          ? [date.weekday]
          : parsedWeekdays;

      final note = step.parameters['note']?.toString() ?? '';
      final soundUri = step.parameters['soundUri']?.toString();
      final soundName = step.parameters['soundName']?.toString();
      final originRaw = step.parameters['origin']?.toString();
      final origin = ReminderOriginX.fromStorage(originRaw);
      final modeRaw =
          (step.parameters['reminderMode'] ?? step.parameters['mode'])
              ?.toString();
      final mode = ReminderModeX.fromStorage(modeRaw);
      final sourceTypeRaw = step.parameters['sourceType']?.toString();
      final sourceType = ReminderSourceTypeX.fromStorage(sourceTypeRaw);
      final sourceId = step.parameters['sourceId']?.toString();
      final previous = await ReminderRepository(_database)
          .getReminder(_householdId, id);
      if (previous != null) {
        final samePayload =
            previous.title == title.trim() &&
            previous.note == (note.isEmpty ? null : note) &&
            previous.scheduledAt == date &&
            previous.recurrenceType == recurrenceType &&
            _sameIntList(previous.weekdays, weekdays) &&
            previous.soundUri == soundUri &&
            previous.soundName == soundName &&
            previous.sourceType == sourceType &&
            previous.sourceId == sourceId &&
            previous.origin == origin &&
            previous.mode == mode;
        return samePayload
            ? const FfmAssistantCapabilityExecutionResult.success(
                'alreadyApplied: pengingat sudah tersimpan sebelumnya.',
              )
            : const FfmAssistantCapabilityExecutionResult.failure(
                'Idempotency key sudah dipakai oleh pengingat dengan isi berbeda.',
              );
      }

      await reminderMutations.save(
        ReminderEntity(
          id: id,
          householdId: _householdId,
          title: title.trim(),
          note: note.isEmpty ? null : note,
          scheduledAt: date,
          recurrenceType: recurrenceType,
          weekdays: weekdays,
          notificationId: stableReminderNotificationId(id, 'initial'),
          soundUri: soundUri,
          soundName: soundName,
          sourceType: sourceType,
          sourceId: sourceId,
          origin: origin,
          mode: mode,
          createdAt: now,
        ),
      );

      final formattedDate = _formatDateIndonesian(date);
      final successMessage =
          'Pengingat berhasil disimpan untuk $formattedDate.';

      return FfmAssistantCapabilityExecutionResult.success(successMessage);
    } on Object {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Pengingat belum disimpan karena izin atau jadwal notifikasi belum siap.',
      );
    }
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
      final duplicate =
          await (_database.select(_database.accounts)..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.name.equals(title.trim()) &
                    row.isArchived.equals(false),
              ))
              .getSingleOrNull();
      if (duplicate != null) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Nama rekening sudah dipakai household ini.',
        );
      }
      final accountType = formValues['accountType']?.toString() ?? 'cash';
      final type = switch (accountType) {
        'cash' || 'tunai' => 'tunai',
        'bank' => 'bank',
        'ewallet' || 'e-wallet' || 'dompet digital' => 'ewallet',
        _ => 'tunai',
      };
      final openingBalance =
          int.tryParse(formValues['openingBalance']?.toString() ?? '0') ?? 0;
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
      final duplicate =
          await (_database.select(_database.merchants)..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.name.equals(title.trim()) &
                    row.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (duplicate != null) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Nama toko sudah dipakai household ini.',
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
    } else if (category == 'kategori') {
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
    } else if (category == 'sumber_pemasukan') {
      final previous =
          await (_database.select(_database.transactionParties)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      if (previous != null) {
        return previous.name == title.trim()
            ? const FfmAssistantCapabilityExecutionResult.success(
                'alreadyApplied: sumber pemasukan sudah tersimpan.',
              )
            : const FfmAssistantCapabilityExecutionResult.failure(
                'Idempotency key sudah dipakai oleh sumber pemasukan dengan isi berbeda.',
              );
      }
      final duplicate =
          await (_database.select(_database.transactionParties)..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.name.equals(title.trim()) &
                    row.isArchived.equals(false) &
                    row.kind.equals(IncomeSourceRepository.kind) &
                    row.role.equals(IncomeSourceRepository.role),
              ))
              .getSingleOrNull();
      if (duplicate != null) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Nama sumber pemasukan sudah dipakai household ini.',
        );
      }
      await _database
          .into(_database.transactionParties)
          .insert(
            TransactionPartiesCompanion.insert(
              id: id,
              householdId: _householdId,
              name: title.trim(),
              role: Value(IncomeSourceRepository.role),
              kind: Value(IncomeSourceRepository.kind),
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
    final note = step.parameters['note']?.toString().trim();
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
    final categoryName = step.parameters['category']?.toString().trim();
    final explicitCategoryId = step.parameters['categoryId']?.toString().trim();
    final category = explicitCategoryId == null || explicitCategoryId.isEmpty
        ? await _findCategory(categoryName, 'expense')
        : await (_database.select(_database.categories)..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.id.equals(explicitCategoryId) &
                    row.type.equals('expense') &
                    row.isActive.equals(true),
              ))
              .getSingleOrNull();
    if (categoryName != null && categoryName.isNotEmpty && category == null) {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Kategori target "$categoryName" tidak ditemukan atau tidak unik.',
      );
    }
    final id = _stableId(idempotencyKey);
    final previous = await (_database.select(
      _database.goals,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (((categoryName != null && categoryName.isNotEmpty) ||
            (explicitCategoryId != null && explicitCategoryId.isNotEmpty)) &&
        category == null) {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Kategori target "$categoryName" tidak ditemukan atau tidak unik.',
      );
    }
    if (previous != null) {
      if (previous.householdId != _householdId) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Idempotency key sudah terikat pada household lain.',
        );
      }
      return previous.name == title.trim() &&
              previous.targetAmount == amount &&
              previous.targetDate == date &&
              previous.categoryId == (category?.id ?? explicitCategoryId) &&
              previous.note == (note == null || note.isEmpty ? null : note)
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
            categoryId: Value(category?.id),
            note: Value(note == null || note.isEmpty ? null : note),
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
    final rawTitle = step.parameters['title']?.toString().trim();
    final rawParty = step.parameters['party']?.toString().trim();
    final amount = _positiveInt(step.parameters['amount']);
    if ((rawTitle == null || rawTitle.isEmpty) &&
        (rawParty == null || rawParty.isEmpty)) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama pihak atau nama hutang belum diisi dengan benar.',
      );
    }
    if (amount == null || amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nominal hutang harus lebih besar dari nol.',
      );
    }
    final title = rawTitle?.isNotEmpty == true ? rawTitle! : 'Hutang';
    final party = rawParty?.isNotEmpty == true ? rawParty! : title;
    final name =
        (rawTitle != null &&
            rawParty != null &&
            rawTitle != rawParty &&
            rawTitle != 'Hutang')
        ? '$title - $party'
        : (rawParty != null && rawParty.isNotEmpty ? rawParty : title);

    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.liabilities)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      return previous.originalAmount == amount
          ? const FfmAssistantCapabilityExecutionResult.success(
              'alreadyApplied: hutang sudah tersimpan.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Idempotency key sudah dipakai oleh hutang dengan isi berbeda.',
            );
    }
    final dueDateRaw =
        step.parameters['dueDate']?.toString() ??
        step.parameters['targetDate']?.toString();
    final dueDate = dueDateRaw != null ? DateTime.tryParse(dueDateRaw) : null;
    final note = step.parameters['note']?.toString().trim();

    await _database
        .into(_database.liabilities)
        .insert(
          LiabilitiesCompanion.insert(
            id: id,
            householdId: _householdId,
            name: name,
            originalAmount: amount,
            remainingBalance: amount,
            startDate: now,
            dueDate: Value(dueDate),
            note: Value(note == null || note.isEmpty ? null : note),
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
    final rawTitle = step.parameters['title']?.toString().trim();
    final rawParty = step.parameters['party']?.toString().trim();
    final amount = _positiveInt(step.parameters['amount']);
    if ((rawTitle == null || rawTitle.isEmpty) &&
        (rawParty == null || rawParty.isEmpty)) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama pihak atau nominal piutang belum diisi dengan benar.',
      );
    }
    if (amount == null || amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nominal piutang harus lebih besar dari nol.',
      );
    }
    final title = rawTitle?.isNotEmpty == true ? rawTitle! : 'Piutang';
    final party = rawParty?.isNotEmpty == true ? rawParty! : title;
    final name =
        (rawTitle != null &&
            rawParty != null &&
            rawTitle != rawParty &&
            rawTitle != 'Piutang')
        ? '$title - $party'
        : (rawParty != null && rawParty.isNotEmpty ? rawParty : title);

    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.receivables)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      return previous.originalAmount == amount
          ? const FfmAssistantCapabilityExecutionResult.success(
              'alreadyApplied: piutang sudah tersimpan.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Idempotency key sudah dipakai oleh piutang dengan isi berbeda.',
            );
    }
    final dueDateRaw =
        step.parameters['dueDate']?.toString() ??
        step.parameters['targetDate']?.toString();
    final dueDate = dueDateRaw != null ? DateTime.tryParse(dueDateRaw) : null;
    final note = step.parameters['note']?.toString().trim();

    await _database
        .into(_database.receivables)
        .insert(
          ReceivablesCompanion.insert(
            id: id,
            householdId: _householdId,
            name: name,
            originalAmount: amount,
            remainingBalance: amount,
            startDate: now,
            dueDate: Value(dueDate),
            note: Value(note == null || note.isEmpty ? null : note),
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
    final name = step.parameters['title']?.toString().trim();
    final note = step.parameters['note']?.toString().trim();
    if (name == null || name.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama pos anggaran belum diisi.',
      );
    }
    final periodType = step.parameters['periodType']?.toString() ?? 'monthly';
    const periodTypes = {
      'weekly',
      'biweekly',
      'monthly',
      'bimonthly',
      'fourmonthly',
      'fivemonthly',
      'nonrecurring',
    };
    if (!periodTypes.contains(periodType)) {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Periode anggaran "$periodType" tidak didukung.',
      );
    }
    final startDate = _dateParameter(step.parameters['date']) ?? now;
    final endDateOverride = _dateParameter(step.parameters['endDate']);
    final endDate =
        endDateOverride ??
        switch (periodType) {
          'nonrecurring' => DateTime(2099, 12, 31, 23, 59, 59),
          'weekly' => startDate.add(
            const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
          ),
          'biweekly' => startDate.add(
            const Duration(days: 13, hours: 23, minutes: 59, seconds: 59),
          ),
          'bimonthly' => DateTime(
            startDate.year,
            startDate.month + 2,
            startDate.day,
          ).subtract(const Duration(seconds: 1)),
          'fourmonthly' => DateTime(
            startDate.year,
            startDate.month + 4,
            startDate.day,
          ).subtract(const Duration(seconds: 1)),
          'fivemonthly' => DateTime(
            startDate.year,
            startDate.month + 5,
            startDate.day,
          ).subtract(const Duration(seconds: 1)),
          _ => DateTime(
            startDate.year,
            startDate.month + 1,
            startDate.day,
          ).subtract(const Duration(seconds: 1)),
        };
    final rawCategoryIds = step.parameters['categoryIdsJson'];
    final categoryIds = <String>[];
    if (rawCategoryIds is String && rawCategoryIds.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCategoryIds);
        if (decoded is List) {
          categoryIds.addAll(
            decoded
                .map((value) => value.toString().trim())
                .where((value) => value.isNotEmpty),
          );
        }
      } on FormatException {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Daftar kategori anggaran tidak valid.',
        );
      }
    }
    if (categoryIds.isEmpty) {
      final categoryName = step.parameters['category']?.toString().trim();
      final category = await _findCategory(categoryName, 'expense');
      if (categoryName != null && categoryName.isNotEmpty && category == null) {
        return FfmAssistantCapabilityExecutionResult.failure(
          'Kategori anggaran "$categoryName" tidak ditemukan atau tidak unik.',
        );
      }
      if (category != null) categoryIds.add(category.id);
    }
    if (categoryIds.isNotEmpty) {
      final validCategories =
          await (_database.select(_database.categories)..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.id.isIn(categoryIds) &
                    row.type.equals('expense') &
                    row.isActive.equals(true),
              ))
              .get();
      if (validCategories.length != categoryIds.toSet().length) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Ada kategori anggaran yang tidak aktif atau tidak ditemukan.',
        );
      }
    }
    final alertPercent = _nonNegativeInt(step.parameters['alertPercent']) ?? 80;
    final rollover = _nonNegativeInt(step.parameters['rollover']) ?? 0;
    if (alertPercent < 0 || alertPercent > 100) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Ambang peringatan Anggaran harus berada antara 0 dan 100 persen.',
      );
    }
    final previous =
        await (_database.select(_database.envelopeBudgets)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      final samePayload =
          previous.name == name &&
          previous.allocated == amount &&
          previous.categoryIdsJson == jsonEncode(categoryIds) &&
          previous.periodType == periodType &&
          previous.startDate == startDate &&
          previous.endDate == endDate &&
          previous.alertPercent == alertPercent &&
          previous.rollover == rollover &&
          previous.note == (note == null || note.isEmpty ? null : note) &&
          previous.householdId == _householdId;
      return samePayload
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
            name: name,
            note: Value(note == null || note.isEmpty ? null : note),
            categoryId: Value(categoryIds.firstOrNull),
            categoryIdsJson: Value(jsonEncode(categoryIds)),
            month: Value(
              '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}',
            ),
            periodType: Value(periodType),
            allocated: Value(amount),
            startDate: startDate,
            endDate: endDate,
            alertPercent: Value(alertPercent),
            rollover: Value(rollover),
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
    final goalId = step.parameters['goalId']?.toString().trim();
    final FfmAssistantReferenceResolution<dynamic> goalResolution;
    if (goalId == null || goalId.isEmpty) {
      goalResolution = await _references.goal(goalName);
    } else {
      final goalById =
          await (_database.select(_database.goals)..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.id.equals(goalId) &
                    row.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (goalById == null) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Target keuangan tidak ditemukan atau tidak aktif.',
        );
      }
      goalResolution = FfmAssistantReferenceResolution.resolved(goalById);
    }
    final goal = goalResolution.value;
    if (goalResolution.status != FfmAssistantReferenceStatus.resolved ||
        goal == null) {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Target keuangan "$goalName" tidak ditemukan atau tidak unik.',
      );
    }
    final accountName =
        (isDeposit
                ? step.parameters['fromAccount']
                : step.parameters['toAccount'])
            ?.toString()
            .trim();
    final accountId = step.parameters['accountId']?.toString().trim();
    final account = accountId == null || accountId.isEmpty
        ? await _findAccount(accountName)
        : await (_database.select(_database.accounts)..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.id.equals(accountId) &
                    row.isActive.equals(true) &
                    row.isArchived.equals(false),
              ))
              .getSingleOrNull();
    if (account == null) {
      return FfmAssistantCapabilityExecutionResult.failure(
        accountName == null || accountName.isEmpty
            ? 'Rekening alokasi target belum disebutkan.'
            : 'Rekening "$accountName" tidak ditemukan atau tidak unik.',
      );
    }
    final now = _clock();
    final date = _dateParameter(step.parameters['date']);
    if (date == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Tanggal alokasi target belum valid.',
      );
    }
    final id = _stableId(idempotencyKey);
    final previous = await (_database.select(
      _database.transactions,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (previous != null) {
      if (previous.householdId != _householdId) {
        return const FfmAssistantCapabilityExecutionResult.failure(
          'Idempotency key sudah terikat pada household lain.',
        );
      }
      final same =
          previous.amount == -amount &&
          previous.accountId == account.id &&
          previous.goalId == goal.id &&
          previous.date == date &&
          previous.source == (isDeposit ? 'goal_contribution' : 'goal_usage') &&
          previous.note == step.parameters['note']?.toString();
      return same
          ? const FfmAssistantCapabilityExecutionResult.success(
              'alreadyApplied: transaksi target sudah tersimpan.',
            )
          : const FfmAssistantCapabilityExecutionResult.failure(
              'Idempotency key sudah dipakai oleh transaksi target dengan isi berbeda.',
            );
    }

    try {
      await _database.transaction(() async {
        final currentGoal =
            await (_database.select(_database.goals)..where(
                  (row) =>
                      row.householdId.equals(_householdId) &
                      row.id.equals(goal.id),
                ))
                .getSingleOrNull();
        if (currentGoal == null || !currentGoal.isActive) {
          throw StateError('Target keuangan tidak ditemukan atau tidak aktif.');
        }
        final accountRow =
            await (_database.select(_database.accounts)..where(
                  (row) =>
                      row.householdId.equals(_householdId) &
                      row.id.equals(account.id) &
                      row.isActive.equals(true) &
                      row.isArchived.equals(false),
                ))
                .getSingleOrNull();
        if (accountRow == null) throw StateError('Rekening tidak aktif.');
        final accountTransactions =
            await (_database.select(_database.transactions)..where(
                  (row) =>
                      row.householdId.equals(_householdId) &
                      row.accountId.equals(account.id) &
                      row.isArchived.equals(false) &
                      row.isDeleted.equals(false) &
                      row.date.isSmallerOrEqualValue(date),
                ))
                .get();
        final transfers =
            await (_database.select(_database.transfers)..where(
                  (row) =>
                      row.householdId.equals(_householdId) &
                      row.isDeleted.equals(false) &
                      row.date.isSmallerOrEqualValue(date) &
                      (row.fromAccountId.equals(account.id) |
                          row.toAccountId.equals(account.id)),
                ))
                .get();
        var balance =
            accountRow.openingBalance +
            accountTransactions.fold<int>(0, (sum, row) => sum + row.amount);
        for (final transfer in transfers) {
          balance += transfer.toAccountId == account.id
              ? transfer.amount
              : -transfer.amount;
        }
        if (balance < amount) {
          throw StateError('Saldo rekening tidak mencukupi.');
        }
        if (!isDeposit && amount > currentGoal.currentAmount) {
          throw StateError(
            'Nominal pemakaian melebihi dana target yang tersedia.',
          );
        }
        await _database
            .into(_database.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: id,
                householdId: _householdId,
                type: 'expense',
                date: date,
                recordedAt: now,
                amount: -amount,
                owner: const Value('Keluarga'),
                note: Value(step.parameters['note']?.toString()),
                source: Value(isDeposit ? 'goal_contribution' : 'goal_usage'),
                accountId: Value(account.id),
                categoryId: Value(goal.categoryId),
                goalId: Value(currentGoal.id),
                createdAt: now,
                updatedAt: Value(now),
                isDeleted: const Value(false),
              ),
            );

        final newAmount = isDeposit
            ? currentGoal.currentAmount + amount
            : currentGoal.currentAmount - amount;

        final updated =
            await (_database.update(_database.goals)..where(
                  (row) =>
                      row.householdId.equals(_householdId) &
                      row.id.equals(currentGoal.id) &
                      row.currentAmount.equals(currentGoal.currentAmount),
                ))
                .write(GoalsCompanion(currentAmount: Value(newAmount)));
        if (updated != 1) {
          throw StateError('Saldo target berubah, silakan ulangi.');
        }
      });
    } on StateError catch (error) {
      return FfmAssistantCapabilityExecutionResult.failure(error.message);
    }

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

  String _formatDateIndonesian(DateTime value) {
    final months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    return '${value.day} ${months[value.month - 1]} ${value.year}';
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveCashFlowProfile(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final id = _stableId(idempotencyKey);
    final title =
        step.parameters['title']?.toString().trim() ??
        step.parameters['name']?.toString().trim() ??
        'Siklus Kas Baru';
    final commodity =
        step.parameters['commodityOrBusinessType']?.toString().trim() ??
        step.parameters['commodity']?.toString().trim() ??
        'Pertanian/Usaha';
    final initialCapital =
        _positiveInt(step.parameters['initialCapital']) ??
        _positiveInt(step.parameters['amount']) ??
        0;
    final estimatedInflow =
        _positiveInt(step.parameters['estimatedInflow']) ?? 0;
    final dailyLiving = _positiveInt(step.parameters['dailyLivingBudget']) ?? 0;
    final dailyOps =
        _positiveInt(step.parameters['dailyOperationalBudget']) ?? 0;

    DateTime targetHarvest;
    if (step.parameters['targetHarvestDate'] != null) {
      targetHarvest =
          DateTime.tryParse(step.parameters['targetHarvestDate'].toString()) ??
          _clock().add(const Duration(days: 90));
    } else {
      targetHarvest = _clock().add(const Duration(days: 90));
    }

    final rawType =
        step.parameters['cycleProfileType']?.toString().toLowerCase() ??
        'agriculture';
    final profileType = switch (rawType) {
      'business' || 'bisnis' => CashFlowProfileType.business,
      'freelance' => CashFlowProfileType.freelance,
      'salaried' || 'gaji' => CashFlowProfileType.salaried,
      _ => CashFlowProfileType.agriculture,
    };

    final profile = CashFlowProfile(
      id: id,
      householdId: _householdId,
      profileType: profileType,
      name: title,
      commodityOrBusinessType: commodity,
      startDate: _clock(),
      targetHarvestDate: targetHarvest,
      initialCapital: initialCapital,
      estimatedInflow: estimatedInflow,
      dailyLivingBudget: dailyLiving,
      dailyOperationalBudget: dailyOps,
      isActive: true,
    );

    CashFlowProfileRepository repo;
    if (getIt.isRegistered<CashFlowProfileRepository>()) {
      repo = getIt<CashFlowProfileRepository>();
    } else {
      repo = CashFlowProfileRepository();
    }
    await repo.saveProfile(profile);

    return FfmAssistantCapabilityExecutionResult.success(
      'Siklus Kas "$title" ($commodity) berhasil disimpan dan diaktifkan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifyCashFlowProfileSaved(
    String id,
  ) async {
    CashFlowProfileRepository repo;
    if (getIt.isRegistered<CashFlowProfileRepository>()) {
      repo = getIt<CashFlowProfileRepository>();
    } else {
      repo = CashFlowProfileRepository();
    }
    final profiles = await repo.getAllProfiles(_householdId);
    final found = profiles.where((p) => p.id == id).firstOrNull;
    if (found == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Verifikasi gagal: profil siklus kas belum ditemukan di data lokal.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'verified: siklus kas "${found.name}" berhasil diverifikasi di data lokal.',
    );
  }
}
