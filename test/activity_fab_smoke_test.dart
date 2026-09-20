import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/activity/domain/entities/activity_entity.dart';
import 'package:ffm_manager/features/activity/presentation/pages/activity_page.dart';

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

  testWidgets('tap Timer FAB opens session form without error', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ActivityPage()));
    await tester.pumpAndSettle();

    final timerFab = find.widgetWithText(FloatingActionButton, 'Timer');
    expect(timerFab, findsOneWidget);

    await tester.tap(timerFab);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('tap Catat FAB opens session form without error', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ActivityPage()));
    await tester.pumpAndSettle();

    final noteFab = find.widgetWithText(FloatingActionButton, 'Catat');
    expect(noteFab, findsOneWidget);

    await tester.tap(noteFab);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Catat Kejadian'), findsOneWidget);
    expect(find.text('Judul catatan'), findsOneWidget);
    expect(find.text('Isi catatan'), findsOneWidget);
    expect(find.byIcon(Icons.edit_note_rounded), findsWidgets);
    expect(find.byIcon(Icons.directions_run_outlined), findsNothing);
    expect(find.text('⏱️ Pakai Timer'), findsNothing);
    expect(find.text('Tambah tag baru'), findsOneWidget);
  });

  testWidgets('assistant history draft opens Daily Note with initial fields', (
    tester,
  ) async {
    final initialDate = DateTime(2026, 9, 20, 8, 30);
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityPage(
          initialTitle: 'Panen selesai',
          initialNotes: 'Catatan dari Asisten',
          initialStartDate: initialDate,
          initialMode: ActivityMode.history,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Catat Kejadian'), findsOneWidget);
    expect(find.text('Panen selesai'), findsOneWidget);
    expect(find.text('Catatan dari Asisten'), findsOneWidget);
    expect(find.text('Tanggal kejadian: 20/09/2026'), findsOneWidget);
  });

  testWidgets('tag baru dibuat inline dan langsung tersedia di form catatan', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ActivityPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Catat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tambah tag baru'));
    await tester.pumpAndSettle();

    expect(find.text('Tambah tag baru'), findsWidgets);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nama tag'),
      'Kendaraan',
    );
    await tester.tap(find.text('Simpan tag'));
    await tester.pumpAndSettle();

    expect(find.text('Kendaraan'), findsOneWidget);
    final tags = await database.select(database.tags).get();
    expect(tags.single.name, 'Kendaraan');
  });
}
