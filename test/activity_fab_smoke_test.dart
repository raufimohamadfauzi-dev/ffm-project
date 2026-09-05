import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/activity/presentation/pages/activity_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await configureDependencies(database: AppDatabase(NativeDatabase.memory()));
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('tap Timer FAB opens session form without error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ActivityPage(),
      ),
    );
    await tester.pumpAndSettle();

    final timerFab = find.widgetWithText(FloatingActionButton, 'Timer');
    expect(timerFab, findsOneWidget);

    await tester.tap(timerFab);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('tap Catat FAB opens session form without error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ActivityPage(),
      ),
    );
    await tester.pumpAndSettle();

    final noteFab = find.widgetWithText(FloatingActionButton, 'Catat');
    expect(noteFab, findsOneWidget);

    await tester.tap(noteFab);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
