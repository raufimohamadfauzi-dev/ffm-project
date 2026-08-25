import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/schedule/data/schedule_repository.dart';

void main() {
  final now = DateTime(2026, 8, 25, 11);
  late AppDatabase database;
  late ScheduleRepository schedules;
  late FfmAssistantInterpreter interpreter;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    schedules = ScheduleRepository(
      database,
      AuditLogger(database),
      clock: () => now,
    );
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
  });

  tearDown(() => database.close());

  test(
    'buat Jadwal hanya menyiapkan draft tanpa write atau notifikasi',
    () async {
      final intent = await interpreter.interpret(
        'buat jadwal kontrol dokter besok jam 09.30',
      );

      expect(intent.type, FfmAssistantIntentType.createSchedule);
      expect(intent.destination, FfmAssistantDestination.activity);
      expect(intent.draft?.kind, FfmAssistantDraftKind.schedule);
      expect(intent.draft?.title, 'kontrol dokter');
      expect(intent.draft?.date, DateTime(2026, 8, 26));
      expect(intent.draft?.formValues['startMinutes'], '570');
      expect(intent.needsConfirmation, isTrue);
      expect(await schedules.readActive(AppContext.householdId), isEmpty);
      expect((await database.select(database.reminders).get()), isEmpty);
    },
  );

  test('pindah Jadwal target tunggal menyiapkan draft tanpa write', () async {
    final entry = await schedules.create(
      householdId: AppContext.householdId,
      title: 'Kontrol dokter',
      scheduledDate: now,
    );

    final intent = await interpreter.interpret(
      'pindahkan jadwal kontrol dokter ke besok',
    );

    expect(intent.type, FfmAssistantIntentType.updateSchedule);
    expect(intent.draft?.kind, FfmAssistantDraftKind.scheduleUpdate);
    expect(intent.draft?.formValues['targetId'], entry.id);
    expect(intent.draft?.date, DateTime(2026, 8, 26));
    expect(
      (await schedules.get(AppContext.householdId, entry.id))?.scheduledDate,
      DateTime(2026, 8, 25),
    );
  });

  test(
    'arsip Jadwal ambigu meminta klarifikasi tanpa memilih target',
    () async {
      await schedules.create(
        id: 'schedule-school-morning',
        householdId: AppContext.householdId,
        title: 'Antar sekolah pagi',
        scheduledDate: now,
      );
      await schedules.create(
        id: 'schedule-school-afternoon',
        householdId: AppContext.householdId,
        title: 'Jemput sekolah sore',
        scheduledDate: now,
      );

      final intent = await interpreter.interpret('arsipkan jadwal sekolah');

      expect(intent.type, FfmAssistantIntentType.archiveSchedule);
      expect(intent.draft, isNull);
      expect(intent.clarification, contains('menemukan 2 Jadwal'));
    },
  );
}
