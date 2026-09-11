import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/data_retention/domain/bulk_retention_service.dart';

void main() {
  late AppDatabase database;
  late BulkRetentionService service;

  final cutoff = DateTime(2025, 6, 1);
  final before = DateTime(2025, 5, 15);
  final after = DateTime(2025, 7, 15);

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    service = BulkRetentionService(database);

    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'tx-before',
            householdId: AppContext.householdId,
            type: 'expense',
            date: before,
            amount: -50000,
            owner: const Value('Keluarga'),
            recordedAt: DateTime.now(),
            createdAt: DateTime.now(),
          ),
        );
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'tx-after',
            householdId: AppContext.householdId,
            type: 'expense',
            date: after,
            amount: -10000,
            owner: const Value('Keluarga'),
            recordedAt: DateTime.now(),
            createdAt: DateTime.now(),
          ),
        );
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'tx-archived-before',
            householdId: AppContext.householdId,
            type: 'expense',
            date: before,
            amount: -2000,
            owner: const Value('Keluarga'),
            recordedAt: DateTime.now(),
            createdAt: DateTime.now(),
            isArchived: const Value(true),
          ),
        );
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'tx-deleted',
            householdId: AppContext.householdId,
            type: 'expense',
            date: before,
            amount: -3000,
            owner: const Value('Keluarga'),
            recordedAt: DateTime.now(),
            createdAt: DateTime.now(),
            isDeleted: const Value(true),
          ),
        );

    await database.into(database.activitySessions).insert(
          ActivitySessionsCompanion.insert(
            id: 'sess-before',
            householdId: AppContext.householdId,
            title: 'Sesi lama',
            category: const Value('Lainnya'),
            kind: const Value('timer'),
            startedAt: before,
            status: const Value('completed'),
            isArchived: const Value(false),
            createdAt: DateTime.now(),
          ),
        );
    await database.into(database.activitySessions).insert(
          ActivitySessionsCompanion.insert(
            id: 'sess-before-archived',
            householdId: AppContext.householdId,
            title: 'Sesi lama arsip',
            category: const Value('Lainnya'),
            kind: const Value('timer'),
            startedAt: before,
            status: const Value('completed'),
            isArchived: const Value(true),
            createdAt: DateTime.now(),
          ),
        );
    await database.into(database.activitySessions).insert(
          ActivitySessionsCompanion.insert(
            id: 'sess-after',
            householdId: AppContext.householdId,
            title: 'Sesi baru',
            category: const Value('Lainnya'),
            kind: const Value('timer'),
            startedAt: after,
            status: const Value('completed'),
            isArchived: const Value(false),
            createdAt: DateTime.now(),
          ),
        );
    await database.into(database.activityCheckpoints).insert(
          ActivityCheckpointsCompanion.insert(
            id: 'cp-before',
            sessionId: 'sess-before-archived',
            label: 'Checkpoint lama',
            occurredAt: before,
            sequence: 0,
            createdAt: DateTime.now(),
          ),
        );
    await database.into(database.activityEntries).insert(
          ActivityEntriesCompanion.insert(
            id: 'ent-before',
            sessionId: const Value('sess-before-archived'),
            householdId: AppContext.householdId,
            activityType: const Value('activity'),
            title: 'Jurnal lama',
            startedAt: before,
            createdAt: DateTime.now(),
          ),
        );

    await database.into(database.dailyNotes).insert(
          DailyNotesCompanion.insert(
            id: 'note-before',
            householdId: AppContext.householdId,
            noteDate: before,
            body: 'Catatan lama',
            createdAt: DateTime.now(),
          ),
        );
    await database.into(database.dailyNotes).insert(
          DailyNotesCompanion.insert(
            id: 'note-before-archived',
            householdId: AppContext.householdId,
            noteDate: before,
            body: 'Catatan lama arsip',
            createdAt: DateTime.now(),
            isArchived: const Value(true),
          ),
        );
    await database.into(database.dailyNotes).insert(
          DailyNotesCompanion.insert(
            id: 'note-after',
            householdId: AppContext.householdId,
            noteDate: after,
            body: 'Catatan baru',
            createdAt: DateTime.now(),
          ),
        );
  });

  tearDown(() async => database.close());

  test('preview archive menghitung hanya data non-arsip sebelum tanggal', () async {
    final preview = await service.previewArchive(cutoff);

    expect(preview.transactions, 1); // tx-before (tx-archived & tx-deleted dikecualikan)
    expect(preview.activitySessions, 1); // sess-before
    expect(preview.dailyNotes, 1); // note-before
    expect(preview.isEmpty, isFalse);
  });

  test('preview delete menghitung hanya data terarsip sebelum tanggal', () async {
    final preview = await service.previewDelete(cutoff);

    expect(preview.transactions, 1); // tx-archived-before
    expect(preview.activitySessions, 1); // sess-before-archived
    expect(preview.dailyNotes, 1); // note-before-archived
  });

  test('archiveBefore mengarsipkan lintas entity dan diverifikasi', () async {
    final result = await service.archiveBefore(cutoff);

    expect(result.transactions, 1);
    expect(result.activitySessions, 1);
    expect(result.dailyNotes, 1);

    final remaining = await service.previewArchive(cutoff);
    expect(remaining.total, 0);

    final tx = await (database.select(database.transactions)
          ..where((row) => row.id.equals('tx-before')))
        .getSingle();
    expect(tx.isArchived, isTrue);
    final sess = await (database.select(database.activitySessions)
          ..where((row) => row.id.equals('sess-before')))
        .getSingle();
    expect(sess.isArchived, isTrue);
    final note = await (database.select(database.dailyNotes)
          ..where((row) => row.id.equals('note-before')))
        .getSingle();
    expect(note.isArchived, isTrue);
  });

  test('deleteBefore menolak tanpa backup gate', () async {
    await service.archiveBefore(cutoff);

    expect(
      () => service.deleteBefore(cutoff, backupVerified: false),
      throwsA(isA<StateError>()),
    );
  });

  test('deleteBefore menghapus permanen data arsip dan meng-cascade sesi', () async {
    await service.archiveBefore(cutoff);
    await service.deleteBefore(cutoff, backupVerified: true);

    final remaining = await service.previewDelete(cutoff);
    expect(remaining.total, 0);

    final txCount = await (database.select(database.transactions)
          ..where((row) => row.id.equals('tx-before')))
        .get();
    // Transaksi lama di-soft-delete (isDeleted) sesuai konvensi aplikasi.
    expect(txCount.single.isDeleted, isTrue);

    final sess = await (database.select(database.activitySessions)
          ..where((row) => row.id.isIn(['sess-before', 'sess-before-archived'])))
        .get();
    expect(sess, isEmpty);
    final notes = await (database.select(database.dailyNotes)
          ..where((row) => row.id.isIn(['note-before', 'note-before-archived'])))
        .get();
    expect(notes, isEmpty);
  });

  test('hapus permanen tidak menyentuh data setelah tanggal', () async {
    await service.deleteBefore(cutoff, backupVerified: true);

    final afterTx = await (database.select(database.transactions)
          ..where((row) => row.id.equals('tx-after')))
        .getSingle();
    expect(afterTx.isDeleted, isFalse);
    final afterSess = await (database.select(database.activitySessions)
          ..where((row) => row.id.equals('sess-after')))
        .getSingle();
    expect(afterSess.isArchived, isFalse);
    final afterNote = await (database.select(database.dailyNotes)
          ..where((row) => row.id.equals('note-after')))
        .getSingle();
    expect(afterNote.isArchived, isFalse);
  });

  test('deleteBefore data arsip ikut menghapus checkpoint dan entry', () async {
    await service.deleteBefore(cutoff, backupVerified: true);

    final checkpoints = await (database.select(database.activityCheckpoints)
          ..where((row) => row.sessionId.equals('sess-before-archived')))
        .get();
    expect(checkpoints, isEmpty);
    final entries = await (database.select(database.activityEntries)
          ..where((row) => row.sessionId.equals('sess-before-archived')))
        .get();
    expect(entries, isEmpty);
  });
}