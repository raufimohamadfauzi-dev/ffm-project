import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/routines/data/routine_repository.dart';

void main() {
  final now = DateTime(2026, 8, 25, 11);
  late AppDatabase database;
  late RoutineRepository routines;
  late FfmAssistantInterpreter interpreter;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    routines = RoutineRepository(
      database,
      AuditLogger(database),
      clock: () => now,
    );
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
  });

  tearDown(() => database.close());

  test(
    'buat Rutinitas hanya menyiapkan draft tanpa write atau notifikasi',
    () async {
      final intent = await interpreter.interpret('buat rutinitas minum air');

      expect(intent.type, FfmAssistantIntentType.createRoutine);
      expect(intent.destination, FfmAssistantDestination.activity);
      expect(intent.draft?.kind, FfmAssistantDraftKind.routine);
      expect(intent.draft?.title, 'minum air');
      expect(intent.needsConfirmation, isTrue);
      expect(await routines.readActive(AppContext.householdId), isEmpty);
    },
  );

  test(
    'tandai Rutinitas target tunggal menyiapkan draft tanpa write',
    () async {
      final routine = await routines.create(
        householdId: AppContext.householdId,
        title: 'Minum air',
      );

      final intent = await interpreter.interpret(
        'tandai selesai rutinitas minum air hari ini',
      );

      expect(intent.type, FfmAssistantIntentType.markRoutineComplete);
      expect(intent.draft?.kind, FfmAssistantDraftKind.routineMarkComplete);
      expect(intent.draft?.formValues['targetId'], routine.id);
      expect(intent.needsConfirmation, isTrue);
      expect(
        await routines.completionForDay(
          householdId: AppContext.householdId,
          routineId: routine.id,
          day: now,
        ),
        isNull,
      );
    },
  );

  test(
    'arsip Rutinitas ambigu meminta klarifikasi tanpa memilih target',
    () async {
      await routines.create(
        id: 'routine-morning',
        householdId: AppContext.householdId,
        title: 'Olahraga pagi',
      );
      await routines.create(
        id: 'routine-evening',
        householdId: AppContext.householdId,
        title: 'Olahraga sore',
      );

      final intent = await interpreter.interpret('arsipkan rutinitas olahraga');

      expect(intent.type, FfmAssistantIntentType.archiveRoutine);
      expect(intent.draft, isNull);
      expect(intent.clarification, contains('menemukan 2 Rutinitas'));
    },
  );
}
