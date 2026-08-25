import 'package:get_it/get_it.dart';

import '../database/app_database.dart';
import '../database/audit_logger.dart';
import '../diagnostics/app_diagnostics_service.dart';
import '../security/app_pin_service.dart';
import '../../features/activity/data/repositories/activity_repository.dart';
import '../../features/activity/domain/services/activity_application_service.dart';
import '../../features/activity/presentation/bloc/activity_bloc.dart';
import '../../features/daily_notes/data/daily_note_repository.dart';
import '../../features/tasks/data/task_repository.dart';
import '../../features/routines/data/routine_repository.dart';
import '../../features/schedule/data/schedule_repository.dart';
import '../../features/advisor/domain/usecases/budget_guard_service.dart';
import '../../features/assistant/data/ffm_assistant_capability_adapters.dart';
import '../../features/assistant/data/ffm_assistant_reminder_mutation_service.dart';
import '../../features/assistant/data/ffm_assistant_response_feedback_repository.dart';
import '../../features/assistant/data/ffm_assistant_interpreter.dart';
import '../../features/assistant/data/ffm_assistant_knowledge_pack_service.dart';
import '../../features/assistant/data/ffm_assistant_learning_repository.dart';
import '../../features/assistant/data/ffm_assistant_personalization_repository.dart';
import '../../features/assistant/data/ffm_assistant_local_memory.dart';
import '../../features/assistant/data/ffm_assistant_local_model_gateway.dart';
import '../../features/assistant/data/ffm_assistant_answer_composer.dart';
import '../../features/assistant/data/ffm_category_suggestion_service.dart';
import '../../features/assistant/data/ffm_activity_habit_learner.dart';
import '../../features/assistant/data/ffm_assistant_slm_follow_up_service.dart';
import '../../features/assistant/data/ffm_local_inference_queue.dart';
import '../../features/assistant/data/ffm_qwen2vl_inference_service.dart';
import '../../features/assistant/data/ffm_qwen2vl_gateway.dart';
import '../../features/assistant/data/ffm_assistant_memory_repository.dart';
import '../../features/assistant/data/ffm_memory_learning_service.dart';
import '../../features/assistant/data/ffm_error_logging_service.dart';
import '../../features/assistant/data/ffm_slm_health_monitor.dart';
import '../../features/assistant/data/ffm_assistant_chat_history_repository.dart';
import '../../features/assistant/data/ffm_assistant_user_model_service.dart';
import '../../features/assistant/data/ffm_personal_memory_service.dart';
import '../../features/assistant/data/ffm_personal_context_provider.dart';
import '../../features/assistant/data/ffm_assistant_report_service.dart';
import '../../features/assistant/data/ffm_assistant_unanswered_question_repository.dart';
import '../../features/assistant/data/ffm_local_model_service.dart';
import '../../features/backup/data/json_export_studio_service.dart';
import '../../features/asset/domain/usecases/asset_crud_usecases.dart';
import '../../features/audit/data/repositories/audit_log_repository.dart';
import '../../features/audit/domain/usecases/audit_log_usecases.dart';
import '../../features/goal/domain/usecases/goal_balance_usecases.dart';
import '../../features/goal/domain/usecases/goal_crud_usecases.dart';
import '../../features/hijri/domain/hijri_calendar_service.dart';
import '../../features/liability/domain/usecases/liability_crud_usecases.dart';
import '../../features/receivable/domain/usecases/receivable_crud_usecases.dart';
import '../../features/recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';
import '../../features/reminder/data/repositories/reminder_repository.dart';
import '../../features/reminder/data/services/reminder_notification_service.dart';
import '../../features/reminder/data/services/reminder_sound_picker.dart';
import '../../features/reminder/domain/usecases/reminder_usecases.dart';
import '../../features/reminder/presentation/bloc/reminder_bloc.dart';
import '../../features/transaction/data/services/offline_ai_engine_service.dart';
import '../../features/transaction/domain/usecases/transaction_crud_usecases.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies({AppDatabase? database}) async {
  if (getIt.isRegistered<AppDatabase>()) return;
  final db = database ?? AppDatabase.openDefault();
  getIt.registerSingleton<AppDatabase>(db);
  getIt.registerLazySingleton<AppDiagnosticsService>(AppDiagnosticsService.new);
  getIt.registerLazySingleton<AppPinService>(AppPinService.new);
  getIt.registerLazySingleton<GetTransactions>(() => GetTransactions(db));
  getIt.registerLazySingleton<BudgetGuardService>(() => BudgetGuardService(db));
  getIt.registerLazySingleton<AuditLogRepository>(
    () => SqliteAuditLogRepository(db),
  );
  getIt.registerLazySingleton<GetAuditLogs>(
    () => GetAuditLogs(getIt<AuditLogRepository>()),
  );
  getIt.registerLazySingleton<GetTransaction>(() => GetTransaction(db));
  getIt.registerLazySingleton<SaveTransaction>(() => SaveTransaction(db));
  getIt.registerLazySingleton<SaveTransactionBatch>(
    () => SaveTransactionBatch(db),
  );
  getIt.registerLazySingleton<SaveMixedTransactionBatch>(
    () => SaveMixedTransactionBatch(db),
  );
  getIt.registerLazySingleton<DeleteTransaction>(() => DeleteTransaction(db));
  getIt.registerLazySingleton<GetAssets>(() => GetAssets(db));
  getIt.registerLazySingleton<SaveAsset>(() => SaveAsset(db));
  getIt.registerLazySingleton<ArchiveAsset>(() => ArchiveAsset(db));
  getIt.registerLazySingleton<GetGoals>(() => GetGoals(db));
  getIt.registerLazySingleton<GetGoal>(() => GetGoal(db));
  getIt.registerLazySingleton<SaveGoal>(() => SaveGoal(db));
  getIt.registerLazySingleton<SyncGoalBalance>(() => SyncGoalBalance(db));
  getIt.registerLazySingleton<GetLiabilities>(() => GetLiabilities(db));
  getIt.registerLazySingleton<SaveLiability>(() => SaveLiability(db));
  getIt.registerLazySingleton<GetReceivables>(() => GetReceivables(db));
  getIt.registerLazySingleton<SaveReceivable>(() => SaveReceivable(db));
  getIt.registerLazySingleton<DeleteReceivable>(() => DeleteReceivable(db));
  getIt.registerLazySingleton<GetRecurringTransactions>(
    () => GetRecurringTransactions(db),
  );
  getIt.registerLazySingleton<CreateRecurringTransaction>(
    () => CreateRecurringTransaction(db),
  );
  getIt.registerLazySingleton<UpdateRecurringTransaction>(
    () => UpdateRecurringTransaction(db),
  );
  getIt.registerLazySingleton<ArchiveRecurringTransaction>(
    () => ArchiveRecurringTransaction(db),
  );
  getIt.registerLazySingleton<ProcessRecurringTransactions>(
    () => ProcessRecurringTransactions(db),
  );
  getIt.registerLazySingleton<GetAccountBookBalance>(
    () => GetAccountBookBalance(db),
  );
  getIt.registerLazySingleton<CreateReconciliationLog>(
    () => CreateReconciliationLog(db),
  );
  getIt.registerLazySingleton<GetReconciliationHistory>(
    () => GetReconciliationHistory(db),
  );
  getIt.registerLazySingleton<HijriCalendarService>(
    () => HijriCalendarService(db),
  );
  getIt.registerLazySingleton<AuditLogger>(() => AuditLogger(db));
  getIt.registerLazySingleton<ActivityRepository>(
    () => ActivityRepository(
      db,
      getIt<AuditLogger>(),
      habitLearner: getIt<FfmActivityHabitLearner>(),
    ),
  );
  getIt.registerLazySingleton<DailyNoteRepository>(
    () => DailyNoteRepository(db, getIt<AuditLogger>()),
  );
  getIt.registerLazySingleton<TaskRepository>(
    () => TaskRepository(db, getIt<AuditLogger>()),
  );
  getIt.registerLazySingleton<RoutineRepository>(
    () => RoutineRepository(db, getIt<AuditLogger>()),
  );
  getIt.registerLazySingleton<ScheduleRepository>(
    () => ScheduleRepository(db, getIt<AuditLogger>()),
  );
  // ActivityBloc as LazySingleton so it can be shared with ActivityApplicationService
  getIt.registerLazySingleton<ActivityBloc>(
    () => ActivityBloc(getIt<ActivityRepository>()),
  );
  getIt.registerLazySingleton<ActivityApplicationService>(
    () => ActivityApplicationService(
      repository: getIt<ActivityRepository>(),
      activityBloc: getIt<ActivityBloc>(),
    ),
  );
  getIt.registerLazySingleton<ReminderRepository>(() => ReminderRepository(db));
  getIt.registerLazySingleton<ReminderOccurrenceCalculator>(
    ReminderOccurrenceCalculator.new,
  );
  getIt.registerLazySingleton<ReminderNotificationService>(
    ReminderNotificationService.new,
  );
  getIt.registerLazySingleton<ReminderSoundPicker>(
    AndroidReminderSoundPicker.new,
  );
  getIt.registerLazySingleton<ReminderBloc>(
    () => ReminderBloc(
      repository: getIt<ReminderRepository>(),
      notificationService: getIt<ReminderNotificationService>(),
      occurrenceCalculator: getIt<ReminderOccurrenceCalculator>(),
      householdId: 'local-household',
    ),
  );
  getIt.registerLazySingleton<OfflineAiEngineService>(
    OfflineAiEngineService.new,
  );
  getIt.registerLazySingleton<FfmAssistantLocalMemory>(
    FfmAssistantLocalMemory.new,
  );
  getIt.registerLazySingleton<FfmLocalModelService>(FfmLocalModelService.new);
  getIt.registerLazySingleton<FfmSingleInferenceQueue>(
    FfmSingleInferenceQueue.new,
  );
  getIt.registerLazySingleton<FfmQwen2VlInferenceService>(
    () => FfmQwen2VlInferenceService(
      getIt<FfmSingleInferenceQueue>(),
      healthMonitor: getIt<FfmSlmHealthMonitor>(),
    ),
  );
  getIt.registerLazySingleton<FfmQwen2VlGateway>(
    () => FfmQwen2VlGateway(
      getIt<FfmLocalModelService>(),
      getIt<FfmQwen2VlInferenceService>(),
      errorLogger: getIt<FfmErrorLoggingService>(),
    ),
  );
  getIt.registerLazySingleton<FfmAssistantLocalModelGateway>(
    () => getIt<FfmQwen2VlGateway>(),
  );
  getIt.registerLazySingleton<FfmAssistantAnswerComposer>(
    () => getIt<FfmQwen2VlGateway>(),
  );
  getIt.registerLazySingleton<FfmAssistantSlmFollowUpService>(
    () => FfmAssistantSlmFollowUpService(getIt<FfmQwen2VlGateway>()),
  );
  getIt.registerLazySingleton<FfmAssistantMemoryRepository>(
    () => FfmAssistantMemoryRepository(db),
  );
  getIt.registerLazySingleton<FfmSlmHealthMonitor>(
    FfmSlmHealthMonitor.new,
  );
  getIt.registerLazySingleton<FfmErrorLoggingService>(
    FfmErrorLoggingService.new,
  );
  getIt.registerLazySingleton<FfmMemoryLearningService>(
    () => FfmMemoryLearningService(
      memoryRepository: getIt<FfmAssistantMemoryRepository>(),
    ),
  );
  getIt.registerLazySingleton<FfmAssistantChatHistoryRepository>(
    FfmAssistantChatHistoryRepository.new,
  );
  getIt.registerLazySingleton<FfmAssistantUserModelService>(
    () => FfmAssistantUserModelService(getIt<FfmAssistantMemoryRepository>()),
  );
  getIt.registerLazySingleton<FfmPersonalMemoryService>(
    () => FfmPersonalMemoryService(getIt<FfmAssistantMemoryRepository>()),
  );
  getIt.registerLazySingleton<FfmAssistantLearningRepository>(
    () => FfmAssistantLearningRepository(db),
  );
  getIt.registerLazySingleton<FfmAssistantResponseFeedbackRepository>(
    () => FfmAssistantResponseFeedbackRepository(db),
  );
  getIt.registerLazySingleton<FfmAssistantUnansweredQuestionRepository>(
    () => FfmAssistantUnansweredQuestionRepository(db),
  );
  getIt.registerLazySingleton<FfmAssistantPersonalizationRepository>(
    () => FfmAssistantPersonalizationRepository(db),
  );
  getIt.registerLazySingleton<FfmAssistantKnowledgePackService>(
    () =>
        FfmAssistantKnowledgePackService(getIt<FfmAssistantMemoryRepository>()),
  );
  getIt.registerLazySingleton<FfmAssistantCapabilityAdapterRegistry>(
    () => FfmAssistantCapabilityAdapterRegistry(
      database: db,
      householdId: 'local-household',
      reminderMutations: FfmAssistantReminderMutationService(
        repository: getIt<ReminderRepository>(),
        notificationGateway: getIt<ReminderNotificationService>(),
        occurrenceCalculator: getIt<ReminderOccurrenceCalculator>(),
      ),
      habitLearner: getIt<FfmActivityHabitLearner>(),
      personalization: getIt<FfmAssistantPersonalizationRepository>(),
    ),
  );
  getIt.registerLazySingleton<FfmActivityHabitLearner>(
    () => FfmActivityHabitLearner(db, getIt<FfmAssistantMemoryRepository>()),
  );
  getIt.registerLazySingleton<FfmCategorySuggestionService>(
    () => FfmCategorySuggestionService(
      database: db,
      personalization: getIt<FfmAssistantPersonalizationRepository>(),
      advisor: getIt<FfmQwen2VlGateway>(),
    ),
  );
  getIt.registerLazySingleton<FfmAssistantInterpreter>(
    () => FfmAssistantInterpreter(
      db,
      memory: getIt<FfmAssistantLocalMemory>(),
      modelGateway: getIt<FfmAssistantLocalModelGateway>(),
      diagnostics: getIt<AppDiagnosticsService>(),
      taughtMemory: getIt<FfmAssistantMemoryRepository>(),
      personalization: getIt<FfmAssistantPersonalizationRepository>(),
      personalContextProvider: () => FfmPersonalContextProvider.maybeInstance,
      slmReadyCheck: () async =>
          await getIt<FfmLocalModelService>().getInstalled() != null,
      answerComposer: getIt<FfmAssistantAnswerComposer>(),
      categorySuggestion: getIt<FfmCategorySuggestionService>(),
    ),
  );
  getIt.registerLazySingleton<JsonExportStudioService>(
    () => JsonExportStudioService(db),
  );
  getIt.registerLazySingleton<FfmAssistantReportService>(
    () => FfmAssistantReportService(getIt<JsonExportStudioService>()),
  );
}
