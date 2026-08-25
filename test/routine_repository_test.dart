import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/routines/data/routine_repository.dart';

void main() {
  const householdId = 'local-household';
  final now = DateTime(2026, 8, 25, 10);
  late AppDatabase database;
  late RoutineRepository repository;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    repository = RoutineRepository(
      database,
      AuditLogger(database),
      clock: () => now,
    );
  });

  tearDown(() => database.close());

  test('buat Rutinitas menyaring teks, menormalkan pola hari, idempoten, dan terisolasi dari Tugas', () async {
    final routine = await repository.create(
      id: 'routine-1',
      householdId: householdId,
      title: '  Baca\n\n\n buku  ',
      note: '  15 menit  ',
      weekdays: [DateTime.friday, DateTime.monday, DateTime.monday],
    );
    final repeated = await repository.create(
      id: 'routine-1',
      householdId: householdId,
      title: 'Baca\n\n buku',
      note: '15 menit',
      weekdays: [DateTime.monday, DateTime.friday],
    );

    expect(routine.title, 'Baca\n\n buku');
    expect(routine.weekdays, [DateTime.monday, DateTime.friday]);
    expect(repeated.id, routine.id);
    expect((await database.select(database.tasks).get()), isEmpty);
  });

  test('pelaksanaan harian idempoten, dapat dibatalkan eksplisit, dan tidak menyentuh Catatan Harian', () async {
    final routine = await repository.create(
      id: 'routine-2',
      householdId: householdId,
      title: 'Minum air',
    );
    final day = DateTime(2026, 8, 25, 22);

    final marked = await repository.markCompletedForDay(
      householdId: householdId,
      routineId: routine.id,
      day: day,
    );
    final repeated = await repository.markCompletedForDay(
      householdId: householdId,
      routineId: routine.id,
      day: day,
    );
    expect(repeated?.id, marked?.id);
    expect(
      (await database.select(database.dailyRoutineCompletions).get()),
      hasLength(1),
    );

    final unmarked = await repository.unmarkCompletedForDay(
      householdId: householdId,
      routineId: routine.id,
      day: day,
    );
    expect(unmarked?.routineDate, DateTime(2026, 8, 25));
    expect(
      (await database.select(database.dailyRoutineCompletions).get()),
      isEmpty,
    );
    expect((await database.select(database.dailyNotes).get()), isEmpty);
  });

  test('aktif/nonaktif dan arsip lunak menyimpan audit lokal serta menolak tanda untuk Rutinitas tidak aktif', () async {
    final routine = await repository.create(
      id: 'routine-3',
      householdId: householdId,
      title: 'Olahraga ringan',
    );
    final inactive = await repository.setActive(
      householdId: householdId,
      id: routine.id,
      isActive: false,
    );
    expect(inactive?.isActive, isFalse);
    expect(
      await repository.markCompletedForDay(
        householdId: householdId,
        routineId: routine.id,
        day: now,
      ),
      isNull,
    );
    final active = await repository.setActive(
      householdId: householdId,
      id: routine.id,
      isActive: true,
    );
    expect(active?.isActive, isTrue);
    final archived = await repository.archive(
      householdId: householdId,
      id: routine.id,
    );
    expect(archived?.isArchived, isTrue);
    expect(await repository.readActive(householdId), isEmpty);

    final logs = await database
        .customSelect(
          "SELECT action FROM audit_logs WHERE entity = 'daily_routine'",
        )
        .get();
    expect(
      logs.map((row) => row.read<String>('action')),
      containsAll(['create', 'deactivate', 'activate', 'archive']),
    );
  });

  test(
    'judul kosong, hari tidak valid, dan reuse id dengan isi berbeda ditolak',
    () async {
      expect(
        () => repository.create(householdId: householdId, title: '   '),
        throwsArgumentError,
      );
      expect(
        () => repository.create(
          householdId: householdId,
          title: 'Peregangan',
          weekdays: [8],
        ),
        throwsArgumentError,
      );
      await repository.create(
        id: 'routine-4',
        householdId: householdId,
        title: 'Peregangan',
      );
      expect(
        () => repository.create(
          id: 'routine-4',
          householdId: householdId,
          title: 'Rutinitas lain',
        ),
        throwsArgumentError,
      );
    },
  );
}
