import 'dart:convert';

import '../../../core/database/app_database.dart';
import 'ffm_assistant_autonomy_conversation_repository.dart';
import 'ffm_assistant_autonomy_job_repository.dart';
import 'ffm_gemini_cloud_orchestrator.dart';

/// Service untuk menghubungkan otonom dengan LLM (Gemini Cloud).
///
/// Service ini membungkus FfmGeminiCloudOrchestrator untuk kebutuhan otonom,
/// dengan instruksi khusus untuk keputusan otonom dan penyimpanan conversation history.
class FfmAssistantAutonomyLlmService {
  FfmAssistantAutonomyLlmService({
    required this.orchestrator,
    required this.jobRepository,
    required this.conversationRepository,
    this.maxRetries = 3,
    this.llmTimeout = const Duration(seconds: 30),
  });

  final FfmGeminiCloudOrchestrator orchestrator;
  final FfmAssistantAutonomyJobRepository jobRepository;
  final FfmAssistantAutonomyConversationRepository conversationRepository;
  final int maxRetries;
  final Duration llmTimeout;

  /// List capability yang boleh write dalam mode otonom.
  static const _autonomyAllowedWriteCapabilities = {
    'createReminder',
    'updateReminder',
    'deleteReminder',
    'sendTelegramReport',
    'queueTelegramDelivery',
  };

  /// Cek apakah capability boleh write dalam mode otonom.
  static bool isAutonomyWriteAllowed(String capabilityId) {
    return _autonomyAllowedWriteCapabilities.contains(capabilityId);
  }

  /// Filter decision untuk memastikan hanya capability yang diizinkan yang boleh write.
  AutonomyLlmDecision filterDecisionForAutonomy(AutonomyLlmDecision decision) {
    if (!decision.isAction) return decision; // Text decision tidak perlu filter

    final action = decision.action ?? '';
    if (action.isEmpty) return decision;

    // Cek apakah action boleh write
    if (!isAutonomyWriteAllowed(action)) {
      // Return decision yang diubah menjadi text dengan penjelasan
      return AutonomyLlmDecision.text(
        text: 'Action "$action" tidak diizinkan dalam mode otonom. '
              'Hanya reminder yang boleh write secara otonom. '
              'User harus melakukan action ini secara manual.',
        reasoning: decision.reasoning ?? '',
      );
    }

    return decision;
  }

  /// Meminta keputusan LLM untuk job otonom tertentu.
  ///
  /// [jobId] - ID job otonom
  /// [householdId] - ID household
  /// [userPrompt] - Prompt yang dikirim ke LLM
  /// [context] - Context tambahan untuk LLM (data financial, dll)
  ///
  /// Returns keputusan LLM dalam format JSON atau string biasa.
  Future<AutonomyLlmDecision> requestDecision({
    required String jobId,
    required String householdId,
    required String userPrompt,
    String? context,
  }) async {
    // 1. Dapatkan job info
    final job = await jobRepository.getJob(jobId);
    if (job == null) {
      throw StateError('Job tidak ditemukan: $jobId');
    }

    // Cek idempotency - jika job sudah completed, return decision yang sudah ada
    if (job.status == 'completed' && job.decisionData != null) {
      try {
        final decisionData = jsonDecode(job.decisionData!) as Map<String, Object?>;
        return _parseDecisionFromJson(decisionData);
      } catch (_) {
        // If parsing fails, continue with new request
      }
    }

    // 2. Update job status ke in_progress
    await jobRepository.updateJobStatus(
      jobId,
      'in_progress',
      startedAt: DateTime.now(),
    );

    // 3. Save user message ke conversation history
    await conversationRepository.createConversation(
      householdId: householdId,
      jobId: jobId,
      role: 'user',
      content: userPrompt,
    );

    // 4. Build bounded context untuk LLM
    final boundedContext = _buildBoundedContext(job, context);

    // 5. Call LLM dengan retry logic
    AutonomyLlmDecision? decision;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // Call LLM dengan timeout
        final result = await orchestrator.run(
          userText: userPrompt,
          boundedContext: boundedContext,
          householdId: householdId,
        ).timeout(llmTimeout);

        if (!result.ok) {
          throw Exception('LLM call failed: ${result.errorMessage}');
        }

        // 6. Save LLM response ke conversation history
        await conversationRepository.createConversation(
          householdId: householdId,
          jobId: jobId,
          role: 'assistant',
          content: result.text ?? '',
          reasoning: result.readEvidence,
        );

        // 7. Parse LLM response menjadi decision
        decision = _parseDecision(result.text ?? '');

        // 8. Filter decision untuk autonomy policy
        decision = filterDecisionForAutonomy(decision);

        // Break on success
        break;
      } catch (e) {
        // Save error ke conversation
        await conversationRepository.createConversation(
          householdId: householdId,
          jobId: jobId,
          role: 'system',
          content: 'Error (attempt ${attempt + 1}/$maxRetries): $e',
        );

        // If last attempt, save error and return failure
        if (attempt == maxRetries - 1) {
          await jobRepository.updateJobStatus(
            jobId,
            'failed',
            completedAt: DateTime.now(),
            resultData: {'error': e.toString()},
          );

          return AutonomyLlmDecision.failure(
            errorMessage: 'LLM call failed after $maxRetries attempts: $e',
          );
        }

        // Wait before retry (exponential backoff)
        await Future.delayed(Duration(seconds: 2 << attempt));
      }
    }

    // 8. Update job status dengan decision
    if (decision != null) {
      await jobRepository.updateJobStatus(
        jobId,
        'completed',
        completedAt: DateTime.now(),
        decisionData: decision.toJson(),
      );
    }

    return decision ?? AutonomyLlmDecision.failure(
      errorMessage: 'Unknown error in LLM decision',
    );
  }

  /// Build bounded context untuk LLM otonom.
  String _buildBoundedContext(AutonomyJob job, String? additionalContext) {
    final jobType = job.type;
    Map<String, Object?> triggerData = {};
    try {
      if (job.triggerData != null) {
        triggerData = jsonDecode(job.triggerData!) as Map<String, Object?>;
      }
    } catch (_) {
      // If parsing fails, use empty map
    }

    final buffer = StringBuffer();
    buffer.writeln('## Otonom Job Context');
    buffer.writeln('Job Type: $jobType');
    buffer.writeln('Job ID: ${job.id}');
    buffer.writeln('Household ID: ${job.householdId}');
    buffer.writeln('Status: ${job.status}');

    if (triggerData.isNotEmpty) {
      buffer.writeln('\n## Trigger Data');
      buffer.writeln(jsonEncode(triggerData));
    }

    // Add domain-specific context based on job type
    buffer.writeln('\n## Domain Context');
    buffer.writeln(_getDomainContext(jobType));

    if (additionalContext != null && additionalContext.isNotEmpty) {
      buffer.writeln('\n## Additional Context');
      buffer.writeln(additionalContext);
    }

    buffer.writeln('\n## Aturan Otonom');
    buffer.writeln('1. Hanya READ data kecuali Reminder (boleh write)');
    buffer.writeln('2. Policy database access harus dijaga');
    buffer.writeln('3. Keputusan harus berbasis data yang ada');
    buffer.writeln('4. Berikan reasoning yang jelas untuk setiap keputusan');
    buffer.writeln('5. Jangan buat data yang tidak ada di database');

    return buffer.toString();
  }

  /// Get domain-specific context based on job type.
  String _getDomainContext(String jobType) {
    switch (jobType) {
      case 'budget_adjust':
        return '''Budget Context:
- Bisa analisis pola pengeluaran
- Bisa sarankan adjust allocation
- Bisa detect budget yang over/under
- READ-ONLY: tidak boleh create/delete budget''';
      case 'reminder_check':
        return '''Reminder Context:
- Bisa create/update reminder
- Bisa detect reminder yang perlu dibuat
- WRITE diizinkan untuk reminder
- Reason harus jelas untuk setiap reminder''';
      case 'consumption_analysis':
        return '''Consumption Context:
- Bisa analisis konsumsi token listrik
- B sarankan hemat listrik
- READ-ONLY: tidak boleh modify meter data
- Data dari halaman Token Listrik''';
      case 'activity_analysis':
        return '''Activity Context:
- Bisa analisis pola aktivitas
- Bisa detect kebiasaan baru
- READ-ONLY: tidak boleh modify activity
- Data dari halaman Aktivitas''';
      case 'transaction_analysis':
        return '''Transaction Context:
- Bisa analisis pola transaksi
- Bisa detect anomali
- READ-ONLY: tidak boleh create/delete transaction
- Data dari halaman Transaksi''';
      case 'liability_analysis':
        return '''Liability Context:
- Bisa analisis hutang keluarga
- Bisa sarankan strategi pelunasan
- Bisa detect pembayaran jatuh tempo
- READ-ONLY: tidak boleh create/delete liability
- Data dari halaman Hutang & Piutang''';
      case 'asset_analysis':
        return '''Asset Context:
- Bisa analisis aset keluarga
- Bisa analisis performa investasi
- Bisa sarankan rebalancing
- READ-ONLY: tidak boleh create/delete asset
- Data dari halaman Aset''';
      case 'goal_analysis':
        return '''Goal Context:
- Bisa analisis progres target keuangan
- Bisa sarankan strategi mencapai target
- Bisa detect target yang tertinggal
- READ-ONLY: tidak boleh create/delete goal
- Data dari halaman Target Keuangan''';
      case 'telegram_report':
        return '''Telegram Report Context:
- Bisa generate laporan mingguan
- Bisa sarankan konten laporan
- Bisa kirim laporan ke Telegram (via existing service)
- READ-ONLY untuk data finansial
- WRITE diizinkan untuk Telegram delivery queue''';
      default:
        return '''General Context:
- Analisis berbasis data yang ada
- READ-ONLY untuk domain finansial
- WRITE hanya untuk reminder dan Telegram delivery''';
    }
  }

  /// Parse LLM response menjadi structured decision.
  AutonomyLlmDecision _parseDecision(String llmResponse) {
    try {
      // Cek apakah response mengandung JSON decision
      final jsonMatch = RegExp(r'\{[^}]*\}').firstMatch(llmResponse);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0) ?? '';
        final jsonData = jsonDecode(jsonStr) as Map<String, Object?>;

        if (jsonData.containsKey('action')) {
          return AutonomyLlmDecision.action(
            action: jsonData['action'] as String,
            parameters: jsonData,
            reasoning: llmResponse,
          );
        }
      }

      // Jika tidak ada JSON, return sebagai text decision
      return AutonomyLlmDecision.text(
        text: llmResponse,
        reasoning: llmResponse,
      );
    } catch (_) {
      // Jika parsing gagal, return sebagai text decision
      return AutonomyLlmDecision.text(
        text: llmResponse,
        reasoning: llmResponse,
      );
    }
  }

  /// Parse decision dari JSON yang sudah ada.
  AutonomyLlmDecision _parseDecisionFromJson(Map<String, Object?> jsonData) {
    final type = jsonData['type'] as String?;
    if (type == 'action') {
      return AutonomyLlmDecision.action(
        action: jsonData['action'] as String,
        parameters: jsonData,
        reasoning: jsonData['reasoning'] as String? ?? '',
      );
    } else if (type == 'text') {
      return AutonomyLlmDecision.text(
        text: jsonData['text'] as String,
        reasoning: jsonData['reasoning'] as String? ?? '',
      );
    } else {
      return AutonomyLlmDecision.failure(
        errorMessage: 'Invalid decision type: $type',
      );
    }
  }
}

/// Result dari LLM decision request.
class AutonomyLlmDecision {
  const AutonomyLlmDecision._({
    required this.type,
    this.action,
    this.parameters,
    this.text,
    this.reasoning,
    this.errorMessage,
  });

  factory AutonomyLlmDecision.action({
    required String action,
    required Map<String, Object?> parameters,
    required String reasoning,
  }) {
    return AutonomyLlmDecision._(
      type: 'action',
      action: action,
      parameters: parameters,
      reasoning: reasoning,
    );
  }

  factory AutonomyLlmDecision.text({
    required String text,
    required String reasoning,
  }) {
    return AutonomyLlmDecision._(
      type: 'text',
      text: text,
      reasoning: reasoning,
    );
  }

  factory AutonomyLlmDecision.failure({
    required String errorMessage,
  }) {
    return AutonomyLlmDecision._(
      type: 'failure',
      errorMessage: errorMessage,
    );
  }

  final String type;
  final String? action;
  final Map<String, Object?>? parameters;
  final String? text;
  final String? reasoning;
  final String? errorMessage;

  bool get isAction => type == 'action';
  bool get isText => type == 'text';
  bool get isFailure => type == 'failure';

  Map<String, Object?> toJson() {
    return {
      'type': type,
      if (action != null) 'action': action,
      if (parameters != null) 'parameters': parameters,
      if (text != null) 'text': text,
      if (reasoning != null) 'reasoning': reasoning,
      if (errorMessage != null) 'error': errorMessage,
    };
  }
}
