import 'package:get_it/get_it.dart';

import '../database/app_database.dart';
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
  getIt.registerLazySingleton<GetTransactions>(() => GetTransactions(db));
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
  getIt.registerFactory<ReminderBloc>(
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
}
