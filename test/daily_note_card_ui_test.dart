import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/activity/data/repositories/activity_repository.dart';
import 'package:ffm_manager/features/activity/presentation/pages/activity_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late ActivityRepository repository;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase(NativeDatabase.memory());
    await configureDependencies(database: database);
    repository = ActivityRepository(database, AuditLogger(database));
  });

  tearDown(() async {
    await getIt.reset();
    await database.close();
  });

  Future<void> pumpActivity(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ActivityPage()));
    await tester.pumpAndSettle();
  }

  Future<void> seedTag(String id, String name) async {
    await database
        .into(database.tags)
        .insert(
          TagsCompanion.insert(
            id: id,
            householdId: AppContext.householdId,
            name: name,
            createdAt: DateTime(2026, 9, 15, 8),
          ),
        );
  }

  Future<void> seedNote({
    required String id,
    required String title,
    required String body,
    DateTime? noteDate,
    List<String> tagIds = const [],
  }) async {
    await repository.saveDailyNote(
      id: id,
      householdId: AppContext.householdId,
      noteDate: noteDate ?? DateTime(2026, 9, 15, 10),
      title: title,
      body: body,
      tagIds: tagIds,
    );
  }

  Future<void> seedArchivedNote({
    required String id,
    required String title,
  }) async {
    await database
        .into(database.dailyNotes)
        .insert(
          DailyNotesCompanion.insert(
            id: id,
            householdId: AppContext.householdId,
            noteDate: DateTime(2026, 9, 14, 9),
            title: Value(title),
            body: 'Catatan yang sudah diarsipkan.',
            isArchived: const Value(true),
            createdAt: DateTime(2026, 9, 14, 9),
          ),
        );
  }

  testWidgets('edit catatan lewat ketuk kartu menyimpan judul & isi baru', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await seedNote(
      id: 'note-edit',
      title: 'Ganti oli mesin',
      body: 'Oli mesin diganti pagi ini.',
    );
    await pumpActivity(tester);

    expect(find.text('Ganti oli mesin'), findsOneWidget);

    await tester.tap(find.text('Ganti oli mesin'));
    await tester.pumpAndSettle();

    expect(find.text('Catat Kejadian'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Judul catatan'),
      'Ganti oli + filter udara',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Isi catatan'),
      'Oli dan filter udara diganti di bengkel langganan.',
    );
    await tester.tap(find.text('Simpan Catatan'));
    await tester.pumpAndSettle();

    final row = await database.select(database.dailyNotes).getSingle();
    expect(row.title, 'Ganti oli + filter udara');
    expect(row.body, 'Oli dan filter udara diganti di bengkel langganan.');
    expect(find.text('Ganti oli + filter udara'), findsOneWidget);
  });

  testWidgets('bintang prioritas menandai catatan dan memperbarui DB', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await seedNote(
      id: 'note-priority',
      title: 'Berangkat haji',
      body: 'Berkat hasil panen tahun ini.',
    );
    await pumpActivity(tester);

    expect(find.byTooltip('Jadikan prioritas'), findsOneWidget);
    await tester.tap(find.byTooltip('Jadikan prioritas'));
    await tester.pumpAndSettle();

    final row = await database.select(database.dailyNotes).getSingle();
    expect(row.priority, 1);
    expect(find.byTooltip('Lepas prioritas'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
  });

  testWidgets('arsip catatan memindahkannya keluar daftar aktif', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await seedNote(
      id: 'note-archive',
      title: 'Perbaikan pagar',
      body: 'Sudah.',
    );
    await pumpActivity(tester);

    expect(find.text('Perbaikan pagar'), findsOneWidget);

    await tester.tap(find.byTooltip('Kelola catatan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arsipkan'));
    await tester.pumpAndSettle();

    expect(find.text('Arsipkan catatan?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Arsipkan'));
    await tester.pumpAndSettle();

    final row = await database.select(database.dailyNotes).getSingle();
    expect(row.isArchived, isTrue);
    expect(find.text('Perbaikan pagar'), findsNothing);
  });

  testWidgets('catatan arsip dapat dipulihkan dari filter Arsip', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await seedArchivedNote(id: 'note-restore', title: 'Catatan lama');
    await pumpActivity(tester);

    expect(find.text('Catatan lama'), findsNothing);

    await tester.tap(find.byTooltip('Filter aktivitas & catatan'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Arsip'));
    await tester.tap(find.text('Terapkan Filter'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('Catatan lama'), findsOneWidget);

    await tester.tap(find.byTooltip('Kelola catatan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pulihkan'));
    await tester.pumpAndSettle();

    expect(find.text('Kembalikan dari arsip?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Pulihkan'));
    await tester.pumpAndSettle();

    final row = await database.select(database.dailyNotes).getSingle();
    expect(row.isArchived, isFalse);
    expect(find.text('Catatan lama'), findsOneWidget);
  });

  testWidgets('hapus permanen menghapus catatan beserta relasi dari DB', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await seedNote(id: 'note-delete', title: 'Buang sampah', body: 'Selesai.');
    await pumpActivity(tester);

    await tester.tap(find.byTooltip('Kelola catatan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus permanen'));
    await tester.pumpAndSettle();

    expect(find.text('Hapus catatan permanen?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Hapus permanen'));
    await tester.pumpAndSettle();

    expect(await database.select(database.dailyNotes).get(), isEmpty);
    expect(find.text('Buang sampah'), findsNothing);
  });

  testWidgets('filter tag menampilkan hanya catatan bertag terpilih', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await seedTag('tag-vehicle', 'Kendaraan');
    await seedTag('tag-garden', 'Kebun');
    await seedNote(
      id: 'note-t1',
      title: 'Ganti oli',
      body: 'Pemeliharaan kendaraan.',
      tagIds: const ['tag-vehicle'],
    );
    await seedNote(
      id: 'note-t2',
      title: 'Panen tomat',
      body: 'Hasil kebun.',
      tagIds: const ['tag-garden'],
    );
    await pumpActivity(tester);

    expect(find.text('Ganti oli'), findsOneWidget);
    expect(find.text('Panen tomat'), findsOneWidget);

    await tester.tap(find.byTooltip('Filter aktivitas & catatan'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Kendaraan'));
    await tester.tap(find.text('Terapkan Filter'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('Ganti oli'), findsOneWidget);
    expect(find.text('Panen tomat'), findsNothing);
    expect(find.text('#Kendaraan'), findsWidgets);
  });
}
