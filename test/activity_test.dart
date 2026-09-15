import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/activity/data/repositories/activity_repository.dart';
import 'package:ffm_manager/features/activity/domain/activity_voice.dart';
import 'package:ffm_manager/features/activity/presentation/bloc/activity_bloc.dart';
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

  test('Catatan Kejadian dapat disimpan tanpa tag', () async {
    final now = DateTime(2026, 9, 15, 9);
    await repository.saveDailyNote(
      id: 'note-without-tag',
      householdId: 'local-household',
      noteDate: now,
      title: 'Ganti oli',
      body: 'Belum mengganti oli mesin.',
      tagIds: const [],
    );

    final note = await database.select(database.dailyNotes).getSingle();
    expect(note.title, 'Ganti oli');
    expect(await database.select(database.dailyNoteTags).get(), isEmpty);
  });

  test(
    'migrasi memindahkan sesi history ke Catatan Kejadian kanonis',
    () async {
      final now = DateTime(2026, 9, 13, 17, 1);
      await repository.saveSession(
        ActivitySessionEntity(
          id: 'legacy-history-note',
          householdId: 'local-household',
          title: 'amistar top dan abacel',
          category: 'Pekerjaan',
          kind: ActivityKind.note,
          mode: ActivityMode.history,
          startedAt: now,
          endedAt: now,
          status: ActivitySessionStatus.completed,
          notes: '1 ml per liter dua-duanya',
          priority: 1,
          createdAt: now,
        ),
      );

      await repository.migrateHistorySessionsToDailyNotes('local-household');

      expect(await database.select(database.activitySessions).get(), isEmpty);
      final migrated = await database.select(database.dailyNotes).getSingle();
      expect(migrated.id, 'legacy-history-note');
      expect(migrated.title, 'amistar top dan abacel');
      expect(migrated.body, '1 ml per liter dua-duanya');
      expect(migrated.noteDate, now);
      expect(migrated.priority, 1);
    },
  );

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

  test(
    'mendukung dua sesi aktif dan aktivitas anak yang berjalan bersamaan',
    () async {
      final start = DateTime(2026, 8, 21, 8);
      await repository.saveSession(
        ActivitySessionEntity(
          id: 'parent-active',
          householdId: 'local-household',
          title: 'OTW ke pasar',
          category: 'Perjalanan',
          startedAt: start,
          status: ActivitySessionStatus.active,
          createdAt: start,
        ),
      );
      await repository.saveSession(
        ActivitySessionEntity(
          id: 'child-active',
          householdId: 'local-household',
          title: 'Makan di perjalanan',
          category: 'Keluarga',
          parentSessionId: 'parent-active',
          startedAt: start.add(const Duration(minutes: 20)),
          status: ActivitySessionStatus.active,
          createdAt: start.add(const Duration(minutes: 20)),
        ),
      );
      await repository.saveSession(
        ActivitySessionEntity(
          id: 'other-active',
          householdId: 'local-household',
          title: 'Cek kebun',
          category: 'Pekerjaan',
          startedAt: start.add(const Duration(minutes: 30)),
          status: ActivitySessionStatus.active,
          createdAt: start.add(const Duration(minutes: 30)),
        ),
      );

      final active = await repository.getActiveSessions('local-household');

      expect(active.map((item) => item.id), [
        'parent-active',
        'child-active',
        'other-active',
      ]);
      expect(active[1].parentSessionId, 'parent-active');
      expect(
        active[1].durationAt(start.add(const Duration(hours: 1))),
        const Duration(minutes: 40),
      );
    },
  );

  test('force close tidak menghentikan parent atau child saat aplikasi dibuka ulang', () async {
    final start = DateTime(2026, 8, 21, 7);
    await repository.saveSession(
      ActivitySessionEntity(
        id: 'restart-parent',
        householdId: 'local-household',
        title: 'Perjalanan pagi',
        category: 'Perjalanan',
        startedAt: start,
        status: ActivitySessionStatus.active,
        createdAt: start,
      ),
    );
    await repository.saveSession(
      ActivitySessionEntity(
        id: 'restart-child',
        householdId: 'local-household',
        title: 'Makan di jalan',
        category: 'Keluarga',
        parentSessionId: 'restart-parent',
        startedAt: start.add(const Duration(minutes: 15)),
        status: ActivitySessionStatus.active,
        createdAt: start.add(const Duration(minutes: 15)),
      ),
    );

    final firstBloc = ActivityBloc(repository);
    await firstBloc.load();
    expect(firstBloc.state.activeSessions.map((item) => item.id), [
      'restart-parent',
      'restart-child',
    ]);
    await firstBloc.close();

    // BLoC baru mensimulasikan proses aplikasi yang dibuat ulang setelah
    // force close. Data aktif dibaca lagi dari database yang persisten.
    final restartedBloc = ActivityBloc(repository);
    await restartedBloc.load();
    expect(restartedBloc.state.activeSessions, hasLength(2));
    expect(
      restartedBloc.state.activeSessions
          .firstWhere((item) => item.id == 'restart-child')
          .parentSessionId,
      'restart-parent',
    );
    await restartedBloc.close();
  });

  test(
    'child aktif yang kehilangan parent tetap dipulihkan dan diaudit',
    () async {
      final start = DateTime(2026, 8, 21, 11);
      await repository.saveSession(
        ActivitySessionEntity(
          id: 'orphan-child',
          householdId: 'local-household',
          title: 'Makan tetap berjalan',
          category: 'Keluarga',
          parentSessionId: 'parent-yang-hilang',
          startedAt: start,
          status: ActivitySessionStatus.active,
          createdAt: start,
        ),
      );

      final recovered = await repository.recoverActiveSessions(
        'local-household',
      );
      expect(recovered.single.id, 'orphan-child');
      final auditRows = await database
          .customSelect('SELECT action FROM audit_logs')
          .get();
      expect(
        auditRows.any(
          (row) => row.read<String>('action') == 'recover_active_sessions',
        ),
        isTrue,
      );
    },
  );

  test(
    'hapus induk menghapus semua child, checkpoint, dan entry tertaut',
    () async {
      final start = DateTime(2026, 8, 21, 9);
      for (final session in [
        ActivitySessionEntity(
          id: 'delete-parent',
          householdId: 'local-household',
          title: 'Perjalanan utama',
          category: 'Perjalanan',
          startedAt: start,
          status: ActivitySessionStatus.completed,
          endedAt: start.add(const Duration(hours: 3)),
          createdAt: start,
        ),
        ActivitySessionEntity(
          id: 'delete-child',
          householdId: 'local-household',
          title: 'Makan di dalam perjalanan',
          category: 'Keluarga',
          parentSessionId: 'delete-parent',
          startedAt: start.add(const Duration(hours: 1)),
          status: ActivitySessionStatus.completed,
          endedAt: start.add(const Duration(hours: 1, minutes: 30)),
          createdAt: start.add(const Duration(hours: 1)),
        ),
        ActivitySessionEntity(
          id: 'delete-grandchild',
          householdId: 'local-household',
          title: 'Bayar makan',
          category: 'Lainnya',
          parentSessionId: 'delete-child',
          startedAt: start.add(const Duration(hours: 1, minutes: 10)),
          status: ActivitySessionStatus.completed,
          endedAt: start.add(const Duration(hours: 1, minutes: 15)),
          createdAt: start.add(const Duration(hours: 1, minutes: 10)),
        ),
      ]) {
        await repository.saveSession(session);
      }
      await repository.saveCheckpoint(
        ActivityCheckpointEntity(
          id: 'delete-child-checkpoint',
          sessionId: 'delete-child',
          label: 'Selesai makan',
          occurredAt: start.add(const Duration(hours: 1, minutes: 30)),
          sequence: 1,
          createdAt: start.add(const Duration(hours: 1, minutes: 30)),
        ),
      );
      await repository.saveEntry(
        ActivityJournalEntryEntity(
          id: 'delete-grandchild-entry',
          sessionId: 'delete-grandchild',
          householdId: 'local-household',
          activityType: 'Lainnya',
          title: 'Catatan legacy tertaut',
          startedAt: start,
          createdAt: start,
        ),
      );

      await repository.deleteSessionPermanently(
        'local-household',
        'delete-parent',
      );

      expect(
        await (database.select(database.activitySessions)..where(
              (row) => row.id.isIn([
                'delete-parent',
                'delete-child',
                'delete-grandchild',
              ]),
            ))
            .get(),
        isEmpty,
      );
      expect(await repository.getCheckpoints('delete-child'), isEmpty);
      expect(await repository.getEntries('local-household'), isEmpty);
    },
  );

  test(
    'ActivityBloc voice intent membuat sesi baru dengan kategori yang dipilih',
    () async {
      final bloc = ActivityBloc(repository);
      addTearDown(bloc.close);

      final intent = ActivityVoiceIntent(
        rawTranscript: 'mulai belanja sayur',
        normalizedText: 'mulai belanja sayur',
        type: ActivityVoiceIntentType.start,
        status: ActivityVoiceStatus.preview,
        category: 'Belanja',
        targetTitle: 'Belanja sayur',
        confidence: 1,
      );

      await bloc.executeVoiceIntent(intent);

      final active = await repository.getActiveSessions('local-household');
      expect(active, hasLength(1));
      expect(active.single.title, 'Belanja sayur');
      expect(active.single.category, 'Belanja');
    },
  );

  test('ActivityBloc voice intent catatan menyimpan ke Daily Notes', () async {
    await database
        .into(database.tags)
        .insert(
          TagsCompanion.insert(
            id: 'tag-panenn',
            householdId: 'local-household',
            name: 'Panen',
            createdAt: DateTime(2026, 8, 23),
          ),
        );
    final bloc = ActivityBloc(repository);
    addTearDown(bloc.close);

    await database
        .into(database.tags)
        .insert(
          TagsCompanion.insert(
            id: 'tag-kebun',
            householdId: 'local-household',
            name: 'Kebun Tomat',
            createdAt: DateTime(2026, 8, 24),
          ),
        );

    final intent = ActivityVoiceIntent(
      rawTranscript: 'catat hasil panen hari ini',
      normalizedText: 'catat hasil panen hari ini',
      type: ActivityVoiceIntentType.start,
      status: ActivityVoiceStatus.preview,
      kind: ActivityKind.note,
      tagIds: const ['tag-kebun'],
      notes: 'Tomat siap dipanen',
      targetTitle: 'Hasil panen hari ini',
      startedAt: DateTime(2026, 8, 24, 9),
      confidence: 1,
    );

    await bloc.executeVoiceIntent(intent);

    final notes = await (database.select(database.dailyNotes)).get();
    expect(notes, hasLength(1));
    expect(notes.single.title, 'Hasil panen hari ini');
    expect(notes.single.body, 'Tomat siap dipanen');
  });

  test('ActivityBloc mengosongkan kartu aktif setelah sesi dihapus', () async {
    final now = DateTime(2026, 8, 21, 11);
    await repository.saveSession(
      ActivitySessionEntity(
        id: 'bloc-active',
        householdId: 'local-household',
        title: 'Aktivitas untuk BLoC',
        category: 'Lainnya',
        startedAt: now,
        status: ActivitySessionStatus.active,
        createdAt: now,
      ),
    );
    final bloc = ActivityBloc(repository);
    addTearDown(bloc.close);

    await bloc.load();
    await bloc.deleteSessionPermanently('bloc-active');

    expect(bloc.state.activeSessions, isEmpty);
    expect(bloc.state.activeSession, isNull);
    expect(bloc.state.sessions, isEmpty);
  });

  test('ActivityBloc memigrasikan catatan sesi lama ke daily notes', () async {
    final oldTime = DateTime(2026, 8, 1, 8);
    // Simpan catatan lama dengan endedAt null dan status active
    await repository.saveSession(
      ActivitySessionEntity(
        id: 'old-note-broken',
        householdId: 'local-household',
        title: 'Beli benih di toko tani',
        category: 'Catatan',
        kind: ActivityKind.note,
        startedAt: oldTime,
        endedAt: null, // broken legacy state
        status: ActivitySessionStatus.active, // broken legacy state
        createdAt: oldTime,
      ),
    );

    final bloc = ActivityBloc(repository);
    addTearDown(bloc.close);

    await bloc.load();

    final migrated = bloc.state.dailyNotes.firstWhere(
      (note) => note.id == 'old-note-broken',
    );
    expect(migrated.title, 'Beli benih di toko tani');
    expect(migrated.noteDate, oldTime);
    expect(
      bloc.state.sessions.where((s) => s.id == 'old-note-broken'),
      isEmpty,
    );
    expect(
      bloc.state.activeSessions.where((s) => s.id == 'old-note-broken'),
      isEmpty,
    );
  });

  test(
    'ActivityBloc editCheckpoint dan deleteCheckpoint bekerja dengan benar',
    () async {
      final now = DateTime(2026, 8, 20, 10);
      await repository.saveSession(
        ActivitySessionEntity(
          id: 'session-cp',
          householdId: 'local-household',
          title: 'Sesi untuk Checkpoint',
          category: 'Kerja',
          startedAt: now,
          status: ActivitySessionStatus.active,
          createdAt: now,
        ),
      );
      final bloc = ActivityBloc(repository);
      addTearDown(bloc.close);
      await bloc.load();

      await bloc.addCheckpoint(
        sessionId: 'session-cp',
        label: 'Typo Checkpoint',
        place: 'Kantor',
        note: 'Catatan awal',
      );

      var checkpoints = bloc.state.checkpoints['session-cp'] ?? [];
      expect(checkpoints, hasLength(1));
      final cpId = checkpoints.first.id;

      // Edit checkpoint untuk memperbaiki typo
      await bloc.editCheckpoint(
        checkpointId: cpId,
        label: 'Label yang Benar',
        place: 'Kantor Pusat',
        note: 'Catatan diperbaiki',
      );

      checkpoints = bloc.state.checkpoints['session-cp'] ?? [];
      expect(checkpoints.first.label, 'Label yang Benar');
      expect(checkpoints.first.place, 'Kantor Pusat');

      // Hapus checkpoint
      await bloc.deleteCheckpoint(cpId);
      checkpoints = bloc.state.checkpoints['session-cp'] ?? [];
      expect(checkpoints, isEmpty);
    },
  );
}
