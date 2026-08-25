import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/tasks/data/task_repository.dart';

void main() {
  final now = DateTime(2026, 8, 25, 11);
  late AppDatabase database;
  late TaskRepository tasks;
  late FfmAssistantInterpreter interpreter;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    tasks = TaskRepository(database, AuditLogger(database), clock: () => now);
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
  });

  tearDown(() => database.close());

  test('buat Tugas hanya menyiapkan draft tanpa write', () async {
    final intent = await interpreter.interpret('buat tugas bayar listrik');

    expect(intent.type, FfmAssistantIntentType.createTask);
    expect(intent.destination, FfmAssistantDestination.activity);
    expect(intent.draft?.kind, FfmAssistantDraftKind.task);
    expect(intent.draft?.title, 'bayar listrik');
    expect(intent.needsConfirmation, isTrue);
    expect(await tasks.readActive(AppContext.householdId), isEmpty);
  });

  test(
    'selesaikan Tugas target tunggal menyiapkan draft tanpa write',
    () async {
      final task = await tasks.create(
        householdId: AppContext.householdId,
        title: 'Bayar listrik',
      );

      final intent = await interpreter.interpret(
        'selesaikan tugas bayar listrik',
      );

      expect(intent.type, FfmAssistantIntentType.completeTask);
      expect(intent.draft?.kind, FfmAssistantDraftKind.taskComplete);
      expect(intent.draft?.formValues['targetId'], task.id);
      expect(intent.needsConfirmation, isTrue);
      expect(
        (await tasks.get(AppContext.householdId, task.id))?.isCompleted,
        isFalse,
      );
    },
  );

  test('arsip Tugas ambigu meminta klarifikasi tanpa memilih target', () async {
    await tasks.create(
      id: 'task-market-morning',
      householdId: AppContext.householdId,
      title: 'Belanja pasar pagi',
    );
    await tasks.create(
      id: 'task-market-evening',
      householdId: AppContext.householdId,
      title: 'Belanja pasar sore',
    );

    final intent = await interpreter.interpret('arsipkan tugas pasar');

    expect(intent.type, FfmAssistantIntentType.archiveTask);
    expect(intent.draft, isNull);
    expect(intent.clarification, contains('menemukan 2 Tugas'));
  });
}
