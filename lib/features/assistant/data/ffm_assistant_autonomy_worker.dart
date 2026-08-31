import 'ffm_assistant_autonomy_repository.dart';

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
  });

  final FfmAssistantAutonomyRepository repository;
  final int maxEventsPerRun;
  final int maxAttempts;

  Future<FfmAssistantAutonomyWorkerRunResult> runOnce(
    FfmAssistantAutonomyWorkerHandler handler,
  ) async {
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
    return FfmAssistantAutonomyWorkerRunResult(
      enqueued: enqueued,
      attempted: events.length,
      processed: processed,
      duplicates: duplicates,
      failed: failed,
    );
  }
}
