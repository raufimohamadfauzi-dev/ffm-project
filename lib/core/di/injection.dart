import 'package:get_it/get_it.dart';

import '../database/app_database.dart';
import '../../features/asset/domain/usecases/asset_crud_usecases.dart';
import '../../features/goal/domain/usecases/goal_crud_usecases.dart';
import '../../features/hijri/domain/hijri_calendar_service.dart';
import '../../features/liability/domain/usecases/liability_crud_usecases.dart';
import '../../features/receivable/domain/usecases/receivable_crud_usecases.dart';
import '../../features/recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';
import '../../features/transaction/data/services/offline_ai_engine_service.dart';
import '../../features/transaction/domain/usecases/transaction_crud_usecases.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies({AppDatabase? database}) async {
  if (getIt.isRegistered<AppDatabase>()) return;
  final db = database ?? AppDatabase.openDefault();
  getIt.registerSingleton<AppDatabase>(db);
  getIt.registerLazySingleton<GetTransactions>(() => GetTransactions(db));
  getIt.registerLazySingleton<GetTransaction>(() => GetTransaction(db));
  getIt.registerLazySingleton<SaveTransaction>(() => SaveTransaction(db));
  getIt.registerLazySingleton<DeleteTransaction>(() => DeleteTransaction(db));
  getIt.registerLazySingleton<GetAssets>(() => GetAssets(db));
  getIt.registerLazySingleton<SaveAsset>(() => SaveAsset(db));
  getIt.registerLazySingleton<DeleteAsset>(() => DeleteAsset(db));
  getIt.registerLazySingleton<GetGoals>(() => GetGoals(db));
  getIt.registerLazySingleton<GetGoal>(() => GetGoal(db));
  getIt.registerLazySingleton<SaveGoal>(() => SaveGoal(db));
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
  getIt.registerLazySingleton<OfflineAiEngineService>(
    OfflineAiEngineService.new,
  );
}
