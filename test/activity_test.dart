import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/activity/data/repositories/activity_repository.dart';
import 'package:ffm_manager/features/activity/domain/entities/activity_entity.dart';

void main() {
  late AppDatabase database;
  late ActivityRepository repository;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    repository = ActivityRepository(database, AuditLogger(database));
  });

  tearDown(() async {
    await database.close();
  });

  test('durasi sesi aktif berjalan dari waktu mulai sampai sekarang', () {
    final start = DateTime(2026, 8, 20, 8, 0);
    final session = ActivitySessionEntity(
      id: 's1',
      householdId: 'local-household',
      title: 'Ke pasar',
      category: 'Perjalanan',
      startedAt: start,
      status: ActivitySessionStatus.active,
      createdAt: start,
    );

    expect(
      session.durationAt(DateTime(2026, 8, 20, 9, 35)),
      const Duration(hours: 1, minutes: 35),
    );
  });

  test(
    'checkpoint tersimpan berurutan dan sesi aktif bisa ditemukan',
    () async {
      final start = DateTime(2026, 8, 20, 8);
      await repository.saveSession(
        ActivitySessionEntity(
          id: 's1',
          householdId: 'local-household',
          title: 'Ke pasar lalu ke kebun',
          category: 'Perjalanan',
          startedAt: start,
          status: ActivitySessionStatus.active,
          createdAt: start,
        ),
      );
      await repository.saveCheckpoint(
        ActivityCheckpointEntity(
          id: 'c1',
          sessionId: 's1',
          label: 'Sampai pasar',
          place: 'Pasar',
          occurredAt: start.add(const Duration(minutes: 25)),
          sequence: 1,
          createdAt: start,
        ),
      );
      await repository.saveCheckpoint(
        ActivityCheckpointEntity(
          id: 'c2',
          sessionId: 's1',
          label: 'Sampai kebun',
          place: 'Kebun',
          occurredAt: start.add(const Duration(hours: 1)),
          sequence: 2,
          createdAt: start,
        ),
      );

      final active = await repository.getActiveSession('local-household');
      final checkpoints = await repository.getCheckpoints('s1');

      expect(active?.title, 'Ke pasar lalu ke kebun');
      expect(checkpoints.map((item) => item.label), [
        'Sampai pasar',
        'Sampai kebun',
      ]);
    },
  );

  test(
    'jurnal pertemuan menyimpan peserta, topik, dan tindak lanjut',
    () async {
      final start = DateTime(2026, 8, 20, 10);
      await repository.saveEntry(
        ActivityJournalEntryEntity(
          id: 'j1',
          householdId: 'local-household',
          activityType: 'Pertemuan/obrolan',
          title: 'Ngobrol dengan Pak Budi',
          participants: 'Pak Budi',
          topic: 'Rencana kerja',
          place: 'Pasar',
          startedAt: start,
          endedAt: start.add(const Duration(minutes: 30)),
          notes: 'Bahas jadwal besok.',
          followUp: 'Kirim kabar besok pagi.',
          createdAt: start,
        ),
      );

      final entries = await repository.getEntries('local-household');

      expect(entries, hasLength(1));
      expect(entries.single.participants, 'Pak Budi');
      expect(entries.single.durationAt(), const Duration(minutes: 30));
      expect(entries.single.followUp, 'Kirim kabar besok pagi.');
    },
  );

  test(
    'arsip aktivitas menyembunyikan data tanpa menghapus permanen',
    () async {
      final now = DateTime(2026, 8, 20, 12);
      await repository.saveEntry(
        ActivityJournalEntryEntity(
          id: 'j1',
          householdId: 'local-household',
          activityType: 'Keluarga',
          title: 'Makan bersama',
          startedAt: now,
          createdAt: now,
        ),
      );
      await repository.archiveEntry('local-household', 'j1');

      expect(await repository.getEntries('local-household'), isEmpty);
      final raw = await (database.select(
        database.activityEntries,
      )..where((row) => row.id.equals('j1'))).getSingle();
      expect(raw.isArchived, isTrue);
    },
  );

  test(
    'hapus permanen menghapus sesi beserta update dan data lama yang tertaut',
    () async {
      final start = DateTime(2026, 8, 20, 13);
      await repository.saveSession(
        ActivitySessionEntity(
          id: 's-delete',
          householdId: 'local-household',
          title: 'Pasar lalu kebun',
          category: 'Perjalanan',
          startedAt: start,
          status: ActivitySessionStatus.completed,
          endedAt: start.add(const Duration(hours: 2)),
          createdAt: start,
        ),
      );
      await repository.saveCheckpoint(
        ActivityCheckpointEntity(
          id: 'c-delete',
          sessionId: 's-delete',
          label: 'Sampai pasar',
          occurredAt: start.add(const Duration(minutes: 20)),
          sequence: 1,
          createdAt: start,
        ),
      );
      await repository.saveEntry(
        ActivityJournalEntryEntity(
          id: 'j-delete',
          sessionId: 's-delete',
          householdId: 'local-household',
          activityType: 'Lainnya',
          title: 'Catatan lama tertaut',
          startedAt: start,
          createdAt: start,
        ),
      );

      await repository.deleteSessionPermanently('local-household', 's-delete');

      expect(
        await repository.getSession('local-household', 's-delete'),
        isNull,
      );
      expect(await repository.getCheckpoints('s-delete'), isEmpty);
      expect(await repository.getEntries('local-household'), isEmpty);
      expect(
        await (database.select(
          database.activitySessions,
        )..where((row) => row.id.equals('s-delete'))).get(),
        isEmpty,
      );
      final auditRows = await database
          .customSelect('SELECT action, entity FROM audit_logs')
          .get();
      expect(
        auditRows.any(
          (row) =>
              row.read<String>('action') == 'delete_permanently' &&
              row.read<String>('entity') == 'activity_session',
        ),
        isTrue,
      );
    },
  );

  test('arsip sesi tetap berbeda dari hapus permanen', () async {
    final now = DateTime(2026, 8, 20, 15);
    await repository.saveSession(
      ActivitySessionEntity(
        id: 's-archive',
        householdId: 'local-household',
        title: 'Aktivitas diarsipkan',
        category: 'Lainnya',
        startedAt: now,
        status: ActivitySessionStatus.completed,
        createdAt: now,
      ),
    );

    await repository.archiveSession('local-household', 's-archive');

    expect(await repository.getSessions('local-household'), isEmpty);
    final raw = await (database.select(
      database.activitySessions,
    )..where((row) => row.id.equals('s-archive'))).getSingle();
    expect(raw.isArchived, isTrue);
  });
}
