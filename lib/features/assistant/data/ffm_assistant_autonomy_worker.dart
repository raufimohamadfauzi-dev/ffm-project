import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/audit_logger.dart';
import '../../budget/data/budget_repository.dart';
import 'ffm_assistant_autonomy_repository.dart';
import 'ffm_assistant_autonomy_llm_service.dart';
import 'ffm_assistant_autonomy_conversation_repository.dart';
import 'ffm_assistant_autonomy_job_repository.dart';
import 'ffm_assistant_autonomy_internet_service.dart';
import 'ffm_assistant_budget_autonomy_event_service.dart';
import 'ffm_assistant_budget_autonomy_repository.dart';
import 'ffm_assistant_learning_candidate_service.dart';
import 'ffm_gemini_cloud_orchestrator.dart';
import '../domain/ffm_assistant_budget_autonomy_service.dart';

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
    FfmAssistantBudgetAutonomyEventService? budgetAutonomyEventService,
    this.llmService,
    this.jobRepository,
    this.conversationRepository,
    this.internetService,
  }) : budgetAutonomyEventService =
           budgetAutonomyEventService ??
           (database == null
               ? null
               : _createBudgetAutonomyEventService(database));

  final FfmAssistantAutonomyRepository repository;
  final int maxEventsPerRun;
  final int maxAttempts;
  final FfmAssistantLearningCandidateService? candidateService;
  final AppDatabase? database;
  final FfmAssistantBudgetAutonomyEventService? budgetAutonomyEventService;
  final FfmAssistantAutonomyLlmService? llmService;
  final FfmAssistantAutonomyJobRepository? jobRepository;
  final FfmAssistantAutonomyConversationRepository? conversationRepository;
  final FfmAssistantAutonomyInternetService? internetService;

  Future<FfmAssistantAutonomyWorkerRunResult> runOnce(
    FfmAssistantAutonomyWorkerHandler handler, {
    String householdId = FfmAssistantAutonomyRepository.householdId,
  }) async {
    var enqueued = await repository.enqueueDueTaskEvents(
      householdId: householdId,
      limit: maxEventsPerRun,
    );
    final budgetEvents = budgetAutonomyEventService;
    if (budgetEvents != null) {
      enqueued += await budgetEvents.enqueueCandidates(
        householdId: householdId,
      );
    }
    await processPendingJobs(householdId: householdId);
    final events = await repository.pendingEvents(
      householdId: householdId,
      limit: maxEventsPerRun,
      maxAttempts: maxAttempts,
    );
    var processed = 0;
    var duplicates = 0;
    var failed = 0;
    for (final event in events) {
      final result = await repository.processEvent(event, (event) async {
        if (event.type == FfmAssistantBudgetAutonomyEventService.eventType &&
            budgetEvents != null) {
          await budgetEvents.handle(event);
          return;
        }
        await handler(event);
      });
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

  /// Menjalankan job otonom dengan LLM decision.
  ///
  /// [jobType] - Tipe job otonom (budget_adjust, reminder_check, dll)
  /// [userPrompt] - Prompt untuk LLM
  /// [context] - Context tambahan untuk LLM
  /// [onDecision] - Callback untuk handle decision dari LLM
  Future<void> runAutonomyJobWithLlm({
    required String householdId,
    required String jobType,
    required String userPrompt,
    String? context,
    required Future<void> Function(AutonomyLlmDecision decision) onDecision,
  }) async {
    final llm = llmService;
    final jobRepo = jobRepository;
    final internet = internetService;
    if (llm == null || jobRepo == null) {
      // Fallback: jika LLM service tidak tersedia, report error
      debugPrint(
        'LLM service or job repository not available for autonomy job',
      );
      return;
    }

    try {
      // 1. Cek internet availability
      final isOnline = internet == null || await internet.checkInternet();
      if (!isOnline) {
        debugPrint('Internet not available, queueing autonomy job for later');
        // Job masih dibuat dengan status pending, tapi tidak di-execute
        await jobRepo.createJob(
          householdId: householdId,
          type: jobType,
          triggerData: _jobRequestData(userPrompt, context),
        );
        return;
      }

      // 2. Create job record
      final job = await jobRepo.createJob(
        householdId: householdId,
        type: jobType,
        triggerData: _jobRequestData(userPrompt, context),
      );

      // 3. Request LLM decision
      final decision = await llm.requestDecision(
        jobId: job.id,
        householdId: householdId,
        userPrompt: userPrompt,
        context: context,
      );

      // 4. Handle decision
      if (decision.isFailure) {
        debugPrint('LLM decision failed: ${decision.errorMessage}');
        return;
      }

      // 5. Apply autonomy policy filter
      final filteredDecision = llm.filterDecisionForAutonomy(decision);

      // 6. Execute decision
      await onDecision(filteredDecision);
    } catch (e, st) {
      debugPrint('Autonomy job with LLM failed: $e\n$st');
    }
  }

  /// Memproses job yang pending (saat internet tersedia).
  Future<void> processPendingJobs({required String householdId}) async {
    final jobRepo = jobRepository;
    final internet = internetService;
    final llm = llmService;
    if (jobRepo == null || internet == null || llm == null) return;

    // Cek internet
    if (!await internet.checkInternet()) {
      debugPrint('Internet not available, skipping pending jobs');
      return;
    }

    // Get pending jobs
    final pendingJobs = await jobRepo.getJobsByStatus(householdId, 'pending');
    for (final job in pendingJobs) {
      try {
        final request = _jobRequestFrom(job);
        if (request == null) {
          await jobRepo.updateJobStatus(
            job.id,
            'failed',
            completedAt: DateTime.now(),
            resultData: {
              'error': 'Job offline lama tidak memiliki permintaan LLM untuk dilanjutkan.',
            },
          );
          continue;
        }

        // Update job status to in_progress
        await jobRepo.updateJobStatus(
          job.id,
          'in_progress',
          startedAt: DateTime.now(),
        );

        // Request LLM decision
        final decision = await llm.requestDecision(
          jobId: job.id,
          householdId: householdId,
          userPrompt: request.userPrompt,
          context: request.context,
        );

        if (decision.isFailure) {
          await jobRepo.updateJobStatus(
            job.id,
            'failed',
            completedAt: DateTime.now(),
            resultData: {'error': decision.errorMessage},
          );
          continue;
        }

        // Apply autonomy policy filter
        final filteredDecision = llm.filterDecisionForAutonomy(decision);

        // Execute decision via callback (caller should provide executor)
        // For now, we'll mark the job as completed with the decision data
        // The actual execution should be handled by the caller via onDecision callback
        await jobRepo.updateJobStatus(
          job.id,
          'completed',
          completedAt: DateTime.now(),
          resultData: {
            'action': filteredDecision.action,
            'parameters': filteredDecision.parameters,
            'text': filteredDecision.text,
          },
        );
      } catch (e, st) {
        debugPrint('Failed to process pending job ${job.id}: $e\n$st');
        await jobRepo.updateJobStatus(
          job.id,
          'failed',
          completedAt: DateTime.now(),
          resultData: {'error': e.toString()},
        );
      }
    }
  }

  static Map<String, Object?> _jobRequestData(
    String userPrompt,
    String? context,
  ) => {
    'userPrompt': userPrompt,
    if (context != null && context.isNotEmpty) 'context': context,
  };

  static _QueuedAutonomyRequest? _jobRequestFrom(AutonomyJob job) {
    final raw = job.triggerData;
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final userPrompt = data['userPrompt']?.toString().trim();
      if (userPrompt == null || userPrompt.isEmpty) return null;
      final context = data['context']?.toString();
      return _QueuedAutonomyRequest(userPrompt, context);
    } on FormatException {
      return null;
    }
  }

  static FfmAssistantBudgetAutonomyEventService
  _createBudgetAutonomyEventService(AppDatabase database) {
    final budgetRepository = BudgetRepository(database, AuditLogger(database));
    final delegationRepository = FfmAssistantBudgetAutonomyRepository(database);
    return FfmAssistantBudgetAutonomyEventService(
      eventRepository: FfmAssistantAutonomyRepository(database),
      delegationRepository: delegationRepository,
      budgetRepository: budgetRepository,
      budgetAutonomyService: FfmAssistantBudgetAutonomyService(
        database,
        budgetRepository,
        delegationRepository,
      ),
    );
  }

  /// Mengonsolidasi memori di background secara otonom berdasarkan observasi transaksi terbaru.
  Future<void> consolidateMemory({required String householdId}) async {
    final db = database;
    final service = candidateService;
    if (db == null || service == null) return;

    try {
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final allTxs = await (db.select(
        db.transactions,
      )..where((row) => row.householdId.equals(householdId))).get();

      final recent = allTxs
          .where(
            (t) =>
                !t.isArchived &&
                !t.isDeleted &&
                t.date.isAfter(sevenDaysAgo) &&
                t.merchantId != null &&
                t.categoryId != null,
          )
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
            final merchant = await (db.select(
              db.merchants,
            )..where((m) => m.id.equals(mId))).getSingleOrNull();
            final category = await (db.select(
              db.categories,
            )..where((c) => c.id.equals(catEntry.key))).getSingleOrNull();
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
                    },
                  ],
                  source: 'background-autonomy-memory',
                );
              }
            }
          }
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Background memory consolidation error: $e\n$st');
      }
    }
  }

  /// Factory untuk membuat LLM service untuk worker.
  static FfmAssistantAutonomyLlmService? createLlmService(
    AppDatabase database,
    FfmGeminiCloudOrchestrator orchestrator,
  ) {
    final jobRepo = FfmAssistantAutonomyJobRepository(database);
    final conversationRepo = FfmAssistantAutonomyConversationRepository(
      database,
    );
    return FfmAssistantAutonomyLlmService(
      orchestrator: orchestrator,
      jobRepository: jobRepo,
      conversationRepository: conversationRepo,
    );
  }
}

class _QueuedAutonomyRequest {
  const _QueuedAutonomyRequest(this.userPrompt, this.context);

  final String userPrompt;
  final String? context;
}
