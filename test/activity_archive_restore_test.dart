import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;

import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/activity/data/repositories/activity_repository.dart';
import 'package:ffm_manager/features/activity/domain/activity_query_layer.dart';
import 'package:ffm_manager/features/activity/domain/entities/activity_entity.dart';

void main() {
  late AppDatabase database;
  late ActivityRepository repository;
  late ActivityQueryLayer queryLayer;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    repository = ActivityRepository(database, AuditLogger(database));
    queryLayer = ActivityQueryLayer(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('arsip sesi disembunyikan dari query default dan tampil via includeArchived', () async {
    final start = DateTime(2026, 8, 20, 9);
    await repository.saveSession(
      ActivitySessionEntity(
        id: 's-arsip',
        householdId: AppContext.householdId,
        title: 'Sesi yang diarsipkan',
        category: 'Kebun',
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 30)),
        status: ActivitySessionStatus.completed,
        isCompleted: true,
        createdAt: start,
      ),
    );
    await repository.archiveSession(AppContext.householdId, 's-arsip');

    final defaultPage = await queryLayer.querySessionsPage(
      householdId: AppContext.householdId,
    );
    expect(defaultPage.items, isEmpty);

    final archivedPage = await queryLayer.querySessionsPage(
      householdId: AppContext.householdId,
      includeArchived: true,
    );
    expect(archivedPage.items.single.id, 's-arsip');
    expect(archivedPage.items.single.isArchived, isTrue);
  });

  test('restoreSession mengembalikan sesi ke daftar aktif', () async {
    final start = DateTime(2026, 8, 20, 9);
    await repository.saveSession(
      ActivitySessionEntity(
        id: 's-restore',
        householdId: AppContext.householdId,
        title: 'Sesi dipulihkan',
        category: 'Kebun',
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 30)),
        status: ActivitySessionStatus.completed,
        isCompleted: true,
        createdAt: start,
      ),
    );
    await repository.archiveSession(AppContext.householdId, 's-restore');
    await repository.restoreSession(AppContext.householdId, 's-restore');

    final defaultPage = await queryLayer.querySessionsPage(
      householdId: AppContext.householdId,
    );
    expect(defaultPage.items.single.id, 's-restore');
    expect(defaultPage.items.single.isArchived, isFalse);
  });

  test('arsip catatan harian ikut query includeArsip lalu bisa dipulihkan', () async {
    await database.into(database.dailyNotes).insert(
      DailyNotesCompanion.insert(
        id: 'note-arsip',
        householdId: AppContext.householdId,
        noteDate: DateTime(2026, 8, 20),
        body: 'Catatan yang diarsipkan',
        createdAt: DateTime.now(),
      ),
    );

    final archivedOnly = await queryLayer.queryDailyNotesPage(
      householdId: AppContext.householdId,
      includeArchived: true,
    );
    // includeArchived menampilkan semua data, termasuk yang belum diarsipkan.
    expect(archivedOnly.items.single.id, 'note-arsip');

    await database
        .update(database.dailyNotes)
        .write(const DailyNotesCompanion(isArchived: Value(true)));
    final archivedPage = await queryLayer.queryDailyNotesPage(
      householdId: AppContext.householdId,
      includeArchived: true,
    );
    expect(archivedPage.items.single.id, 'note-arsip');
    expect(archivedPage.items.single.isArchived, isTrue);

    final defaultPage = await queryLayer.queryDailyNotesPage(
      householdId: AppContext.householdId,
    );
    expect(defaultPage.items, isEmpty);

    await repository.restoreDailyNote(AppContext.householdId, 'note-arsip');
    final restoredPage = await queryLayer.queryDailyNotesPage(
      householdId: AppContext.householdId,
    );
    expect(restoredPage.items.single.id, 'note-arsip');
    expect(restoredPage.items.single.isArchived, isFalse);
  });

  test('query default mengecualikan arsip tapi catatan aktif tetap tampil', () async {
    final start = DateTime(2026, 8, 20, 9);
    await repository.saveSession(
      ActivitySessionEntity(
        id: 's-aktif',
        householdId: AppContext.householdId,
        title: 'Sesi aktif',
        category: 'Kebun',
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 30)),
        status: ActivitySessionStatus.completed,
        isCompleted: true,
        createdAt: start,
      ),
    );
    await repository.saveSession(
      ActivitySessionEntity(
        id: 's-arsip',
        householdId: AppContext.householdId,
        title: 'Sesi arsip',
        category: 'Kebun',
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 30)),
        status: ActivitySessionStatus.completed,
        isCompleted: true,
        createdAt: start,
      ),
    );
    await repository.archiveSession(AppContext.householdId, 's-arsip');

    final defaultPage = await queryLayer.querySessionsPage(
      householdId: AppContext.householdId,
    );
    expect(defaultPage.items.map((s) => s.id), ['s-aktif']);

    final includePage = await queryLayer.querySessionsPage(
      householdId: AppContext.householdId,
      includeArchived: true,
    );
    expect(
      includePage.items.map((s) => s.id),
      containsAll(['s-aktif', 's-arsip']),
    );
  });
}