import 'package:get_it/get_it.dart';

import '../database/app_database.dart';
import '../database/audit_logger.dart';
import '../diagnostics/app_diagnostics_service.dart';
import '../security/app_pin_service.dart';
import '../theme/app_theme_controller.dart';
import '../../features/activity/data/repositories/activity_repository.dart';
import '../../features/activity/domain/services/activity_application_service.dart';
import '../../features/activity/presentation/bloc/activity_bloc.dart';
import '../../features/activity/domain/activity_query_layer.dart';
import '../../features/activity/domain/activity_analysis_engine.dart';
import '../../features/activity/domain/activity_verified_fact_layer.dart';
import '../../features/activity/domain/activity_mode_detector.dart';
import '../../features/advisor/domain/usecases/budget_guard_service.dart';
import '../../features/advisor/domain/services/smart_budget_engine.dart';
import '../../features/advisor/domain/services/smart_envelope_rebalance.dart';
import '../../features/assistant/data/ffm_assistant_capability_adapters.dart';
import '../../features/assistant/data/ffm_assistant_reminder_mutation_service.dart';
import '../../features/assistant/data/ffm_assistant_response_feedback_repository.dart';
import '../../features/assistant/data/calendar_bridge.dart';
import '../../features/assistant/data/ffm_assistant_interpreter.dart';

import '../../features/assistant/data/ffm_assistant_learning_repository.dart';
import '../../features/assistant/data/ffm_assistant_personalization_repository.dart';
import '../../features/assistant/data/ffm_assistant_local_memory.dart';
import '../../features/assistant/data/ffm_category_suggestion_service.dart';
import '../../features/assistant/data/ffm_activity_habit_learner.dart';
import '../../features/assistant/data/ffm_assistant_memory_repository.dart';
import '../../features/assistant/data/ffm_assistant_draft_feedback_service.dart';
import '../../features/assistant/data/ffm_assistant_intent_classification_service.dart';
import '../../features/assistant/data/ffm_personal_memory_service.dart';
import '../../features/assistant/data/ffm_memory_learning_service.dart';
import '../../features/assistant/data/ffm_memory_maintenance_service.dart';
import '../../features/assistant/data/ffm_error_logging_service.dart';
import '../../features/assistant/data/ffm_assistant_chat_history_repository.dart';
import '../../features/assistant/data/ffm_assistant_autonomy_repository.dart';
import '../../features/assistant/data/ffm_assistant_agent_task_plan_resolver.dart';
import '../../features/assistant/data/ffm_assistant_agent_task_event_handler.dart';
import '../../features/assistant/data/ffm_assistant_autonomy_trigger_service.dart';
import '../../features/assistant/data/ffm_assistant_autonomy_task_execution_host.dart';
import '../../features/assistant/data/ffm_assistant_autonomy_worker.dart';
import '../../features/assistant/data/ffm_assistant_autonomy_background_handler.dart';
import '../../features/assistant/data/nfc_bridge.dart';
import '../../features/assistant/data/nfc_card_repository.dart';
import '../../features/assistant/data/ffm_assistant_autonomy_background_scheduler.dart';
import '../../features/assistant/data/ffm_assistant_foreground_service.dart';
import '../../features/assistant/data/ffm_assistant_proactive_evaluation_task.dart';
import '../../features/assistant/data/ffm_assistant_user_model_service.dart';
import '../../features/assistant/data/ffm_personal_context_provider.dart';
import '../../features/assistant/data/ffm_assistant_report_service.dart';
import '../../features/assistant/data/ffm_assistant_unanswered_question_repository.dart';
import '../../features/assistant/data/telegram_bot_service.dart';
import '../../features/assistant/data/telegram_config_repository.dart';
import '../../features/assistant/data/ffm_assistant_insight_repository.dart';
import '../../features/assistant/data/payment_draft_repository.dart';
import '../../features/assistant/data/notification_listener_bridge.dart';
import '../../features/advisor/data/cash_flow_profile_repository.dart';
import '../../features/advisor/domain/services/proactive_cash_flow_checkin_service.dart';
import '../../features/advisor/domain/usecases/flexible_cash_flow_calculator.dart';
import '../../features/assistant/data/habit_pattern_repository.dart';
import '../../features/assistant/domain/services/transaction_pattern_miner.dart';
import '../../features/assistant/domain/services/executive_morning_briefing_service.dart';
import '../../features/assistant/domain/services/ffm_follow_up_suggestion_engine.dart';
import '../../features/assistant/data/autonomous_activity_repository.dart';
import '../../features/settings/data/utility_meter_repository.dart';
import '../../features/settings/data/vehicle_repository.dart';
import '../../features/assistant/domain/autonomous_evaluation_coordinator.dart';
import '../../features/assistant/domain/assistant_onboarding_orchestrator.dart';
import '../../features/assistant/domain/ffm_proactive_delivery_policy.dart';
import '../../features/backup/data/json_export_studio_service.dart';
import '../../features/asset/domain/usecases/asset_crud_usecases.dart';
import '../../features/asset/data/repositories/market_news_cache_repository.dart';
import '../../features/asset/data/services/market_news_radar_service.dart';
import '../../features/asset/domain/usecases/asset_auto_valuation_service.dart';
import '../../features/audit/data/repositories/audit_log_repository.dart';
import '../../features/audit/domain/usecases/audit_log_usecases.dart';
import '../../features/goal/domain/usecases/goal_balance_usecases.dart';
import '../../features/goal/domain/usecases/goal_crud_usecases.dart';
import '../../features/hijri/domain/hijri_calendar_service.dart';
import '../../features/liability/domain/services/debt_payoff_strategist_service.dart';
import '../../features/liability/domain/usecases/liability_crud_usecases.dart';
import '../../features/liability/domain/usecases/process_debt_payment.dart';
import '../../features/receivable/domain/usecases/receivable_crud_usecases.dart';
import '../../features/recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';
import '../../features/reminder/data/repositories/reminder_repository.dart';
import '../../features/reminder/data/services/reminder_notification_service.dart';
import '../../features/reminder/data/services/reminder_sound_picker.dart';
import '../../features/reminder/domain/usecases/reminder_usecases.dart';
import '../../features/reminder/presentation/bloc/reminder_bloc.dart';
import '../../features/settings/data/category_repository.dart';
import '../../features/transaction/data/services/offline_ai_engine_service.dart';
import '../../features/transaction/domain/usecases/transaction_crud_usecases.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies({AppDatabase? database}) async {
  if (getIt.isRegistered<AppDatabase>()) return;
  final db = database ?? AppDatabase.openDefault();
  getIt.registerSingleton<AppDatabase>(db);
  getIt.registerLazySingleton<AppDiagnosticsService>(AppDiagnosticsService.new);
  getIt.registerLazySingleton<AppPinService>(AppPinService.new);
  getIt.registerLazySingleton<AppThemeController>(AppThemeController.new);
  getIt.registerLazySingleton<GetTransactions>(() => GetTransactions(db));
  getIt.registerLazySingleton<BudgetGuardService>(() => BudgetGuardService(db));
  getIt.registerLazySingleton<AuditLogRepository>(
    () => SqliteAuditLogRepository(db),
  );
  getIt.registerLazySingleton<GetAuditLogs>(
    () => GetAuditLogs(getIt<AuditLogRepository>()),
  );
  getIt.registerLazySingleton<GetTransaction>(() => GetTransaction(db));
  getIt.registerLazySingleton<SaveTransaction>(
    () => SaveTransaction(
      db,
      autonomyTrigger: getIt<FfmAssistantAutonomyTriggerService>(),
      telegramBotService: getIt<TelegramBotService>(),
      telegramConfigRepository: getIt<TelegramConfigRepository>(),
    ),
  );
  getIt.registerLazySingleton<SaveTransactionBatch>(
    () => SaveTransactionBatch(
      db,
      autonomyTrigger: getIt<FfmAssistantAutonomyTriggerService>(),
    ),
  );
  getIt.registerLazySingleton<SaveMixedTransactionBatch>(
    () => SaveMixedTransactionBatch(
      db,
      autonomyTrigger: getIt<FfmAssistantAutonomyTriggerService>(),
    ),
  );
  getIt.registerLazySingleton<DeleteTransaction>(() => DeleteTransaction(db));
  getIt.registerLazySingleton<GetAssets>(() => GetAssets(db));
  getIt.registerLazySingleton<SaveAsset>(() => SaveAsset(db));
  getIt.registerLazySingleton<ArchiveAsset>(() => ArchiveAsset(db));
  getIt.registerLazySingleton<MarketNewsRadarService>(
    MarketNewsRadarService.new,
  );
  getIt.registerLazySingleton<MarketNewsCacheRepository>(
    MarketNewsCacheRepository.new,
  );
  getIt.registerLazySingleton<AssetAutoValuationService>(
    () => AssetAutoValuationService(db),
  );
  getIt.registerLazySingleton<GetGoals>(() => GetGoals(db));
  getIt.registerLazySingleton<GetGoal>(() => GetGoal(db));
  getIt.registerLazySingleton<SaveGoal>(() => SaveGoal(db));
  getIt.registerLazySingleton<SyncGoalBalance>(() => SyncGoalBalance(db));
  getIt.registerLazySingleton<GetLiabilities>(() => GetLiabilities(db));
  getIt.registerLazySingleton<SaveLiability>(() => SaveLiability(db));
  getIt.registerLazySingleton<DeleteLiability>(() => DeleteLiability(db));
  getIt.registerLazySingleton<ProcessDebtPayment>(() => ProcessDebtPayment(db));
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
  getIt.registerLazySingleton<CategoryRepository>(
    () => CategoryRepository(db, getIt<AuditLogger>()),
  );
  getIt.registerLazySingleton<ActivityRepository>(
    () => ActivityRepository(
      db,
      getIt<AuditLogger>(),
      habitLearner: getIt<FfmActivityHabitLearner>(),
      autonomyTrigger: getIt<FfmAssistantAutonomyTriggerService>(),
    ),
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
  // Activity Intelligence Upgrade services
  getIt.registerLazySingleton<ActivityQueryLayer>(() => ActivityQueryLayer(db));
  getIt.registerLazySingleton<ActivityAnalysisEngine>(
    () => ActivityAnalysisEngine(getIt<ActivityQueryLayer>()),
  );
  getIt.registerLazySingleton<ActivityVerifiedFactLayer>(
    () => ActivityVerifiedFactLayer(getIt<ActivityAnalysisEngine>()),
  );
  getIt.registerLazySingleton<ActivityModeDetector>(ActivityModeDetector.new);
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
      autonomyTrigger: getIt<FfmAssistantAutonomyTriggerService>(),
    ),
  );
  getIt.registerLazySingleton<OfflineAiEngineService>(
    OfflineAiEngineService.new,
  );
  getIt.registerLazySingleton<FfmAssistantLocalMemory>(
    FfmAssistantLocalMemory.new,
  );
  getIt.registerLazySingleton<FfmAssistantMemoryRepository>(
    () => FfmAssistantMemoryRepository(db),
  );
  getIt.registerLazySingleton<FfmErrorLoggingService>(
    FfmErrorLoggingService.new,
  );
  getIt.registerLazySingleton<FfmMemoryLearningService>(
    () => FfmMemoryLearningService(
      memoryRepository: getIt<FfmAssistantMemoryRepository>(),
    ),
  );
  getIt.registerLazySingleton<FfmMemoryMaintenanceService>(
    () => FfmMemoryMaintenanceService(
      learning: getIt<FfmMemoryLearningService>(),
      repository: getIt<FfmAssistantMemoryRepository>(),
    ),
  );
  if (!getIt.isRegistered<FfmAssistantChatHistoryRepository>()) {
    getIt.registerLazySingleton<FfmAssistantChatHistoryRepository>(
      FfmAssistantChatHistoryRepository.new,
    );
  }
  getIt.registerLazySingleton<FfmAssistantAutonomyRepository>(
    () => FfmAssistantAutonomyRepository(db),
  );
  getIt.registerLazySingleton<AutonomousActivityRepository>(
    () => AutonomousActivityRepository(
      database: db,
      vehicleRepository: getIt.isRegistered<VehicleRepository>()
          ? getIt<VehicleRepository>()
          : VehicleRepository(),
      meterRepository: getIt.isRegistered<UtilityMeterRepository>()
          ? getIt<UtilityMeterRepository>()
          : UtilityMeterRepository(),
      cashFlowProfileRepository: getIt.isRegistered<CashFlowProfileRepository>()
          ? getIt<CashFlowProfileRepository>()
          : CashFlowProfileRepository(),
    ),
  );
  getIt.registerLazySingleton<HabitPatternRepository>(
    () => HabitPatternRepository(),
  );
  getIt.registerLazySingleton<TransactionPatternMiner>(
    () => TransactionPatternMiner(db),
  );
  getIt.registerLazySingleton<ExecutiveMorningBriefingService>(
    () => ExecutiveMorningBriefingService(
      database: db,
      patternMiner: getIt<TransactionPatternMiner>(),
    ),
  );
  getIt.registerLazySingleton<DebtPayoffStrategistService>(
    () => DebtPayoffStrategistService(db),
  );
  getIt.registerLazySingleton<FfmAssistantAutonomyTriggerService>(
    () => FfmAssistantAutonomyTriggerService(
      getIt<FfmAssistantAutonomyRepository>(),
    ),
  );
  getIt.registerLazySingleton<FfmAssistantAgentTaskPlanResolver>(
    () => FfmAssistantAgentTaskPlanResolver(
      getIt<FfmAssistantAutonomyRepository>(),
    ),
  );
  getIt.registerLazySingleton<FfmAssistantProactiveEvaluationTask>(
    () => FfmAssistantProactiveEvaluationTask(
      db,
      getIt<FfmAssistantChatHistoryRepository>(),
    ),
  );
  getIt.registerLazySingleton<FfmAssistantAutonomyWorker>(
    () => FfmAssistantAutonomyWorker(
      repository: getIt<FfmAssistantAutonomyRepository>(),
    ),
  );
  getIt.registerLazySingleton<FfmAssistantAutonomyTaskExecutionHost>(
    () => FfmAssistantAutonomyTaskExecutionHost(
      database: db,
      repository: getIt<FfmAssistantAutonomyRepository>(),
      adapters: getIt<FfmAssistantCapabilityAdapterRegistry>(),
    ),
  );
  getIt.registerLazySingleton<FfmAssistantAgentTaskEventHandler>(
    () => FfmAssistantAgentTaskEventHandler(
      repository: getIt<FfmAssistantAutonomyRepository>(),
      resolver: getIt<FfmAssistantAgentTaskPlanResolver>(),
      executePlan: getIt<FfmAssistantAutonomyTaskExecutionHost>().execute,
    ),
  );
  getIt.registerLazySingleton<FfmAssistantAutonomyBackgroundScheduler>(
    FfmAssistantAutonomyBackgroundScheduler.new,
  );
  getIt.registerLazySingleton<FfmAssistantForegroundServiceManager>(
    FfmAssistantForegroundServiceManager.new,
  );
  getIt.registerLazySingleton<FfmProactiveDeliveryPolicy>(
    FfmProactiveDeliveryPolicy.new,
  );
  getIt.registerLazySingleton<TelegramBotService>(TelegramBotService.new);
  getIt.registerLazySingleton<TelegramConfigRepository>(
    TelegramConfigRepository.new,
  );
  // Fitur 02: Pendeteksi Notifikasi QRIS & Bank
  getIt.registerLazySingleton<PaymentDraftRepository>(
    PaymentDraftRepository.new,
  );
  getIt.registerLazySingleton<NotificationListenerBridge>(
    () => NotificationListenerBridge(getIt<PaymentDraftRepository>()),
  );
  // Fitur #1: Pembaca NFC e-Money & Adaptasi Saldo
  getIt.registerLazySingleton<NfcBridge>(NfcBridge.new);
  getIt.registerLazySingleton<NfcCardRepository>(
    () => NfcCardRepository(
      getIt<PaymentDraftRepository>(),
      database: getIt<AppDatabase>(),
    ),
  );
  // Smart Budget Engine & Envelope Rebalance
  getIt.registerLazySingleton<SmartBudgetEngine>(SmartBudgetEngine.new);
  getIt.registerLazySingleton<SmartEnvelopeRebalance>(SmartEnvelopeRebalance.new);
  // Fitur 03: Model Arus Kas Fleksibel & Siklus Pertanian / Musiman / Bisnis
  getIt.registerLazySingleton<CashFlowProfileRepository>(
    CashFlowProfileRepository.new,
  );
  getIt.registerLazySingleton<FlexibleCashFlowCalculator>(
    FlexibleCashFlowCalculator.new,
  );
  // Buku Saku Meteran & Token Listrik PLN
  getIt.registerLazySingleton<UtilityMeterRepository>(
    UtilityMeterRepository.new,
  );
  // Buku Saku Kendaraan & Log BBM
  getIt.registerLazySingleton<VehicleRepository>(
    VehicleRepository.new,
  );
  // Saran Pertanyaan Lanjutan Adaptif (💡) & Wawancara Proaktif Usaha/Tani
  getIt.registerLazySingleton<ProactiveCashFlowCheckInService>(
    () => ProactiveCashFlowCheckInService(getIt<CashFlowProfileRepository>()),
  );
  getIt.registerLazySingleton<FfmFollowUpSuggestionEngine>(
    FfmFollowUpSuggestionEngine.new,
  );
  getIt.registerLazySingleton<AutonomousEvaluationCoordinator>(
    () => AutonomousEvaluationCoordinator(
      database: db,
      insightRepository: FfmAssistantInsightRepository(db),
      notificationService: getIt<ReminderNotificationService>(),
      deliveryPolicy: getIt<FfmProactiveDeliveryPolicy>(),
      telegramBotService: getIt<TelegramBotService>(),
      telegramConfigRepository: getIt<TelegramConfigRepository>(),
    ),
  );
  getIt.registerLazySingleton<FfmAssistantAutonomyBackgroundEventHandler>(
    () => FfmAssistantAutonomyBackgroundEventHandler(
      getIt<FfmAssistantAgentTaskEventHandler>(),
      getIt<AutonomousEvaluationCoordinator>(),
    ),
  );
  getIt.registerLazySingleton<FfmAssistantUserModelService>(
    () => FfmAssistantUserModelService(getIt<FfmAssistantMemoryRepository>()),
  );
  getIt.registerLazySingleton<FfmAssistantDraftFeedbackService>(
    FfmAssistantDraftFeedbackService.new,
  );
  getIt.registerLazySingleton<FfmAssistantIntentClassificationService>(
    FfmAssistantIntentClassificationService.new,
  );
  getIt.registerLazySingleton<FfmPersonalMemoryService>(
    () => FfmPersonalMemoryService(
      getIt<FfmAssistantMemoryRepository>(),
      getIt<FfmAssistantDraftFeedbackService>(),
    ),
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

  getIt.registerLazySingleton<FfmAssistantCapabilityAdapterRegistry>(
    () => FfmAssistantCapabilityAdapterRegistry(
      database: db,
      householdId: 'local-household',
      reminderMutations: FfmAssistantReminderMutationService(
        repository: getIt<ReminderRepository>(),
        notificationGateway: getIt<ReminderNotificationService>(),
        occurrenceCalculator: getIt<ReminderOccurrenceCalculator>(),
        calendarBridge: CalendarBridge(),
      ),
      habitLearner: getIt<FfmActivityHabitLearner>(),
      personalization: getIt<FfmAssistantPersonalizationRepository>(),
      themeController: getIt<AppThemeController>(),
    ),
  );
  getIt.registerLazySingleton<FfmActivityHabitLearner>(
    () => FfmActivityHabitLearner(db, getIt<FfmAssistantMemoryRepository>()),
  );
  getIt.registerLazySingleton<FfmCategorySuggestionService>(
    () => FfmCategorySuggestionService(
      database: db,
      personalization: getIt<FfmAssistantPersonalizationRepository>(),
    ),
  );
  getIt.registerLazySingleton<FfmAssistantInterpreter>(
    () => FfmAssistantInterpreter(
      db,
      memory: getIt<FfmAssistantLocalMemory>(),
      diagnostics: getIt<AppDiagnosticsService>(),
      taughtMemory: getIt<FfmAssistantMemoryRepository>(),
      personalization: getIt<FfmAssistantPersonalizationRepository>(),
      personalContextProvider: () => FfmPersonalContextProvider.maybeInstance,
      categorySuggestion: getIt<FfmCategorySuggestionService>(),
      themeController: getIt<AppThemeController>(),
      marketCache: getIt<MarketNewsCacheRepository>(),
    ),
  );
  getIt.registerLazySingleton<JsonExportStudioService>(
    () => JsonExportStudioService(db),
  );
  getIt.registerLazySingleton<FfmAssistantReportService>(
    () => FfmAssistantReportService(getIt<JsonExportStudioService>()),
  );
  getIt.registerLazySingleton<AssistantOnboardingOrchestrator>(
    () => AssistantOnboardingOrchestrator(database: db),
  );
}
