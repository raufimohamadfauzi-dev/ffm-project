import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/activity/data/repositories/activity_repository.dart';
import 'package:ffm_manager/features/activity/domain/entities/activity_entity.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  final now = DateTime(2026, 8, 24, 11);
  late AppDatabase database;
  late FfmAssistantInterpreter interpreter;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seed({
    required String id,
    required String title,
    ActivitySessionStatus status = ActivitySessionStatus.completed,
  }) => ActivityRepository(database, AuditLogger(database)).saveSession(
    ActivitySessionEntity(
      id: id,
      householdId: AppContext.householdId,
      title: title,
      category: 'Keluarga',
      startedAt: now.subtract(const Duration(hours: 1)),
      endedAt: status == ActivitySessionStatus.active ? null : now,
      status: status,
      createdAt: now.subtract(const Duration(hours: 1)),
      updatedAt: now,
    ),
  );

  test(
    'arsip aktivitas membuat draft lokal tanpa write sebelum konfirmasi',
    () async {
      await seed(id: 'market', title: 'Belanja pasar');

      final intent = await interpreter.interpret('arsipkan aktivitas pasar');

      expect(intent.type, FfmAssistantIntentType.archiveActivity);
      expect(intent.destination, FfmAssistantDestination.activity);
      expect(intent.draft?.kind, FfmAssistantDraftKind.activityArchive);
      expect(intent.draft?.formValues['entity'], 'activity_session');
      expect(intent.draft?.formValues['targetId'], 'market');
      expect(intent.needsConfirmation, isTrue);
      final activity = await ActivityRepository(
        database,
        AuditLogger(database),
      ).getSession(AppContext.householdId, 'market');
      expect(activity?.isArchived, isFalse);
    },
  );

  test(
    'hapus aktivitas ambigu tidak memilih target secara diam-diam',
    () async {
      await seed(id: 'meal-a', title: 'Makan pagi');
      await seed(id: 'meal-b', title: 'Makan malam');

      final intent = await interpreter.interpret('hapus aktivitas makan');

      expect(intent.type, FfmAssistantIntentType.deleteActivity);
      expect(intent.draft, isNull);
      expect(intent.clarification, contains('menemukan 2 aktivitas'));
    },
  );

  test(
    'aktivitas aktif tidak menghasilkan draft archive atau delete',
    () async {
      await seed(
        id: 'travel',
        title: 'Perjalanan kebun',
        status: ActivitySessionStatus.active,
      );

      final intent = await interpreter.interpret('hapus aktivitas perjalanan');

      expect(intent.type, FfmAssistantIntentType.deleteActivity);
      expect(intent.draft, isNull);
      expect(intent.clarification, contains('masih berjalan'));
    },
  );
}
