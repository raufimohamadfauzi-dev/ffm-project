import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/settings/data/category_repository.dart';

// Helper function for creating in-memory database
AppDatabase createInMemoryDatabaseForTests() =>
    AppDatabase(NativeDatabase.memory());

void main() {
  tearDown(() async {
    // Reset GetIt instance after each test
    if (getIt.isRegistered<AppDatabase>()) {
      final db = getIt<AppDatabase>();
      await db.close();
    }
    getIt.reset();
  });

  test('CategoryRepository should be registered in GetIt', () async {
    // Configure dependencies with in-memory database
    final db = createInMemoryDatabaseForTests();
    await configureDependencies(database: db);

    // Verify CategoryRepository is registered
    expect(getIt.isRegistered<CategoryRepository>(), true);

    // Verify we can get the instance
    final repository = getIt<CategoryRepository>();
    expect(repository, isA<CategoryRepository>());
  });

  test('CategoryRepository should be available after AuditLogger registration', () async {
    final db = createInMemoryDatabaseForTests();
    await configureDependencies(database: db);

    // Both should be registered
    expect(getIt.isRegistered<CategoryRepository>(), true);
    expect(getIt.isRegistered<AuditLogger>(), true);
  });
}
