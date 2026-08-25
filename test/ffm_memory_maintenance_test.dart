import 'package:drift/drift.dart' hide Column, isNull;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_memory_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_memory_learning_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_memory_maintenance_service.dart';

void main() {
  late AppDatabase db;
  late FfmAssistantMemoryRepository repo;

  setUp(() {
    db = createInMemoryDatabaseForTests();
    repo = FfmAssistantMemoryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> seedMemory({
    required String id,
    required DateTime createdAt,
    int useCount = 0,
    double importance = 0.5,
    bool archived = false,
  }) async {
    final record = await repo.save(
      id: id,
      kind: 'explicitfact',
      triggerText: 'fakta-$id',
      valueText: 'isi-$id',
      metadata: {'useCount': useCount, 'importance': importance},
    );
    if (archived) await repo.archive(record.id);
    // Paksa createdAt tua langsung di database untuk simulasi usia.
    await (db.update(
      db.assistantMemories,
    )..where((row) => row.id.equals(id))).write(
      AssistantMemoriesCompanion(createdAt: Value(createdAt)),
    );
    return record.id;
  }

  test('decay sekali jalan: memori tua jarang dipakai diarsipkan', () async {
    final oldId = await seedMemory(
      id: 'tua',
      createdAt: DateTime.now().subtract(const Duration(days: 200)),
      // Decay memangkas importance ~50% pada usia ini; 0.3 -> ~0.15 < 0.2.
      importance: 0.3,
    );
    final freshId = await seedMemory(id: 'baru', createdAt: DateTime.now());
    final service = FfmMemoryMaintenanceService(
      learning: FfmMemoryLearningService(memoryRepository: repo),
      repository: repo,
    );

    await service.runDecayOnce();

    final all = await repo.readAll();
    final oldRow = all.firstWhere((row) => row.id == oldId);
    final freshRow = all.firstWhere((row) => row.id == freshId);
    expect(oldRow.isArchived, isTrue);
    expect(freshRow.isArchived, isFalse);
  });

  test('memori penting dan sering dipakai selamat dari decay', () async {
    final goalId = await seedMemory(
      id: 'goal',
      createdAt: DateTime.now().subtract(const Duration(days: 300)),
      importance: 1.0,
    );
    final usedId = await seedMemory(
      id: 'sering',
      createdAt: DateTime.now().subtract(const Duration(days: 300)),
      useCount: 5,
    );
    final service = FfmMemoryMaintenanceService(
      learning: FfmMemoryLearningService(memoryRepository: repo),
      repository: repo,
    );

    await service.runDecayOnce();

    final all = await repo.readAll();
    expect(all.firstWhere((row) => row.id == goalId).isArchived, isFalse);
    expect(all.firstWhere((row) => row.id == usedId).isArchived, isFalse);
  });

  test('jadwal start(): decay jalan setelah delay lalu berulang tiap interval',
      () async {
    fakeAsync((async) {
      final service = FfmMemoryMaintenanceService(
        learning: FfmMemoryLearningService(memoryRepository: repo),
        repository: repo,
      );
      service.start(initialDelay: Duration.zero);
      // runDecayOnce async; beri kesempatan microtask+timer.
      async.elapse(const Duration(milliseconds: 5));
      service.stop();

      // Tidak ada exception; timer periodik terpasang lalu dibersihkan.
      service.start(initialDelay: const Duration(hours: 25));
      async.elapse(const Duration(hours: 26));
      service.dispose();
      service.dispose(); // dispose ganda aman
    });
  });

  test('runDecayOnce tidak menumpuk saat siklus masih berjalan', () async {
    var calls = 0;
    final slowLearning = _CountingLearningService(
      onRun: () async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
      repository: repo,
    );
    final service = FfmMemoryMaintenanceService(
      learning: slowLearning,
      repository: repo,
    );

    final first = service.runDecayOnce();
    await service.runDecayOnce(); // diabaikan karena siklus pertama berjalan
    await first;

    expect(calls, 1);
  });
}

class _CountingLearningService extends FfmMemoryLearningService {
  _CountingLearningService({
    required this.onRun,
    required FfmAssistantMemoryRepository repository,
  }) : super(memoryRepository: repository);

  final Future<void> Function() onRun;

  @override
  Future<void> applyMemoryDecay({
    required FfmAssistantMemoryRepository repository,
    Duration maxAge = const Duration(days: 180),
    int minUseCount = 2,
  }) async {
    await onRun();
  }
}
