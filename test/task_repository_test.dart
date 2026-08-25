import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/tasks/data/task_repository.dart';
import 'package:ffm_manager/features/tasks/domain/entities/task_entity.dart';

void main() {
  const householdId = 'local-household';
  final now = DateTime(2026, 8, 25, 10);
  late AppDatabase database;
  late TaskRepository repository;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    repository = TaskRepository(
      database,
      AuditLogger(database),
      clock: () => now,
    );
  });

  tearDown(() => database.close());

  test(
    'buat Tugas sanitasi, idempoten, dan tidak menyentuh Catatan Harian',
    () async {
      final task = await repository.create(
        id: 'task-1',
        householdId: householdId,
        title: '  Bayar\n\n\n listrik  ',
        note: '  sebelum jatuh tempo  ',
        dueDate: now.add(const Duration(days: 2)),
      );
      final repeated = await repository.create(
        id: 'task-1',
        householdId: householdId,
        title: 'Bayar\n\n listrik',
        note: 'sebelum jatuh tempo',
        dueDate: now.add(const Duration(days: 2)),
      );

      expect(task.title, 'Bayar\n\n listrik');
      expect(task.note, 'sebelum jatuh tempo');
      expect(repeated.id, task.id);
      expect(await repository.readActive(householdId), hasLength(1));
      expect((await database.select(database.dailyNotes).get()), isEmpty);
    },
  );

  test(
    'selesai, buka kembali, dan arsip menyimpan jejak audit lokal',
    () async {
      final task = await repository.create(
        id: 'task-2',
        householdId: householdId,
        title: 'Cek anggaran',
      );

      final completed = await repository.complete(
        householdId: householdId,
        id: task.id,
      );
      expect(completed?.status, TaskStatus.completed);
      expect(completed?.completedAt, now);

      final reopened = await repository.reopen(
        householdId: householdId,
        id: task.id,
      );
      expect(reopened?.status, TaskStatus.open);
      expect(reopened?.completedAt, isNull);

      final archived = await repository.archive(
        householdId: householdId,
        id: task.id,
      );
      expect(archived?.isArchived, isTrue);
      expect(await repository.readActive(householdId), isEmpty);

      final logs = await database
          .customSelect("SELECT action FROM audit_logs WHERE entity = 'task'")
          .get();
      expect(
        logs.map((row) => row.read<String>('action')),
        containsAll(['create', 'complete', 'reopen', 'archive']),
      );
    },
  );

  test('judul kosong dan key idempoten dengan isi berbeda ditolak', () async {
    expect(
      () => repository.create(householdId: householdId, title: '   '),
      throwsArgumentError,
    );
    await repository.create(
      id: 'task-3',
      householdId: householdId,
      title: 'Belanja',
    );
    expect(
      () => repository.create(
        id: 'task-3',
        householdId: householdId,
        title: 'Belanja lain',
      ),
      throwsArgumentError,
    );
  });
}
