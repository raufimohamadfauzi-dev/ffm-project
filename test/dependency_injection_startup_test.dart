import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_chat_history_repository.dart';

void main() {
  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    if (getIt.isRegistered<AppDatabase>()) {
      await getIt<AppDatabase>().close();
    }
    await getIt.reset();
  });

  test('configureDependencies runs once in a clean process without failure', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await configureDependencies(database: db);

    expect(getIt.isRegistered<AppDatabase>(), isTrue);
    expect(getIt.isRegistered<FfmAssistantChatHistoryRepository>(), isTrue);
    expect(getIt<FfmAssistantChatHistoryRepository>(), isA<FfmAssistantChatHistoryRepository>());
  });

  test('configureDependencies is idempotent and does not throw on multiple calls', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await configureDependencies(database: db);
    // Second call should return early and not throw
    await configureDependencies(database: db);

    expect(getIt.isRegistered<FfmAssistantChatHistoryRepository>(), isTrue);
  });

  test('FfmAssistantChatHistoryRepository pre-registration does not cause duplicate error', () async {
    final customRepo = FfmAssistantChatHistoryRepository();
    getIt.registerSingleton<FfmAssistantChatHistoryRepository>(customRepo);

    final db = AppDatabase(NativeDatabase.memory());
    await configureDependencies(database: db);

    expect(getIt<FfmAssistantChatHistoryRepository>(), same(customRepo));
  });
}
