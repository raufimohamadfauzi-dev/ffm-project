import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/activity/data/repositories/activity_repository.dart';
import 'package:ffm_manager/features/activity/domain/entities/activity_entity.dart';
import 'package:ffm_manager/features/activity/presentation/bloc/activity_bloc.dart';
import 'package:ffm_manager/features/assistant/data/autonomous_activity_repository.dart';
import 'package:ffm_manager/features/assistant/domain/entities/autonomous_activity_models.dart';
import 'package:ffm_manager/features/transaction/domain/usecases/transaction_crud_usecases.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late ActivityRepository activityRepository;
  late AutonomousActivityRepository autonomousRepository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = createInMemoryDatabaseForTests();
    activityRepository = ActivityRepository(database, AuditLogger(database));
    autonomousRepository = AutonomousActivityRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  test('ActivityBloc memuat aksi otonom dari AutonomousActivityRepository', () async {
    final record = AutonomousActivityRecord(
      id: 'auto-1',
      householdId: 'local-household',
      title: 'Pencatatan BBM Otomatis',
      description: 'Konsumsi BBM 25L Pertalite tercatat',
      activityType: AutonomousActivityType.fuelLog,
      occurredAt: DateTime.now(),
      status: AutonomousActivityStatus.active,
    );
    await autonomousRepository.recordActivity(record);

    final bloc = ActivityBloc(
      activityRepository,
      autonomousRepository: autonomousRepository,
    );
    addTearDown(bloc.close);

    await bloc.load();

    expect(bloc.state.autonomousActivities, hasLength(1));
    expect(bloc.state.autonomousActivities.first.id, 'auto-1');
    expect(bloc.state.autonomousActivities.first.title, 'Pencatatan BBM Otomatis');
  });

  test('ActivityBloc revertAutonomousActivity membatalkan aksi otonom', () async {
    final record = AutonomousActivityRecord(
      id: 'auto-revert',
      householdId: 'local-household',
      title: 'Pergeseran Anggaran Defisit',
      description: 'Plafon defisit Rp 50.000 diseimbangkan',
      activityType: AutonomousActivityType.envelopeRebalance,
      occurredAt: DateTime.now(),
      status: AutonomousActivityStatus.active,
    );
    await autonomousRepository.recordActivity(record);

    final bloc = ActivityBloc(
      activityRepository,
      autonomousRepository: autonomousRepository,
    );
    addTearDown(bloc.close);

    await bloc.load();
    expect(bloc.state.autonomousActivities.first.status, AutonomousActivityStatus.active);

    final reverted = await bloc.revertAutonomousActivity('auto-revert');
    expect(reverted, isTrue);

    expect(
      bloc.state.autonomousActivities.first.status,
      AutonomousActivityStatus.reverted,
    );
  });

  test('SaveTransaction menautkan transaksi ke sesi aktif secara otonom dan mencatat checkpoint', () async {
    final now = DateTime.now();
    // Buat sesi aktif
    final session = ActivitySessionEntity(
      id: 'session-trip',
      householdId: 'local-household',
      title: 'Perjalanan Belanja Toko',
      category: 'Perjalanan',
      startedAt: now.subtract(const Duration(minutes: 30)),
      status: ActivitySessionStatus.active,
      createdAt: now.subtract(const Duration(minutes: 30)),
    );
    await activityRepository.saveSession(session);

    final saveTransaction = SaveTransaction(
      database,
      activityRepository: activityRepository,
    );

    final transaction = TransactionEntity(
      id: 'tx-fuel-1',
      householdId: 'local-household',
      date: now,
      amount: -50000,
      owner: 'Ayah',
      categoryId: 'cat-transport',
      note: 'Beli Bensin Pertalite',
      recordedAt: now,
    );

    await saveTransaction(transaction);

    // Verifikasi transaksi tertaut ke sesi aktif
    final dbRows = await (database.select(database.transactions)
          ..where((t) => t.id.equals('tx-fuel-1')))
        .get();
    expect(dbRows, hasLength(1));
    expect(dbRows.first.linkedActivityId, 'session-trip');

    // Verifikasi checkpoint otomatis tercatat di sesi aktif
    final checkpoints = await activityRepository.getCheckpoints('session-trip');
    expect(checkpoints.any((c) => c.label.contains('[🤖 Otonom]')), isTrue);
    expect(checkpoints.any((c) => c.label.contains('50.000')), isTrue);

    // Verifikasi total biaya kegiatan terhitung
    final cost = await activityRepository.getActivityLinkedCost('session-trip');
    expect(cost, 50000);
  });

  test('generateDailyAiJournal menyusun ringkasan sesi kegiatan dan finansial', () async {
    final testDate = DateTime(2026, 9, 8, 15, 0);

    // Sesi 1
    await activityRepository.saveSession(
      ActivitySessionEntity(
        id: 's-1',
        householdId: 'local-household',
        title: 'Kerja di Kebun',
        category: 'Pekerjaan',
        startedAt: testDate.subtract(const Duration(hours: 3)),
        endedAt: testDate.subtract(const Duration(hours: 1)),
        status: ActivitySessionStatus.completed,
        createdAt: testDate.subtract(const Duration(hours: 3)),
      ),
    );

    // Aksi Otonom
    await autonomousRepository.recordActivity(
      AutonomousActivityRecord(
        id: 'auto-harvest',
        householdId: 'local-household',
        title: 'Penyesuaian Siklus Panen',
        description: 'Jadwal panen disesuaikan 30 hari ke depan',
        activityType: AutonomousActivityType.harvestShift,
        occurredAt: testDate,
        status: AutonomousActivityStatus.active,
      ),
    );

    final bloc = ActivityBloc(
      activityRepository,
      autonomousRepository: autonomousRepository,
    );
    addTearDown(bloc.close);

    await bloc.load();

    final journal = await bloc.generateDailyAiJournal(targetDate: testDate);
    expect(journal, isNotNull);
    expect(journal!.title, contains('Refleksi Jurnal Harian'));
    expect(journal.notes, contains('Kerja di Kebun'));
    expect(journal.notes, contains('Penyesuaian Siklus Panen'));
  });
}
