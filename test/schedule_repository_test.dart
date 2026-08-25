import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/schedule/data/schedule_repository.dart';

void main() {
  const householdId = 'local-household';
  final now = DateTime(2026, 8, 25, 10);
  late AppDatabase database;
  late ScheduleRepository repository;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    repository = ScheduleRepository(
      database,
      AuditLogger(database),
      clock: () => now,
    );
  });

  tearDown(() => database.close());

  test('buat Jadwal menyaring teks, menormalkan tanggal, idempoten, dan terisolasi dari Rutinitas', () async {
    final entry = await repository.create(
      id: 'schedule-1',
      householdId: householdId,
      title: '  Antar\n\n\n anak  ',
      note: '  ke sekolah  ',
      scheduledDate: DateTime(2026, 8, 28, 18),
      isAllDay: false,
      startMinutes: 7 * 60,
      endMinutes: 7 * 60 + 30,
    );
    final repeated = await repository.create(
      id: 'schedule-1',
      householdId: householdId,
      title: 'Antar\n\n anak',
      note: 'ke sekolah',
      scheduledDate: DateTime(2026, 8, 28),
      isAllDay: false,
      startMinutes: 7 * 60,
      endMinutes: 7 * 60 + 30,
    );

    expect(entry.title, 'Antar\n\n anak');
    expect(entry.scheduledDate, DateTime(2026, 8, 28));
    expect(entry.timeRangeLabel, '07:00–07:30');
    expect(repeated.id, entry.id);
    expect((await database.select(database.dailyRoutines).get()), isEmpty);
  });

  test('Jadwal sepanjang hari, update, dan arsip menyimpan audit tanpa membuat Pengingat', () async {
    final entry = await repository.create(
      id: 'schedule-2',
      householdId: householdId,
      title: 'Libur keluarga',
      scheduledDate: now,
    );
    expect(entry.isAllDay, isTrue);
    expect(entry.timeRangeLabel, isNull);

    final updated = await repository.update(
      householdId: householdId,
      id: entry.id,
      title: 'Libur keluarga di rumah',
      note: 'tanpa alarm',
      scheduledDate: now.add(const Duration(days: 1)),
    );
    expect(updated?.scheduledDate, DateTime(2026, 8, 26));
    final archived = await repository.archive(
      householdId: householdId,
      id: entry.id,
    );
    expect(archived?.isArchived, isTrue);
    expect(await repository.readActive(householdId), isEmpty);
    expect((await database.select(database.reminders).get()), isEmpty);

    final logs = await database
        .customSelect(
          "SELECT action FROM audit_logs WHERE entity = 'schedule_entry'",
        )
        .get();
    expect(
      logs.map((row) => row.read<String>('action')),
      containsAll(['create', 'update', 'archive']),
    );
  });

  test('waktu dan idempotency key yang tidak valid ditolak', () async {
    expect(
      () => repository.create(
        householdId: householdId,
        title: 'Jadwal tanpa jam mulai',
        scheduledDate: now,
        isAllDay: false,
      ),
      throwsArgumentError,
    );
    expect(
      () => repository.create(
        householdId: householdId,
        title: 'Jadwal waktu terbalik',
        scheduledDate: now,
        isAllDay: false,
        startMinutes: 600,
        endMinutes: 599,
      ),
      throwsArgumentError,
    );
    await repository.create(
      id: 'schedule-3',
      householdId: householdId,
      title: 'Kontrol kesehatan',
      scheduledDate: now,
    );
    expect(
      () => repository.create(
        id: 'schedule-3',
        householdId: householdId,
        title: 'Kontrol lain',
        scheduledDate: now,
      ),
      throwsArgumentError,
    );
  });
}
