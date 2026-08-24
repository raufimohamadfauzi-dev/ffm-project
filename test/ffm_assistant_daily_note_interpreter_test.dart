import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/daily_notes/data/daily_note_repository.dart';

void main() {
  final now = DateTime(2026, 8, 25, 11);
  late AppDatabase database;
  late DailyNoteRepository notes;
  late FfmAssistantInterpreter interpreter;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    notes = DailyNoteRepository(
      database,
      AuditLogger(database),
      clock: () => now,
    );
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
  });

  tearDown(() => database.close());

  test('buat Catatan Harian hanya menyiapkan draft tanpa write', () async {
    final intent = await interpreter.interpret(
      'catat catatan harian: Belanja kebutuhan sudah selesai',
    );

    expect(intent.type, FfmAssistantIntentType.createDailyNote);
    expect(intent.destination, FfmAssistantDestination.activity);
    expect(intent.draft?.kind, FfmAssistantDraftKind.dailyNote);
    expect(intent.draft?.note, 'Belanja kebutuhan sudah selesai');
    expect(intent.needsConfirmation, isTrue);
    expect(await notes.readActive(AppContext.householdId), isEmpty);
  });

  test(
    'arsip Catatan Harian membuat draft tanpa write sebelum konfirmasi',
    () async {
      final note = await notes.create(
        householdId: AppContext.householdId,
        noteDate: now,
        title: 'Pasar pagi',
        body: 'Belanja kebutuhan rumah.',
      );

      final intent = await interpreter.interpret(
        'arsipkan catatan harian pasar',
      );

      expect(intent.type, FfmAssistantIntentType.archiveDailyNote);
      expect(intent.destination, FfmAssistantDestination.activity);
      expect(intent.draft?.kind, FfmAssistantDraftKind.dailyNoteArchive);
      expect(intent.draft?.formValues['targetId'], note.id);
      expect(intent.needsConfirmation, isTrue);
      expect(await notes.get(AppContext.householdId, note.id), isNotNull);
      expect(
        (await notes.get(AppContext.householdId, note.id))?.isArchived,
        isFalse,
      );
    },
  );

  test(
    'arsip Catatan Harian ambigu tidak memilih target secara diam-diam',
    () async {
      await notes.create(
        id: 'daily-note-market-morning',
        householdId: AppContext.householdId,
        noteDate: now,
        title: 'Pasar pagi',
        body: 'Belanja kebutuhan rumah.',
      );
      await notes.create(
        id: 'daily-note-market-evening',
        householdId: AppContext.householdId,
        noteDate: now.subtract(const Duration(days: 1)),
        title: 'Pasar sore',
        body: 'Belanja sayur.',
      );

      final intent = await interpreter.interpret('arsipkan catatan pasar');

      expect(intent.type, FfmAssistantIntentType.archiveDailyNote);
      expect(intent.draft, isNull);
      expect(intent.clarification, contains('menemukan 2 Catatan Harian'));
    },
  );
}
