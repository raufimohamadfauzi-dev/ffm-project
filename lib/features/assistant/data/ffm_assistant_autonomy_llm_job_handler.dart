import 'package:flutter/foundation.dart';

import 'ffm_assistant_autonomy_repository.dart';
import 'ffm_assistant_autonomy_llm_service.dart';
import 'ffm_assistant_autonomy_job_repository.dart';
import 'ffm_assistant_autonomy_conversation_repository.dart';
import 'ffm_assistant_autonomy_internet_service.dart';
import 'ffm_assistant_autonomy_task_execution_host.dart';
import 'telegram_delivery_repository.dart';
import 'telegram_config_repository.dart';

/// Handler untuk menjalankan job otonom yang membutuhkan LLM reasoning.
/// Handler ini menerima event, memanggil LLM untuk decision, dan mengeksekusi
/// decision via capability executor dengan policy enforcement.
class FfmAssistantAutonomyLlmJobHandler {
  FfmAssistantAutonomyLlmJobHandler({
    required this.llmService,
    required this.jobRepository,
    required this.conversationRepository,
    required this.internetService,
    required this.executionHost,
    this.telegramDeliveryRepository,
    this.telegramConfigRepository,
  });

  final FfmAssistantAutonomyLlmService llmService;
  final FfmAssistantAutonomyJobRepository jobRepository;
  final FfmAssistantAutonomyConversationRepository conversationRepository;
  final FfmAssistantAutonomyInternetService internetService;
  final FfmAssistantAutonomyTaskExecutionHost executionHost;
  final TelegramDeliveryRepository? telegramDeliveryRepository;
  final TelegramConfigRepository? telegramConfigRepository;

  static const eventType = 'autonomy.llm.job';

  /// Menangani event LLM job.
  Future<void> handle(FfmAssistantAutonomyEvent event) async {
    if (event.type != eventType) {
      throw StateError('Tipe event LLM job tidak valid: ${event.type}');
    }

    // Extract job parameters from event payload
    final jobType = event.payload['jobType'];
    final userPrompt = event.payload['userPrompt'];
    final context = event.payload['context'];

    if (jobType is! String || userPrompt is! String) {
      debugPrint('Invalid LLM job payload: jobType or userPrompt missing');
      return;
    }

    try {
      // 1. Cek internet availability
      final isOnline = await internetService.checkInternet();
      if (!isOnline) {
        debugPrint('Internet not available, queueing LLM job for later');
        // Job masih dibuat dengan status pending, tapi tidak di-execute
        await jobRepository.createJob(
          householdId: event.householdId,
          type: jobType,
          triggerData: _jobRequestData(userPrompt, context),
        );
        return;
      }

      // 2. Create job record
      final job = await jobRepository.createJob(
        householdId: event.householdId,
        type: jobType,
        triggerData: _jobRequestData(userPrompt, context),
      );

      // 3. Request LLM decision
      final decision = await llmService.requestDecision(
        jobId: job.id,
        householdId: event.householdId,
        userPrompt: userPrompt,
        context: context?.toString(),
      );

      // 4. Handle decision
      if (decision.isFailure) {
        debugPrint('LLM decision failed: ${decision.errorMessage}');
        await jobRepository.updateJobStatus(
          job.id,
          'failed',
          completedAt: DateTime.now(),
          resultData: {'error': decision.errorMessage},
        );
        return;
      }

      // 5. Apply autonomy policy filter
      final filteredDecision = llmService.filterDecisionForAutonomy(decision);

      // 6. Execute decision via capability executor
      await _executeDecision(filteredDecision, event.householdId);

      // 7. Update job status to completed
      await jobRepository.updateJobStatus(
        job.id,
        'completed',
        completedAt: DateTime.now(),
        resultData: {
          'action': filteredDecision.action,
          'parameters': filteredDecision.parameters,
        },
      );
    } catch (e, st) {
      debugPrint('LLM job handler failed: $e\n$st');
    }
  }

  /// Execute decision via capability executor.
  Future<void> _executeDecision(
    AutonomyLlmDecision decision,
    String householdId,
  ) async {
    if (decision.isText) {
      // Text decision: hanya penjelasan, tidak ada action
      debugPrint('LLM returned text decision: ${decision.text}');
      return;
    }

    if (decision.isAction) {
      // Action decision: execute via capability executor
      final action = decision.action;
      final parameters = decision.parameters;

      debugPrint('Executing LLM decision: $action with parameters: $parameters');

      // Map LLM decision to capability execution
      // This is a simplified mapping - in production, you might need more sophisticated mapping
      switch (action) {
        case 'createReminder':
          await _executeCreateReminder(parameters, householdId);
          break;
        case 'sendTelegramReport':
          await _executeSendTelegramReport(parameters, householdId);
          break;
        default:
          debugPrint('Unsupported LLM action: $action');
      }
    }
  }

  /// Execute create reminder capability.
  Future<void> _executeCreateReminder(
    Map<String, Object?>? parameters,
    String householdId,
  ) async {
    if (parameters == null) {
      debugPrint('Invalid reminder parameters: parameters is null');
      return;
    }

    // Extract reminder parameters
    final title = parameters['title']?.toString();
    final dueDate = parameters['dueDate']?.toString();
    final reason = parameters['reason']?.toString();

    if (title == null || dueDate == null) {
      debugPrint('Invalid reminder parameters: title or dueDate missing');
      return;
    }

    // TODO: Implement actual reminder creation via capability executor
    // For now, just log the action
    debugPrint('Creating reminder: $title, due: $dueDate, reason: $reason');
  }

  /// Execute send Telegram report capability.
  Future<void> _executeSendTelegramReport(
    Map<String, Object?>? parameters,
    String householdId,
  ) async {
    if (parameters == null) {
      debugPrint('Invalid Telegram report parameters: parameters is null');
      return;
    }

    // Extract report parameters
    final reportType = parameters['reportType']?.toString();
    final content = parameters['content']?.toString();

    if (reportType == null || content == null) {
      debugPrint('Invalid Telegram report parameters: reportType or content missing');
      return;
    }

    // Queue report ke Telegram delivery
    final telegramRepo = telegramDeliveryRepository;
    if (telegramRepo == null) {
      debugPrint('Telegram delivery repository not available');
      return;
    }

    try {
      final deliveryId = 'llm_${reportType}_${DateTime.now().millisecondsSinceEpoch}';
      await telegramRepo.enqueue(
        deliveryId: deliveryId,
        householdId: householdId,
        operation: 'weekly.report',
        messageText: content,
      );
      debugPrint('Telegram report queued successfully: type=$reportType');
    } catch (e, st) {
      debugPrint('Failed to queue Telegram report: $e\n$st');
    }
  }

  static Map<String, Object?> _jobRequestData(
    String userPrompt,
    Object? context,
  ) {
    final data = <String, Object?>{'userPrompt': userPrompt};
    if (context != null) {
      data['context'] = context;
    }
    return data;
  }
}
