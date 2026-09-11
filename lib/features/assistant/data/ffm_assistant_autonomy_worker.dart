import '../../../core/database/app_database.dart';
import 'ffm_assistant_autonomy_repository.dart';
import 'ffm_assistant_learning_candidate_service.dart';

typedef FfmAssistantAutonomyWorkerHandler = Future<void> Function(
  FfmAssistantAutonomyEvent event,
);

class FfmAssistantAutonomyWorkerRunResult {
  const FfmAssistantAutonomyWorkerRunResult({
    required this.enqueued,
    required this.attempted,
    required this.processed,
    required this.duplicates,
    required this.failed,
  });

  final int enqueued;
  final int attempted;
  final int processed;
  final int duplicates;
  final int failed;
}

/// Menjalankan satu batch event durable. Scheduler Android/backend dapat
/// memanggil [runOnce] tanpa menaruh loop tak terbatas di UI.
class FfmAssistantAutonomyWorker {
  FfmAssistantAutonomyWorker({
    required this.repository,
    this.maxEventsPerRun = 10,
    this.maxAttempts = 3,
    this.candidateService,
    this.database,
  });

  final FfmAssistantAutonomyRepository repository;
  final int maxEventsPerRun;
  final int maxAttempts;
  final FfmAssistantLearningCandidateService? candidateService;
  final AppDatabase? database;

  Future<FfmAssistantAutonomyWorkerRunResult> runOnce(
    FfmAssistantAutonomyWorkerHandler handler, {
    String householdId = FfmAssistantAutonomyRepository.householdId,
  }) async {
    final enqueued = await repository.enqueueDueTaskEvents(
      limit: maxEventsPerRun,
    );
    final events = await repository.pendingEvents(
      limit: maxEventsPerRun,
      maxAttempts: maxAttempts,
    );
    var processed = 0;
    var duplicates = 0;
    var failed = 0;
    for (final event in events) {
      final result = await repository.processEvent(event, handler);
      switch (result) {
        case FfmAssistantAutonomyEventProcessResult.processed:
          processed++;
        case FfmAssistantAutonomyEventProcessResult.duplicate:
          duplicates++;
        case FfmAssistantAutonomyEventProcessResult.failed:
          failed++;
      }
    }

    await consolidateMemory(householdId: householdId);

    return FfmAssistantAutonomyWorkerRunResult(
      enqueued: enqueued,
      attempted: events.length,
      processed: processed,
      duplicates: duplicates,
      failed: failed,
    );
  }

  /// Mengonsolidasi memori di background secara otonom berdasarkan observasi transaksi terbaru.
  Future<void> consolidateMemory({
    required String householdId,
  }) async {
    final db = database;
    final service = candidateService;
    if (db == null || service == null) return;

    try {
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final allTxs = await (db.select(db.transactions)
            ..where((row) => row.householdId.equals(householdId)))
          .get();

      final recent = allTxs
          .where((t) =>
              !t.isArchived &&
              !t.isDeleted &&
              t.date.isAfter(sevenDaysAgo) &&
              t.merchantId != null &&
              t.categoryId != null)
          .toList();

      final merchantCategoryCount = <String, Map<String, int>>{};

      for (final tx in recent) {
        final mId = tx.merchantId!;
        final cId = tx.categoryId!;
        merchantCategoryCount.putIfAbsent(mId, () => {});
        merchantCategoryCount[mId]![cId] =
            (merchantCategoryCount[mId]![cId] ?? 0) + 1;
      }

      for (final entry in merchantCategoryCount.entries) {
        final mId = entry.key;
        final catMap = entry.value;
        for (final catEntry in catMap.entries) {
          if (catEntry.value >= 3) {
            final merchant = await (db.select(db.merchants)
                  ..where((m) => m.id.equals(mId)))
                .getSingleOrNull();
            final category = await (db.select(db.categories)
                  ..where((c) => c.id.equals(catEntry.key)))
                .getSingleOrNull();
            if (merchant != null && category != null) {
              final trigger = 'otonom.kategori.${merchant.name.toLowerCase()}';
              final pending = await service.readPending();
              if (!pending.any((c) => c.trigger == trigger)) {
                await service.proposeWorkflow(
                  trigger: trigger,
                  steps: [
                    {
                      'capabilityId': 'system.set_merchant_category',
                      'merchantName': merchant.name,
                      'categoryName': category.name,
                    }
                  ],
                  source: 'background-autonomy-memory',
                );
              }
            }
          }
        }
      }
    } catch (_) {}
  }
}
