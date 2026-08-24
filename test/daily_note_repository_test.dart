import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/daily_notes/data/daily_note_repository.dart';

void main() {
  const householdId = 'local-household';
  late AppDatabase database;
  late DailyNoteRepository repository;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    repository = DailyNoteRepository(
      database,
      AuditLogger(database),
      clock: () => DateTime(2026, 8, 25, 9, 30),
    );
  });

  tearDown(() => database.close());

  test(
    'simpan dan baca Catatan Harian tanpa mengubah tabel aktivitas',
    () async {
      final note = await repository.create(
        householdId: householdId,
        noteDate: DateTime(2026, 8, 25, 17, 45),
        title: '  Ringkasan hari ini  ',
        body: 'Belanja sudah dicatat.\n\n\nBesok cek anggaran.',
      );

      final active = await repository.readActive(householdId);
      final activityRows = await database
          .select(database.activityEntries)
          .get();

      expect(note.noteDate, DateTime(2026, 8, 25));
      expect(note.title, 'Ringkasan hari ini');
      expect(note.body, 'Belanja sudah dicatat.\n\nBesok cek anggaran.');
      expect(active, hasLength(1));
      expect(activityRows, isEmpty);
    },
  );

  test('update disanitasi, soft-archive tidak menghapus catatan, dan readback tetap tersedia', () async {
    final note = await repository.create(
      householdId: householdId,
      noteDate: DateTime(2026, 8, 25),
      body: 'Catatan awal',
    );

    final updated = await repository.update(
      householdId: householdId,
      id: note.id,
      noteDate: DateTime(2026, 8, 24),
      title: '\u0000 Update ',
      body: '  Isi akhir  ',
    );
    final archived = await repository.archive(
      householdId: householdId,
      id: note.id,
    );
    final active = await repository.readActive(householdId);

    expect(updated?.noteDate, DateTime(2026, 8, 24));
    expect(updated?.title, 'Update');
    expect(updated?.body, 'Isi akhir');
    expect(archived?.isArchived, isTrue);
    expect(await repository.get(householdId, note.id), isNotNull);
    expect(active, isEmpty);
  });

  test('menolak catatan kosong atau terlalu panjang tanpa write', () async {
    expect(
      () => repository.create(
        householdId: householdId,
        noteDate: DateTime(2026, 8, 25),
        body: '   ',
      ),
      throwsArgumentError,
    );
    expect(
      () => repository.create(
        householdId: householdId,
        noteDate: DateTime(2026, 8, 25),
        body: 'x' * (DailyNoteRepository.maxBodyLength + 1),
      ),
      throwsArgumentError,
    );
  });

  test(
    'id eksplisit yang sama bersifat idempoten dan menolak isi berbeda',
    () async {
      final first = await repository.create(
        id: 'agent-note-1',
        householdId: householdId,
        noteDate: DateTime(2026, 8, 25),
        title: 'Rencana',
        body: 'Cek kebutuhan besok.',
      );
      final repeated = await repository.create(
        id: 'agent-note-1',
        householdId: householdId,
        noteDate: DateTime(2026, 8, 25),
        title: 'Rencana',
        body: 'Cek kebutuhan besok.',
      );

      expect(repeated.id, first.id);
      expect(await repository.readActive(householdId), hasLength(1));
      expect(
        () => repository.create(
          id: 'agent-note-1',
          householdId: householdId,
          noteDate: DateTime(2026, 8, 25),
          body: 'Isi berbeda.',
        ),
        throwsArgumentError,
      );
    },
  );
}
