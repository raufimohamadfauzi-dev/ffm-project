import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/features/activity/presentation/pages/activity_page.dart';
import 'package:ffm_manager/features/activity/domain/entities/activity_entity.dart';
import 'package:ffm_manager/features/activity/data/repositories/activity_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase(NativeDatabase.memory());
    await configureDependencies(database: database);
  });

  tearDown(() async {
    await getIt.reset();
    await database.close();
  });

  testWidgets('Smart routine empty state renders with routine chips when sessions empty', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: ActivityPage(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify empty state is rendered with time-based recommendation
    expect(find.byType(ActionChip), findsWidgets);
    expect(find.text('Atau buat aktivitas baru bebas'), findsOneWidget);
  });

  testWidgets('Active session older than 8 hours displays Zombie Timer warning banner', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final activityRepo = getIt<ActivityRepository>();
    // Create a zombie session started 10 hours ago
    final zombieStarted = DateTime.now().subtract(const Duration(hours: 10));
    final zombieSession = ActivitySessionEntity(
      id: 'zombie_1',
      householdId: AppContext.householdId,
      title: 'Kerja Lembur Tak Terpantau',
      category: 'Pekerjaan',
      kind: ActivityKind.timer,
      status: ActivitySessionStatus.active,
      startedAt: zombieStarted,
      createdAt: zombieStarted,
      updatedAt: zombieStarted,
    );
    await activityRepo.saveSession(zombieSession);

    await tester.pumpWidget(
      const MaterialApp(
        home: ActivityPage(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify zombie timer warning banner is displayed
    expect(find.textContaining('Deteksi Timer Zombie'), findsOneWidget);
    expect(find.text('Hentikan Sekarang'), findsOneWidget);
  });
}
