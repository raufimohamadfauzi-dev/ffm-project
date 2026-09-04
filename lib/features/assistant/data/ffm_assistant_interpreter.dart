import '../domain/ffm_assistant_analysis_engine.dart';
import '../domain/ffm_assistant_models.dart';
import '../domain/ffm_assistant_cloud_context.dart';
import '../domain/ffm_assistant_cloud_rollout_config.dart';
import '../domain/ffm_assistant_grounding_validator.dart';
import '../domain/ffm_assistant_verified_fact_service.dart';
import '../domain/ffm_assistant_reasoning_context.dart';
import 'package:flutter/material.dart' show ThemeMode;
import '../../../core/theme/app_theme_controller.dart';
import '../../../core/di/injection.dart';

import 'package:drift/drift.dart' hide Column;

import 'dart:async';
import 'dart:convert';

import '../../../core/database/app_context.dart';
import '../../../core/database/app_database.dart';
import '../../../core/diagnostics/app_diagnostics_service.dart';
import '../../advisor/domain/usecases/budget_guard_service.dart';
import '../../hijri/domain/hijri_calendar_service.dart';
import 'ffm_assistant_memory_repository.dart';
import 'ffm_assistant_user_model_service.dart';
import 'ffm_assistant_local_memory.dart';
import 'ffm_assistant_local_calendar.dart';
import 'ffm_assistant_proposal_json_service.dart';
import 'ffm_assistant_query_tools.dart';
import 'ffm_assistant_financial_snapshot_service.dart';
import 'ffm_gemini_read_capability_service.dart';
import 'ffm_gemini_cloud_orchestrator.dart';
import 'ffm_assistant_personalization_repository.dart';
import 'ffm_personal_context_provider.dart';
import 'ffm_personal_memory_service.dart';
import 'ffm_assistant_typo_normalizer.dart';
import '../../../core/network/gemini_service.dart';
import '../../../core/network/supabase_service.dart';
import '../../../core/network/supabase_config.dart';
import '../domain/ffm_assistant_action_tool.dart';
import '../domain/ffm_assistant_execution_limits.dart';
import '../domain/ffm_assistant_draft_validator.dart';
import '../domain/ffm_assistant_self_description.dart';
import '../domain/ffm_assistant_financial_education.dart';
import '../domain/ffm_context_relevance.dart';
import '../domain/ffm_assistant_work_item.dart';
import 'ffm_assistant_work_item_service.dart';
import '../../activity/domain/entities/activity_entity.dart';
import '../../activity/domain/activity_mode_detector.dart';

import '../domain/ffm_agent_harness.dart';
import 'ffm_agent_plugins.dart';

/// Interpreter lokal berbasis aturan. Ia tidak pernah menulis database; semua
/// perubahan dikembalikan sebagai draft untuk dipreview dan dikonfirmasi user.
import 'ffm_assistant_local_model_gateway.dart';
import 'ffm_assistant_answer_composer.dart';
import 'ffm_category_suggestion_service.dart';

class FfmAssistantInterpreter {
  FfmAssistantInterpreter(
    this._database, {
    FfmAssistantLocalMemory? memory,
    FfmAssistantLocalModelGateway? modelGateway,
    DateTime Function()? clock,
    AppDiagnosticsService? diagnostics,
    FfmAssistantSelfDescriptionService? selfDescription,
    FfmAssistantPersonalizationRepository? personalization,
    FfmAssistantMemoryRepository? taughtMemory,
    FfmPersonalContextProvider? Function()? personalContextProvider,
    Future<bool> Function()? slmReadyCheck,
    FfmAssistantAnswerComposer? answerComposer,
    FfmCategorySuggestionService? categorySuggestion,
    GeminiService? geminiService,
    SupabaseConfig? config,
    FfmPersonalMemoryService? personalMemoryService,
    FfmAssistantAnalysisEngine? analysisEngine,
    FfmAssistantVerifiedFactService? verifiedFactService,
    bool? geminiContextFirstEnabled,
    AppThemeController? themeController,
  }) : _memory = memory ?? FfmAssistantLocalMemory(),
       _personalization =
           personalization ?? FfmAssistantPersonalizationRepository(_database),
       _taughtMemory = taughtMemory ?? FfmAssistantMemoryRepository(_database),
       _personalMemoryService =
           personalMemoryService ??
           FfmPersonalMemoryService(
             taughtMemory ?? FfmAssistantMemoryRepository(_database),
           ),
       _clock = clock ?? DateTime.now,
       _diagnostics = diagnostics ?? AppDiagnosticsService(),
       _selfDescription =
           selfDescription ?? const FfmAssistantSelfDescriptionService(),
       _geminiContextFirstEnabled =
           geminiContextFirstEnabled ??
           FfmAssistantCloudRolloutConfig.contextFirstEnabled,
       _gemini = geminiService ?? GeminiService(),
       _config = config ?? SupabaseConfig(),
       _themeController =
           themeController ??
           (getIt.isRegistered<AppThemeController>()
               ? getIt<AppThemeController>()
               : null) {
    _personalContextProvider = personalContextProvider;
    _categorySuggestion = categorySuggestion;
    _modelGateway = modelGateway;
    _slmReadyCheck = slmReadyCheck;
    _answerComposer = answerComposer;
    _financialSnapshot = FfmAssistantFinancialSnapshotService(
      _database,
      HijriCalendarService(_database),
    );
    _geminiReadCapabilities = FfmGeminiReadCapabilityService(
      _financialSnapshot,
    );
    _geminiCloud = FfmGeminiCloudOrchestrator(
      gemini: _gemini,
      config: _config,
      readCapabilities: _geminiReadCapabilities,
      clock: _clock,
      recordUsage: _recordGeminiUsage,
    );
    _queryRegistry = FfmAssistantQueryRegistry(_database, clock: _clock);
    _actionRegistry = FfmAssistantContextualActionRegistry(clock: _clock);
    _harness = createDefaultHarness(_database);
    _analysisEngine = analysisEngine ?? FfmAssistantAnalysisEngine(_database);
    _verifiedFactService =
        verifiedFactService ??
        FfmAssistantVerifiedFactService(
          database: _database,
          analysisEngine: _analysisEngine,
        );
  }

  final AppDatabase _database;
  final FfmAssistantLocalMemory _memory;
  final AppThemeController? _themeController;
  FfmCategorySuggestionService? _categorySuggestion;
  FfmAssistantLocalModelGateway? _modelGateway;
  Future<bool> Function()? _slmReadyCheck;
  FfmAssistantAnswerComposer? _answerComposer;
  final FfmAssistantPersonalizationRepository _personalization;
  final FfmAssistantMemoryRepository _taughtMemory;
  final FfmPersonalMemoryService _personalMemoryService;
  FfmPersonalContextProvider? Function()? _personalContextProvider;
  final DateTime Function() _clock;
  final AppDiagnosticsService _diagnostics;
  final FfmAssistantSelfDescriptionService _selfDescription;
  final bool _geminiContextFirstEnabled;
  final _financialEducation = const FfmAssistantFinancialEducationService();

  final _supabase = SupabaseService();
  final GeminiService _gemini;
  final SupabaseConfig _config;
  late final FfmAssistantAnalysisEngine _analysisEngine;
  late final FfmAssistantVerifiedFactService _verifiedFactService;

  static const _personalContextBudget = FfmContextBudget(
    workingMemoryMax: 2,
    personalFactsMax: 3,
    preferencesMax: 3,
    goalsMax: 2,
    behaviorPatternsMax: 2,
    episodesMax: 1,
    correctionsMax: 2,
    maxTotalItems: 10,
  );

  static const _personalContextBlockedDestinations = <FfmAssistantDestination>{
    FfmAssistantDestination.appSecurity,
    FfmAssistantDestination.privacyCenter,
    FfmAssistantDestination.backup,
    FfmAssistantDestination.diagnostics,
    FfmAssistantDestination.databaseStructure,
    FfmAssistantDestination.assistantProfile,
    FfmAssistantDestination.masterData,
    FfmAssistantDestination.activityLog,
    FfmAssistantDestination.reconciliation,
    FfmAssistantDestination.recurringTransaction,
  };

  /// Memori entitas sesi — dipakai untuk coreference resolution dalam satu
  /// sesi percakapan. Tidak dipersistensikan ke database.
  final _sessionMemory = _FfmSessionEntityMemory();
  late final FfmAssistantFinancialSnapshotService _financialSnapshot;
  late final FfmGeminiReadCapabilityService _geminiReadCapabilities;
  late final FfmGeminiCloudOrchestrator _geminiCloud;
  late final FfmAssistantQueryRegistry _queryRegistry;
  late final FfmAssistantContextualActionRegistry _actionRegistry;

  /// Harness modular ala DeepSeek Harness — 14 plugin Mata/Tangan/Logika offline.
  late final FfmAgentHarness _harness;

  /// Intent tambahan dari Gemini (untuk kasus multi-draft).
  List<FfmAssistantIntent> _pendingGeminiExtraIntents = const [];

  /// Memberikan sapaan pembuka yang kontekstual berdasarkan halaman aktif.
  String getContextualGreeting(FfmAssistantDestination? destination) {
    if (destination == null) {
      return _randomGreeting();
    }
    final page = FfmAssistantCatalog.findByDestination(destination);
    final pageName = page?.name ?? 'halaman ini';

    final now = DateTime.now();
    return switch (destination) {
      FfmAssistantDestination.summary => [
        'Hai! Lagi lihat ringkasan? Aku bisa bantu analisis.',
        'Ringkasan keuangan nih? Mau dicek?',
        'Sedang melihat ringkasan? Ada yang perlu dijelaskan?',
      ][now.millisecondsSinceEpoch % 3],
      FfmAssistantDestination.transactions => [
        'Mau catat transaksi? Sebutkan nominal dan kategorinya.',
        'Ingin mencatat? Ketik saja detailnya.',
        'Transaksi baru? Siap bantu catat.',
      ][now.millisecondsSinceEpoch % 3],
      FfmAssistantDestination.budget => [
        'Anggaran sedang dipantau? Aku bisa bantu cek.',
        'Mau lihat pos anggaran mana yang hampir habis?',
        'Cek anggaran yuk. Ada yang perlu diperiksa?',
      ][now.millisecondsSinceEpoch % 3],
      FfmAssistantDestination.goals => [
        'Target keuangan nih? Aku bantu hitung.',
        'Mau cek sisa setoran target?',
        'Fokus ke target? Ada yang bisa dibantu.',
      ][now.millisecondsSinceEpoch % 3],
      FfmAssistantDestination.liabilities => [
        'Hutang piutang sedang dikelola? Siap bantu catat.',
        'Mau catat pinjaman baru?',
        'Kelola hutang yuk. Ada yang perlu dicatat?',
      ][now.millisecondsSinceEpoch % 3],
      FfmAssistantDestination.activity => [
        'Aktivitas sedang dipantau? Mau catat yang baru?',
        'Mau catat durasi perjalanan?',
        'Aktivitas baru? Ketik saja detailnya.',
      ][now.millisecondsSinceEpoch % 3],
      _ => [
        'Aku lihat kamu di $pageName. Ada yang perlu?',
        'Sedang di $pageName? Ada yang bisa dibantu?',
        '$pageName nih. Mau lihat data atau catat sesuatu?',
      ][now.millisecondsSinceEpoch % 3],
    };
  }

  FfmAssistantCloudRequestClass _classifyCloudRequest({
    required String normalized,
    required FfmAssistantReasoningEvidenceScope evidenceScope,
    required FfmAssistantDraft? activeDraft,
  }) {
    // Mutasi eksplisit selalu menang atas pending draft. Dengan begitu perintah
    // baru (misal "catat pemasukan 500 rb") tidak dikira revisi draft lama oleh
    // Gemini meskipun ada activeDraft, sehingga intent tidak tertukar.
    final isExplicitMutation =
        RegExp(r'\b(buat|tambah|catat|beli|bayar)\b').hasMatch(normalized) &&
        RegExp(
          r'\b(kategori|rekening|toko|sumber|anggaran|target|tujuan|goal|transaksi|pemasukan|pengeluaran|belanja|transfer|aktivitas|pengingat|aset|hutang|piutang)\b',
        ).hasMatch(normalized);
    if (isExplicitMutation) {
      return FfmAssistantCloudRequestClass.mutationProposal;
    }
    if (activeDraft != null) {
      return FfmAssistantCloudRequestClass.draftReview;
    }
    if (RegExp(
      r'\b(analisa|analisis|trend|tren|pola|frekuensi|perbandingan|bandingkan|saran|rekomendasi|evaluasi|apa yang harus saya lakukan|harus lakukan|langkah apa|tips|strategi|bulan depan|3 bulan|tiga bulan)\b',
    ).hasMatch(normalized)) {
      return FfmAssistantCloudRequestClass.analysis;
    }
    if (RegExp(r'\b(bantuan|help|fitur|apa yang bisa|cara pakai|panduan)\b')
        .hasMatch(normalized)) {
      return FfmAssistantCloudRequestClass.help;
    }
    // Mutation proposal eksplisit: buat/tambah/catat dengan target jelas.
    if (RegExp(r'\b(buat|tambah|catat)\b').hasMatch(normalized) &&
        RegExp(
          r'\b(kategori|rekening|toko|sumber|anggaran|target|transaksi|pemasukan|pengeluaran|transfer|hutang|piutang)\b',
        ).hasMatch(normalized)) {
      return FfmAssistantCloudRequestClass.mutationProposal;
    }
    if (evidenceScope.includeRecentTransactions) {
      return FfmAssistantCloudRequestClass.recentTransactions;
    }
    if (RegExp(r'\b(ringkasan|rangkuman|rekap|laporan)\b')
        .hasMatch(normalized)) {
      if (normalized.contains('bulan lalu') ||
          normalized.contains('bulan kemarin') ||
          normalized.contains('minggu lalu') ||
          normalized.contains('3 bulan') ||
          normalized.contains('tahun ini')) {
        return FfmAssistantCloudRequestClass.analysis;
      }
      return FfmAssistantCloudRequestClass.summary;
    }
    if (RegExp(r'\b(rekening|akun)\b').hasMatch(normalized)) {
      return FfmAssistantCloudRequestClass.accounts;
    }
    if (RegExp(r'\b(anggaran|budget)\b').hasMatch(normalized)) {
      return FfmAssistantCloudRequestClass.budget;
    }
    if (RegExp(r'\b(kategori)\b').hasMatch(normalized)) {
      return FfmAssistantCloudRequestClass.categories;
    }
    if (RegExp(r'\b(target|goal|tujuan)\b').hasMatch(normalized)) {
      return FfmAssistantCloudRequestClass.goals;
    }
    if (evidenceScope.includeFinancialSummary) {
      return FfmAssistantCloudRequestClass.financialRead;
    }
    if (evidenceScope.includeMasterData) {
      return FfmAssistantCloudRequestClass.masterData;
    }
    return FfmAssistantCloudRequestClass.general;
  }

  FfmAnalysisPeriod _analysisPeriodFor(String normalized) {
    if (_containsAny(normalized, const ['7 hari', 'seminggu'])) {
      return FfmAnalysisPeriod.last7Days;
    }
    if (_containsAny(normalized, const [
      '90 hari',
      '3 bulan',
      'tiga bulan',
      '3 bulan ke belakang',
      '3 bulan terakhir',
    ])) {
      return FfmAnalysisPeriod.last90Days;
    }
    if (normalized.contains('bulan lalu') ||
        normalized.contains('bulan kemarin')) {
      return FfmAnalysisPeriod.lastMonth;
    }
    if (normalized.contains('bulan ini') ||
        normalized.contains('bulan depan')) {
      return FfmAnalysisPeriod.thisMonth;
    }
    if (normalized.contains('tahun ini')) return FfmAnalysisPeriod.thisYear;
    return FfmAnalysisPeriod.last30Days;
  }

  Future<String> _buildGeminiContext({
    required String rawText,
    required String normalized,
    required FfmAssistantDestination? currentDestination,
    required String? pageContext,
    required String? conversationHistory,
    required List<String> capabilityIds,
    required String cloudContext,
    FfmAssistantDraft? activeDraft,
  }) async {
    final capturedAt = _clock();
    final evidenceScope = FfmAssistantReasoningEvidencePolicy.forRequest(
      normalized,
    );
    final requestClass = _classifyCloudRequest(
      normalized: normalized,
      evidenceScope: evidenceScope,
      activeDraft: activeDraft,
    );
    final financialContext = evidenceScope.includeFinancialSummary
        ? _financialSnapshot.buildBoundedPrompt(
            await _financialSnapshot.readCurrentMonth(
              householdId: AppContext.householdId,
              now: capturedAt,
            ),
          )
        : '';
    final householdContext = await _financialSnapshot.buildHouseholdProfileContext(
      householdId: AppContext.householdId,
    );
    final masterDataContext = evidenceScope.includeMasterData
        ? await _financialSnapshot.buildMasterDataContext(
            householdId: AppContext.householdId,
          )
        : '';
    final hijriContext = evidenceScope.includeMasterData
        ? await _financialSnapshot.buildHijriContext(
            householdId: AppContext.householdId,
            now: capturedAt,
          )
        : '';
    final harvestContext =
        _containsAny(normalized, const [
          'panen',
          'hasil kebun',
          'harga jual',
          'komoditas',
          'pupuk',
          'bibit',
          'pestisida',
          'tani',
          'sawah',
          'kebun',
          'pakan',
          'ternak',
        ])
        ? await _financialSnapshot.buildHarvestContext(
            householdId: AppContext.householdId,
          )
        : '';
    final activitiesContext =
        _containsAny(normalized, const [
          'aktivitas',
          'kegiatan',
          'jadwal',
          'agenda',
          'tugas',
          'catatan harian',
          'pekerjaan',
        ])
        ? await _financialSnapshot.buildActivitiesDigest(
            householdId: AppContext.householdId,
          )
        : '';
    final remindersContext =
        _containsAny(normalized, const [
          'pengingat',
          'ingatkan',
          'alarm',
          'jatuh tempo',
          'tagihan',
          'jadwal bayar',
        ])
        ? await _financialSnapshot.buildRemindersDigest(
            householdId: AppContext.householdId,
          )
        : '';
    final assetsContext =
        _containsAny(normalized, const [
          'aset',
          'harta',
          'kekayaan',
          'tanah',
          'kendaraan',
          'emas',
        ])
        ? await _financialSnapshot.buildAssetsDigest(
            householdId: AppContext.householdId,
          )
        : '';
    final liabilitiesContext =
        _containsAny(normalized, const [
          'hutang',
          'utang',
          'piutang',
          'cicilan',
          'pinjaman',
          'kredit',
          'pinjol',
        ])
        ? await _financialSnapshot.buildLiabilitiesDigest(
            householdId: AppContext.householdId,
          )
        : '';
    final goalsContext =
        _containsAny(normalized, const [
          'target',
          'goal',
          'tujuan',
          'dana darurat',
          'cadangan',
          'darurat',
          'impian',
        ])
        ? await _financialSnapshot.buildGoalsDigest(
            householdId: AppContext.householdId,
            now: capturedAt,
          )
        : '';
    final approvedUserContext = await FfmAssistantUserModelService(
      _taughtMemory,
    ).buildContext(query: normalized);
    final personalizationContext = await _personalization
        .buildPersonalizedContext(
          householdId: AppContext.householdId,
          query: normalized,
        );
    final activeThemeMode = _themeController?.themeMode;
    final currentThemeLabel = switch (activeThemeMode) {
      ThemeMode.dark => 'Mode Gelap (Dark Mode 🌙)',
      ThemeMode.light => 'Mode Terang (Light Mode ☀️)',
      ThemeMode.system => 'Mode Sistem (Mengikuti setelan perangkat 📱)',
      null => 'Mode Terang (Light Mode ☀️)',
    };
    final reasoningContext = FfmAssistantReasoningContext(
      request: rawText,
      capturedAt: capturedAt,
      currentPage: currentDestination,
      currentTheme: currentThemeLabel,
      pageSummary: [
        if (pageContext != null && pageContext.trim().isNotEmpty) pageContext,
        'Tema UI aplikasi: $currentThemeLabel',
        if (householdContext.trim().isNotEmpty) householdContext,
        financialContext,
        masterDataContext,
        hijriContext,
        harvestContext,
        activitiesContext,
        remindersContext,
        assetsContext,
        liabilitiesContext,
        goalsContext,
      ].where((value) => value.trim().isNotEmpty).join('\n'),
      capabilityIds: capabilityIds,
      approvedUserContext: approvedUserContext,
      personalizationContext: personalizationContext,
      modelReady: true,
      recentTransactions: evidenceScope.includeRecentTransactions
          ? await _recentTransactionSummaries(
              householdId: AppContext.householdId,
            )
          : const <String>[],
    );

    final verifiedFacts = await _verifiedFactService.generateFacts(
      householdId: AppContext.householdId,
      scope: evidenceScope,
      referenceDate: capturedAt,
    );

    FfmAnalysisFacts? analysisFacts;
    if (requestClass == FfmAssistantCloudRequestClass.analysis) {
      try {
        analysisFacts = await _verifiedFactService.generateAnalysisFacts(
          householdId: AppContext.householdId,
          period: _analysisPeriodFor(normalized),
          referenceDate: capturedAt,
        );
      } on Object {
        // Analysis adalah enhancement; Gemini tetap dibatasi ke verified facts.
      }
    }

    final contextWithPersonal = await _withPersonalContext(reasoningContext);
    final personalMemoryContext = await _personalMemoryService.buildContext();

    final enhancedContext = _personalMemoryService.getEnhancedContextForLLM(
      activeDraft,
    );
    final draftFeedbackText = enhancedContext['draftFeedback'] as String? ?? '';

    return FfmAssistantCloudContextEnvelope(
      capturedAt: capturedAt,
      routingMode: FfmAssistantRoutingMode.geminiCloud,
      requestClass: requestClass,
      evidenceScope: evidenceScope,
      currentDestination: currentDestination,
      reasoningContext: contextWithPersonal,
      verifiedFacts: verifiedFacts,
      analysisFacts: analysisFacts,
      activeDraft: activeDraft == null
          ? null
          : FfmAssistantCloudDraftContext.fromDraft(activeDraft),
      personalMemoryContext: personalMemoryContext,
      draftFeedback: draftFeedbackText,
      conversationHistory: _boundedConversationHistory(
        conversationHistory,
        maxLines: 12,
      ),
      cloudMemoryContext: cloudContext,
    ).toBoundedPrompt();
  }

  String _boundedConversationHistory(String? history, {int maxLines = 12}) {
    if (history == null || history.trim().isEmpty) return '';
    final lines = history
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    if (lines.length <= maxLines) return history;
    return lines.sublist(lines.length - maxLines).join('\n');
  }

  Future<_InterpretResult?> _tryGeminiResponse(
    String rawText,
    String normalized, {
    required FfmAssistantDestination? currentDestination,
    required String? pageContext,
    required String? conversationHistory,
    required List<String> capabilityIds,
    required String cloudContext,
    required List<Account> accounts,
    required List<Category> categories,
    FfmAssistantDraft? activeDraft,
  }) async {
    late final String geminiContext;
    try {
      geminiContext = await _buildGeminiContext(
        rawText: rawText,
        normalized: normalized,
        currentDestination: currentDestination,
        pageContext: pageContext,
        conversationHistory: conversationHistory,
        capabilityIds: capabilityIds,
        cloudContext: cloudContext,
        activeDraft: activeDraft,
      );
    } on Object {
      return _InterpretResult.single(
        _cloudError(
          rawText,
          normalized,
          'Data lokal tidak dapat dibaca saat ini. Coba lagi nanti tanpa menebak angka.',
          model: 'evidence-unavailable',
        ),
      );
    }
    final turn = await _geminiCloud.run(
      userText: rawText,
      boundedContext: geminiContext,
      householdId: AppContext.householdId,
    );
    if (!turn.ok) {
      return _InterpretResult.single(
        _cloudError(
          rawText,
          normalized,
          _friendlyCloudError(turn.errorMessage!),
          model: turn.model,
          statusCode: turn.statusCode,
        ),
      );
    }
    final proposal = FfmAssistantProposalJsonService.parseMultiple(
      turn.text!,
      createdAt: _clock(),
    );
    final requestScopeForMeta = FfmAssistantReasoningEvidencePolicy.forRequest(
      normalized,
    );
    final requestClassForMeta = _classifyCloudRequest(
      normalized: normalized,
      evidenceScope: requestScopeForMeta,
      activeDraft: activeDraft,
    );
    final geminiMetadata = <String, dynamic>{
      'model': turn.model,
      'statusCode': turn.statusCode,
      'latencyMs': turn.latency?.inMilliseconds,
      if (turn.usageMetadata != null)
        'tokenUsage': turn.usageMetadata!.toJson(),
      'proposal':
          proposal.drafts.isNotEmpty || proposal.teachingProposals.isNotEmpty,
      'usedReadCapability': turn.usedReadCapability,
      'hasReadEvidence': turn.readEvidence != null,
      'schemaVersion': FfmAssistantCloudContextEnvelope.schemaVersion,
      'requestClass': requestClassForMeta.name,
      'capturedAt': _clock().toIso8601String(),
      'evidenceScope': {
        'financialSummary': requestScopeForMeta.includeFinancialSummary,
        'recentTransactions': requestScopeForMeta.includeRecentTransactions,
        'masterData': requestScopeForMeta.includeMasterData,
      },
    };
    if (proposal.error != null) {
      _logAssistantFailure(
        code: 'gemini-proposal-parse',
        technical: proposal.error!,
        impact: 'Output JSON Gemini tidak valid; fallback ramah tanpa draft.',
      );
      return _InterpretResult.single(
        FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.unknown,
          confidence: .8,
          response: _friendlyProposalError(proposal.error!),
          clarification: _friendlyProposalError(proposal.error!),
          responseOrigin: FfmAssistantResponseOrigin.geminiCloud,
          pluginName: 'gemini_cloud',
          pluginCategory: 'gemini_cloud',
          pluginMetadata: geminiMetadata,
        ),
      );
    }
    if (proposal.drafts.length > 1) {
      final draftIntents = proposal.drafts.map((d) {
        final validated = _validateGeminiDraft(d, accounts, categories);
        final intent = _intentForDraft(rawText, normalized, validated);
        return intent.copyWith(
          responseOrigin: FfmAssistantResponseOrigin.geminiCloud,
          pluginName: 'gemini_cloud',
          pluginCategory: 'gemini_cloud_multi',
          pluginMetadata: geminiMetadata,
        );
      }).toList();
      final count = proposal.drafts.length;
      final kinds = proposal.drafts.map((d) => d.kind.name).join(', ');
      draftIntents.first = draftIntents.first.copyWith(
        response:
            'Gemini sudah menyusun $count draft sekaligus ($kinds). Cek detail masing-masing, koreksi bila perlu, lalu konfirmasi.',
      );
      return _InterpretResult.multi(draftIntents);
    }
    if (proposal.drafts.isNotEmpty) {
      final draft = _validateGeminiDraft(
        proposal.drafts.first,
        accounts,
        categories,
      );

      // Handle navigation proposals specially
      if (draft.formValues['navigation'] == 'true') {
        final destinationName = draft.formValues['destination'];
        final destination = _destinationForName(destinationName);
        if (destination != null) {
          final page = FfmAssistantCatalog.findByDestination(destination);
          final pageDescription = page?.description ?? '';
          return _InterpretResult.single(
            FfmAssistantIntent(
              rawText: rawText,
              normalizedText: normalized,
              type: FfmAssistantIntentType.openPage,
              destination: destination,
              confidence: 1,
              response:
                  'Siap, aku arahkan ke halaman ${page?.name ?? destination.name}. Tekan Buka untuk $pageDescription',
              responseOrigin: FfmAssistantResponseOrigin.geminiCloud,
              pluginName: 'gemini_cloud',
              pluginCategory: 'gemini_cloud',
              pluginMetadata: geminiMetadata,
            ),
          );
        }
      }

      final draftIntent = _intentForDraft(rawText, normalized, draft);
      return _InterpretResult.single(
        draftIntent.copyWith(
          response:
              'Gemini sudah menyusun draft ${draft.kind.name}. Cek detailnya, koreksi bila perlu, lalu konfirmasi sebelum disimpan.',
          responseOrigin: FfmAssistantResponseOrigin.geminiCloud,
          pluginName: 'gemini_cloud',
          pluginCategory: 'gemini_cloud',
          pluginMetadata: geminiMetadata,
        ),
      );
    }
    if (proposal.teachingProposals.isNotEmpty) {
      return _InterpretResult.single(
        FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.teachMemory,
          confidence: .9,
          response: 'Gemini mengusulkan memory baru. Tinjau isinya lalu pilih \u201cSimpan ajaran\u201d jika memang benar.',
          teachingProposal: proposal.teachingProposals.first,
          responseOrigin: FfmAssistantResponseOrigin.geminiCloud,
          pluginName: 'gemini_cloud',
          pluginCategory: 'gemini_cloud',
          pluginMetadata: geminiMetadata,
        ),
      );
    }
    String? analysisForIntent;
    if (requestClassForMeta == FfmAssistantCloudRequestClass.analysis) {
      try {
        final af = await _verifiedFactService.generateAnalysisFacts(
          householdId: AppContext.householdId,
          period: _analysisPeriodFor(normalized),
          referenceDate: _clock(),
        );
        analysisForIntent = af.toLLMContext();
      } on Object {
        analysisForIntent = null;
      }
    }
    final verifiedForIntent = await _generateVerifiedFactsForQuery(normalized);
    final groundingError = FfmAssistantGroundingValidator.validatePlainText(
      geminiText: turn.text!,
      verifiedFacts: verifiedForIntent,
      analysisFacts: analysisForIntent,
      capabilityEvidence:
          turn.readEvidence ??
          (geminiMetadata['usedReadCapability'] != null
              ? verifiedForIntent
              : null),
    );
    if (groundingError != null) {
      return _InterpretResult.single(
        FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.queryData,
          confidence: 0.9,
          response: groundingError,
          clarification: groundingError,
          responseOrigin: FfmAssistantResponseOrigin.geminiCloud,
          pluginName: 'gemini_cloud',
          pluginCategory: 'gemini_cloud',
          pluginMetadata: {...geminiMetadata, 'groundingBlocked': true},
          verifiedFacts: verifiedForIntent,
          analysisResults: analysisForIntent,
        ),
      );
    }
    final isGreeting = _isGreetingWord(normalized);
    final isConversationalOrHelp =
        isGreeting ||
        requestClassForMeta == FfmAssistantCloudRequestClass.help ||
        requestClassForMeta == FfmAssistantCloudRequestClass.general;
    final resolvedIntentType = isConversationalOrHelp
        ? FfmAssistantIntentType.help
        : FfmAssistantIntentType.queryData;

    return _InterpretResult.single(
      FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: resolvedIntentType,
        confidence: 1.0,
        response: turn.text,
        responseOrigin: FfmAssistantResponseOrigin.geminiCloud,
        pluginName: 'gemini_cloud',
        pluginCategory: 'gemini_cloud',
        pluginMetadata: geminiMetadata,
        verifiedFacts: verifiedForIntent,
        analysisResults: analysisForIntent,
      ),
    );
  }

  /// Menjawab pertanyaan bebas Mode Agent dengan SLM lokal yang tersedia.
  ///
  /// Hanya merangkai jawaban dari fakta terarah yang sudah dibangun oleh aturan
  /// lokal (tidak boleh mengarang nilai). Mengembalikan null bila SLM tidak
  /// dipasang, belum siap, sibuk, atau outputnya gagal lolos sanitasi — lalu
  /// interpreter jatuh ke `_unknown` secara jujur tanpa berpindah provider.
  Future<FfmAssistantIntent?> _tryLocalModelResponse(
    String rawText,
    String normalized, {
    required FfmAssistantDestination? currentDestination,
    required String? pageContext,
    required List<String> capabilityIds,
  }) async {
    final readyCheck = _slmReadyCheck;
    if (readyCheck != null) {
      try {
        if (!await readyCheck()) return null;
      } on Object {
        return null;
      }
    }
    if (_modelGateway == null && _answerComposer == null) return null;

    final composer = _answerComposer;
    if (composer != null) {
      final facts = await _buildLocalAnswerFacts(
        normalized: normalized,
        currentDestination: currentDestination,
        pageContext: pageContext,
      );
      if (facts.trim().isNotEmpty) {
        String? answer;
        try {
          answer = await composer.composeGroundedAnswer(
            question: rawText,
            facts: facts,
          );
        } on Object {
          return null;
        }
        final sanitized = FfmAssistantComposedAnswerContract.sanitize(
          answer ?? '',
        );
        if (sanitized != null) {
          return FfmAssistantIntent(
            rawText: rawText,
            normalizedText: normalized,
            type: FfmAssistantIntentType.queryData,
            confidence: .8,
            response: sanitized,
            responseOrigin: FfmAssistantResponseOrigin.localSlm,
            responseMode: FfmAssistantResponseMode.localModel,
            pluginName: 'slm_generator',
            pluginCategory: '🧠 SLM Lokal',
          );
        }
      }
    }

    // Jalur proposal: SLM hanya memberi pemahaman/maksud; teks jawaban yang
    // boleh dipakai hanyalah pesan bantuan terstruktur — bukan draft mutasi.
    final gateway = _modelGateway;
    if (gateway == null) return null;
    final accounts = await _activeAccounts();
    final categories = await _activeCategories();
    final FfmAssistantModelProposal? proposal;
    try {
      proposal = await gateway.proposeWithContext(
        input: rawText,
        pageContext: pageContext,
        capabilityIds: capabilityIds,
        activeAccountNames: accounts.map((account) => account.name).toList(),
        activeCategoryNames: categories
            .map((category) => category.name)
            .toList(),
      );
    } on Object {
      return null;
    }
    if (proposal == null || !proposal.isUsable) return null;
    if (proposal.draft != null) return null;
    final safeIntents = const {
      FfmAssistantIntentType.help,
      FfmAssistantIntentType.outOfDomain,
    };
    if (!safeIntents.contains(proposal.intent)) return null;
    final message = proposal.notes?.trim() ?? proposal.clarification?.trim();
    if (message == null || message.isEmpty) return null;
    final sanitized = FfmAssistantComposedAnswerContract.sanitize(message);
    if (sanitized == null) return null;
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: proposal.intent,
      confidence: proposal.confidence,
      response: sanitized,
      responseOrigin: FfmAssistantResponseOrigin.localSlm,
      responseMode: FfmAssistantResponseMode.localModel,
      pluginName: 'slm_local',
      pluginCategory: '🧠 SLM Lokal',
      clarification: proposal.clarification,
    );
  }

  /// Membangun fakta terarah (bounded, aman-pribadi) untuk penyusun jawaban
  /// SLM lokal. Tidak pernah menyertakan PIN, token, saldo per transaksi, atau
  /// data mentah sensitif — hanya ringkasan keuangan dan konteks halaman.
  Future<String> _buildLocalAnswerFacts({
    required String normalized,
    required FfmAssistantDestination? currentDestination,
    required String? pageContext,
  }) async {
    final evidenceScope = FfmAssistantReasoningEvidencePolicy.forRequest(
      normalized,
    );
    final financialContext = evidenceScope.includeFinancialSummary
        ? _financialSnapshot.buildBoundedPrompt(
            await _financialSnapshot.readCurrentMonth(
              householdId: AppContext.householdId,
              now: _clock(),
            ),
          )
        : '';
    final masterDataContext = evidenceScope.includeMasterData
        ? await _financialSnapshot.buildMasterDataContext(
            householdId: AppContext.householdId,
          )
        : '';
    final householdContext = await _financialSnapshot.buildHouseholdProfileContext(
      householdId: AppContext.householdId,
    );
    final approvedUserContext = await FfmAssistantUserModelService(
      _taughtMemory,
    ).buildContext(query: normalized);
    final personalizationContext = await _personalization
        .buildPersonalizedContext(
          householdId: AppContext.householdId,
          query: normalized,
        );
    return [
          if (pageContext != null && pageContext.trim().isNotEmpty) pageContext,
          if (householdContext.trim().isNotEmpty) householdContext,
          financialContext,
          masterDataContext,
          approvedUserContext,
          personalizationContext,
        ]
        .where((value) => value.trim().isNotEmpty)
        .map((value) => value.trim())
        .join('\n\n')
        .trim();
  }

  Future<FfmAssistantUnderstandingResult> interpretMany(
    String rawText, {
    FfmAssistantDestination? currentDestination,
    String? pageContext,
    String? lastAssistantMessage,
    String? conversationHistory,
    List<String> capabilityIds = const <String>[],
    ActivityLiveSnapshot? activitySnapshot,
    FfmAssistantRoutingMode? routingMode,
    FfmAssistantDraft? activeDraft,
  }) async {
    final normalized = _normalize(rawText);
    final commands = _splitCompositeCommands(rawText);
    if (commands.length >
        FfmAssistantExecutionLimits.maxSubCommandsPerMessage) {
      return FfmAssistantUnderstandingResult(
        workItems: const [],
        intents: [
          FfmAssistantIntent(
            rawText: rawText,
            normalizedText: normalized,
            type: FfmAssistantIntentType.unknown,
            confidence: 1,
            response: FfmAssistantExecutionLimits.tooComplexMessage,
          ),
        ],
        rawText: rawText,
        normalizedText: normalized,
      );
    }
    if (commands.length <= 1) {
      final intent = _withRequiredDraftClarification(
        await interpret(
          rawText,
          currentDestination: currentDestination,
          pageContext: pageContext,
          lastAssistantMessage: lastAssistantMessage,
          conversationHistory: conversationHistory,
          capabilityIds: capabilityIds,
          activitySnapshot: activitySnapshot,
          routingMode: routingMode,
          activeDraft: activeDraft,
        ),
      );
      final allIntents = [intent, ..._pendingGeminiExtraIntents];
      _pendingGeminiExtraIntents = const [];
      return const FfmAssistantWorkItemService().intentsToWorkItems(
        allIntents,
        rawText,
        normalized,
        currentDestination: currentDestination,
        supportedForms: capabilityIds
            .map(_capabilityToDestination)
            .whereType<FfmAssistantDestination>()
            .toList(),
      );
    }
    final results = <FfmAssistantIntent>[];
    for (final command in commands) {
      results.add(
        _withRequiredDraftClarification(
          await interpret(
            command,
            currentDestination: currentDestination,
            pageContext: pageContext,
            lastAssistantMessage: lastAssistantMessage,
            conversationHistory: conversationHistory,
            capabilityIds: capabilityIds,
            activitySnapshot: activitySnapshot,
            routingMode: routingMode,
            activeDraft: activeDraft,
          ),
        ),
      );
    }
    return const FfmAssistantWorkItemService().intentsToWorkItems(
      results,
      rawText,
      normalized,
      currentDestination: currentDestination,
      supportedForms: capabilityIds
          .map(_capabilityToDestination)
          .whereType<FfmAssistantDestination>()
          .toList(),
    );
  }

  FfmAssistantDestination? _capabilityToDestination(String capabilityId) {
    // Map capability IDs to destinations for context
    // This is a simplified mapping - in practice this would be more comprehensive
    if (capabilityId.contains('expense') || capabilityId.contains('income')) {
      return FfmAssistantDestination.transactions;
    }
    if (capabilityId.contains('budget')) {
      return FfmAssistantDestination.budget;
    }
    if (capabilityId.contains('goal')) {
      return FfmAssistantDestination.goals;
    }
    if (capabilityId.contains('asset')) {
      return FfmAssistantDestination.assets;
    }
    if (capabilityId.contains('liability')) {
      return FfmAssistantDestination.liabilities;
    }
    if (capabilityId.contains('activity')) {
      return FfmAssistantDestination.activity;
    }
    return null;
  }

  FfmAssistantIntent _withRequiredDraftClarification(
    FfmAssistantIntent intent,
  ) {
    final draft = intent.draft;
    if (draft == null || intent.clarification != null) return intent;
    final requiredFields = FfmAssistantDraftValidator.validate(draft)
        .where((issue) => issue.blocksContinuation)
        .map((issue) => issue.field ?? issue.code)
        .toSet()
        .toList();
    if (requiredFields.isEmpty) return intent;
    final prompt =
        'Agar draft tidak salah, aku masih perlu ${requiredFields.join(', ')}.';
    return intent.copyWith(response: prompt, clarification: prompt);
  }

  // ── PILAR 1: Multi-Action Chaining ─────────────────────────────────────────
  /// Memecah teks perintah majemuk menjadi sub-perintah terpisah.
  ///
  /// Mendukung pemisahan via:
  /// - Tanda baca: `;`, baris baru
  /// - Konjungsi temporal: *lalu*, *kemudian*, *terus*, *selanjutnya*, *setelah itu*
  /// - Konjungsi aditif di antara dua kata kerja aksi: *dan*, *serta*, *juga*
  ///   (hanya jika kedua sisi berisi kata kerja aksi finansial agar kalimat deskriptif
  ///   seperti *"rekening BCA dan Mandiri"* tidak ikut dipecah).
  static List<String> _splitCompositeCommands(String rawText) {
    // Pemisah eksplisit: titik koma, baris baru, konjungsi temporal.
    final explicit = rawText
        .split(
          RegExp(
            r'\s*(?:;|\n|\blalu\b|\bterus\b|\bkemudian\b|\bselanjutnya\b|\bsetelah itu\b)\s*',
            caseSensitive: false,
          ),
        )
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (explicit.length > 1) return explicit;

    // Pemisah aditif: *dan*/*serta*/*juga* di antara dua kata kerja aksi atau dua nominal.
    const actionVerbs = <String>[
      'catat',
      'tambah',
      'buat',
      'ingatkan',
      'simpan',
      'transfer',
      'pindahkan',
      'bayar',
      'hapus',
      'ubah',
      'update',
      'buka',
    ];
    final conjPattern = RegExp(r'\b(dan|serta|juga)\b', caseSensitive: false);
    final parts = rawText.split(conjPattern);
    if (parts.length < 2) return [rawText.trim()];

    final hasAmountRegExp = RegExp(
      r'\d+\s*(?:rb|ribu|jt|juta|k|ratus|000)?\b',
      caseSensitive: false,
    );

    final result = <String>[];
    var pending = parts[0].trim();
    String? currentVerbPrefix;

    for (var i = 1; i < parts.length; i++) {
      final next = parts[i].trim();
      final pendingHasVerb = actionVerbs.any((v) => pending.contains(v));
      final nextHasVerb = actionVerbs.any((v) => next.contains(v));
      final pendingHasAmount = hasAmountRegExp.hasMatch(pending);
      final nextHasAmount = hasAmountRegExp.hasMatch(next);

      if (pendingHasVerb) {
        final match = RegExp(
          r'^(catat\s+(?:pemasukan|pengeluaran|belanja|transfer)?|tambah\s+(?:pemasukan|pengeluaran)?|buat\s+(?:target|anggaran)?|bayar)',
          caseSensitive: false,
        ).firstMatch(pending);
        if (match != null) {
          currentVerbPrefix = match.group(0);
        } else {
          for (final v in actionVerbs) {
            if (pending.contains(v)) {
              currentVerbPrefix = v;
              break;
            }
          }
        }
      }

      final isSeparateAction =
          (pendingHasVerb && nextHasVerb) ||
          (pendingHasAmount && nextHasAmount);

      if (isSeparateAction) {
        result.add(pending);
        if (!nextHasVerb && currentVerbPrefix != null) {
          pending = '$currentVerbPrefix $next';
        } else {
          pending = next;
        }
      } else {
        pending = '$pending ${parts[i]}'.trim();
      }
    }
    if (pending.isNotEmpty) result.add(pending);
    return result.where((s) => s.isNotEmpty).toList();
  }

  /// Menjawab pertanyaan lanjutan hanya terhadap draft yang masih tertahan.
  /// Tidak ada insert atau update data FFM pada tahap ini.
  Future<List<FfmAssistantIntent>> resolvePendingDialog(
    String rawText,
    FfmAssistantPendingDialog pending, {
    FfmAssistantDestination? currentDestination,
    String? pageContext,
    List<String> capabilityIds = const <String>[],
  }) async {
    final normalized = _normalize(rawText);
    if (_containsAny(normalized, const ['batal', 'jangan jadi'])) {
      return [
        FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.cancel,
          confidence: 1,
          response: 'Oke, draft ini dibatalkan. Belum ada data yang tersimpan.',
        ),
      ];
    }
    if (_isGreetingWord(normalized)) {
      final greeting = _randomGreeting();
      return [
        FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.help,
          confidence: 1,
          response:
              '$greeting Masih ada draf yang belum lengkap nih. Mau lanjut melengkapi draf di atas, atau ada hal lain yang mau kamu catat?',
        ),
      ];
    }
    // Explicit new intent tidak boleh diserap pending draft yang belum
    // lengkap. Misal pending goal kurang nominal + "catat pemasukan 500 rb"
    // harus menjadi transaksi baru, bukan mengisi nominal goal lama.
    // Follow-up tanpa intent baru ("500 ribu") tetap melengkapi draft lama.
    if (_hasExplicitIntent(normalized)) {
      return [
        await interpret(
          rawText,
          currentDestination: currentDestination,
          pageContext: pageContext,
          capabilityIds: capabilityIds,
        ),
      ];
    }
    final initial = pending.draft;
    if (initial == null) {
      if (pending.missingFields.contains('jenis transaksi')) {
        final isIncome = _containsAny(normalized, const [
          'pemasukan',
          'uang masuk',
          'masuk',
        ]);
        final isExpense = _containsAny(normalized, const [
          'pengeluaran',
          'uang keluar',
          'keluar',
        ]);
        if (isIncome != isExpense) {
          return [
            await interpret(
              '$rawText ${pending.originalRequest}',
              currentDestination: currentDestination,
              pageContext: pageContext,
              capabilityIds: capabilityIds,
            ),
          ];
        }
        return [
          FfmAssistantIntent(
            rawText: rawText,
            normalizedText: normalized,
            type: FfmAssistantIntentType.unknown,
            confidence: .45,
            clarification: 'Aku masih perlu pilih jenisnya dulu: ini pemasukan atau pengeluaran? Tidak ada data yang disimpan.',
          ),
        ];
      }
      return [
        await interpret(
          rawText,
          currentDestination: currentDestination,
          pageContext: pageContext,
          capabilityIds: capabilityIds,
        ),
      ];
    }

    var draft = initial;
    if (pending.missingFields.contains('nominal')) {
      final amount = FfmAssistantAmountParser.parse(normalized);
      if (amount != null) draft = draft.copyWith(amount: amount);
    }
    final accounts = await _activeAccounts();
    final matchingAccounts = accounts
        .where((account) => normalized.contains(account.name.toLowerCase()))
        .toList(growable: false);
    if (matchingAccounts.length == 1) {
      final accountName = matchingAccounts.single.name;
      if (pending.missingFields.contains('rekening asal')) {
        draft = draft.copyWith(fromAccountName: accountName);
      }
      if (pending.missingFields.contains('rekening tujuan')) {
        draft = draft.copyWith(toAccountName: accountName);
      }
    }
    if (draft.kind == FfmAssistantDraftKind.profile) {
      final profileValues = _extractProfileValues(rawText);
      if (profileValues.isNotEmpty) {
        draft = draft.copyWith(
          formValues: {...draft.formValues, ...profileValues},
          note: [
            ...{...draft.formValues, ...profileValues}.entries,
          ].map((entry) => '${entry.key}: ${entry.value}').join('\n'),
        );
      }
    }

    final resolved = _intentForDraft(
      pending.originalRequest,
      _normalize(pending.originalRequest),
      draft,
    );
    if (resolved.needsClarification) {
      final accountMissing =
          (pending.missingFields.contains('rekening asal') ||
              pending.missingFields.contains('rekening tujuan')) &&
          matchingAccounts.isEmpty;
      return [
        FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: resolved.type,
          destination: resolved.destination,
          draft: draft,
          review: FfmAssistantDraftReview(
            draft: draft,
            version: 1,
            issues: const [],
          ),
          confidence: .6,
          clarification:
              '${resolved.clarification ?? pending.prompt}${accountMissing ? ' Rekening yang kamu sebut belum ada. Sebut rekening yang terdaftar atau buat dulu lewat “tambah rekening [nama]”.' : ''}',
        ),
      ];
    }
    return [
      FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: resolved.type,
        destination: resolved.destination,
        draft: draft,
        review: FfmAssistantDraftReview(
          draft: draft,
          version: 1,
          issues: const [],
        ),
        confidence: .9,
        response: 'Sip, datanya sudah lengkap. Cek draft ini dulu sebelum kamu simpan.',
      ),
    ];
  }

  Future<FfmAssistantIntent> interpret(
    String rawText, {
    FfmAssistantDestination? currentDestination,
    String? pageContext,
    String? lastAssistantMessage,
    String? conversationHistory,
    List<String> capabilityIds = const <String>[],
    ActivityLiveSnapshot? activitySnapshot,
    FfmAssistantRoutingMode? routingMode,
    FfmAssistantDraft? activeDraft,
  }) async {
    var normalized = _normalize(rawText);
    final isGeminiConversationMode =
        routingMode == FfmAssistantRoutingMode.geminiCloud;
    final hasActionVerb = _containsAny(normalized, const [
      'buat',
      'tambah',
      'mulai',
      'jalankan',
      'simpan',
      'catat',
      'masukkan',
      'selesai',
      'beres',
      'stop',
      'tutup',
      'perbarui',
      'update',
      'hapus',
      'buka',
    ]);
    // Kata arah perubahan/pindah yang memicu jalur draft deterministic tetapi
    // tidak memblokir pertanyaan bebas (mis. "sebaiknya saya jual motor?")
    // agar Gemini tetap bisa menjawab tanpa membuka gate mutasi.
    final hasDraftOrientedVerb = _containsAny(normalized, const [
      'beli',
      'bayar',
      'jual',
      'transfer',
      'pindahkan',
      'ubah',
      'koreksi',
      'edit',
      'isi saldo',
      'top up',
      'topup',
    ]);

    // Semua guard deterministik berjalan lebih dahulu. Jika tidak menangani
    // permintaan, pertanyaan bebas diteruskan ke Gemini Cloud yang sudah diverifikasi.
    // Dengan urutan ini, PIN, diagnostik, konfirmasi, dan query lokal tidak
    // pernah diserahkan kepada teks bebas dari model.

    // Fetch master data early for Gemini validation
    final accounts = await _activeAccounts();
    final categories = await _activeCategories();

    // Fallback rule-based
    if (normalized.isEmpty) {
      return _unknown(
        rawText,
        normalized,
        'Tulis atau ucapkan dulu yang mau kamu lakukan, ya.',
      );
    }

    if (isGeminiConversationMode && !_geminiContextFirstEnabled) {
      return _cloudError(
        rawText,
        normalized,
        'Jalur context-first Gemini sedang dinonaktifkan sementara. Gunakan mode Agent atau coba lagi setelah rollout diaktifkan.',
        model: 'context-first-disabled',
      );
    }

    // Mode Gemini menjadikan Gemini sebagai lawan bicara utama. Dialog
    // deterministik hanya dipakai di mode Agent agar kata seperti "mau",
    // "bisa", atau "sip" dalam pertanyaan normal tidak menelan request
    // sebelum Gemini sempat memahaminya.
    if (!isGeminiConversationMode) {
      final conversationalTurn = await _resolveConversationalDialogueTurn(
        rawText,
        normalized,
        lastAssistantMessage: lastAssistantMessage,
      );
      if (conversationalTurn != null) return conversationalTurn;
    }

    final proposal = FfmAssistantProposalJsonService.parse(
      rawText,
      createdAt: _clock(),
    );
    if (proposal.draft != null) {
      final intent = _intentForDraft(rawText, normalized, proposal.draft!);
      final hasActive =
          activitySnapshot != null && activitySnapshot.hasActiveSessions;

      final baseIntent = intent.copyWith(
        pluginName: 'rule_actuator',
        pluginCategory: '✋ Actuator',
      );

      if (proposal.draft!.kind == FfmAssistantDraftKind.activity && hasActive) {
        final active = activitySnapshot.activeSessions.last;
        return baseIntent.copyWith(
          response:
              'Sip, draft aktivitas “${proposal.draft!.title}” sudah siap. Berhubung kamu masih menjalankan “${active.title}”, apakah ini bagian dari kegiatan tersebut atau aktivitas baru yang terpisah?',
        );
      }

      if ((proposal.draft!.kind == FfmAssistantDraftKind.expense ||
              proposal.draft!.kind == FfmAssistantDraftKind.income) &&
          hasActive) {
        final active = activitySnapshot.activeSessions.last;
        return baseIntent.copyWith(
          response:
              'Draft ${proposal.draft!.kind == FfmAssistantDraftKind.expense ? 'pengeluaran' : 'pemasukan'} sudah siap. Mau aku hubungkan sekalian dengan aktivitas “${active.title}” yang sedang jalan?',
        );
      }
      return baseIntent;
    }
    if (proposal.error != null) {
      _logAssistantFailure(
        code: 'agent-proposal-parse',
        technical: proposal.error!,
        impact: 'Proposal tidak valid; fallback ramah tanpa draft.',
      );
      return _unknown(
        rawText,
        normalized,
        _friendlyProposalError(proposal.error!),
      );
    }

    // Gemini menyusun proposal memory pada mode Gemini; mode Agent tetap
    // menggunakan parser lokal supaya tetap bisa bekerja tanpa cloud.
    if (!isGeminiConversationMode) {
      final userProfileIntent = _parseUserProfileMemory(rawText, normalized);
      if (userProfileIntent != null) return userProfileIntent;
      final aliasIntent = _parseAliasMemory(rawText, normalized);
      if (aliasIntent != null) return aliasIntent;
    }
    normalized = await _memory.applyAliases(normalized);
    normalized = await _taughtMemory.applyAliases(normalized);

    // Provider konteks personal bersifat enhancement. Jika pabrik provider
    // gagal, interpreter tetap lanjut dengan konteks dasar tanpa crash.
    FfmPersonalContextProvider? provider;
    try {
      provider = _personalContextProvider?.call();
    } catch (_) {
      provider = null;
    }
    final workingContext = provider?.workingContextManager.currentContext;

    // ── PILAR 2: Coreference Resolution ─────────────────────────────────────
    // Selesaikan kata ganti/rujukan ke entitas terakhir yang ada di memori
    // sesi sebelum menjalankan guard deterministik lebih lanjut.
    if (_sessionMemory.hasAnyEntity) {
      normalized = _sessionMemory.resolveCoref(normalized);
    } else if (workingContext != null &&
        workingContext.lastActivityTitle != null) {
      // Persistence fallback coref
      if (normalized == 'berapa lama' || normalized == 'durasi') {
        normalized = 'berapa lama ${workingContext.lastActivityTitle}';
      } else if (normalized == 'selesai' ||
          normalized == 'beres' ||
          normalized == 'stop') {
        normalized = 'selesai ${workingContext.lastActivityTitle}';
      }
    }

    // Memory cloud hanya relevan bagi Gemini. Agent lokal tidak perlu
    // melakukan request Supabase untuk jawaban deterministiknya.
    String cloudContext = '';
    if (isGeminiConversationMode) {
      try {
        final cloudMemories = await _supabase.searchMemories(query: normalized);
        if (cloudMemories.isNotEmpty) {
          cloudContext =
              '\n\n**Ingatan tambahan dari Cloud:**\n${cloudMemories.map((m) => '- ${m['content']}').join('\n')}';
        }
      } catch (_) {}
    }

    // ── KONTROL TEMA APLIKASI (Deterministik) ─────────────────────────────────
    // Perubahan tema (mode gelap / terang / sistem) adalah kontrol UI lokal murni.
    // Dijalankan deterministik sebelum Gemini Cloud agar instan (<10ms) dan tidak halusinasi.
    final earlyThemeIntent = _parseThemeChangeRequest(rawText, normalized);
    if (earlyThemeIntent != null) return earlyThemeIntent;

    // ── GREETING & SAPAAN (Deterministik) ─────────────────────────────────────
    // Sapaan simple dijawab langsung tanpa ke Gemini untuk respons cepat, hanya
    // di mode Agent. Di mode Gemini Cloud, sapaan tetap diteruskan ke Gemini
    // agar asisten cloud menjadi lawan bicara utama.
    if (!isGeminiConversationMode && _isGreetingWord(normalized)) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 1,
        response: _randomGreeting(),
      );
    }

    // Gemini-first: semua percakapan biasa, termasuk sapaan, penjelasan
    // fitur, dan pertanyaan singkat, menjadi tanggung jawab Gemini. JSON
    // proposal yang dikembalikan tetap diparse dan divalidasi oleh FFM;
    // Gemini tidak pernah menulis state aplikasi secara langsung.
    if (isGeminiConversationMode) {
      final geminiResult = await _tryGeminiResponse(
        rawText,
        normalized,
        currentDestination: currentDestination,
        pageContext: pageContext,
        conversationHistory: conversationHistory,
        capabilityIds: capabilityIds,
        cloudContext: cloudContext,
        accounts: accounts,
        categories: categories,
        activeDraft: activeDraft,
      );
      if (geminiResult != null) {
        final list = geminiResult.toList();
        _pendingGeminiExtraIntents = list.length > 1
            ? list.sublist(1)
            : const [];
        return list.first;
      }
    }

    // Gemini dipanggil setelah guard deterministic dan parser draft selesai.
    // seperti “tanggal berapa sekarang”, jadi harus diprioritaskan.
    if (_isHijriDateRequest(normalized)) {
      final now = _clock();
      DateTime targetDate = now;
      String dateLabel = 'sekarang';

      // Check for hijri event queries
      final eventQuery = _parseHijriEventQuery(normalized);
      if (eventQuery != null) {
        return await _handleHijriEventQuery(rawText, normalized, eventQuery);
      }

      // Parse relative dates (X hari ke depan/belakang)
      final daysToAdd = _parseRelativeDays(normalized);
      if (daysToAdd != null) {
        targetDate = now.add(Duration(days: daysToAdd));
        if (daysToAdd > 0) {
          dateLabel = '$daysToAdd hari ke depan';
        } else if (daysToAdd < 0) {
          dateLabel = '${daysToAdd.abs()} hari ke belakang';
        }
      } else {
        // Check for simple "besok"/"esok"
        final isTomorrow = _containsAny(normalized, const ['besok', 'esok']);
        if (isTomorrow) {
          targetDate = now.add(const Duration(days: 1));
          dateLabel = 'besok';
        }
      }

      final hijri = await HijriCalendarService(_database)
          .convert(AppContext.householdId, targetDate);
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.calendarQuery,
        confidence: 1,
        response:
            'Tanggal Hijriah $dateLabel: ${_formatHijriDate(hijri)}. Ini mengikuti pengaturan Kalender Hijriah FFM di perangkat kamu.',
      );
    }

    final taughtAnswer = await _findTaughtAnswer(normalized);
    if (taughtAnswer != null) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: .95,
        response: taughtAnswer.valueText,
      );
    }

    // ── PILAR 3: Knowledge Base 15 Fitur & Zakat ────────────────────────────
    // Dipanggil sebelum query data atau Gemini agar pertanyaan panduan
    // dijawab deterministik tanpa membebani model, KECUALI query analisis data spesifik.
    final isLoanAffordabilityQuery = _containsAny(normalized, const [
      'cicilan maksimal',
      'kemampuan cicilan',
      'kemampuan pinjaman',
      'batas cicilan',
      'bisa pinjam berapa',
      'hitung cicilan',
      'simulasi pinjaman',
      'simulasi kredit',
    ]);
    final financialEducation = isLoanAffordabilityQuery
        ? null
        : _financialEducation.answer(normalized);
    final isActionRequest = _containsAny(normalized, const [
      'buat',
      'tambah',
      'catat',
      'simpan',
      'ubah',
      'hapus',
      'buka',
      'jalankan',
    ]);
    final isQuestion = _containsAny(normalized, const [
      'bagaimana',
      'gimana',
      'cara',
      'apa ',
      'berapa',
      'boleh',
      'sebaiknya',
      'mengapa',
      'kenapa',
      'tips',
    ]);
    if (financialEducation != null && isQuestion && !isActionRequest) {
      final personalContext = await _buildPersonalFinancialContext();
      final contextNote = personalContext.isNotEmpty
          ? '\n\n**Kondisi kamu:** $personalContext'
          : '';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 1,
        response:
            '${financialEducation.title}\n${financialEducation.message}$contextNote',
      );
    }

    final calendarAnswer = FfmAssistantLocalCalendar.answer(
      normalized,
      now: _clock(),
    );
    if (calendarAnswer != null) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.calendarQuery,
        confidence: 1,
        response: calendarAnswer,
      );
    }

    final themeIntent = _parseThemeChangeRequest(rawText, normalized);
    if (themeIntent != null) return themeIntent;

    if (_isOtherMenuListRequest(normalized)) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.listPages,
        destination: FfmAssistantDestination.otherMenu,
        confidence: 1,
        response:
            'Menu Lainnya memiliki ${FfmAssistantCatalog.otherMenuItems.length} menu berikut beserta fungsinya:\n${FfmAssistantCatalog.listOtherMenuForChat()}',
      );
    }

    final earlyNavigationDestination = _parseDestination(normalized);
    if (earlyNavigationDestination != null &&
        (_isNavigationRequest(normalized) ||
            _isExplicitPageNavigationRequest(normalized)) &&
        !_containsAny(normalized, const [
          'mulai aktivitas',
          'mulai kegiatan',
          'catat aktivitas',
          'buat aktivitas',
        ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.openPage,
        destination: earlyNavigationDestination.destination,
        confidence: .98,
        response:
            'Siap, aku pindahkan kamu ke ${earlyNavigationDestination.name}. Tekan “Buka & cek” kalau sudah siap.',
      );
    }

    final basicQuestion = FfmAssistantCatalog.classifyBasicQuestion(normalized);
    if (basicQuestion != null && !_isNavigationRequest(normalized)) {
      if (basicQuestion.kind == FfmAssistantBasicQuestionKind.completeness) {
        final queryAnswer = await _queryRegistry.tryAnswer(
          normalized,
          householdId: AppContext.householdId,
        );
        if (queryAnswer != null) {
          return FfmAssistantIntent(
            rawText: rawText,
            normalizedText: normalized,
            type: FfmAssistantIntentType.queryData,
            destination: basicQuestion.page.destination,
            confidence: .98,
            response: '${queryAnswer.title}\n${queryAnswer.message}',
          );
        }
      }
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.featureHelp,
        destination: basicQuestion.page.destination,
        confidence: .98,
        response: FfmAssistantCatalog.answerBasicQuestion(basicQuestion),
      );
    }

    // Input gambar tidak tersedia; asisten menerima perintah teks.
    if (_containsAny(normalized, const [
      'bisa membaca struk',
      'bisa baca struk',
      'bisa baca nota',
      'bisa scan struk',
      'baca struk',
      'baca nota',
      'scan struk',
      'foto struk',
      'baca gambar',
      'bisa lihat gambar',
      'bisa melihat gambar',
      'bisa ocr',
      'bisa vision',
      'ekstrak nota',
      'baca bukti transfer',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 1,
        response:
            'Asisten saat ini hanya menerima perintah teks. '
            'Ketikkan rincian belanja secara manual atau tempel hasil JSON '
            'nota di menu impor transaksi.',
      );
    }

    if (_containsAny(normalized, const [
      'kamu siapa',
      'kamu itu siapa',
      'anda siapa',
      'asisten siapa',
      'asisten ini siapa',
      'aplikasi apa ini',
      'ini aplikasi apa',
      'ffm itu apa',
      'dia itu siapa',
      'asisten ffm itu apa',
      'siapa pembuat aplikasi',
      'pembuat aplikasi ini siapa',
      'pembuat aplikasi ini siapa ya',
      'siapa developer aplikasi',
      'developer aplikasi fmm',
      'siapa developer fmm',
      'developer fmm siapa',
      'developer aplikasi ini siapa',
      'developer nya siapa',
      'developernya siapa',
      'developer aplikasi ini',
      'siapa pengembang aplikasi',
      'pengembang aplikasi fmm',
      'siapa pengembang fmm',
      'pengembang aplikasi ini siapa',
      'siapa yang membuat kamu',
      'siapa yang buat kamu',
      'siapa yang membuat fmm',
      'siapa pembuatmu',
      'siapa penciptamu',
      'siapa yang menciptakan kamu',
      'aplikasi ini buatan siapa',
      'aplikasi fmm buatan siapa',
      'ffm buatan siapa',
      'buatan siapa ini',
      'besutan siapa',
      'kamu besutan siapa',
      'rafi sinkkat siapa',
      'siapa rafi sinkkat',
      'siapa rafi',
      'rafi siapa',
      'rafi sinkkat itu siapa',
      'siapa rafi sinkkat itu',
      'creator kamu siapa',
      'creator aplikasi ini siapa',
      'dibuat oleh siapa',
      'aplikasi ini dibuat oleh siapa',
      'dibuat oleh siapa aplikasi ini',
      'kamu bisa apa',
      'kamu bisa apa saja',
      'sekarang bisa apa',
      'sekarang bisa apa saja',
      'asisten bisa apa',
      'anda bisa apa',
      'kemampuan kamu',
      'kemampuanmu',
      'kemampuan asisten',
      'apa saja yang kamu bisa',
      'kamu dapat melakukan apa',
      'tugas kamu',
    ])) {
      final cannedResponse = _selfDescription.build(
        slmConfigured: false,
        includeCreatorLinks: RegExp(
          r'pembuat|developer|pengembang|creator|pencipta|rafi',
          caseSensitive: false,
        ).hasMatch(rawText),
        currentDestination: currentDestination,
      );
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.assistantIdentity,
        confidence: 1,
        response: cannedResponse,
      );
    }

    if (_isGeminiStatusRequest(normalized)) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        destination: FfmAssistantDestination.intelligenceDashboard,
        confidence: 1,
        response: 'Status Gemini Cloud dapat dilihat di Dashboard Intelligence. API key dan model hanya dianggap aktif setelah model berhasil ditemukan dan Test API Key mengembalikan jawaban. Jika belum diverifikasi, chat tidak akan menyamarkan jawaban lokal sebagai Gemini.',
      );
    }

    if (_isCashVerificationStatement(normalized)) {
      return _verifyCashAccount(rawText, normalized);
    }

    if (normalized == 'cash') {
      const clarification =
          'Maksud Cash yang mana? Kamu bisa pilih: cek apakah rekening Cash sudah ada, tambah rekening Cash, atau pakai Cash sebagai sumber transaksi. Aku belum mengubah data apa pun.';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 1,
        response: clarification,
        clarification: clarification,
      );
    }

    if (_isBudgetNavigationRequest(normalized)) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.openPage,
        destination: FfmAssistantDestination.budget,
        confidence: 1,
        response: 'Siap, aku arahkan ke halaman Anggaran. Tekan Buka untuk melihat dan mengatur anggaran.',
      );
    }

    // General navigation handler for any page
    if (_isNavigationRequest(normalized) &&
        !_isOtherMenuListRequest(normalized) &&
        !_containsAny(normalized, const [
          'mulai aktivitas',
          'mulai kegiatan',
          'catat aktivitas',
          'buat aktivitas',
        ])) {
      final targetPage = FfmAssistantCatalog.findByText(normalized);
      if (targetPage != null) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.openPage,
          destination: targetPage.destination,
          confidence: 1,
          response:
              'Siap, aku arahkan ke halaman ${targetPage.name}. Tekan Buka untuk ${targetPage.description.toLowerCase()}',
        );
      }
    }

    if (_containsAny(normalized, const [
      'data lokal',
      'apa itu data lokal',
      'maksud data lokal',
      'kenapa data lokal',
      'privasi data',
      'keamanan data',
      'apakah data aman',
      'apakah offline',
      'apakah butuh internet',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 1,
        response: '**Data Lokal** berarti seluruh data keuangan keluarga (transaksi, rekening, anggaran, aset, dan catatan hutang) disimpan 100% di penyimpanan internal HP kamu menggunakan database SQLite lokal.\n\n🛡️ **Keunggulan Privasi FFM:**\n- **100% Offline**: Tidak ada data keuangan yang dikirim ke cloud atau server internet.\n- **Tanpa Tracking**: Tidak ada analitik atau pelacakan pihak ketiga.\n- **AI On-Device**: Model bahasa lokal membantu memahami perintah teks secara mandiri di dalam RAM/chipset HP kamu.',
      );
    }

    if (_isOtherMenuListRequest(normalized)) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.listPages,
        destination: FfmAssistantDestination.otherMenu,
        confidence: 1,
        response:
            'Menu Lainnya memiliki ${FfmAssistantCatalog.otherMenuItems.length} menu berikut beserta fungsinya:\n${FfmAssistantCatalog.listOtherMenuForChat()}',
      );
    }

    if (_containsAny(normalized, const [
      'halaman apa saja',
      'ada berapa halaman',
      'berapa halaman',
      'jumlah halaman',
      'halaman ada berapa',
      'halaman berapa',
      'menu apa saja',
      'fitur apa saja',
      'ada menu apa',
      'menu ada berapa',
      'bisa apa saja',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.listPages,
        confidence: 1,
        response:
            'FFM punya ${FfmAssistantCatalog.pages.length} halaman yang bisa kamu buka. Ini daftar dan fungsi singkatnya:\n${FfmAssistantCatalog.listForChat()}\n\nKamu bisa meminta aku untuk membantu pindah ke halaman tertentu. Cukup sebutkan nama halamannya, misalnya "pindah ke Data Utama" atau "buka halaman Anggaran".',
      );
    }

    if (_isReadRequest(normalized) &&
        _containsAny(normalized, const ['ulang', 'baca lagi', 'bacakan'])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.readLastResponse,
        confidence: .95,
      );
    }

    if (_containsAny(normalized, const [
      'ada error apa',
      'error apa',
      'error terakhir',
      'cek error',
      'cek bug',
      'kenapa tadi gagal',
      'masalah aplikasi',
    ])) {
      return _diagnosticStatus(rawText, normalized);
    }

    if (_containsAny(normalized, const [
      'lupa pin',
      'lupa kunci aplikasi',
      'pin lupa',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.openPage,
        destination: FfmAssistantDestination.appSecurity,
        confidence: .98,
        response: 'Aku buka Kunci aplikasi. Demi keamanan, PIN tidak bisa diganti tanpa PIN lama. Tekan “Lupa PIN?” untuk melihat langkah reset data aplikasi dan impor cadangan.',
      );
    }

    if (_containsAny(normalized, const [
      'ganti pin',
      'ubah pin',
      'ganti kunci aplikasi',
      'matikan pin',
      'aktifkan pin',
      'buat pin aplikasi',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.openPage,
        destination: FfmAssistantDestination.appSecurity,
        confidence: .98,
        response: 'Siap, aku buka Kunci aplikasi. PIN lama dan PIN baru kamu masukkan di keypad khusus, bukan di chat. Setelah PIN baru kamu ulangi, kamu tetap diminta konfirmasi terakhir sebelum berubah.',
      );
    }

    if (_containsAny(normalized, const [
      'batal',
      'jangan jadi',
      'hapus semua draft',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.cancel,
        confidence: 1,
        response: 'Oke, draft yang sedang dibahas tidak akan disimpan.',
      );
    }
    if (_containsAny(normalized, const [
      'ok simpan',
      'oke simpan',
      'konfirmasi simpan',
      'ya simpan',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.confirm,
        confidence: 1,
      );
    }

    final dailyNoteMutation = await _parseDailyNoteMutation(
      rawText,
      normalized,
    );
    if (dailyNoteMutation != null) return dailyNoteMutation;

    final taskMutation = await _parseTaskMutation(rawText, normalized);
    if (taskMutation != null) return taskMutation;

    final routineMutation = await _parseRoutineMutation(rawText, normalized);
    if (routineMutation != null) return routineMutation;

    final scheduleMutation = await _parseScheduleMutationSafe(
      rawText,
      normalized,
    );
    if (scheduleMutation != null) return scheduleMutation;

    final activityMutation = await _parseActivityMutation(rawText, normalized);
    if (activityMutation != null) return activityMutation;

    final reminderMutation = await _parseReminderMutation(rawText, normalized);
    if (reminderMutation != null) return reminderMutation;

    final assetMutation = await _parseAssetMutation(rawText, normalized);
    if (assetMutation != null) return assetMutation;

    final liabilityMutation = await _parseLiabilityMutation(
      rawText,
      normalized,
    );
    if (liabilityMutation != null) return liabilityMutation;

    final receivableMutation = await _parseReceivableMutation(
      rawText,
      normalized,
    );
    if (receivableMutation != null) return receivableMutation;

    final recurringMutation = await _parseRecurringTransactionMutation(
      rawText,
      normalized,
    );
    if (recurringMutation != null) return recurringMutation;

    final merchantMutation = await _parseMerchantMutation(rawText, normalized);
    if (merchantMutation != null) return merchantMutation;

    final tagMutation = await _parseTagMutation(rawText, normalized);
    if (tagMutation != null) return tagMutation;

    final incomeSourceMutation = await _parseIncomeSourceMutation(
      rawText,
      normalized,
    );
    if (incomeSourceMutation != null) return incomeSourceMutation;

    final categoryMutation = await _parseCategoryMutation(rawText, normalized);
    if (categoryMutation != null) return categoryMutation;

    final accountMutation = await _parseAccountMutation(rawText, normalized);
    if (accountMutation != null) return accountMutation;

    final budgetMutation = await _parseBudgetMutation(rawText, normalized);
    if (budgetMutation != null) return budgetMutation;

    final goalMutation = await _parseGoalMutation(rawText, normalized);
    if (goalMutation != null) return goalMutation;

    final transactionMutation = await _parseTransactionMutation(
      rawText,
      normalized,
    );
    if (transactionMutation != null) {
      _sessionMemory.updateFromDraft(
        accountName:
            transactionMutation.draft?.fromAccountName ??
            transactionMutation.draft?.toAccountName,
        categoryName: transactionMutation.draft?.categoryName,
        amount: transactionMutation.draft?.amount,
      );
      return transactionMutation;
    }

    final correction = _parseCorrection(rawText, normalized);
    if (correction != null) return correction;

    if (_isSetupRequest(normalized)) {
      return _setupGuide(rawText, normalized);
    }

    if (_isDraftHelpRequest(normalized)) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 1,
        response: 'Rancangan itu isi sementara yang aku siapkan hanya saat kamu memang minta tambah atau ubah data. Rancangan belum menyimpan apa pun. Di kartu rancangan kamu bisa lihat data yang akan dibuka, benarkan pesan kalau maksudnya salah, lalu pilih “Buka & cek” untuk mengisi form resmi. Kalau cuma bertanya fungsi fitur, aku seharusnya menjawab tanpa membuat rancangan.',
      );
    }

    if (_isDatabaseStructureRequest(normalized) &&
        !_isExplicitPageNavigationRequest(normalized)) {
      final queryAnswer = await _queryRegistry.tryAnswer(
        normalized,
        householdId: AppContext.householdId,
      );
      if (queryAnswer != null) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.queryData,
          confidence: .98,
          response: '${queryAnswer.title}\n${queryAnswer.message}',
        );
      }
    }

    final featureHelp = _isNavigationRequest(normalized)
        ? null
        : _featureHelp(
            rawText,
            normalized,
            currentDestination: currentDestination,
          );
    if (featureHelp != null) {
      return featureHelp;
    }

    if (_isWeeklyAnalysisRequest(normalized)) {
      return _weeklyAnalysis(rawText, normalized);
    }

    if (_isTransactionStats(normalized)) {
      return _transactionStats(rawText, normalized);
    }

    if (_isFinancialWarningRequest(normalized)) {
      return _financialWarnings(rawText, normalized);
    }

    // Explicit intent harus mengalahkan page context. Jika user memberikan perintah
    // eksplisit seperti "catat pemasukan", jangan override dengan page context
    // meskipun user sedang di halaman tertentu.
    if (_isCurrentPageRequest(normalized) &&
        currentDestination != null &&
        !_hasExplicitIntent(normalized)) {
      return _currentPageContext(rawText, normalized, currentDestination);
    }

    if (!_isNavigationRequest(normalized)) {
      final queryAnswer = await _queryRegistry.tryAnswer(
        normalized,
        householdId: AppContext.householdId,
      );
      if (queryAnswer != null) {
        // Generate verified facts for grounding
        String? verifiedFacts;
        try {
          final scope = FfmAssistantReasoningEvidencePolicy.forRequest(
            normalized,
          );
          final facts = await _verifiedFactService.generateFacts(
            householdId: AppContext.householdId,
            scope: scope,
          );
          verifiedFacts = facts.toLLMContext();
        } catch (_) {
          // If verified fact service fails, continue without it
          verifiedFacts = null;
        }

        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.queryData,
          confidence: .98,
          response: '${queryAnswer.title}\n${queryAnswer.message}',
          verifiedFacts: verifiedFacts,
        );
      }
    }

    if (_containsAny(normalized, const [
      'buat json',
      'bikin json',
      'template json',
    ])) {
      return _jsonTemplateHelp(rawText, normalized);
    }
    if (_containsAny(normalized, const [
      'fungsi json',
      'json buat apa',
      'jelaskan json',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.explainJson,
        destination: FfmAssistantDestination.backup,
        confidence: .9,
        response: 'JSON adalah format data terstruktur. Di FFM, JSON bisa dipakai untuk mengekspor data lokal, menyiapkan prompt ke LLM di luar aplikasi, atau mengimpor batch transaksi sebagai draft. JSON tidak pernah langsung disimpan tanpa kamu cek dan konfirmasi.',
      );
    }
    if (_containsAny(normalized, const [
      'buat laporan',
      'laporan bulan ini',
      'jadi pdf',
      'ke pdf',
      'jadi html',
      'ke html',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.exportReport,
        destination: FfmAssistantDestination.backup,
        confidence: .9,
        response: 'Aku buka Ekspor & cadangan. Pilih PDF atau HTML; laporan akan dibuat dari data lokal pada periode yang kamu pilih.',
      );
    }

    final directDestination = _parseDestination(normalized);
    if (directDestination != null &&
        !_containsAny(normalized, const [
          'mulai aktivitas',
          'mulai kegiatan',
          'catat aktivitas',
          'buat aktivitas',
        ]) &&
        _containsAny(normalized, const [
          'buka',
          'pindah',
          'ke halaman',
          'ke bagian',
          'arah ke',
          'bawa ke',
          'pergi ke halaman',
          'pergi ke menu',
          'masuk halaman',
          'masuk menu',
          'tampilkan',
        ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.openPage,
        destination: directDestination.destination,
        confidence: .98,
        response:
            'Siap, aku pindahkan kamu ke ${directDestination.name}. Tekan “Buka & cek” kalau sudah siap.',
      );
    }

    if (_isAmbiguousLoan(normalized)) {
      return _unknown(
        rawText,
        normalized,
        'Aku perlu pastikan arahnya dulu: kamu meminjam dari orang itu, atau orang itu meminjam dari kamu? Sebut “hutang” atau “piutang”, ya.',
      );
    }

    // ── ROUTING MODE GEMINI DRAFT ──────────────────────────────────────────────
    // Gemini boleh memahami permintaan natural sebagai proposal JSON. Agent tetap
    // memvalidasi draft dan menjadi satu-satunya jalur konfirmasi/penyimpanan.
    if (routingMode == FfmAssistantRoutingMode.geminiCloud &&
        _looksLikeDraftRequest(normalized)) {
      final geminiDraftResult = await _tryGeminiResponse(
        rawText,
        normalized,
        currentDestination: currentDestination,
        pageContext: pageContext,
        conversationHistory: conversationHistory,
        capabilityIds: capabilityIds,
        cloudContext: cloudContext,
        accounts: accounts,
        categories: categories,
        activeDraft: activeDraft,
      );
      if (geminiDraftResult != null) {
        final list = geminiDraftResult.toList();
        _pendingGeminiExtraIntents = list.length > 1
            ? list.sublist(1)
            : const [];
        return list.first;
      }
    }

    // ── MASTER DATA CREATION (early guard) ───────────────────────────────────────
    // Deteksi dini permintaan pembuatan data master (tag, kategori, rekening, dll.)
    // agar tidak tertangkap oleh harness atau SLM sebelum sampai ke _parseFinancialDraft.
    final earlyMasterData = _masterDataRequest(normalized);
    if (earlyMasterData != null) {
      final names = _masterDataDraftNames(normalized, earlyMasterData.$2);
      final target = earlyMasterData.$1;
      if ((target == 'tag' || target == 'sumber_pemasukan') &&
          names.length > 1) {
        final intents = names
            .map(
              (name) => _intentForDraft(
                rawText,
                normalized,
                FfmAssistantDraft(
                  kind: FfmAssistantDraftKind.masterData,
                  createdAt: _clock(),
                  title: name,
                  categoryName: target,
                  note: rawText.trim(),
                  date: _clock(),
                ),
              ),
            )
            .toList(growable: false);
        _pendingGeminiExtraIntents = intents.length > 1
            ? intents.sublist(1)
            : const [];
        return intents.first.copyWith(
          response:
              'Aku menyiapkan ${intents.length} draft ${_masterDataTargetName(target).toLowerCase()}. Cek semuanya dulu, lalu konfirmasi yang sudah benar.',
        );
      }
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.masterData,
        createdAt: _clock(),
        title: names.firstOrNull,
        categoryName: target,
        note: rawText.trim(),
        date: _clock(),
      );
      return _intentForDraft(rawText, normalized, draft);
    }

    if (_containsAny(normalized, const [
      'mulai aktivitas',
      'mulai kegiatan',
      'catat aktivitas',
      'buat aktivitas',
    ])) {
      final activityDraft = _parseFinancialDraft(
        rawText,
        normalized,
        accounts,
        categories,
        currentDestination: currentDestination,
        activitySnapshot: activitySnapshot,
      );
      if (activityDraft != null) {
        return _intentForDraft(rawText, normalized, activityDraft);
      }
    }

    // ── ROUTING MODE GEMINI CLOUD ─────────────────────────────────────────────
    // Mode eksplisit Gemini mengambil pertanyaan bebas sebelum harness Agent.
    // Perintah aksi/nominal tetap melewati guard deterministic di bawah agar
    // Gemini tidak pernah mendapat hak mutasi langsung.
    if (routingMode == FfmAssistantRoutingMode.geminiCloud &&
        !hasActionVerb &&
        FfmAssistantAmountParser.parse(normalized) == null) {
      final geminiResult = await _tryGeminiResponse(
        rawText,
        normalized,
        currentDestination: currentDestination,
        pageContext: pageContext,
        conversationHistory: conversationHistory,
        capabilityIds: capabilityIds,
        cloudContext: cloudContext,
        accounts: accounts,
        categories: categories,
        activeDraft: activeDraft,
      );
      if (geminiResult != null) {
        final list = geminiResult.toList();
        _pendingGeminiExtraIntents = list.length > 1
            ? list.sublist(1)
            : const [];
        return list.first;
      }
    }

    // ── HARNESS DISPATCH ──────────────────────────────────────────────────────
    // Plugin Mata / Tangan / Logika berjalan lebih dahulu untuk perintah
    // terstruktur (catat, buka, hapus, dll). Pertanyaan bebas diteruskan ke
    // Gemini setelah aturan deterministic selesai.

    final harnessResult = await _harness.dispatch(
      FfmHarnessContext(
        rawText: rawText,
        normalizedText: normalized,
        householdId: AppContext.householdId,
        now: _clock(),
        activitySnapshot: activitySnapshot,
      ),
    );
    if (harnessResult != null) {
      final catLabel = switch (harnessResult.category) {
        FfmPluginCategory.sense => '👁️ Sense',
        FfmPluginCategory.actuator => '✋ Actuator',
        FfmPluginCategory.logic => '🧮 Logic',
      };
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: harnessResult.isDraft
            ? FfmAssistantIntentType.confirm
            : FfmAssistantIntentType.queryData,
        confidence: .97,
        response: harnessResult.text,
        pluginName: harnessResult.pluginName,
        pluginCategory: catLabel,
        pluginMetadata: harnessResult.metadata,
      );
    }

    if (hasActionVerb ||
        hasDraftOrientedVerb ||
        FfmAssistantAmountParser.parse(normalized) != null) {
      final contextualDraft = await _actionRegistry.buildDraft(
        input: rawText,
        activePage: currentDestination,
      );
      if (contextualDraft != null) {
        return _intentForDraft(rawText, normalized, contextualDraft);
      }
      final draft = _parseFinancialDraft(
        rawText,
        normalized,
        accounts,
        categories,
        currentDestination: currentDestination,
        activitySnapshot: activitySnapshot,
      );
      if (draft != null) {
        final enriched = await _enrichWithCategorySuggestion(rawText, draft);
        _sessionMemory.updateFromDraft(
          accountName: enriched.fromAccountName ?? enriched.toAccountName,
          categoryName: enriched.categoryName,
          amount: enriched.amount,
        );
        return _intentForDraft(rawText, normalized, enriched);
      }
    }

    final mentionsAccount = _containsAny(normalized, const [
      'rekening',
      'akun',
      'bank',
    ]);
    if (FfmAssistantAmountParser.parse(normalized) != null &&
        mentionsAccount &&
        _matchAccount(normalized, accounts) == null) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.unknown,
        confidence: .45,
        clarification: 'Rekening yang kamu sebut belum ada di Data Utama. Ini pemasukan atau pengeluaran? Setelah itu aku siapkan draft dulu—tidak ada yang tersimpan otomatis.',
      );
    }

    final amount = FfmAssistantAmountParser.parse(normalized);
    if (amount != null) {
      final candidateTerms = _extractCandidateEntityTerms(normalized);
      for (final term in candidateTerms) {
        final matchedAccount = _matchAccount(term, accounts);
        final matchedCategory =
            _matchCategory(term, categories, 'expense') ??
            _matchCategory(term, categories, 'income');
        if (matchedAccount == null &&
            matchedCategory == null &&
            _looksLikeFinancialSourceTerm(term)) {
          return FfmAssistantIntent(
            rawText: rawText,
            normalizedText: normalized,
            type: FfmAssistantIntentType.unknown,
            confidence: .6,
            clarification:
                '"$term" belum ada di Data Utama. Mau aku buatkan dulu sebagai akun/kategori baru sebelum lanjut mencatat transaksinya?',
          );
        }
      }
    }

    final hasAmount = FfmAssistantAmountParser.parse(normalized) != null;
    if (routingMode != FfmAssistantRoutingMode.agent &&
        !hasActionVerb &&
        !hasAmount) {
      final geminiResult = await _tryGeminiResponse(
        rawText,
        normalized,
        currentDestination: currentDestination,
        pageContext: pageContext,
        conversationHistory: conversationHistory,
        capabilityIds: capabilityIds,
        cloudContext: cloudContext,
        accounts: accounts,
        categories: categories,
        activeDraft: activeDraft,
      );
      if (geminiResult != null) {
        final list = geminiResult.toList();
        _pendingGeminiExtraIntents = list.length > 1
            ? list.sublist(1)
            : const [];
        return list.first;
      }
    }

    // Jalur jawaban SLM lokal untuk Mode Agent. Pertanyaan bebas tanpa aksi atau
    // nominal yang tidak terselesaikan aturan deterministik dicoba dijawab oleh
    // penyusun jawaban lokal yang hanya merangkai fakta terarah dari konteks
    // (tidak boleh mengarang nilai). Jika SLM tidak siap/sibuk/gagal, tetap
    // jatuh ke _unknown secara jujur — tidak diam-diam beralih provider.
    if (routingMode == FfmAssistantRoutingMode.agent &&
        !hasActionVerb &&
        !hasDraftOrientedVerb &&
        !hasAmount) {
      final localSlmIntent = await _tryLocalModelResponse(
        rawText,
        normalized,
        currentDestination: currentDestination,
        pageContext: pageContext,
        capabilityIds: capabilityIds,
      );
      if (localSlmIntent != null) return localSlmIntent;
    }

    return _unknown(
      rawText,
      normalized,
      _unsupportedQuestionHelp(normalized) ??
          (_isKnownFfmFeatureGap(normalized)
              ? 'Pertanyaanmu berkaitan dengan fitur FFM, tetapi pengecekan khususnya belum tersedia di aturan lokal saat ini. Aku simpan sebagai gap fitur di Pengetahuan Asisten pada menu Lainnya supaya bisa disalin atau diekspor untuk update berikutnya. Tidak ada data yang dibuat atau diubah.'
              : (lastAssistantMessage != null &&
                        lastAssistantMessage.trim().isNotEmpty
                    ? 'Aku belum bisa menangkap maksudmu terkait percakapan tadi. '
                          'Bisa ulangi dengan lebih spesifik? Misalnya sebutkan nominal, kategori, atau rekening yang dimaksud. '
                          'Ketik *"bisa apa?"* untuk melihat semua kemampuanku.'
                    : 'Aku belum punya jawaban yang pas untuk itu. '
                          'Kalau ada typo, tekan "Benarkan & kirim ulang". '
                          'Kalau pertanyaannya memang belum terjawab, aku simpan di Pengetahuan Asisten pada menu Lainnya. '
                          'Di sana kamu bisa salin atau ekspor pertanyaannya untuk bahan update aplikasi.')),
    );
  }

  bool _looksLikeDraftRequest(String normalized) {
    final hasDraftVerb = _containsAny(normalized, const [
      'buat',
      'tambah',
      'catat',
      'beli',
      'bayar',
      'jual',
      'rekam',
      'siapkan draft',
      'simpan sebagai',
      'ingat bahwa',
      'ingat saya',
    ]);
    if (!hasDraftVerb) return false;
    return _containsAny(normalized, const [
      'transaksi',
      'pemasukan',
      'pengeluaran',
      'belanja',
      'beli',
      'bayar',
      'jual',
      'makan',
      'tag',
      'kategori',
      'rekening',
      'aktivitas',
      'kegiatan',
      'catatan',
      'pengingat',
      'target',
      'aset',
      'hutang',
      'utang',
      'piutang',
      'profil',
      'memory',
      'ingat',
    ]);
  }

  /// Memahami respon percakapan multi-turn yang menanggapi pesan/pertanyaan
  /// asisten sebelumnya (seperti sapaan, tawaran bantuan, atau klarifikasi).
  Future<FfmAssistantIntent?> _resolveConversationalDialogueTurn(
    String rawText,
    String normalized, {
    String? lastAssistantMessage,
  }) async {
    if (lastAssistantMessage == null || lastAssistantMessage.trim().isEmpty) {
      return null;
    }
    final normalizedLast = _normalize(lastAssistantMessage);
    final words = normalized.trim().split(RegExp(r'\s+'));
    if (words.length > 12) return null;

    final isGreetingLast =
        normalizedLast.contains('ada yang bisa kubantu') ||
        normalizedLast.contains('bisa aku bantu') ||
        normalizedLast.contains('siap membantu') ||
        normalizedLast.contains('halo') ||
        normalizedLast.contains('hai');

    // 1. Kasus Penolakan / Selesai ("tidak", "enggak", "belum", "makasih", "cukup", "gak ada")
    final isNegativeOrDone = const {
      'tidak',
      'enggak',
      'nggak',
      'belum',
      'cukup',
      'makasih',
      'terima kasih',
      'nanti dulu',
      'sudah',
      'udah',
      'gak ada',
      'ngga ada',
      'ga ada',
      'tidak ada',
      'tidak ada makasih',
      'tidak ada, makasih',
    }.contains(normalized);

    if (isGreetingLast && isNegativeOrDone) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 0.98,
        response: 'Baik, tidak masalah! Jika sewaktu-waktu butuh bantuan mencatat transaksi atau mengecek anggaran, tinggal sapa aku lagi ya. Selamat beraktivitas!',
      );
    }

    // 2. Kasus Sapaan & Penawaran Bantuan Afirmatif ("ada", "iya", "mau", "bisa", dsb.)
    final isAffirmative = const {
      'ada',
      'iya',
      'ya',
      'yep',
      'yup',
      'mau',
      'bisa',
      'oke',
      'ok',
      'tolong',
      'bantu',
      'siap',
      'lanjut',
      'dong',
      'tentu',
      'boleh',
      'iya mau',
      'ya mau',
      'mau dong',
    }.contains(normalized);

    if (isGreetingLast && isAffirmative) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 0.98,
        response:
            'Sip! Aku siap membantu. Kamu bisa langsung ketik atau pilih tindakan berikut:\n\n'
            '• **Catat transaksi** — contoh: *"catat beli makan 25rb"* atau *"gaji masuk 5jt"*\n'
            '• **Cek ringkasan keuangan** — contoh: *"berapa saldo sekarang"* atau *"anggaran bulan ini"*\n'
            '• **Evaluasi pinjaman** — contoh: *"apakah bisa ambil cicilan 500rb per bulan"*\n'
            'Ada yang ingin kamu mulai terlebih dahulu?',
      );
    }

    // 3. Kasus Permintaan Lanjut ("lanjut", "bagaimana", "lalu apa", "terus gimana")
    if (_containsAny(normalized, const [
      'lanjut',
      'terus',
      'lalu apa',
      'bagaimana',
    ])) {
      if (normalizedLast.contains('draft') || normalizedLast.contains('draf')) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.help,
          confidence: 0.95,
          response: 'Kamu bisa meninjau draf di atas lalu tekan **Simpan** untuk mencatatnya, atau tulis koreksinya jika ada nominal/kategori yang ingin diubah.',
        );
      }
    }

    // 4. Kasus Keraguan / Thinking ("hmm", "bentar", "bentar ya", "sebentar")
    if (_containsAny(normalized, const [
      'hmm',
      'hm',
      'hmmmm',
      'bentar',
      'bentar ya',
      'sebentar',
      'tunggu',
      'tunggu ya',
      'thinking',
    ])) {
      if (normalizedLast.contains('draft') || normalizedLast.contains('draf')) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.help,
          confidence: 0.95,
          response: 'Take your time! Draft-nya masih aman di atas. Kalau sudah yakin, tekan **Simpan**. Kalau ada yang perlu diubah, tinggal bilang aja.',
        );
      }
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 0.9,
        response:
            'Silakan ambil waktu. Aku di sini kalau sudah siap melanjutkan.',
      );
    }

    // 5. Kasus Pujian ("bagus", "keren", "hebat", "mantap", "top")
    if (_containsAny(normalized, const [
      'bagus',
      'keren',
      'hebat',
      'mantap',
      'top',
      'sip',
      'asik',
      'jos',
      'ok mantap',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 0.95,
        response: 'Makasih! Senang bisa bantu. Kalau butuh bantuan lagi, langsung aja ketik atau bilang apa yang mau dilakukan.',
      );
    }

    // 6. Kasus Kritik ("kurang tepat", "salah", "bukan gitu", "keliru")
    if (_containsAny(normalized, const [
      'kurang tepat',
      'salah',
      'bukan gitu',
      'keliru',
      'kurang',
      'kok salah',
      'terlalu',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 0.9,
        response: 'Maaf ya kalau kurang tepat. Bisa diperjelas lagi apa yang salah atau apa yang kamu mau? Aku akan coba perbaiki.',
      );
    }

    // 7. Kasus Permintaan Penjelasan ("kenapa", "maksudnya", "bisa jelaskan", "gimana caranya")
    if (_containsAny(normalized, const [
      'kenapa',
      'maksudnya',
      'bisa jelaskan',
      'gimana caranya',
      'bagaimana bisa',
      'jelaskan',
      'penjelasan',
    ])) {
      if (normalizedLast.contains('draft') || normalizedLast.contains('draf')) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.help,
          confidence: 0.95,
          response: 'Draft adalah data sementara yang aku siapkan berdasarkan permintaanmu. Draft belum tersimpan ke database — kamu perlu review dan tekan **Simpan** sendiri. Ini untuk memastikan tidak ada yang salah sebelum data benar-benar dicatat.',
        );
      }
      if (normalizedLast.contains('transfer')) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.help,
          confidence: 0.95,
          response: 'Transfer di FFM adalah pemindahan dana antar rekening milikmu. Transfer tidak mengubah total kekayaan bersih, hanya memindahkan saldo dari satu dompet ke dompet lain. Biaya admin transfer dicatat sebagai pengeluaran terpisah.',
        );
      }
      if (normalizedLast.contains('anggaran') ||
          normalizedLast.contains('budget')) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.help,
          confidence: 0.95,
          response: 'Anggaran membantu kamu membatasi pengeluaran per kategori dalam satu periode. FFM akan memantau pengeluaran aktual terhadap batas yang kamu tetapkan dan memberi peringatan saat mendekati batas.',
        );
      }
    }

    // 8. Kasus "Apa lagi yang bisa kamu lakukan?" / "Apa selanjutnya?"
    if (_containsAny(normalized, const [
      'apa lagi',
      'apa selanjutnya',
      'apa yang bisa',
      'bisa apa lagi',
      'fitur lain',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 0.95,
        response:
            'Selain yang tadi, aku juga bisa:\n\n'
            '• **Cek saldo rekening** — *"berapa saldo BCA?"*\n'
            '• **Lihat progres tabungan** — *"progres tabungan liburan"*\n'
            '• **Analisis pengeluaran** — *"kategori mana paling boros?"*\n'
            '• **Hitung zakat** — *"hitung zakat mal"*\n\n'
            'Mau coba yang mana?',
      );
    }

    // 9. Kasus follow-up umum — pesan pendek yang merujuk ke konteks sebelumnya
    //    ("bagaimana", "yang mana", "bisa tolong", "lanjut dong", "gimana", dll.)
    if (words.length <= 6) {
      final isFollowUp = _containsAny(normalized, const [
        'bagaimana',
        'gimana',
        'yang mana',
        'bisa tolong',
        'tolong',
        'lanjut',
        'terus',
        'lalu',
        'selanjutnya',
        'lagi',
        'berapa',
        'berapa total',
        'totalnya',
        'sisa',
        'kurang',
        'lebih',
        'tambah',
        'kurangi',
        'ubah',
        'ganti',
        'edit',
        'hapus',
        'batal',
        'undo',
        'koreksi',
        'salah',
      ]);
      if (isFollowUp) {
        final lastSnippet = normalizedLast.length > 150
            ? normalizedLast.substring(0, 150)
            : normalizedLast;
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.help,
          confidence: 0.85,
          response:
              'Tentang yang tadi — $lastSnippet\n\n'
              'Bisa jelaskan lebih spesifik bagian mana yang perlu ditindaklanjuti? '
              'Misalnya: nominal, kategori, rekening, atau langkah selanjutnya.',
        );
      }
    }

    return null;
  }

  Future<FfmAssistantIntent> _diagnosticStatus(
    String rawText,
    String normalized,
  ) async {
    final latest = await _diagnostics.latestEntry();
    if (latest == null) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.diagnosticStatus,
        destination: FfmAssistantDestination.diagnostics,
        confidence: 1,
        response: 'Belum ada error teknis yang tercatat di FFM. Kalau masalahnya muncul lagi, coba ulangi lalu tanya aku lagi atau buka Bantuan perbaikan untuk salin laporan aman.',
      );
    }
    final time = latest.occurredAt.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final formattedTime =
        '${twoDigits(time.day)}/${twoDigits(time.month)}/${time.year} ${twoDigits(time.hour)}:${twoDigits(time.minute)}';
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.diagnosticStatus,
      destination: FfmAssistantDestination.diagnostics,
      confidence: 1,
      response:
          'Ada error teknis terbaru di ${latest.feature} pada $formattedTime. Kode: ${latest.code}. Ringkasan aman: ${latest.summary}. Dampak: ${latest.impact} Buka Bantuan perbaikan untuk lihat dan salin laporan yang sudah disaring.',
    );
  }

  Future<FfmAssistantReasoningContext> _withPersonalContext(
    FfmAssistantReasoningContext base,
  ) async {
    if (_personalContextBlockedDestinations.contains(base.currentPage)) {
      return base;
    }
    try {
      final provider = _personalContextProvider?.call();
      if (provider == null) return base;
      final personalContext = await provider
          .buildContext(
            query: base.request,
            reasoningContext: base,
            budget: _personalContextBudget,
          )
          .timeout(const Duration(milliseconds: 350));
      if (!provider.contextAdapter.validateContext(personalContext)) {
        return base;
      }
      return provider.updateReasoningContext(
        originalContext: base,
        personalContext: personalContext,
      );
    } on Object {
      // Context personal hanya enhancement. Jika belum siap atau gagal,
      // jalur model tetap memakai konteks bounded yang sudah ada.
      return base;
    }
  }

  Future<List<Account>> _activeAccounts() =>
      (_database.select(_database.accounts)..where(
            (row) =>
                row.householdId.equals(AppContext.householdId) &
                row.isArchived.equals(false) &
                row.isActive.equals(true),
          ))
          .get();

  bool _isGeminiStatusRequest(String text) => _containsAny(text, const [
    'sudah terhubung slm',
    'udah terhubung slm',
    'slm sudah terhubung',
    'slm terhubung',
    'ai lokal sudah terhubung',
    'model lokal sudah terhubung',
    'ai lokal sudah siap',
    'model lokal sudah siap',
    'gemini sudah terhubung',
    'sudah terhubung gemini',
    'gemini terhubung',
    'gemini sudah siap',
    'gemini siap',
  ]);

  bool _isCashVerificationStatement(String text) => _containsAny(text, const [
    'sudah saya tambahkan cash',
    'sudah tambah cash',
    'cash sudah ditambahkan',
    'cash sudah ada',
  ]);

  bool _isBudgetNavigationRequest(String text) => _containsAny(text, const [
    'cek halaman anggaran',
    'cek halaman budget',
    'buka halaman anggaran',
    'buka halaman budget',
  ]);

  Future<FfmAssistantIntent> _verifyCashAccount(
    String rawText,
    String normalized,
  ) async {
    final accounts = await _activeAccounts();
    final matches = accounts
        .where((account) {
          final name = account.name.trim().toLowerCase();
          final type = account.type.trim().toLowerCase();
          return name == 'cash' || type == 'cash' || type == 'tunai';
        })
        .toList(growable: false);
    final response = matches.isEmpty
        ? 'Aku belum menemukan rekening aktif bernama atau bertipe Cash di Data Utama. Mungkin belum tersimpan, masih tidak aktif, atau namanya berbeda. Kamu bisa buka Data Utama untuk mengeceknya.'
        : matches.length == 1
        ? 'Ya, aku menemukan satu rekening Cash yang aktif di Data Utama. Aku tidak mengubah saldo atau data apa pun.'
        : 'Aku menemukan ${matches.length} rekening Cash yang aktif di Data Utama. Aku tidak mengubah saldo atau data apa pun.';
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.help,
      confidence: 1,
      response: response,
    );
  }

  Future<List<Category>> _activeCategories() =>
      (_database.select(_database.categories)..where(
            (row) =>
                row.householdId.equals(AppContext.householdId) &
                row.isActive.equals(true),
          ))
          .get();

  Future<List<String>> _recentTransactionSummaries({
    required String householdId,
    int limit = 5,
  }) async {
    final rows =
        await (_database.select(_database.transactions)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isArchived.equals(false) &
                    row.isDeleted.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.date)])
              ..limit(limit))
            .get();
    return rows
        .map(
          (row) =>
              '${row.type == 'income' ? 'Pemasukan' : 'Pengeluaran'} ${row.amount.abs()} pada ${row.date.toIso8601String().substring(0, 10)}',
        )
        .toList();
  }

  Future<FfmAssistantMemoryRecord?> _findTaughtAnswer(String normalized) async {
    final records = await _taughtMemory.readActive(kind: 'answer');
    final matches = records
        .where((record) {
          final trigger = _normalize(record.triggerText);
          return trigger.isNotEmpty &&
              (normalized == trigger || normalized.contains(trigger));
        })
        .toList(growable: false);
    if (matches.length == 1) return matches.single;
    return _taughtMemory.findFuzzyAnswer(normalized);
  }

  FfmAssistantIntent? _parseThemeChangeRequest(
    String rawText,
    String normalized,
  ) {
    final clean = normalized.toLowerCase().trim();

    // 1. Cek query status tema saat ini (misal: "mode apa sekarang?", "lagi mode apa?", "cek mode")
    final isQueryMode = clean.contains('mode apa') ||
        clean.contains('tema apa') ||
        clean.contains('apakah sekarang mode') ||
        clean.contains('apakah ini mode') ||
        clean.contains('apakah mode gelap') ||
        clean.contains('apakah mode terang') ||
        clean.contains('sedang mode apa') ||
        clean.contains('lagi mode apa') ||
        clean.contains('status tema') ||
        clean.contains('status mode') ||
        clean.contains('cek tema') ||
        clean.contains('cek mode');

    if (isQueryMode) {
      final isDark = _themeController?.isDark ?? false;
      final modeLabel = isDark ? 'Mode Gelap 🌙' : 'Mode Terang ☀️';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.queryData,
        confidence: 1.0,
        response: 'Saat ini aplikasi FFM sedang aktif dalam **$modeLabel**.',
      );
    }

    // 2. Variasi Dark Mode: redup, gelap, hitam, malam, dark, black, matiin lampu
    final darkPatterns = [
      'gelap',
      'dark',
      'hitam',
      'redup',
      'malam',
      'black',
      'matiin lampu',
      'matikan lampu',
      'padamkan lampu',
    ];
    final hasDark = darkPatterns.any(clean.contains);

    // 3. Variasi Light Mode: terang, light, putih, siang, white, nyalain lampu
    final lightPatterns = [
      'terang',
      'light',
      'putih',
      'siang',
      'white',
      'nyalain lampu',
      'nyalakan lampu',
      'hidupkan lampu',
    ];
    final hasLight = lightPatterns.any(clean.contains);

    // 4. Variasi Sistem: sistem, default, hp, bawaan
    final systemPatterns = ['sistem', 'default', 'bawaan hp', 'sesuai sistem'];
    final hasSystem = systemPatterns.any(clean.contains);

    // Kata-kata tema & aksi
    final isThemeWord = clean.contains('tema') ||
        clean.contains('theme') ||
        clean.contains('mode') ||
        clean.contains('tampilan') ||
        clean.contains('layar') ||
        clean.contains('warna');

    final isActionWord = clean.contains('ubah') ||
        clean.contains('ganti') ||
        clean.contains('tukar') ||
        clean.contains('pindah') ||
        clean.contains('aktifkan') ||
        clean.contains('hidupkan') ||
        clean.contains('gantiin') ||
        clean.contains('bikin') ||
        clean.contains('jadikan') ||
        clean.contains('buat') ||
        clean.contains('setel') ||
        clean.contains('atur');

    final isDirectThemeCommand = clean.endsWith('kan') ||
        clean.endsWith('in') ||
        clean.startsWith('gelap') ||
        clean.startsWith('terang') ||
        clean.startsWith('hitam') ||
        clean.startsWith('redup') ||
        clean.startsWith('putih');

    // Perintah toggle umum tanpa menyebut gelap/terang: "ubah mode", "ganti tema", "ganti warna", "tema ganti"
    final isGenericToggle = (isThemeWord &&
            (isActionWord ||
                clean.startsWith('tema ganti') ||
                clean.startsWith('mode ganti') ||
                clean.startsWith('warna ganti'))) &&
        !hasDark &&
        !hasLight &&
        !hasSystem;

    if (!hasDark && !hasLight && !hasSystem && !isGenericToggle) {
      return null;
    }

    if (!isGenericToggle &&
        !isThemeWord &&
        !isActionWord &&
        !isDirectThemeCommand) {
      if (clean.length > 25) return null;
    }

    String themeTarget;
    String responseText;

    if (hasDark) {
      themeTarget = 'dark';
      responseText = 'Siap! Tampilan aplikasi sudah diubah ke mode gelap 🌙';
    } else if (hasLight) {
      themeTarget = 'light';
      responseText = 'Siap! Tampilan aplikasi sudah diubah ke mode terang ☀️';
    } else if (hasSystem) {
      themeTarget = 'system';
      responseText =
          'Baik, tema aplikasi sekarang mengikuti pengaturan sistem perangkat Anda 📱';
    } else if (isGenericToggle) {
      final currentIsDark = _themeController?.isDark ?? false;
      if (currentIsDark) {
        themeTarget = 'light';
        responseText = 'Siap! Tampilan aplikasi sudah diubah ke mode terang ☀️';
      } else {
        themeTarget = 'dark';
        responseText = 'Siap! Tampilan aplikasi sudah diubah ke mode gelap 🌙';
      }
    } else {
      return null;
    }

    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.changeTheme,
      confidence: 1.0,
      response: responseText,
      pluginMetadata: {'theme': themeTarget},
    );
  }

  Future<FfmAssistantIntent> _setupGuide(
    String rawText,
    String normalized,
  ) async {
    final household = await (_database.select(
      _database.households,
    )..where((row) => row.id.equals(AppContext.householdId))).getSingleOrNull();
    final accounts = await _activeAccounts();
    final categories = await _activeCategories();
    final hasNamedHousehold =
        household != null &&
        household.name.trim().isNotEmpty &&
        household.name.trim().toLowerCase() != 'keluarga';
    final expenseCategories = categories
        .where((item) => item.type == 'expense')
        .length;
    final incomeCategories = categories
        .where((item) => item.type == 'income')
        .length;
    final steps = <String>[];
    if (!hasNamedHousehold) {
      steps.add(
        '1. Isi nama keluarga di Data Utama. Nama suami/istri boleh kamu isi kalau memang perlu.',
      );
    }
    if (accounts.isEmpty) {
      steps.add(
        '${steps.length + 1}. Tambah rekening yang dipakai, misalnya Tunai atau rekening bank. Isi saldo awal sesuai uang yang benar-benar ada sekarang.',
      );
    }
    if (expenseCategories == 0 || incomeCategories == 0) {
      steps.add(
        '${steps.length + 1}. Lengkapi kategori pemasukan dan pengeluaran agar riwayat lebih gampang dibaca.',
      );
    }
    steps.add(
      '${steps.length + 1}. Catat transaksi pertama. Pilih rekening bila uangnya memang perlu mengubah saldo; kalau sumber dana belum tahu, biarkan sebagai “Belum terlacak”.',
    );
    steps.add(
      '${steps.length + 1}. Setelah ada catatan, atur Anggaran mingguan/bulanan kalau kamu mau memantau batas belanja.',
    );
    final condition = accounts.isEmpty
        ? 'Saat ini belum ada rekening aktif.'
        : 'Saat ini ada ${accounts.length} rekening aktif.';
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.setupGuide,
      confidence: 1,
      response:
          '$condition Kategori aktif: $expenseCategories pengeluaran dan $incomeCategories pemasukan. Kita mulai dari yang paling kepake ya:\n${steps.join('\n')}',
    );
  }

  FfmAssistantIntent? _featureHelp(
    String rawText,
    String normalized, {
    FfmAssistantDestination? currentDestination,
  }) {
    final isQuestion = _containsAny(normalized, const [
      'fungsi',
      'buat apa',
      'apa itu',
      'apa saja',
      'ada apa',
      'isinya',
      'isi ',
      'fitur ',
      'menu ',
      'cara ',
      'gimana ',
      'bagaimana ',
      'jelaskan',
    ]);
    if (!isQuestion) return null;
    if (_containsAny(normalized, const [
      'fungsi tag',
      'tag buat apa',
      'apa itu tag',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.featureHelp,
        destination: FfmAssistantDestination.masterData,
        confidence: 1,
        response: 'Tag itu penanda tambahan transaksi, bukan kategori dan tidak mengubah saldo. Contohnya “belanja pasar”, “panen cabai”, atau “keperluan anak”. Tag berguna buat cari dan menyaring transaksi yang punya tema sama. Tambah atau rapikan tag di Data Utama. Ketuk **Buka** di bawah untuk langsung ke Data Utama.',
      );
    }
    if (_containsAny(normalized, const [
      'fungsi lampiran',
      'lampiran buat apa',
      'apa itu lampiran',
      'foto nota buat apa',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.featureHelp,
        confidence: 1,
        response: 'Lampiran dipakai untuk menyimpan bukti, misalnya foto nota atau dokumen transaksi. Lampiran biasa tidak mengubah nominal. Kalau punya hasil dari LLM, kamu bisa impor JSON transaksi lalu cek dan edit isinya sebelum disimpan.',
      );
    }
    if (_containsAny(normalized, const [
      'cara catat belanja',
      'cara input belanja',
      'cara catat pengeluaran',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.featureHelp,
        confidence: 1,
        response: 'Buka Transaksi, pilih Pengeluaran, isi nominal dan kategori, lalu pilih rekening atau Tunai jika belanja itu memang mengurangi saldo. Kalau sumber uangnya belum tahu, pilih “Belum terlacak” supaya saldo rekening tidak berubah. Tambahkan catatan atau lampiran kalau perlu, lalu cek dan simpan.',
      );
    }
    if (_containsAny(normalized, const [
      'transfer dengan admin',
      'cara transfer',
      'biaya admin transfer',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.featureHelp,
        confidence: 1,
        response: 'Untuk transfer, pilih rekening asal dan tujuan. Nominal transfer hanya memindahkan saldo, jadi tidak dihitung sebagai pemasukan atau pengeluaran. Kalau ada biaya admin, isi nominal adminnya; FFM akan mencatat biaya itu sebagai pengeluaran terpisah dari rekening asal.',
      );
    }
    if (_containsAny(normalized, const [
      'anggaran tidak rutin',
      'budget tidak rutin',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.featureHelp,
        confidence: 1,
        response: 'Anggaran Tidak Rutin cocok untuk kebutuhan yang tidak dibeli tiap bulan, misalnya sandal atau perbaikan rumah. Batasnya tidak direset otomatis seperti anggaran bulanan. Pengeluaran baru akan mengisi rincian aktual dari transaksi yang memang sudah kamu simpan.',
      );
    }
    if (_containsAny(normalized, const [
      'cara impor json',
      'cara pakai json',
      'kolom json',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.featureHelp,
        confidence: 1,
        response: 'JSON dipakai untuk menyiapkan banyak data sekaligus sebagai draft. Untuk transaksi, tiap baris biasanya berisi tipe, tanggal, nominal, kategori, rekening, catatan, dan bila perlu rincian item. Untuk transfer tambahkan rekening asal, tujuan, serta biaya admin bila ada. Tempel JSON di Transaksi, cek preview dan revisi, lalu konfirmasi. Tidak ada data yang masuk otomatis.',
      );
    }
    final page = FfmAssistantCatalog.findByText(normalized);
    final asksAboutCurrentPage = _containsAny(normalized, const [
      'halaman ini',
      'menu ini',
      'fitur di sini',
      'fitur halaman ini',
      'yang ada di sini',
      'isi halaman ini',
      'menu yang ini',
    ]);
    final asksAboutPage = page != null || asksAboutCurrentPage;
    final destination =
        page?.destination ?? (asksAboutCurrentPage ? currentDestination : null);
    if (destination != null && asksAboutPage) {
      final targetPage =
          page ?? FfmAssistantCatalog.findByDestination(destination);
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.featureHelp,
        destination: destination,
        confidence: 1,
        response:
            '${targetPage?.name ?? 'Halaman ini'}: ${FfmAssistantCatalog.detailFor(destination)}',
      );
    }
    return null;
  }

  FfmAssistantIntent _jsonTemplateHelp(String rawText, String normalized) {
    final type = _containsAny(normalized, const ['mutasi', 'rekening'])
        ? 'mutasi rekening'
        : _containsAny(normalized, const ['cadangan', 'backup'])
        ? 'cadangan data'
        : _containsAny(normalized, const ['laporan', 'pdf', 'html'])
        ? 'laporan'
        : null;
    if (type == null) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.createJsonTemplate,
        confidence: .9,
        response: 'Kamu mau JSON untuk apa dulu: impor transaksi, mutasi rekening, cadangan data, atau bahan laporan? Sebut salah satunya, nanti aku arahkan ke template dan jelaskan kolomnya.',
      );
    }
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.createJsonTemplate,
      destination: FfmAssistantDestination.backup,
      confidence: .9,
      response:
          'Aku buka Ekspor & cadangan untuk template $type. Salin templatenya, isi atau perbaiki di LLM di luar aplikasi, lalu tempel balik untuk preview. Hasil impor tetap draft sampai kamu konfirmasi.',
    );
  }

  Future<FfmAssistantIntent> _transactionStats(
    String rawText,
    String normalized,
  ) async {
    final now = DateTime.now();
    final period = _transactionPeriod(now, normalized);
    final start = period.$1;
    final end = period.$2;
    final label = period.$3;
    final transactions =
        await (_database.select(_database.transactions)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isDeleted.equals(false) &
                  row.date.isBiggerOrEqualValue(start) &
                  row.date.isSmallerThanValue(end),
            ))
            .get();
    final transfers =
        await (_database.select(_database.transfers)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isDeleted.equals(false) &
                  row.date.isBiggerOrEqualValue(start) &
                  row.date.isSmallerThanValue(end),
            ))
            .get();
    final income = transactions.where((item) => item.type == 'income').length;
    final expense = transactions.where((item) => item.type == 'expense').length;
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.transactionStats,
      confidence: 1,
      response:
          '$label kamu punya ${transactions.length + transfers.length} catatan: $income pemasukan, $expense pengeluaran, dan ${transfers.length} transfer. Transfer tetap tidak dihitung sebagai arus kas, ya.',
    );
  }

  Future<FfmAssistantIntent> _weeklyAnalysis(
    String rawText,
    String normalized,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
    final isLastWeek = _containsAny(normalized, const [
      'minggu lalu',
      'minggu kemarin',
    ]);
    final start = isLastWeek
        ? thisWeekStart.subtract(const Duration(days: 7))
        : thisWeekStart;
    final end = start.add(const Duration(days: 7));
    final label = isLastWeek ? 'Minggu lalu' : 'Minggu ini';
    final transactions =
        await (_database.select(_database.transactions)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isDeleted.equals(false) &
                  row.date.isBiggerOrEqualValue(start) &
                  row.date.isSmallerThanValue(end),
            ))
            .get();
    final transfers =
        await (_database.select(_database.transfers)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isDeleted.equals(false) &
                  row.date.isBiggerOrEqualValue(start) &
                  row.date.isSmallerThanValue(end),
            ))
            .get();
    if (transactions.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.weeklyAnalysis,
        destination: FfmAssistantDestination.analysis,
        confidence: 1,
        response:
            '$label belum punya transaksi yang tersimpan, jadi aku belum bisa bikin analisa. Kalau ada belanja atau pemasukan yang belum dicatat, masukkan dulu sebagai draft lalu cek sebelum simpan.',
      );
    }
    final categories = await (_database.select(
      _database.categories,
    )..where((row) => row.householdId.equals(AppContext.householdId))).get();
    final categoryNames = {
      for (final category in categories) category.id: category.name,
    };
    final income = transactions
        .where((item) => item.type == 'income')
        .fold<int>(0, (total, item) => total + item.amount.abs());
    final expenseTransactions = transactions
        .where((item) => item.type == 'expense')
        .toList();
    final expense = expenseTransactions.fold<int>(
      0,
      (total, item) => total + item.amount.abs(),
    );
    final byCategory = <String, int>{};
    for (final transaction in expenseTransactions) {
      final name = categoryNames[transaction.categoryId] ?? 'Tanpa kategori';
      byCategory.update(
        name,
        (total) => total + transaction.amount.abs(),
        ifAbsent: () => transaction.amount.abs(),
      );
    }
    final biggest = byCategory.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    final biggestText = biggest.isEmpty
        ? 'Belum ada pengeluaran tercatat.'
        : 'Pengeluaran terbesar: ${biggest.take(3).map((item) => '${item.key} ${_formatRupiah(item.value)}').join(', ')}.';
    final net = income - expense;
    final netText = net > 0
        ? 'arus kas surplus ${_formatRupiah(net)}'
        : net < 0
        ? 'arus kas defisit ${_formatRupiah(net.abs())}'
        : 'arus kas seimbang';
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.weeklyAnalysis,
      destination: FfmAssistantDestination.analysis,
      confidence: 1,
      response:
          '$label, dari ${transactions.length} transaksi yang tersimpan: pemasukan ${_formatRupiah(income)}, pengeluaran ${_formatRupiah(expense)}, jadi $netText. $biggestText Ada ${transfers.length} transfer; transfer tidak masuk hitungan arus kas.',
    );
  }

  (DateTime, DateTime, String) _transactionPeriod(
    DateTime now,
    String normalized,
  ) {
    if (_containsAny(normalized, const ['hari ini', 'hari sekarang'])) {
      final start = DateTime(now.year, now.month, now.day);
      return (start, start.add(const Duration(days: 1)), 'Hari ini');
    }
    if (_containsAny(normalized, const ['minggu ini', 'minggu sekarang'])) {
      final start = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - DateTime.monday));
      return (start, start.add(const Duration(days: 7)), 'Minggu ini');
    }
    final start = DateTime(now.year, now.month);
    return (start, DateTime(now.year, now.month + 1), 'Bulan ini');
  }

  Future<FfmAssistantIntent> _financialWarnings(
    String rawText,
    String normalized,
  ) async {
    final service = BudgetGuardService(_database);
    final suggestions = await service.check(AppContext.householdId);
    final isBudgetQuestion = _containsAny(normalized, const [
      'anggaran',
      'budget',
      'batas belanja',
    ]);
    final visibleSuggestions = isBudgetQuestion
        ? suggestions
              .where(
                (item) =>
                    item.kind == FinancialGuardKind.budgetExceeded ||
                    item.kind == FinancialGuardKind.budgetNearLimit ||
                    item.kind == FinancialGuardKind.budgetFastUse,
              )
              .toList(growable: false)
        : suggestions;
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.financialWarnings,
      destination: isBudgetQuestion
          ? FfmAssistantDestination.budget
          : FfmAssistantDestination.summary,
      confidence: 1,
      response: service.responseForAssistant(
        visibleSuggestions,
        emptyMessage: isBudgetQuestion
            ? 'Belum ada anggaran aktif yang melewati batas, mendekati batas, atau memakai dana lebih cepat dari periode resminya.'
            : null,
      ),
    );
  }

  Future<FfmAssistantIntent> _currentPageContext(
    String rawText,
    String normalized,
    FfmAssistantDestination destination,
  ) async {
    final page = FfmAssistantCatalog.findByDestination(destination);
    final pageName = page?.name ?? 'halaman ini';
    if (_isCurrentPageLabelRequest(normalized)) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        destination: destination,
        confidence: 1,
        response:
            'Sekarang kamu ada di halaman $pageName. ${page?.description ?? 'Kamu bisa bertanya fungsi halaman ini atau data yang ingin dicek.'}',
      );
    }
    if (destination == FfmAssistantDestination.summary ||
        destination == FfmAssistantDestination.transactions) {
      final stats = await _transactionStats(rawText, normalized);
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.transactionStats,
        destination: destination,
        confidence: 1,
        response: 'Kamu lagi di $pageName. ${stats.response}',
      );
    }
    if (destination == FfmAssistantDestination.budget) {
      final warnings = await _financialWarnings(rawText, normalized);
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.financialWarnings,
        destination: destination,
        confidence: 1,
        response: 'Kamu lagi di Anggaran. ${warnings.response}',
      );
    }
    if (destination == FfmAssistantDestination.activity) {
      final activeSessions =
          await (_database.select(_database.activitySessions)..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isArchived.equals(false) &
                    row.status.equals('active'),
              ))
              .get();
      final count = activeSessions.length;
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        destination: destination,
        confidence: 1,
        response: count == 0
            ? 'Kamu lagi di Aktivitas. Belum ada aktivitas yang sedang jalan. Kamu bisa mulai dari tombol Tambah atau bilang “mulai perjalanan”.'
            : 'Kamu lagi di Aktivitas. Ada $count aktivitas yang masih jalan: ${activeSessions.map((item) => item.title).join(', ')}.',
      );
    }
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.help,
      destination: destination,
      confidence: 1,
      response:
          'Kamu lagi di $pageName. ${page?.description ?? 'Kamu bisa bilang data apa yang mau dicek.'}',
    );
  }

  bool _isOtherMenuListRequest(String text) =>
      (text.contains('menu lainnya') || text.contains('bagian lainnya')) &&
      _containsAny(text, const [
        'apa saja',
        'daftar',
        'isi',
        'fitur',
        'menu',
        'tampilkan',
        'fungsi',
        'ada apa',
      ]);

  bool _isNavigationRequest(String text) => _containsAny(text, const [
    'buka halaman',
    'buka menu',
    'pindah ke halaman',
    'pindah ke menu',
    'pindah ke',
    'ke halaman',
    'ke bagian',
    'pergi ke halaman',
    'pergi ke menu',
    'pergi ke',
    'arah ke halaman',
    'arah ke menu',
    'arahkan ke',
    'bawa ke halaman',
    'bawa ke menu',
    'bawa ke',
    'masuk halaman',
    'masuk menu',
    'masuk ke',
    'tampilkan halaman',
    'tampilkan menu',
    'lihat halaman',
    'cek halaman',
    'goto',
    'go to',
    'navigate',
  ]);

  bool _isExplicitPageNavigationRequest(String text) =>
      text.startsWith('buka') || text.startsWith('tampilkan');

  bool _isCurrentPageRequest(String text) =>
      _isCurrentPageLabelRequest(text) ||
      _containsAny(text, const [
        'halaman ini',
        'di sini ada apa',
        'di sini ada data apa',
        'kondisi halaman ini',
        'baca halaman ini',
      ]);

  bool _isCurrentPageLabelRequest(String text) => _containsAny(text, const [
    'saya sedang di halaman apa',
    'sedang di halaman apa',
    'sekarang di halaman apa',
    'lagi di halaman apa',
    'saya ada di halaman apa',
    'saya lagi di halaman apa',
    'halaman sekarang apa',
    'ini halaman apa',
    'nama halaman ini',
  ]);

  bool _hasExplicitIntent(String text) {
    final normalized = text.toLowerCase();
    // Deteksi kata kerja aksi eksplisit
    final hasActionVerb = RegExp(
      r'\b(buat|tambah|catat|beli|bayar|transfer|pindahkan|ingatkan|simpan|hapus|ubah|update)\b',
      caseSensitive: false,
    ).hasMatch(normalized);

    if (!hasActionVerb) return false;

    // Deteksi kata kunci domain spesifik untuk memastikan ini bukan request generik
    final hasDomainKeyword = RegExp(
      r'\b(kategori|rekening|toko|sumber|anggaran|target|tujuan|goal|transaksi|pemasukan|pengeluaran|belanja|transfer|aktivitas|pengingat|aset|hutang|piutang)\b',
      caseSensitive: false,
    ).hasMatch(normalized);

    return hasDomainKeyword;
  }

  bool _isDatabaseStructureRequest(String text) {
    final namesDatabase = RegExp(
      r'\b(database|basis data|struktur database|struktur data|tabel)\b',
    ).hasMatch(text);
    final asksAppData =
        text.contains('ada data apa saja') &&
        (text.contains('aplikasi') || text.contains('ffm'));
    // Don't treat navigation requests as database structure queries
    if (_isExplicitPageNavigationRequest(text)) return false;
    return namesDatabase || asksAppData;
  }

  /// Melengkapi draft transaksi yang belum punya kategori dengan saran
  /// berlapis: pola historis pengguna (Agent) → tebakan SLM dari daftar
  /// kategori resmi. Draft tanpa saran dikembalikan apa adanya.
  Future<FfmAssistantDraft> _enrichWithCategorySuggestion(
    String rawText,
    FfmAssistantDraft draft,
  ) async {
    final suggestionService = _categorySuggestion;
    if (suggestionService == null) return draft;
    if (draft.categoryName != null) return draft;
    try {
      final suggestion = await suggestionService.suggestForDraft(
        kind: draft.kind,
        queryText: draft.note ?? rawText,
        merchantName: draft.merchantName,
      );
      if (suggestion == null) return draft;
      return draft.copyWith(
        categoryName: suggestion.categoryName,
        slmFieldValues: {
          ...draft.slmFieldValues,
          'category': suggestion.categoryName,
          'categorySource': suggestion.sourceLabel,
        },
      );
    } on Object {
      return draft;
    }
  }

  FfmAssistantIntent _intentForDraft(
    String rawText,
    String normalized,
    FfmAssistantDraft draft,
  ) {
    final config = switch (draft.kind) {
      FfmAssistantDraftKind.transfer => (
        type: FfmAssistantIntentType.createTransfer,
        destination: FfmAssistantDestination.transactions,
        action: 'transfer',
      ),
      FfmAssistantDraftKind.income => (
        type: FfmAssistantIntentType.createIncome,
        destination: FfmAssistantDestination.transactions,
        action: 'pemasukan',
      ),
      FfmAssistantDraftKind.expense => (
        type: FfmAssistantIntentType.createExpense,
        destination: FfmAssistantDestination.transactions,
        action: 'pengeluaran',
      ),
      FfmAssistantDraftKind.goalDeposit => (
        type: FfmAssistantIntentType.createGoalDeposit,
        destination: FfmAssistantDestination.transactions,
        action: 'setoran target',
      ),
      FfmAssistantDraftKind.goalUsage => (
        type: FfmAssistantIntentType.createGoalUsage,
        destination: FfmAssistantDestination.transactions,
        action: 'pemakaian dana target',
      ),
      FfmAssistantDraftKind.liability => (
        type: FfmAssistantIntentType.createLiability,
        destination: FfmAssistantDestination.liabilities,
        action: 'hutang',
      ),
      FfmAssistantDraftKind.liabilityPayment => (
        type: FfmAssistantIntentType.createLiabilityPayment,
        destination: FfmAssistantDestination.liabilities,
        action: 'pembayaran hutang',
      ),
      FfmAssistantDraftKind.liabilityUpdate => (
        type: FfmAssistantIntentType.updateLiability,
        destination: FfmAssistantDestination.liabilities,
        action: 'ubah hutang',
      ),
      FfmAssistantDraftKind.liabilityArchive => (
        type: FfmAssistantIntentType.archiveLiability,
        destination: FfmAssistantDestination.liabilities,
        action: 'arsip hutang',
      ),
      FfmAssistantDraftKind.receivable => (
        type: FfmAssistantIntentType.createReceivable,
        destination: FfmAssistantDestination.liabilities,
        action: 'piutang',
      ),
      FfmAssistantDraftKind.receivablePayment => (
        type: FfmAssistantIntentType.createReceivablePayment,
        destination: FfmAssistantDestination.liabilities,
        action: 'penerimaan piutang',
      ),
      FfmAssistantDraftKind.receivableUpdate => (
        type: FfmAssistantIntentType.updateReceivable,
        destination: FfmAssistantDestination.liabilities,
        action: 'ubah piutang',
      ),
      FfmAssistantDraftKind.receivableArchive => (
        type: FfmAssistantIntentType.archiveReceivable,
        destination: FfmAssistantDestination.liabilities,
        action: 'arsip piutang',
      ),
      FfmAssistantDraftKind.recurringTransactionUpdate => (
        type: FfmAssistantIntentType.updateRecurringTransaction,
        destination: FfmAssistantDestination.recurringTransaction,
        action: 'ubah Transaksi Berkala',
      ),
      FfmAssistantDraftKind.recurringTransactionArchive => (
        type: FfmAssistantIntentType.archiveRecurringTransaction,
        destination: FfmAssistantDestination.recurringTransaction,
        action: 'nonaktifkan Transaksi Berkala',
      ),
      FfmAssistantDraftKind.goal => (
        type: FfmAssistantIntentType.createGoal,
        destination: FfmAssistantDestination.goals,
        action: 'target keuangan',
      ),
      FfmAssistantDraftKind.asset => (
        type: FfmAssistantIntentType.createAsset,
        destination: FfmAssistantDestination.assets,
        action: 'aset',
      ),
      FfmAssistantDraftKind.assetUpdate => (
        type: FfmAssistantIntentType.updateAsset,
        destination: FfmAssistantDestination.assets,
        action: 'ubah aset',
      ),
      FfmAssistantDraftKind.assetArchive => (
        type: FfmAssistantIntentType.archiveAsset,
        destination: FfmAssistantDestination.assets,
        action: 'arsip aset',
      ),
      FfmAssistantDraftKind.budget => (
        type: FfmAssistantIntentType.createBudget,
        destination: FfmAssistantDestination.budget,
        action: 'anggaran',
      ),
      FfmAssistantDraftKind.budgetUpdate => (
        type: FfmAssistantIntentType.updateBudget,
        destination: FfmAssistantDestination.budget,
        action: 'ubah batas Anggaran',
      ),
      FfmAssistantDraftKind.budgetArchive => (
        type: FfmAssistantIntentType.archiveBudget,
        destination: FfmAssistantDestination.budget,
        action: 'arsip Anggaran',
      ),
      FfmAssistantDraftKind.masterData => (
        type: FfmAssistantIntentType.createMasterData,
        destination: FfmAssistantDestination.masterData,
        action: 'Data Utama',
      ),
      FfmAssistantDraftKind.merchantUpdate => (
        type: FfmAssistantIntentType.updateMerchant,
        destination: FfmAssistantDestination.masterData,
        action: 'ubah Toko/Tempat',
      ),
      FfmAssistantDraftKind.merchantArchive => (
        type: FfmAssistantIntentType.archiveMerchant,
        destination: FfmAssistantDestination.masterData,
        action: 'arsip Toko/Tempat',
      ),
      FfmAssistantDraftKind.merchantDelete => (
        type: FfmAssistantIntentType.deleteMerchant,
        destination: FfmAssistantDestination.masterData,
        action: 'hapus Toko/Tempat',
      ),
      FfmAssistantDraftKind.tagUpdate => (
        type: FfmAssistantIntentType.updateTag,
        destination: FfmAssistantDestination.masterData,
        action: 'ubah Tag',
      ),
      FfmAssistantDraftKind.tagArchive => (
        type: FfmAssistantIntentType.archiveTag,
        destination: FfmAssistantDestination.masterData,
        action: 'arsip Tag',
      ),
      FfmAssistantDraftKind.tagDelete => (
        type: FfmAssistantIntentType.deleteTag,
        destination: FfmAssistantDestination.masterData,
        action: 'hapus Tag',
      ),
      FfmAssistantDraftKind.incomeSourceUpdate => (
        type: FfmAssistantIntentType.updateIncomeSource,
        destination: FfmAssistantDestination.masterData,
        action: 'ubah Sumber Pemasukan',
      ),
      FfmAssistantDraftKind.incomeSourceArchive => (
        type: FfmAssistantIntentType.archiveIncomeSource,
        destination: FfmAssistantDestination.masterData,
        action: 'arsip Sumber Pemasukan',
      ),
      FfmAssistantDraftKind.incomeSourceDelete => (
        type: FfmAssistantIntentType.deleteIncomeSource,
        destination: FfmAssistantDestination.masterData,
        action: 'hapus Sumber Pemasukan',
      ),
      FfmAssistantDraftKind.categoryUpdate => (
        type: FfmAssistantIntentType.updateCategory,
        destination: FfmAssistantDestination.masterData,
        action: 'ubah nama Kategori',
      ),
      FfmAssistantDraftKind.categoryArchive => (
        type: FfmAssistantIntentType.archiveCategory,
        destination: FfmAssistantDestination.masterData,
        action: 'arsip Kategori',
      ),
      FfmAssistantDraftKind.categoryDelete => (
        type: FfmAssistantIntentType.deleteCategory,
        destination: FfmAssistantDestination.masterData,
        action: 'hapus Kategori',
      ),
      FfmAssistantDraftKind.accountUpdate => (
        type: FfmAssistantIntentType.updateAccount,
        destination: FfmAssistantDestination.masterData,
        action: 'ubah nama Rekening',
      ),
      FfmAssistantDraftKind.accountArchive => (
        type: FfmAssistantIntentType.archiveAccount,
        destination: FfmAssistantDestination.masterData,
        action: 'arsip Rekening',
      ),
      FfmAssistantDraftKind.accountDelete => (
        type: FfmAssistantIntentType.deleteAccount,
        destination: FfmAssistantDestination.masterData,
        action: 'hapus Rekening',
      ),
      FfmAssistantDraftKind.reminder => (
        type: FfmAssistantIntentType.createReminder,
        destination: FfmAssistantDestination.reminders,
        action: 'pengingat',
      ),
      FfmAssistantDraftKind.reminderUpdate => (
        type: FfmAssistantIntentType.updateReminder,
        destination: FfmAssistantDestination.reminders,
        action: 'ubah pengingat',
      ),
      FfmAssistantDraftKind.activity => (
        type: FfmAssistantIntentType.createActivity,
        destination: FfmAssistantDestination.activity,
        action: 'aktivitas',
      ),
      FfmAssistantDraftKind.dailyNote => (
        type: FfmAssistantIntentType.createDailyNote,
        destination: FfmAssistantDestination.activity,
        action: 'Catatan Harian',
      ),
      FfmAssistantDraftKind.dailyNoteArchive => (
        type: FfmAssistantIntentType.archiveDailyNote,
        destination: FfmAssistantDestination.activity,
        action: 'arsip Catatan Harian',
      ),
      FfmAssistantDraftKind.task => (
        type: FfmAssistantIntentType.createTask,
        destination: FfmAssistantDestination.activity,
        action: 'Tugas',
      ),
      FfmAssistantDraftKind.taskUpdate => (
        type: FfmAssistantIntentType.updateTask,
        destination: FfmAssistantDestination.activity,
        action: 'ubah Tugas',
      ),
      FfmAssistantDraftKind.taskComplete => (
        type: FfmAssistantIntentType.completeTask,
        destination: FfmAssistantDestination.activity,
        action: 'selesaikan Tugas',
      ),
      FfmAssistantDraftKind.taskReopen => (
        type: FfmAssistantIntentType.reopenTask,
        destination: FfmAssistantDestination.activity,
        action: 'buka kembali Tugas',
      ),
      FfmAssistantDraftKind.taskArchive => (
        type: FfmAssistantIntentType.archiveTask,
        destination: FfmAssistantDestination.activity,
        action: 'arsip Tugas',
      ),
      FfmAssistantDraftKind.routine => (
        type: FfmAssistantIntentType.createRoutine,
        destination: FfmAssistantDestination.activity,
        action: 'Rutinitas',
      ),
      FfmAssistantDraftKind.routineUpdate => (
        type: FfmAssistantIntentType.updateRoutine,
        destination: FfmAssistantDestination.activity,
        action: 'ubah Rutinitas',
      ),
      FfmAssistantDraftKind.routineMarkComplete => (
        type: FfmAssistantIntentType.markRoutineComplete,
        destination: FfmAssistantDestination.activity,
        action: 'tandai Rutinitas hari ini',
      ),
      FfmAssistantDraftKind.routineUnmarkComplete => (
        type: FfmAssistantIntentType.unmarkRoutineComplete,
        destination: FfmAssistantDestination.activity,
        action: 'batalkan tanda Rutinitas hari ini',
      ),
      FfmAssistantDraftKind.routineActivate => (
        type: FfmAssistantIntentType.activateRoutine,
        destination: FfmAssistantDestination.activity,
        action: 'aktifkan Rutinitas',
      ),
      FfmAssistantDraftKind.routineDeactivate => (
        type: FfmAssistantIntentType.deactivateRoutine,
        destination: FfmAssistantDestination.activity,
        action: 'nonaktifkan Rutinitas',
      ),
      FfmAssistantDraftKind.routineArchive => (
        type: FfmAssistantIntentType.archiveRoutine,
        destination: FfmAssistantDestination.activity,
        action: 'arsip Rutinitas',
      ),
      FfmAssistantDraftKind.schedule => (
        type: FfmAssistantIntentType.createSchedule,
        destination: FfmAssistantDestination.activity,
        action: 'Jadwal',
      ),
      FfmAssistantDraftKind.scheduleUpdate => (
        type: FfmAssistantIntentType.updateSchedule,
        destination: FfmAssistantDestination.activity,
        action: 'ubah Jadwal',
      ),
      FfmAssistantDraftKind.scheduleArchive => (
        type: FfmAssistantIntentType.archiveSchedule,
        destination: FfmAssistantDestination.activity,
        action: 'arsip Jadwal',
      ),
      FfmAssistantDraftKind.profile => (
        type: FfmAssistantIntentType.createProfile,
        destination: FfmAssistantDestination.assistantProfile,
        action: 'profil',
      ),
      FfmAssistantDraftKind.reminderArchive => (
        type: FfmAssistantIntentType.archiveReminder,
        destination: FfmAssistantDestination.reminders,
        action: 'arsip pengingat',
      ),
      FfmAssistantDraftKind.goalUpdate => (
        type: FfmAssistantIntentType.updateGoal,
        destination: FfmAssistantDestination.goals,
        action: 'perubahan target keuangan',
      ),
      FfmAssistantDraftKind.goalArchive => (
        type: FfmAssistantIntentType.archiveGoal,
        destination: FfmAssistantDestination.goals,
        action: 'arsip target keuangan',
      ),
      FfmAssistantDraftKind.transactionUpdate => (
        type: FfmAssistantIntentType.updateTransaction,
        destination: FfmAssistantDestination.transactions,
        action: 'perubahan transaksi',
      ),
      FfmAssistantDraftKind.transactionArchive => (
        type: FfmAssistantIntentType.archiveTransaction,
        destination: FfmAssistantDestination.transactions,
        action: 'arsip transaksi',
      ),
      FfmAssistantDraftKind.transactionDelete => (
        type: FfmAssistantIntentType.deleteTransaction,
        destination: FfmAssistantDestination.transactions,
        action: 'hapus transaksi',
      ),
      FfmAssistantDraftKind.activityArchive => (
        type: FfmAssistantIntentType.archiveActivity,
        destination: FfmAssistantDestination.activity,
        action: 'arsip aktivitas',
      ),
      FfmAssistantDraftKind.activityDelete => (
        type: FfmAssistantIntentType.deleteActivity,
        destination: FfmAssistantDestination.activity,
        action: 'hapus aktivitas',
      ),
      FfmAssistantDraftKind.activityFinish => (
        type: FfmAssistantIntentType.finishActivity,
        destination: FfmAssistantDestination.activity,
        action: 'selesai aktivitas',
      ),
      FfmAssistantDraftKind.activityUpdate => (
        type: FfmAssistantIntentType.updateActivity,
        destination: FfmAssistantDestination.activity,
        action: 'update aktivitas',
      ),
      FfmAssistantDraftKind.activityEdit => (
        type: FfmAssistantIntentType.editActivity,
        destination: FfmAssistantDestination.activity,
        action: 'edit aktivitas',
      ),
    };
    if (draft.kind == FfmAssistantDraftKind.masterData) {
      final target = _masterDataTargetName(draft.categoryName);
      final name = draft.title?.trim();
      final nameDetail = name == null || name.isEmpty
          ? ''
          : ' dengan nama sementara “$name”';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.createMasterData,
        destination: FfmAssistantDestination.masterData,
        draft: draft,
        review: FfmAssistantDraftReview(
          draft: draft,
          version: 1,
          issues: const [],
        ),
        confidence: .9,
        response:
            'Aku akan membuka form $target di Data Utama$nameDetail. Belum ada data yang disimpan. Kamu bisa cek dan lengkapi kolom yang belum ada, lalu tekan Simpan sendiri di form.',
      );
    }
    final missing = <String>[];
    const amountKinds = {
      FfmAssistantDraftKind.income,
      FfmAssistantDraftKind.expense,
      FfmAssistantDraftKind.transfer,
      FfmAssistantDraftKind.goalDeposit,
      FfmAssistantDraftKind.goalUsage,
      FfmAssistantDraftKind.goal,
      FfmAssistantDraftKind.goalUpdate,
      FfmAssistantDraftKind.liability,
      FfmAssistantDraftKind.receivable,
      FfmAssistantDraftKind.asset,
      FfmAssistantDraftKind.budget,
    };
    if (amountKinds.contains(draft.kind) && !draft.hasAmount) {
      missing.add('nominal');
    }
    if (draft.kind == FfmAssistantDraftKind.transfer) {
      if (draft.fromAccountName == null) missing.add('rekening asal');
      if (draft.toAccountName == null) missing.add('rekening tujuan');
    }
    if (draft.kind == FfmAssistantDraftKind.expense) {
      if (draft.fromAccountName == null) missing.add('rekening sumber');
      if (draft.categoryName == null) missing.add('kategori');
    }
    if (draft.kind == FfmAssistantDraftKind.income) {
      if (draft.toAccountName == null) missing.add('rekening tujuan');
      if (draft.categoryName == null) missing.add('kategori');
    }
    if ((draft.kind == FfmAssistantDraftKind.liability ||
            draft.kind == FfmAssistantDraftKind.receivable) &&
        (draft.partyName == null || draft.partyName!.isEmpty)) {
      missing.add('nama orangnya');
    }
    if (draft.kind == FfmAssistantDraftKind.profile &&
        draft.formValues.isNotEmpty) {
      for (final field in const ['Nama', 'Pekerjaan', 'Rutinitas', 'Tujuan']) {
        final value = draft.formValues[field];
        if (value == null || value.trim().isEmpty) {
          missing.add(field.toLowerCase());
        }
      }
    }
    final safetyWarning = switch (draft.kind) {
      FfmAssistantDraftKind.transfer => FfmAssistantSanityCheck.transferWarning(
        amount: draft.amount,
        fromAccount: draft.fromAccountName,
        toAccount: draft.toAccountName,
        adminFee: draft.adminFee,
      ),
      FfmAssistantDraftKind.income =>
        FfmAssistantSanityCheck.transactionWarning(
          amount: draft.amount,
          isIncome: true,
        ),
      FfmAssistantDraftKind.expense =>
        FfmAssistantSanityCheck.transactionWarning(
          amount: draft.amount,
          isIncome: false,
        ),
      _ => null,
    };
    String? clarification;
    if (missing.isNotEmpty) {
      final needsMasterData =
          missing.contains('kategori') ||
          missing.contains('rekening sumber') ||
          missing.contains('rekening tujuan') ||
          missing.contains('rekening asal');
      final transferNeedsDestination =
          draft.kind == FfmAssistantDraftKind.transfer &&
          missing.contains('rekening tujuan') &&
          !RegExp(r'\bke\b').hasMatch(normalized);
      if (needsMasterData && !transferNeedsDestination) {
        final missingItems = <String>[];
        if (missing.contains('kategori')) missingItems.add('kategori');
        if (missing.contains('rekening sumber') ||
            missing.contains('rekening tujuan') ||
            missing.contains('rekening asal')) {
          missingItems.add('rekening');
        }
        clarification =
            '${missingItems.map((e) => e[0].toUpperCase() + e.substring(1)).join(' dan ')} belum ada di Data Utama. '
            'Mau buat dulu lewat perintah seperti "buat kategori [nama]" atau "tambah rekening [nama]"? '
            'Atau sebut nama yang sudah ada di Data Utama.';
      } else {
        clarification =
            'Aku sudah menyiapkan draft ${config.action}, tapi masih butuh ${missing.join(', ')}.';
      }
    } else {
      clarification = safetyWarning;
    }
    final categoryHint = draft.categoryName == null
        ? ''
        : ' Kategori ${draft.categoryName} sudah aku pilih dari Data Utama.';
    final review = FfmAssistantDraftReview(
      draft: draft,
      version: 1,
      issues: const [],
    );
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: config.type,
      destination: config.destination,
      draft: draft,
      review: review,
      confidence: missing.isEmpty ? .9 : .55,
      clarification: clarification,
      response: missing.isEmpty
          ? 'Draft ${config.action} sudah siap.$categoryHint Cek dulu, lalu konfirmasi di halaman terkait.'
          : null,
    );
  }

  Map<String, String> _extractProfileValues(String rawText) {
    final values = <String, String>{};
    final patterns = <String, RegExp>{
      'Nama': RegExp(
        r'(?:nama(?: saya|ku)?|panggil(?: saya| aku)?)\s*(?:adalah|:)?\s*([^,;.\n]+)',
        caseSensitive: false,
      ),
      'Pekerjaan': RegExp(
        r'(?:pekerjaan|profesi|kerja sebagai|bekerja sebagai)\s*(?:adalah|:)?\s*([^,;.\n]+)',
        caseSensitive: false,
      ),
      'Rutinitas': RegExp(
        r'(?:rutinitas|kebiasaan)\s*(?:saya|aku|ku)?\s*(?:adalah|:)?\s*([^;.\n]+)',
        caseSensitive: false,
      ),
      'Tujuan': RegExp(
        r'(?:tujuan|prioritas|target)\s*(?:saya|aku|ku)?\s*(?:adalah|:)?\s*([^;.\n]+)',
        caseSensitive: false,
      ),
    };
    for (final entry in patterns.entries) {
      final value = entry.value.firstMatch(rawText)?.group(1)?.trim();
      if (value != null && value.isNotEmpty) values[entry.key] = value;
    }
    return values;
  }

  Future<FfmAssistantIntent?> _parseActivityMutation(
    String rawText,
    String normalized,
  ) async {
    final archive = RegExp(r'^(?:arsip|arsipkan)\s+aktivitas\s+(.+)$')
        .firstMatch(normalized);
    final delete = RegExp(r'^hapus\s+aktivitas\s+(.+)$').firstMatch(normalized);
    final finish = RegExp(r'^(?:selesai(?:kan)?|tutup)\s+aktivitas\s+(.+)$')
        .firstMatch(normalized);
    final update = RegExp(
      r'^(?:update|tambah\s+(?:catatan|checkpoint))\s+aktivitas\s+(.+?)(?:\s*:\s*(.+))?$',
    ).firstMatch(normalized);
    final categoryEdit = RegExp(
      r'^(?:edit|ubah|ganti)\s+kategori\s+aktivitas\s+(.+?)\s+(?:jadi|ke)\s+(.+)$',
    ).firstMatch(normalized);
    final edit = RegExp(
      r'^(?:edit|ubah|ganti)\s+aktivitas\s+(.+?)(?:\s+jadi\s+|\s+ke\s+)(.+)$',
    ).firstMatch(normalized);

    if (archive == null &&
        delete == null &&
        finish == null &&
        update == null &&
        categoryEdit == null &&
        edit == null) {
      return null;
    }
    String operation;
    String targetText;
    String? extraText;
    var isCategoryEdit = false;

    if (finish != null) {
      operation = 'finish';
      targetText = finish.group(1)!.trim();
      extraText = null;
    } else if (update != null) {
      operation = 'update';
      targetText = update.group(1)!.trim();
      extraText = update.group(2)?.trim();
    } else if (categoryEdit != null) {
      operation = 'edit';
      isCategoryEdit = true;
      targetText = categoryEdit.group(1)!.trim();
      extraText = categoryEdit.group(2)?.trim();
    } else if (edit != null) {
      operation = 'edit';
      targetText = edit.group(1)!.trim();
      extraText = edit.group(2)?.trim();
      if (extraText?.startsWith('kategori ') == true) {
        isCategoryEdit = true;
        extraText = extraText!.substring('kategori '.length).trim();
      }
    } else if (archive != null) {
      operation = 'archive';
      targetText = archive.group(1)!.trim();
      extraText = null;
    } else {
      operation = 'delete';
      targetText = delete!.group(1)!.trim();
      extraText = null;
    }
    final candidates = await _findActivityCandidates(
      targetText,
      activeOnly: operation == 'finish' || operation == 'update',
    );
    if (candidates.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: _activityOperationIntentType(operation),
        confidence: .8,
        clarification: _activityOperationClarification(operation, targetText),
      );
    }
    if (candidates.length > 1) {
      final options = candidates
          .take(3)
          .map(_activityCandidateLabel)
          .join('; ');
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: _activityOperationIntentType(operation),
        confidence: .72,
        clarification:
            'Aku menemukan ${candidates.length} aktivitas yang cocok: $options. Sebut judul yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final formValues = <String, String>{
      'entity': 'activity_session',
      'targetId': target.id,
      'operation': operation,
      'targetSummary': _activityCandidateLabel(target),
    };
    if (operation == 'update' && extraText != null) {
      formValues['label'] = extraText;
    }
    if (operation == 'edit' && extraText != null) {
      formValues['beforeTitle'] = target.title;
      formValues['beforeCategory'] = target.category;
      if (isCategoryEdit) {
        formValues['category'] = extraText;
      } else {
        formValues['title'] = extraText;
      }
    }
    final draftKind = switch (operation) {
      'finish' => FfmAssistantDraftKind.activityFinish,
      'update' => FfmAssistantDraftKind.activityUpdate,
      'edit' => FfmAssistantDraftKind.activityEdit,
      'archive' => FfmAssistantDraftKind.activityArchive,
      _ => FfmAssistantDraftKind.activityDelete,
    };
    final draft = FfmAssistantDraft(
      kind: draftKind,
      createdAt: _clock(),
      title: operation == 'edit'
          ? (isCategoryEdit ? target.title : extraText)
          : _activityCandidateLabel(target),
      categoryName: operation == 'edit' && isCategoryEdit ? extraText : null,
      note: target.notes,
      date: target.startedAt,
      formValues: formValues,
    );
    return _intentForDraft(
      rawText,
      normalized,
      draft,
    ).copyWith(response: _activityOperationResponse(operation));
  }

  FfmAssistantIntentType _activityOperationIntentType(String operation) =>
      switch (operation) {
        'finish' => FfmAssistantIntentType.finishActivity,
        'update' => FfmAssistantIntentType.updateActivity,
        'edit' => FfmAssistantIntentType.editActivity,
        'archive' => FfmAssistantIntentType.archiveActivity,
        _ => FfmAssistantIntentType.deleteActivity,
      };

  String _activityOperationClarification(
    String operation,
    String targetText,
  ) => switch (operation) {
    'finish' =>
      'Aku tidak menemukan satu aktivitas aktif yang cocok dengan $targetText. Aktivitas harus dalam status berjalan untuk diselesaikan. Belum ada data yang diubah.',
    'update' =>
      'Aku tidak menemukan satu aktivitas aktif yang cocok dengan $targetText. Aktivitas harus dalam status berjalan untuk ditambahkan checkpoint. Belum ada data yang diubah.',
    'edit' =>
      'Aku tidak menemukan satu aktivitas yang cocok dengan $targetText. Sebut judul yang lebih spesifik. Belum ada data yang diubah.',
    _ =>
      'Aku tidak menemukan satu aktivitas yang cocok dengan $targetText. Aktivitas yang masih berjalan harus diselesaikan dari halaman Aktivitas dulu. Belum ada data yang diubah.',
  };

  String _activityOperationResponse(String operation) => switch (operation) {
    'finish' => 'Aku menemukan satu aktivitas aktif untuk diselesaikan. Cek preview dulu; belum ada data yang diubah.',
    'update' => 'Aku menemukan satu aktivitas aktif untuk ditambahkan checkpoint. Cek preview dulu; belum ada data yang diubah.',
    'edit' => 'Aku menemukan satu aktivitas untuk diedit. Cek preview dulu; belum ada data yang diubah.',
    'archive' => 'Aku menemukan satu aktivitas selesai untuk diarsipkan. Cek preview dulu; belum ada data yang diubah.',
    _ => 'Aku menemukan satu aktivitas selesai untuk dihapus permanen beserta data turunannya. Cek preview dampaknya dulu; belum ada data yang diubah.',
  };
  Future<List<ActivitySession>> _findActivityCandidates(
    String targetText, {
    bool activeOnly = false,
  }) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where(
          (term) =>
              term.length >= 3 &&
              !const {'aktivitas', 'pada', 'tanggal'}.contains(term) &&
              !RegExp(r'^\d+$').hasMatch(term),
        )
        .toSet();
    if (terms.isEmpty) return const [];
    final rows =
        await (_database.select(_database.activitySessions)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isArchived.equals(false) &
                    (activeOnly
                        ? row.status.equals('active')
                        : row.status.isNotValue('active')),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.startedAt)]))
            .get();
    return rows
        .where((row) {
          final haystack = '${row.title} ${row.category} ${row.notes ?? ''}'
              .toLowerCase();
          return terms.every(haystack.contains);
        })
        .take(4)
        .toList(growable: false);
  }

  String _activityCandidateLabel(ActivitySession row) {
    final date = row.startedAt.toIso8601String().substring(0, 10);
    return '${row.title} • ${row.category} • $date';
  }

  Future<FfmAssistantIntent?> _parseDailyNoteMutation(
    String rawText,
    String normalized,
  ) async {
    final archive = RegExp(
      r'^(?:arsip|arsipkan)\s+(?:catatan harian|catatan)\s+(.+)$',
    ).firstMatch(normalized);
    if (archive == null) return null;
    final targetText = archive.group(1)!.trim();
    final candidates = await _findDailyNoteCandidates(targetText);
    if (candidates.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.archiveDailyNote,
        confidence: .8,
        clarification:
            'Aku tidak menemukan satu Catatan Harian aktif yang cocok dengan “$targetText”. Belum ada data yang diubah.',
      );
    }
    if (candidates.length > 1) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.archiveDailyNote,
        confidence: .72,
        clarification:
            'Aku menemukan ${candidates.length} Catatan Harian yang cocok: ${candidates.take(3).map(_dailyNoteCandidateLabel).join('; ')}. Sebut judul atau isi yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.dailyNoteArchive,
      createdAt: _clock(),
      title: _dailyNoteCandidateLabel(target),
      note: target.body,
      date: target.noteDate,
      formValues: {
        'entity': 'daily_note',
        'targetId': target.id,
        'operation': 'archive',
        'targetSummary': _dailyNoteCandidateLabel(target),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: 'Aku menemukan satu Catatan Harian untuk diarsipkan. Cek preview dulu; catatan tidak akan dihapus permanen.',
    );
  }

  Future<List<DailyNote>> _findDailyNoteCandidates(String targetText) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where((term) => term.length >= 3 && !RegExp(r'^\d+$').hasMatch(term))
        .toSet();
    if (terms.isEmpty) return const [];
    final rows =
        await (_database.select(_database.dailyNotes)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.noteDate)]))
            .get();
    return rows
        .where((row) {
          final haystack =
              '${row.title ?? ''} ${row.body} ${row.noteDate.toIso8601String().substring(0, 10)}'
                  .toLowerCase();
          return terms.every(haystack.contains);
        })
        .take(4)
        .toList(growable: false);
  }

  String _dailyNoteCandidateLabel(DailyNote row) {
    final date = row.noteDate.toIso8601String().substring(0, 10);
    return row.title?.trim().isNotEmpty == true
        ? '${row.title} ($date)'
        : 'Catatan $date';
  }

  Future<FfmAssistantIntent?> _parseTaskMutation(
    String rawText,
    String normalized,
  ) async {
    final create = RegExp(
      r'^(?:tambah|buat|catat)(?:kan)?\s+tugas\s*[:\-]?\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    if (create != null) {
      final title = create.group(1)?.trim() ?? '';
      if (title.isEmpty) return null;
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.task,
        createdAt: _clock(),
        title: title,
        formValues: const {'entity': 'task'},
      );
      return _intentForDraft(rawText, normalized, draft).copyWith(
        response: 'Aku siapkan draft Tugas. Cek preview dulu; belum ada data yang disimpan.',
      );
    }

    final update = RegExp(
      r'^(?:ubah|ganti)\s+tugas\s+(.+?)\s+(?:menjadi|jadi)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    final complete = RegExp(
      r'^(?:selesai|selesaikan|tandai selesai)\s+tugas\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    final reopen = RegExp(
      r'^(?:buka kembali|aktifkan kembali)\s+tugas\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    final archive = RegExp(
      r'^(?:arsip|arsipkan)\s+tugas\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    if (update == null &&
        complete == null &&
        reopen == null &&
        archive == null) {
      return null;
    }
    final operation = update != null
        ? 'update'
        : complete != null
        ? 'complete'
        : reopen != null
        ? 'reopen'
        : 'archive';
    final targetText =
        (update?.group(1) ??
                complete?.group(1) ??
                reopen?.group(1) ??
                archive?.group(1) ??
                '')
            .trim();
    final candidates = await _findTaskCandidates(
      targetText,
      operation: operation,
    );
    final type = switch (operation) {
      'update' => FfmAssistantIntentType.updateTask,
      'complete' => FfmAssistantIntentType.completeTask,
      'reopen' => FfmAssistantIntentType.reopenTask,
      _ => FfmAssistantIntentType.archiveTask,
    };
    if (candidates.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: .8,
        clarification:
            'Aku tidak menemukan satu Tugas aktif yang cocok dengan “$targetText”. Belum ada data yang diubah.',
      );
    }
    if (candidates.length > 1) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: .72,
        clarification:
            'Aku menemukan ${candidates.length} Tugas yang cocok: ${candidates.take(3).map(_taskCandidateLabel).join('; ')}. Sebut judul yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final newTitle = update?.group(2)?.trim();
    final kind = switch (operation) {
      'update' => FfmAssistantDraftKind.taskUpdate,
      'complete' => FfmAssistantDraftKind.taskComplete,
      'reopen' => FfmAssistantDraftKind.taskReopen,
      _ => FfmAssistantDraftKind.taskArchive,
    };
    final draft = FfmAssistantDraft(
      kind: kind,
      createdAt: _clock(),
      title: newTitle ?? _taskCandidateLabel(target),
      note: target.note,
      date: target.dueDate,
      formValues: {
        'entity': 'task',
        'targetId': target.id,
        'operation': operation,
        'targetSummary': _taskCandidateLabel(target),
        'title': ?newTitle,
      },
    );
    final action = switch (operation) {
      'update' => 'diubah',
      'complete' => 'ditandai selesai',
      'reopen' => 'dibuka kembali',
      _ => 'diarsipkan tanpa dihapus permanen',
    };
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response:
          'Aku menemukan satu Tugas untuk $action. Cek preview dulu; belum ada data yang diubah.',
    );
  }

  Future<List<Task>> _findTaskCandidates(
    String targetText, {
    required String operation,
  }) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where((term) => term.length >= 3 && !RegExp(r'^\d+$').hasMatch(term))
        .toSet();
    if (terms.isEmpty) return const [];
    final rows =
        await (_database.select(_database.tasks)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
            .get();
    return rows
        .where((row) {
          if (operation == 'complete' && row.status != 'open') return false;
          if (operation == 'reopen' && row.status != 'completed') return false;
          final haystack = '${row.title} ${row.note ?? ''}'.toLowerCase();
          return terms.every(haystack.contains);
        })
        .take(4)
        .toList(growable: false);
  }

  Future<FfmAssistantIntent?> _parseRoutineMutation(
    String rawText,
    String normalized,
  ) async {
    final create = RegExp(
      r'^(?:tambah|buat|catat)(?:kan)?\s+rutinitas\s*[:\-]?\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    if (create != null) {
      final title = create.group(1)?.trim() ?? '';
      if (title.isEmpty) return null;
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.routine,
        createdAt: _clock(),
        title: title,
        formValues: const {'entity': 'daily_routine'},
      );
      return _intentForDraft(rawText, normalized, draft).copyWith(
        response: 'Aku siapkan draft Rutinitas. Cek preview dulu; belum ada data yang disimpan atau notifikasi yang dibuat.',
      );
    }

    final update = RegExp(
      r'^(?:ubah|ganti)\s+rutinitas\s+(.+?)\s+(?:menjadi|jadi)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    final mark = RegExp(
      r'^(?:selesai|selesaikan|tandai selesai)\s+rutinitas\s+(.+?)(?:\s+hari ini)?$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    final unmark = RegExp(
      r'^(?:batalkan|batal|hapus)\s+(?:tanda\s+)?(?:selesai\s+)?rutinitas\s+(.+?)(?:\s+hari ini)?$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    final activate = RegExp(
      r'^aktifkan\s+rutinitas\s+(.+$)',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    final deactivate = RegExp(
      r'^(?:nonaktifkan|matikan)\s+rutinitas\s+(.+$)',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    final archive = RegExp(
      r'^(?:arsip|arsipkan)\s+rutinitas\s+(.+$)',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    if (update == null &&
        mark == null &&
        unmark == null &&
        activate == null &&
        deactivate == null &&
        archive == null) {
      return null;
    }
    final operation = update != null
        ? 'update'
        : mark != null
        ? 'mark'
        : unmark != null
        ? 'unmark'
        : activate != null
        ? 'activate'
        : deactivate != null
        ? 'deactivate'
        : 'archive';
    final targetText =
        (update?.group(1) ??
                mark?.group(1) ??
                unmark?.group(1) ??
                activate?.group(1) ??
                deactivate?.group(1) ??
                archive?.group(1) ??
                '')
            .trim();
    final candidates = await _findRoutineCandidates(
      targetText,
      operation: operation,
    );
    final type = switch (operation) {
      'update' => FfmAssistantIntentType.updateRoutine,
      'mark' => FfmAssistantIntentType.markRoutineComplete,
      'unmark' => FfmAssistantIntentType.unmarkRoutineComplete,
      'activate' => FfmAssistantIntentType.activateRoutine,
      'deactivate' => FfmAssistantIntentType.deactivateRoutine,
      _ => FfmAssistantIntentType.archiveRoutine,
    };
    if (candidates.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: .8,
        clarification:
            'Aku tidak menemukan satu Rutinitas aktif yang cocok dengan “$targetText”. Sebut judul yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    if (candidates.length > 1) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: .72,
        clarification:
            'Aku menemukan ${candidates.length} Rutinitas yang cocok: ${candidates.take(3).map(_routineCandidateLabel).join('; ')}. Sebut judul yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final newTitle = update?.group(2)?.trim();
    final kind = switch (operation) {
      'update' => FfmAssistantDraftKind.routineUpdate,
      'mark' => FfmAssistantDraftKind.routineMarkComplete,
      'unmark' => FfmAssistantDraftKind.routineUnmarkComplete,
      'activate' => FfmAssistantDraftKind.routineActivate,
      'deactivate' => FfmAssistantDraftKind.routineDeactivate,
      _ => FfmAssistantDraftKind.routineArchive,
    };
    final now = _clock();
    final day = DateTime(now.year, now.month, now.day);
    final draft = FfmAssistantDraft(
      kind: kind,
      createdAt: _clock(),
      title: newTitle ?? target.title,
      note: target.note,
      date: operation == 'mark' || operation == 'unmark' ? day : null,
      formValues: {
        'entity': 'daily_routine',
        'targetId': target.id,
        'operation': operation,
        'targetSummary': _routineCandidateLabel(target),
        'weekdays': target.weekdaysJson,
        'title': ?newTitle,
      },
    );
    final action = switch (operation) {
      'update' => 'diubah',
      'mark' => 'ditandai selesai hari ini',
      'unmark' => 'dibatalkan tandanya untuk hari ini',
      'activate' => 'diaktifkan',
      'deactivate' => 'dinonaktifkan',
      _ => 'diarsipkan tanpa dihapus permanen',
    };
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response:
          'Aku menemukan satu Rutinitas untuk $action. Cek preview dulu; belum ada data yang diubah.',
    );
  }

  Future<List<DailyRoutine>> _findRoutineCandidates(
    String targetText, {
    required String operation,
  }) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where((term) => term.length >= 3 && !RegExp(r'^\d+$').hasMatch(term))
        .toSet();
    if (terms.isEmpty) return const [];
    final rows =
        await (_database.select(_database.dailyRoutines)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
            .get();
    return rows
        .where((row) {
          if (operation == 'mark' && !row.isActive) return false;
          if (operation == 'activate' && row.isActive) return false;
          if (operation == 'deactivate' && !row.isActive) return false;
          final haystack = '${row.title} ${row.note ?? ''}'.toLowerCase();
          return terms.every(haystack.contains);
        })
        .take(4)
        .toList(growable: false);
  }

  String _routineCandidateLabel(DailyRoutine row) {
    final state = row.isActive ? 'aktif' : 'nonaktif';
    return '${row.title} • $state';
  }

  Future<FfmAssistantIntent?> _parseScheduleMutationSafe(
    String rawText,
    String normalized,
  ) async {
    final direct = await _parseScheduleMutationDirect(rawText, normalized);
    return direct ?? _parseScheduleMutation(rawText, normalized);
  }

  Future<FfmAssistantIntent?> _parseScheduleMutationDirect(
    String rawText,
    String normalized,
  ) async {
    final create = RegExp(r'^(?:buat|tambah|jadwalkan)[ ]+jadwal[ ]+(.+)$')
        .firstMatch(normalized);
    if (create != null) {
      return _draftScheduleCreate(rawText, normalized, create.group(1)!);
    }
    final move = RegExp(
      r'^(?:pindah|pindahkan|jadwalkan ulang)[ ]+jadwal[ ]+(.+?)[ ]+ke[ ]+(.+)$',
    ).firstMatch(normalized);
    final rename = RegExp(
      r'^(?:ubah|ganti|koreksi)[ ]+jadwal[ ]+(.+?)[ ]+(?:jadi|menjadi)[ ]+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(r'^(?:arsip|arsipkan)[ ]+jadwal[ ]+(.+)$')
        .firstMatch(normalized);
    if (move == null && rename == null && archive == null) return null;
    return _draftScheduleMutation(
      rawText,
      normalized,
      move: move,
      rename: rename,
      archive: archive,
    );
  }

  Future<FfmAssistantIntent> _draftScheduleCreate(
    String rawText,
    String normalized,
    String source,
  ) async {
    final date = _scheduleDateFromText(source);
    if (date == null) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.createSchedule,
        confidence: .75,
        clarification: 'Sebutkan tanggal Jadwal, misalnya “buat jadwal kontrol dokter besok” atau “buat jadwal kontrol dokter tanggal 28/08/2026”. Belum ada data yang diubah.',
      );
    }
    final title = _scheduleTitleFromText(source);
    if (title.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.createSchedule,
        confidence: .75,
        clarification:
            'Sebutkan judul agenda Jadwal. Belum ada data yang diubah.',
      );
    }
    final startMinutes = _scheduleMinutesFromText(source);
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.schedule,
      createdAt: _clock(),
      title: title,
      date: date,
      formValues: {
        'entity': 'schedule_entry',
        'date': date.toIso8601String(),
        'isAllDay': (startMinutes == null).toString(),
        if (startMinutes != null) 'startMinutes': startMinutes.toString(),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: 'Aku menyiapkan Jadwal lokal tanpa alarm atau notifikasi. Cek preview dan konfirmasi bila sudah benar.',
    );
  }

  Future<FfmAssistantIntent> _draftScheduleMutation(
    String rawText,
    String normalized, {
    RegExpMatch? move,
    RegExpMatch? rename,
    RegExpMatch? archive,
  }) async {
    final operation = move != null || rename != null ? 'update' : 'archive';
    final targetSource =
        move?.group(1) ?? rename?.group(1) ?? archive?.group(1);
    final type = operation == 'archive'
        ? FfmAssistantIntentType.archiveSchedule
        : FfmAssistantIntentType.updateSchedule;
    if (targetSource == null) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: .5,
        clarification: 'Sebutkan Judul Jadwal yang ingin diubah. Belum ada data yang diubah.',
      );
    }
    final targetText = targetSource.trim();
    final candidates = await _findScheduleCandidates(targetText);
    if (candidates.isEmpty || candidates.length > 1) {
      final detail = candidates.isEmpty
          ? 'Aku tidak menemukan satu Jadwal aktif yang cocok dengan “$targetText”.'
          : 'Aku menemukan ${candidates.length} Jadwal yang cocok: ${candidates.take(3).map(_scheduleCandidateLabel).join('; ')}.';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: candidates.isEmpty ? .8 : .72,
        clarification:
            '$detail Sebut judul yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final replacement = move?.group(2)?.trim();
    final date = move == null
        ? target.scheduledDate
        : _scheduleDateFromText(replacement ?? '');
    if (move != null && date == null) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.updateSchedule,
        confidence: .75,
        clarification: 'Tanggal tujuan Jadwal belum dipahami. Gunakan “besok” atau format “tanggal 28/08/2026”. Belum ada data yang diubah.',
      );
    }
    final draft = FfmAssistantDraft(
      kind: operation == 'archive'
          ? FfmAssistantDraftKind.scheduleArchive
          : FfmAssistantDraftKind.scheduleUpdate,
      createdAt: _clock(),
      title: rename?.group(2)?.trim() ?? target.title,
      note: target.note,
      date: date,
      formValues: {
        'entity': 'schedule_entry',
        'targetId': target.id,
        'operation': operation,
        'targetSummary': _scheduleCandidateLabel(target),
        if (operation == 'update') 'date': date!.toIso8601String(),
        if (operation == 'update') 'isAllDay': target.isAllDay.toString(),
        if (operation == 'update' && target.startMinutes != null)
          'startMinutes': target.startMinutes.toString(),
        if (operation == 'update' && target.endMinutes != null)
          'endMinutes': target.endMinutes.toString(),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'archive'
          ? 'Aku menemukan satu Jadwal untuk diarsipkan tanpa hapus permanen. Cek preview dulu; belum ada data yang diubah.'
          : 'Aku menyiapkan perubahan satu Jadwal tanpa alarm atau notifikasi. Cek preview dulu; belum ada data yang diubah.',
    );
  }

  Future<FfmAssistantIntent?> _parseScheduleMutation(
    String rawText,
    String normalized,
  ) async {
    final create = RegExp(r'^(?:buat|tambah|jadwalkan)s+jadwals+(.+)$')
        .firstMatch(normalized);
    if (create != null) {
      final source = create.group(1)!.trim();
      final date = _scheduleDateFromText(source);
      if (date == null) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.createSchedule,
          confidence: .75,
          clarification: 'Sebutkan tanggal Jadwal, misalnya “buat jadwal kontrol dokter besok” atau “buat jadwal kontrol dokter tanggal 28/08/2026”. Belum ada data yang diubah.',
        );
      }
      final title = _scheduleTitleFromText(source);
      if (title.isEmpty) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.createSchedule,
          confidence: .75,
          clarification:
              'Sebutkan judul agenda Jadwal. Belum ada data yang diubah.',
        );
      }
      final startMinutes = _scheduleMinutesFromText(source);
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.schedule,
        createdAt: _clock(),
        title: title,
        date: date,
        formValues: {
          'entity': 'schedule_entry',
          'date': date.toIso8601String(),
          'isAllDay': (startMinutes == null).toString(),
          if (startMinutes != null) 'startMinutes': startMinutes.toString(),
        },
      );
      return _intentForDraft(rawText, normalized, draft).copyWith(
        response: 'Aku menyiapkan Jadwal lokal tanpa alarm atau notifikasi. Cek preview dan konfirmasi bila sudah benar.',
      );
    }

    final move = RegExp(
      r'^(?:pindah|pindahkan|jadwalkan ulang)s+jadwals+(.+?)s+kes+(.+)$',
    ).firstMatch(normalized);
    final rename = RegExp(
      r'^(?:ubah|ganti|koreksi)s+jadwals+(.+?)s+(?:jadi|menjadi)s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(r'^(?:arsip|arsipkan)s+jadwals+(.+)$')
        .firstMatch(normalized);
    if (move == null && rename == null && archive == null) return null;

    final operation = move != null
        ? 'update'
        : rename != null
        ? 'update'
        : 'archive';
    final targetSource =
        move?.group(1) ?? rename?.group(1) ?? archive?.group(1);
    if (targetSource == null) return null;
    final targetText = targetSource.trim();
    final candidates = await _findScheduleCandidates(targetText);
    final type = operation == 'archive'
        ? FfmAssistantIntentType.archiveSchedule
        : FfmAssistantIntentType.updateSchedule;
    if (candidates.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: .8,
        clarification:
            'Aku tidak menemukan satu Jadwal aktif yang cocok dengan “$targetText”. Sebut judul yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    if (candidates.length > 1) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: .72,
        clarification:
            'Aku menemukan ${candidates.length} Jadwal yang cocok: ${candidates.take(3).map(_scheduleCandidateLabel).join('; ')}. Sebut judul yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final replacement = move?.group(2)?.trim();
    final date = move == null
        ? target.scheduledDate
        : _scheduleDateFromText(replacement ?? '');
    if (move != null && date == null) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.updateSchedule,
        confidence: .75,
        clarification: 'Tanggal tujuan Jadwal belum dipahami. Gunakan “besok” atau format “tanggal 28/08/2026”. Belum ada data yang diubah.',
      );
    }
    final newTitle = rename?.group(2)?.trim() ?? target.title;
    final draft = FfmAssistantDraft(
      kind: operation == 'archive'
          ? FfmAssistantDraftKind.scheduleArchive
          : FfmAssistantDraftKind.scheduleUpdate,
      createdAt: _clock(),
      title: newTitle,
      note: target.note,
      date: date,
      formValues: {
        'entity': 'schedule_entry',
        'targetId': target.id,
        'operation': operation,
        'targetSummary': _scheduleCandidateLabel(target),
        if (operation == 'update') 'date': date!.toIso8601String(),
        if (operation == 'update') 'isAllDay': target.isAllDay.toString(),
        if (operation == 'update' && target.startMinutes != null)
          'startMinutes': target.startMinutes.toString(),
        if (operation == 'update' && target.endMinutes != null)
          'endMinutes': target.endMinutes.toString(),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'archive'
          ? 'Aku menemukan satu Jadwal untuk diarsipkan tanpa hapus permanen. Cek preview dulu; belum ada data yang diubah.'
          : 'Aku menyiapkan perubahan satu Jadwal tanpa alarm atau notifikasi. Cek preview dulu; belum ada data yang diubah.',
    );
  }

  Future<List<ScheduleEntry>> _findScheduleCandidates(String targetText) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where(
          (term) =>
              term.length >= 3 &&
              !const {
                'jadwal',
                'pada',
                'tanggal',
                'hari',
                'besok',
              }.contains(term) &&
              !RegExp(r'^\d+$').hasMatch(term),
        )
        .toSet();
    if (terms.isEmpty) return const [];
    final rows =
        await (_database.select(_database.scheduleEntries)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.scheduledDate)]))
            .get();
    return rows
        .where((row) {
          final haystack = '${row.title} ${row.note ?? ''}'.toLowerCase();
          return terms.every(haystack.contains);
        })
        .take(4)
        .toList(growable: false);
  }

  String _scheduleCandidateLabel(ScheduleEntry row) {
    final date = row.scheduledDate.toIso8601String().substring(0, 10);
    final time = row.isAllDay || row.startMinutes == null
        ? 'sepanjang hari'
        : '${(row.startMinutes! ~/ 60).toString().padLeft(2, '0')}:${(row.startMinutes! % 60).toString().padLeft(2, '0')}';
    return '${row.title} • $date • $time';
  }

  DateTime? _scheduleDateFromText(String value) {
    final now = _clock();
    if (RegExp(r'\b(?:besok|esok)\b').hasMatch(value)) {
      return DateTime(now.year, now.month, now.day + 1);
    }
    if (RegExp(r'\b(?:hari ini|sekarang)\b').hasMatch(value)) {
      return DateTime(now.year, now.month, now.day);
    }
    final numeric = RegExp(
      r'\btanggal\s+(\d{1,2})[/-](\d{1,2})(?:[/-](\d{4}))?\b',
    ).firstMatch(value);
    if (numeric == null) return null;
    final day = int.tryParse(numeric.group(1)!);
    final month = int.tryParse(numeric.group(2)!);
    final year = int.tryParse(numeric.group(3) ?? '') ?? now.year;
    if (day == null || month == null || day < 1 || month < 1 || month > 12) {
      return null;
    }
    final date = DateTime(year, month, day);
    return date.day == day && date.month == month ? date : null;
  }

  int? _scheduleMinutesFromText(String value) {
    final match = RegExp(r'\b(?:jam|pukul)\s*(\d{1,2})(?:[.:](\d{2}))?\b')
        .firstMatch(value);
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2) ?? '0');
    if (hour == null || minute == null || hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  String _scheduleTitleFromText(String value) => value
      .replaceAll(RegExp(r'\b(?:hari ini|besok|esok)\b'), '')
      .replaceAll(RegExp(r'\btanggal\s+\d{1,2}[/-]\d{1,2}(?:[/-]\d{4})?\b'), '')
      .replaceAll(RegExp(r'\b(?:jam|pukul)\s*\d{1,2}(?:[.:]\d{2})?\b'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _taskCandidateLabel(Task row) {
    final due = row.dueDate == null
        ? ''
        : ' • target ${row.dueDate!.toIso8601String().substring(0, 10)}';
    return '${row.title}$due';
  }

  Future<FfmAssistantIntent?> _parseReminderMutation(
    String rawText,
    String normalized,
  ) async {
    final update = RegExp(
      r'^(?:ubah|ganti|koreksi|jadwalkan ulang)\s+pengingat\s+(.+?)\s+(?:jadi|menjadi|ke)\s+(.+)$',
    ).firstMatch(normalized);
    if (update != null) {
      final targetText = update.group(1)!.trim();
      final changeText = update.group(2)!.trim();
      final candidates = await _findReminderCandidates(targetText);
      if (candidates.isEmpty || candidates.length > 1) {
        final detail = candidates.isEmpty
            ? 'Aku tidak menemukan satu pengingat aktif yang cocok dengan “$targetText”.'
            : 'Aku menemukan ${candidates.length} pengingat yang cocok: ${candidates.take(3).map(_reminderCandidateLabel).join('; ')}.';
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.updateReminder,
          confidence: candidates.isEmpty ? .8 : .72,
          clarification:
              '$detail Sebut judul pengingat yang lebih spesifik. Belum ada data yang diubah.',
        );
      }
      final target = candidates.single;
      final parsedDate = _scheduleDateFromText(changeText);
      final parsedMinutes = _scheduleMinutesFromText(changeText);
      final day = parsedDate ?? target.scheduledAt;
      final scheduledAt = DateTime(
        day.year,
        day.month,
        day.day,
        parsedMinutes == null ? target.scheduledAt.hour : parsedMinutes ~/ 60,
        parsedMinutes == null ? target.scheduledAt.minute : parsedMinutes % 60,
      );
      final titleCandidate = _scheduleTitleFromText(changeText);
      final title = titleCandidate.isEmpty ? target.title : titleCandidate;
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.reminderUpdate,
        createdAt: _clock(),
        title: title,
        note: target.note,
        date: scheduledAt,
        formValues: {
          'entity': 'reminder',
          'targetId': target.id,
          'operation': 'update',
          'targetSummary': _reminderCandidateLabel(target),
          'scheduledAt': scheduledAt.toIso8601String(),
          'preserveRecurrence': 'true',
          'preserveSound': 'true',
          'preserveNotificationId': 'true',
        },
      );
      return _intentForDraft(rawText, normalized, draft).copyWith(
        response: 'Aku menyiapkan perubahan satu pengingat. Pola berulang, suara, snooze, dan identitas notifikasi akan dipertahankan. Cek preview lalu konfirmasi; belum ada data yang diubah.',
      );
    }
    final archive = RegExp(
      r'^(?:arsip|arsipkan|nonaktifkan|matikan)\s+pengingat\s+(.+)$',
    ).firstMatch(normalized);
    if (archive == null) return null;
    final targetText = archive.group(1)!.trim();
    final candidates = await _findReminderCandidates(targetText);
    if (candidates.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.archiveReminder,
        confidence: .8,
        clarification:
            'Aku tidak menemukan satu pengingat aktif yang cocok dengan “$targetText”. Sebut judul pengingat yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    if (candidates.length > 1) {
      final options = candidates
          .take(3)
          .map(_reminderCandidateLabel)
          .join('; ');
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.archiveReminder,
        confidence: .72,
        clarification:
            'Aku menemukan ${candidates.length} pengingat yang cocok: $options. Sebut judul yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.reminderArchive,
      createdAt: _clock(),
      title: _reminderCandidateLabel(target),
      date: target.scheduledAt,
      formValues: {
        'entity': 'reminder',
        'targetId': target.id,
        'operation': 'archive',
        'targetSummary': _reminderCandidateLabel(target),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: 'Aku menemukan satu pengingat aktif untuk dinonaktifkan. Alarm berikutnya akan dibatalkan, tetapi riwayat tetap tersimpan. Cek preview dulu sebelum mengonfirmasi.',
    );
  }

  Future<List<Reminder>> _findReminderCandidates(String targetText) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where(
          (term) =>
              term.length >= 3 &&
              !const {
                'pengingat',
                'pada',
                'tanggal',
                'hari',
                'besok',
              }.contains(term) &&
              !RegExp(r'^\d+$').hasMatch(term),
        )
        .toSet();
    if (terms.isEmpty) return const [];
    final rows =
        await (_database.select(_database.reminders)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isActive.equals(true),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.scheduledAt)]))
            .get();
    return rows
        .where((row) => terms.every(row.title.toLowerCase().contains))
        .take(4)
        .toList(growable: false);
  }

  String _reminderCandidateLabel(Reminder row) =>
      '${row.title} • ${row.scheduledAt.toIso8601String().substring(0, 16)}';

  Future<FfmAssistantIntent?> _parseAssetMutation(
    String rawText,
    String normalized,
  ) async {
    final update = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+aset\s+(.+?)\s+(?:jadi|menjadi|ke)\s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(r'^(?:arsip|arsipkan)\s+aset\s+(.+)$')
        .firstMatch(normalized);
    if (update == null && archive == null) return null;
    final operation = update == null ? 'archive' : 'update';
    final targetText = (update?.group(1) ?? archive!.group(1)!).trim();
    final candidates = await _findAssetCandidates(targetText);
    final type = operation == 'update'
        ? FfmAssistantIntentType.updateAsset
        : FfmAssistantIntentType.archiveAsset;
    if (candidates.isEmpty || candidates.length > 1) {
      final detail = candidates.isEmpty
          ? 'Aku tidak menemukan satu aset aktif yang cocok dengan “$targetText”.'
          : 'Aku menemukan ${candidates.length} aset yang cocok: ${candidates.take(3).map(_assetCandidateLabel).join('; ')}.';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: candidates.isEmpty ? .8 : .72,
        clarification:
            '$detail Sebut nama aset yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    if (operation == 'archive') {
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.assetArchive,
        createdAt: _clock(),
        title: target.name,
        amount: target.value,
        formValues: {
          'entity': 'asset',
          'targetId': target.id,
          'operation': 'archive',
          'targetSummary': _assetCandidateLabel(target),
        },
      );
      return _intentForDraft(rawText, normalized, draft).copyWith(
        response: 'Aku menemukan satu aset untuk diarsipkan tanpa hapus permanen. Tidak ada transaksi atau saldo yang diubah. Cek preview dulu.',
      );
    }
    final replacement = update!.group(2)!.trim();
    final parsedValue = FfmAssistantAmountParser.parse(replacement);
    final title = _assetTitleFromReplacement(
      replacement,
      fallback: target.name,
    );
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.assetUpdate,
      createdAt: _clock(),
      title: title,
      amount: parsedValue ?? target.value,
      note: target.note,
      formValues: {
        'entity': 'asset',
        'targetId': target.id,
        'operation': 'update',
        'targetSummary': _assetCandidateLabel(target),
        'assetType': target.assetType,
        'placement': target.placement,
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: 'Aku menyiapkan perubahan satu aset. Tidak ada transaksi atau saldo yang akan dibuat. Cek preview lalu konfirmasi.',
    );
  }

  Future<List<Asset>> _findAssetCandidates(String targetText) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where(
          (term) =>
              term.length >= 3 &&
              term != 'aset' &&
              !RegExp(r'^\d+$').hasMatch(term),
        )
        .toSet();
    if (terms.isEmpty) return const [];
    final rows =
        await (_database.select(_database.assets)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .get();
    return rows
        .where((row) {
          final haystack = '${row.name} ${row.assetType} ${row.placement}'
              .toLowerCase();
          return terms.every(haystack.contains);
        })
        .take(4)
        .toList(growable: false);
  }

  String _assetCandidateLabel(Asset row) =>
      '${row.name} • ${row.assetType} • ${row.value}';

  String _assetTitleFromReplacement(String value, {required String fallback}) {
    final withoutAmount = value
        .replaceAll(
          RegExp(r'\b(?:rp|rupiah|nilai)\b', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\d+(?:[.,]\d+)*(?:\s*(?:rb|ribu|jt|juta|m))?'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return withoutAmount.isEmpty ? fallback : withoutAmount;
  }

  Future<FfmAssistantIntent?> _parseLiabilityMutation(
    String rawText,
    String normalized,
  ) async {
    final update = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+(?:hutang|utang)\s+(.+?)\s+(?:jadi|menjadi)\s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(r'^(?:arsip|arsipkan)\s+(?:hutang|utang)\s+(.+)$')
        .firstMatch(normalized);
    if (update == null && archive == null) return null;
    final operation = update == null ? 'archive' : 'update';
    final targetText = (update?.group(1) ?? archive!.group(1)!).trim();
    final rows =
        await (_database.select(_database.liabilities)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final terms = targetText
        .split(RegExp(r'\s+'))
        .where((term) => term.length >= 3)
        .toList();
    final candidates = rows
        .where((row) => terms.every(row.name.toLowerCase().contains))
        .take(4)
        .toList(growable: false);
    final type = operation == 'update'
        ? FfmAssistantIntentType.updateLiability
        : FfmAssistantIntentType.archiveLiability;
    if (candidates.length != 1) {
      final detail = candidates.isEmpty
          ? 'Aku tidak menemukan satu Hutang aktif yang cocok dengan “$targetText”.'
          : 'Aku menemukan ${candidates.length} Hutang yang cocok: ${candidates.map((row) => row.name).join('; ')}.';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: candidates.isEmpty ? .8 : .72,
        clarification:
            '$detail Sebut nama Hutang yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final draft = FfmAssistantDraft(
      kind: operation == 'update'
          ? FfmAssistantDraftKind.liabilityUpdate
          : FfmAssistantDraftKind.liabilityArchive,
      createdAt: _clock(),
      title: operation == 'update' ? update!.group(2)!.trim() : target.name,
      note: target.note,
      date: target.dueDate ?? target.startDate,
      formValues: {
        'entity': 'liability',
        'targetId': target.id,
        'operation': operation,
        'targetSummary': '${target.name} • sisa ${target.remainingBalance}',
        'originalAmount': target.originalAmount.toString(),
        'remainingBalance': target.remainingBalance.toString(),
        'monthlyInstallment': target.monthlyInstallment.toString(),
        'interestRate': target.interestRate.toString(),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'update'
          ? 'Aku menyiapkan perubahan metadata satu Hutang. Nilai pokok dan sisa Hutang tidak akan diubah. Cek preview dulu.'
          : 'Aku menyiapkan arsip lunak satu Hutang tanpa hapus permanen, pembayaran, atau transaksi. Cek preview dulu.',
    );
  }

  Future<FfmAssistantIntent?> _parseReceivableMutation(
    String rawText,
    String normalized,
  ) async {
    final update = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+piutang\s+(.+?)\s+(?:jadi|menjadi)\s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(r'^(?:arsip|arsipkan)\s+piutang\s+(.+)$')
        .firstMatch(normalized);
    if (update == null && archive == null) return null;
    final operation = update == null ? 'archive' : 'update';
    final targetText = (update?.group(1) ?? archive!.group(1)!).trim();
    final rows =
        await (_database.select(_database.receivables)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final terms = targetText
        .split(RegExp(r'\s+'))
        .where((term) => term.length >= 3)
        .toList();
    final candidates = rows
        .where((row) => terms.every(row.name.toLowerCase().contains))
        .take(4)
        .toList(growable: false);
    final type = operation == 'update'
        ? FfmAssistantIntentType.updateReceivable
        : FfmAssistantIntentType.archiveReceivable;
    if (candidates.length != 1) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: candidates.isEmpty ? .8 : .72,
        clarification: candidates.isEmpty
            ? 'Aku tidak menemukan satu Piutang aktif yang cocok dengan "$targetText". Belum ada data yang diubah.'
            : 'Aku menemukan ${candidates.length} Piutang yang cocok. Sebut nama yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final draft = FfmAssistantDraft(
      kind: operation == 'update'
          ? FfmAssistantDraftKind.receivableUpdate
          : FfmAssistantDraftKind.receivableArchive,
      createdAt: _clock(),
      title: operation == 'update' ? update!.group(2)!.trim() : target.name,
      note: target.note,
      date: target.dueDate ?? target.startDate,
      formValues: {
        'entity': 'receivable',
        'targetId': target.id,
        'operation': operation,
        'originalAmount': target.originalAmount.toString(),
        'remainingBalance': target.remainingBalance.toString(),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'update'
          ? 'Aku menyiapkan perubahan metadata Piutang. Nilai pokok dan sisa Piutang tidak akan diubah. Cek preview dulu.'
          : 'Aku menyiapkan arsip lunak Piutang tanpa hapus permanen, penagihan, atau transaksi. Cek preview dulu.',
    );
  }

  Future<FfmAssistantIntent?> _parseRecurringTransactionMutation(
    String rawText,
    String normalized,
  ) async {
    final updateName = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+(?:jadwal\s+)?(?:transaksi\s+)?berkala\s+(.+?)\s+(?:jadi|menjadi)\s+(.+)$',
    ).firstMatch(normalized);
    final updateNote = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+catatan\s+(?:jadwal\s+)?(?:transaksi\s+)?berkala\s+(.+?)\s+(?:jadi|menjadi)\s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(
      r'^(?:arsip|arsipkan|nonaktifkan)\s+(?:jadwal\s+)?(?:transaksi\s+)?berkala\s+(.+)$',
    ).firstMatch(normalized);
    if (updateName == null && updateNote == null && archive == null) {
      return null;
    }

    final operation = updateName == null && updateNote == null
        ? 'archive'
        : 'update';
    final metadataField = updateNote == null ? 'name' : 'note';
    final targetText =
        (updateName?.group(1) ?? updateNote?.group(1) ?? archive!.group(1)!)
            .trim();
    final rows =
        await (_database.select(_database.recurringTransactions)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final terms = targetText
        .split(RegExp(r'\s+'))
        .where((term) => term.length >= 3)
        .toList();
    final candidates = rows
        .where((row) => terms.every(row.name.toLowerCase().contains))
        .take(4)
        .toList(growable: false);
    final type = operation == 'update'
        ? FfmAssistantIntentType.updateRecurringTransaction
        : FfmAssistantIntentType.archiveRecurringTransaction;
    if (candidates.length != 1) {
      final detail = candidates.isEmpty
          ? 'Aku tidak menemukan satu jadwal Transaksi Berkala aktif yang cocok dengan “$targetText”.'
          : 'Aku menemukan ${candidates.length} jadwal Transaksi Berkala yang cocok: ${candidates.map((row) => row.name).join('; ')}.';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: candidates.isEmpty ? .8 : .72,
        clarification:
            '$detail Sebut nama jadwal yang lebih spesifik. Belum ada aturan, transaksi, atau run yang diubah.',
      );
    }

    final target = candidates.single;
    final draft = FfmAssistantDraft(
      kind: operation == 'update'
          ? FfmAssistantDraftKind.recurringTransactionUpdate
          : FfmAssistantDraftKind.recurringTransactionArchive,
      createdAt: _clock(),
      title: metadataField == 'name' && operation == 'update'
          ? updateName!.group(2)!.trim()
          : target.name,
      note: metadataField == 'note' && operation == 'update'
          ? updateNote!.group(2)!.trim()
          : target.note,
      date: target.startDate,
      formValues: {
        'entity': 'recurring_transaction',
        'targetId': target.id,
        'operation': operation,
        'metadataField': metadataField,
        'targetSummary': '${target.name} • ${target.periodType}',
        'amount': target.amount.toString(),
        'type': target.type,
        'periodType': target.periodType,
        'calcMode': target.calcMode,
        'ratePercent': target.ratePercent?.toString() ?? '',
        'accountId': target.accountId ?? '',
        'categoryId': target.categoryId ?? '',
        'sourceId': target.sourceId ?? '',
        'startDate': target.startDate.toIso8601String(),
        'endDate': target.endDate?.toIso8601String() ?? '',
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'update'
          ? 'Aku menyiapkan perubahan ${metadataField == 'note' ? 'catatan' : 'nama'} satu Transaksi Berkala. Jadwal tidak akan dijalankan dan tidak ada transaksi baru dibuat. Cek preview dulu.'
          : 'Aku menyiapkan penonaktifan satu Transaksi Berkala tanpa mengubah riwayat, transaksi, atau run. Cek preview dulu.',
    );
  }

  Future<FfmAssistantIntent?> _parseMerchantMutation(
    String rawText,
    String normalized,
  ) async {
    const noun = r'(?:toko|tempat|merchant)';
    final updateName = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+' +
          noun +
          r'\s+(.+?)\s+(?:jadi|menjadi)\s+(.+)$',
    );
    final nameMatch = updateName.firstMatch(normalized);
    final updateNote = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+(?:keterangan|catatan)\s+' +
          noun +
          r'\s+(.+?)\s+(?:jadi|menjadi)\s+(.+)$',
    );
    final noteMatch = updateNote.firstMatch(normalized);
    final archiveMatch = RegExp(r'^(?:arsip|arsipkan)\s+' + noun + r'\s+(.+)$')
        .firstMatch(normalized);
    final deleteMatch = RegExp(
      r'^(?:hapus|buang|hilangkan)\s+' + noun + r'\s+(.+)$',
    ).firstMatch(normalized);
    if (nameMatch == null &&
        noteMatch == null &&
        archiveMatch == null &&
        deleteMatch == null) {
      return null;
    }

    final operation = deleteMatch != null
        ? 'delete'
        : (nameMatch == null && noteMatch == null ? 'archive' : 'update');
    final metadataField = noteMatch == null ? 'name' : 'details';
    final targetText =
        (nameMatch?.group(1) ??
                noteMatch?.group(1) ??
                archiveMatch?.group(1) ??
                deleteMatch!.group(1)!)
            .trim();
    final rows =
        await (_database.select(_database.merchants)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final terms = targetText
        .split(RegExp(r'\s+'))
        .where((term) => term.length >= 3)
        .toList();
    final candidates = rows
        .where((row) => terms.every(row.name.toLowerCase().contains))
        .take(4)
        .toList(growable: false);
    final type = operation == 'update'
        ? FfmAssistantIntentType.updateMerchant
        : operation == 'delete'
        ? FfmAssistantIntentType.deleteMerchant
        : FfmAssistantIntentType.archiveMerchant;
    if (candidates.length != 1) {
      final detail = candidates.isEmpty
          ? 'Aku tidak menemukan satu Toko/Tempat aktif yang cocok dengan “$targetText”.'
          : 'Aku menemukan ${candidates.length} Toko/Tempat yang cocok: ${candidates.map((row) => row.name).join('; ')}.';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: candidates.isEmpty ? .8 : .72,
        clarification:
            '$detail Sebut nama Toko/Tempat yang lebih spesifik. Belum ada data atau transaksi yang diubah.',
      );
    }

    final target = candidates.single;
    final draft = FfmAssistantDraft(
      kind: operation == 'update'
          ? FfmAssistantDraftKind.merchantUpdate
          : operation == 'delete'
          ? FfmAssistantDraftKind.merchantDelete
          : FfmAssistantDraftKind.merchantArchive,
      createdAt: _clock(),
      title: metadataField == 'name' && operation == 'update'
          ? nameMatch!.group(2)!.trim()
          : target.name,
      note: metadataField == 'details' && operation == 'update'
          ? noteMatch!.group(2)!.trim()
          : target.details,
      formValues: {
        'entity': 'merchant',
        'targetId': target.id,
        'operation': operation,
        'metadataField': metadataField,
        'targetSummary': target.name,
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'update'
          ? 'Aku menyiapkan perubahan ${metadataField == 'details' ? 'keterangan' : 'nama'} satu Toko/Tempat. Transaksi historis tidak akan diubah. Cek preview dulu.'
          : operation == 'delete'
          ? 'Aku menyiapkan hapus permanen satu Toko/Tempat. Data akan dihapus total dari database. Tindakan ini tidak dapat dibatalkan. Cek preview dulu.'
          : 'Aku menyiapkan arsip lunak satu Toko/Tempat. Data tidak akan muncul di transaksi baru, tetapi transaksi historis tetap utuh. Cek preview dulu.',
    );
  }

  Future<FfmAssistantIntent?> _parseTagMutation(
    String rawText,
    String normalized,
  ) async {
    final update = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+tag\s+(.+?)\s+(?:jadi|menjadi)\s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(r'^(?:arsip|arsipkan)\s+tag\s+(.+)$')
        .firstMatch(normalized);
    final delete = RegExp(r'^(?:hapus|buang|hilangkan)\s+tag\s+(.+)$')
        .firstMatch(normalized);
    if (update == null && archive == null && delete == null) return null;

    final operation = delete != null
        ? 'delete'
        : (update == null ? 'archive' : 'update');
    final targetText =
        (update?.group(1) ?? archive?.group(1) ?? delete!.group(1)!).trim();
    final rows =
        await (_database.select(_database.tags)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isArchived.equals(false),
            ))
            .get();
    final terms = targetText
        .split(RegExp(r'\s+'))
        .where((term) => term.length >= 3)
        .toList();
    final candidates = rows
        .where((row) => terms.every(row.name.toLowerCase().contains))
        .take(4)
        .toList(growable: false);
    final type = operation == 'update'
        ? FfmAssistantIntentType.updateTag
        : operation == 'delete'
        ? FfmAssistantIntentType.deleteTag
        : FfmAssistantIntentType.archiveTag;
    if (candidates.length != 1) {
      final detail = candidates.isEmpty
          ? 'Aku tidak menemukan satu Tag aktif yang cocok dengan “$targetText”.'
          : 'Aku menemukan ${candidates.length} Tag yang cocok: ${candidates.map((row) => row.name).join('; ')}.';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: candidates.isEmpty ? .8 : .72,
        clarification:
            '$detail Sebut nama Tag yang lebih spesifik. Belum ada Tag atau relasi transaksi yang diubah.',
      );
    }

    final target = candidates.single;
    final draft = FfmAssistantDraft(
      kind: operation == 'update'
          ? FfmAssistantDraftKind.tagUpdate
          : operation == 'delete'
          ? FfmAssistantDraftKind.tagDelete
          : FfmAssistantDraftKind.tagArchive,
      createdAt: _clock(),
      title: operation == 'update' ? update!.group(2)!.trim() : target.name,
      formValues: {
        'entity': 'tag',
        'targetId': target.id,
        'operation': operation,
        'targetSummary': target.name,
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'update'
          ? 'Aku menyiapkan perubahan nama satu Tag. Relasi Tag pada transaksi tidak akan diubah. Cek preview dulu.'
          : operation == 'delete'
          ? 'Aku menyiapkan hapus permanen satu Tag. Data akan dihapus total dari database. Tindakan ini tidak dapat dibatalkan. Cek preview dulu.'
          : 'Aku menyiapkan arsip lunak satu Tag. Tag tidak akan muncul pada pilihan baru, tetapi relasi pada transaksi historis tetap utuh. Cek preview dulu.',
    );
  }

  Future<FfmAssistantIntent?> _parseIncomeSourceMutation(
    String rawText,
    String normalized,
  ) async {
    const noun = r'sumber\s+(?:pemasukan|pendapatan)';
    final updateName = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+' +
          noun +
          r'\s+(.+?)\s+(?:jadi|menjadi)\s+(.+)$',
    ).firstMatch(normalized);
    final updateNote = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+(?:keterangan|catatan)\s+' +
          noun +
          r'\s+(.+?)\s+(?:jadi|menjadi)\s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(r'^(?:arsip|arsipkan)\s+' + noun + r'\s+(.+)$')
        .firstMatch(normalized);
    final delete = RegExp(r'^(?:hapus|buang|hilangkan)\s+' + noun + r'\s+(.+)$')
        .firstMatch(normalized);
    if (updateName == null &&
        updateNote == null &&
        archive == null &&
        delete == null) {
      return null;
    }

    final operation = delete != null
        ? 'delete'
        : (updateName == null && updateNote == null ? 'archive' : 'update');
    final metadataField = updateNote == null ? 'name' : 'details';
    final targetText =
        (updateName?.group(1) ??
                updateNote?.group(1) ??
                archive?.group(1) ??
                delete!.group(1)!)
            .trim();
    final rows =
        await (_database.select(_database.transactionParties)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.kind.equals('income_source') &
                  row.isArchived.equals(false),
            ))
            .get();
    final terms = targetText
        .split(RegExp(r'\s+'))
        .where((term) => term.length >= 3)
        .toList();
    final candidates = rows
        .where((row) => terms.every(row.name.toLowerCase().contains))
        .take(4)
        .toList(growable: false);
    final type = operation == 'update'
        ? FfmAssistantIntentType.updateIncomeSource
        : operation == 'delete'
        ? FfmAssistantIntentType.deleteIncomeSource
        : FfmAssistantIntentType.archiveIncomeSource;
    if (candidates.length != 1) {
      final detail = candidates.isEmpty
          ? 'Aku tidak menemukan satu Sumber Pemasukan aktif yang cocok dengan “$targetText”.'
          : 'Aku menemukan ${candidates.length} Sumber Pemasukan yang cocok: ${candidates.map((row) => row.name).join('; ')}.';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: candidates.isEmpty ? .8 : .72,
        clarification:
            '$detail Sebut nama sumber yang lebih spesifik. Belum ada sumber atau transaksi yang diubah.',
      );
    }

    final target = candidates.single;
    final draft = FfmAssistantDraft(
      kind: operation == 'update'
          ? FfmAssistantDraftKind.incomeSourceUpdate
          : operation == 'delete'
          ? FfmAssistantDraftKind.incomeSourceDelete
          : FfmAssistantDraftKind.incomeSourceArchive,
      createdAt: _clock(),
      title: metadataField == 'name' && operation == 'update'
          ? updateName!.group(2)!.trim()
          : target.name,
      note: metadataField == 'details' && operation == 'update'
          ? updateNote!.group(2)!.trim()
          : target.details,
      formValues: {
        'entity': 'income_source',
        'targetId': target.id,
        'operation': operation,
        'metadataField': metadataField,
        'targetSummary': target.name,
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'update'
          ? 'Aku menyiapkan perubahan ${metadataField == 'details' ? 'keterangan' : 'nama'} satu Sumber Pemasukan. Tidak ada sourceId transaksi yang diubah. Cek preview dulu.'
          : operation == 'delete'
          ? 'Aku menyiapkan hapus permanen satu Sumber Pemasukan. Data akan dihapus total dari database. Tindakan ini tidak dapat dibatalkan. Cek preview dulu.'
          : 'Aku menyiapkan arsip lunak satu Sumber Pemasukan. Sumber tidak muncul di input baru, tetapi transaksi historis tetap utuh. Cek preview dulu.',
    );
  }

  Future<FfmAssistantIntent?> _parseCategoryMutation(
    String rawText,
    String normalized,
  ) async {
    final update = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+(?:nama\s+)?kategori\s+(.+?)\s+(?:jadi|menjadi)\s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(r'^(?:arsip|arsipkan)\s+kategori\s+(.+)$')
        .firstMatch(normalized);
    final delete = RegExp(r'^(?:hapus|buang|hilangkan)\s+kategori\s+(.+)$')
        .firstMatch(normalized);
    if (update == null && archive == null && delete == null) return null;

    final operation = delete != null
        ? 'delete'
        : (update == null ? 'archive' : 'update');
    final targetText =
        (update?.group(1) ?? archive?.group(1) ?? delete!.group(1)!).trim();
    final rows =
        await (_database.select(_database.categories)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final terms = targetText
        .split(RegExp(r'\s+'))
        .where((term) => term.length >= 3)
        .toList();
    final candidates = rows
        .where((row) => terms.every(row.name.toLowerCase().contains))
        .take(4)
        .toList(growable: false);
    final type = operation == 'update'
        ? FfmAssistantIntentType.updateCategory
        : operation == 'delete'
        ? FfmAssistantIntentType.deleteCategory
        : FfmAssistantIntentType.archiveCategory;
    if (candidates.length != 1) {
      final detail = candidates.isEmpty
          ? 'Aku tidak menemukan satu Kategori aktif yang cocok dengan “$targetText”.'
          : 'Aku menemukan ${candidates.length} Kategori yang cocok: ${candidates.map((row) => row.name).join('; ')}.';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: candidates.isEmpty ? .8 : .72,
        clarification:
            '$detail Sebut nama Kategori yang lebih spesifik. Belum ada kategori, transaksi, atau Anggaran yang diubah.',
      );
    }

    final target = candidates.single;
    final draft = FfmAssistantDraft(
      kind: operation == 'update'
          ? FfmAssistantDraftKind.categoryUpdate
          : operation == 'delete'
          ? FfmAssistantDraftKind.categoryDelete
          : FfmAssistantDraftKind.categoryArchive,
      createdAt: _clock(),
      title: operation == 'update' ? update!.group(2)!.trim() : target.name,
      formValues: {
        'entity': 'category',
        'targetId': target.id,
        'operation': operation,
        'targetSummary': target.name,
        'protectedType': target.type,
        'protectedParentId': target.parentId ?? '',
        'protectedDefaultBudgetPeriod': target.defaultBudgetPeriod,
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'update'
          ? 'Aku menyiapkan perubahan nama satu Kategori. Tipe, hierarki, periode Anggaran, transaksi, dan Anggaran tidak akan diubah. Cek preview dulu.'
          : operation == 'delete'
          ? 'Aku menyiapkan hapus permanen satu Kategori. Data akan dihapus total dari database. Tindakan ini tidak dapat dibatalkan. Cek preview dulu.'
          : 'Aku menyiapkan arsip lunak satu Kategori. Guard akan memeriksa subkategori, transaksi berkala, Target Keuangan, dan Anggaran aktif sebelum ada perubahan. Cek preview dulu.',
    );
  }

  Future<FfmAssistantIntent?> _parseAccountMutation(
    String rawText,
    String normalized,
  ) async {
    final update = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+(?:nama\s+)?rekening\s+(.+?)\s+(?:jadi|menjadi)\s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(r'^(?:arsip|arsipkan)\s+rekening\s+(.+)$')
        .firstMatch(normalized);
    final delete = RegExp(r'^(?:hapus|buang|hilangkan)\s+rekening\s+(.+)$')
        .firstMatch(normalized);
    if (update == null && archive == null && delete == null) return null;

    final operation = delete != null
        ? 'delete'
        : (update == null ? 'archive' : 'update');
    final targetText =
        (update?.group(1) ?? archive?.group(1) ?? delete!.group(1)!).trim();
    final rows =
        await (_database.select(_database.accounts)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isActive.equals(true) &
                  row.isArchived.equals(false),
            ))
            .get();
    final terms = targetText
        .split(RegExp(r'\s+'))
        .where((term) => term.length >= 3)
        .toList();
    final candidates = rows
        .where(
          (row) =>
              terms.isNotEmpty && terms.every(row.name.toLowerCase().contains),
        )
        .take(4)
        .toList(growable: false);
    final type = operation == 'update'
        ? FfmAssistantIntentType.updateAccount
        : operation == 'delete'
        ? FfmAssistantIntentType.deleteAccount
        : FfmAssistantIntentType.archiveAccount;
    if (candidates.length != 1) {
      final detail = candidates.isEmpty
          ? 'Aku tidak menemukan satu Rekening aktif yang cocok dengan “$targetText”.'
          : 'Aku menemukan ${candidates.length} Rekening yang cocok: ${candidates.map((row) => row.name).join('; ')}.';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: candidates.isEmpty ? .8 : .72,
        clarification:
            '$detail Sebut nama Rekening yang lebih spesifik. Belum ada saldo, transaksi, transfer, atau data Rekening yang diubah.',
      );
    }

    final target = candidates.single;
    final draft = FfmAssistantDraft(
      kind: operation == 'update'
          ? FfmAssistantDraftKind.accountUpdate
          : operation == 'delete'
          ? FfmAssistantDraftKind.accountDelete
          : FfmAssistantDraftKind.accountArchive,
      createdAt: _clock(),
      title: operation == 'update' ? update!.group(2)!.trim() : target.name,
      formValues: {
        'entity': 'account',
        'targetId': target.id,
        'operation': operation,
        'targetSummary': target.name,
        'protectedId': target.id,
        'protectedHouseholdId': target.householdId,
        'protectedType': target.type,
        'protectedOpeningBalance': target.openingBalance.toString(),
        'protectedIsActive': target.isActive.toString(),
        'protectedCreatedAt': target.createdAt.toIso8601String(),
        'protectedArchiveResult': (operation == 'archive').toString(),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'update'
          ? 'Aku menyiapkan perubahan nama satu Rekening. Saldo awal, tipe, status aktif, dan seluruh referensi transaksi/transfer tidak akan diubah. Cek preview dulu.'
          : operation == 'delete'
          ? 'Aku menyiapkan hapus permanen satu Rekening. Data akan dihapus total dari database. Tindakan ini tidak dapat dibatalkan. Cek preview dulu.'
          : 'Aku menyiapkan arsip lunak satu Rekening. Arsip hanya boleh jika Rekening belum pernah dipakai transaksi, transfer, transaksi berkala, atau rekonsiliasi. Cek preview dulu.',
    );
  }

  /// Deteksi isyarat periode anggaran dari kalimat user. Hanya isyarat
  /// eksplisit yang dipetakan (mingguan/bulanan/tidak rutin); tanpa isyarat,
  /// periode mengikuti filter halaman atau default kategori di form.
  String? _budgetPeriodType(String normalized) {
    if (RegExp(r'\b(tidak rutin|tak rutin|sekali saja|non.?rutin)\b')
        .hasMatch(normalized)) {
      return 'nonrecurring';
    }
    if (RegExp(r'\b(mingguan|per minggu|tiap minggu|setiap minggu)\b')
        .hasMatch(normalized)) {
      return 'weekly';
    }
    if (RegExp(
      r'\b(bulanan|per bulan|perbulan|tiap bulan|setiap bulan|sebulan)\b',
    ).hasMatch(normalized)) {
      return 'monthly';
    }
    return null;
  }

  Future<FfmAssistantIntent?> _parseBudgetMutation(
    String rawText,
    String normalized,
  ) async {
    final update = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+(?:batas\s+)?anggaran\s+(.+?)\s+(?:jadi|menjadi|ke)\s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(r'^(?:arsip|arsipkan)\s+(?:pos\s+)?anggaran\s+(.+)$')
        .firstMatch(normalized);
    final create = RegExp(r'^(?:atur|buat|tambah|set)\s+anggaran\b')
        .hasMatch(normalized);
    if (update == null && archive == null) {
      if (!create) return null;
      final amount = FfmAssistantAmountParser.parse(normalized);
      if (amount == null || amount <= 0) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.createBudget,
          confidence: .7,
          destination: FfmAssistantDestination.budget,
          clarification: 'Sebut batas Anggaran yang ingin dibuat, misalnya: “atur anggaran makan 350 ribu”. Belum ada data yang diubah.',
        );
      }
      final categories =
          await (_database.select(_database.categories)..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isActive.equals(true) &
                    row.type.equals('expense'),
              ))
              .get();
      final categoryCandidates = categories
          .where((row) => normalized.contains(row.name.trim().toLowerCase()))
          .toList(growable: false);
      final category = categoryCandidates.length == 1
          ? categoryCandidates.single
          : null;
      final periodType = _budgetPeriodType(normalized);
      final periodLabel = switch (periodType) {
        'weekly' => ' mingguan',
        'monthly' => ' bulanan',
        'nonrecurring' => ' tidak rutin',
        _ => '',
      };
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.budget,
        createdAt: _clock(),
        amount: amount,
        title: category?.name ?? 'Anggaran keseluruhan',
        categoryName: category?.name,
        note: rawText.trim(),
        date: _clock(),
        formValues: {if (periodType case final String p) 'periodType': p},
      );
      return _intentForDraft(rawText, normalized, draft).copyWith(
        response: category == null
            ? 'Aku menyiapkan batas Anggaran$periodLabel keseluruhan ${_money(amount)}. Cek preview dulu sebelum mengisi dan menyimpannya.'
            : 'Aku menyiapkan batas Anggaran$periodLabel ${category.name} sebesar ${_money(amount)}. Cek preview dulu sebelum mengisi dan menyimpannya.',
      );
    }

    final operation = update == null ? 'archive' : 'update';
    final targetText = (update?.group(1) ?? archive!.group(1)!).trim();
    final amount = update == null
        ? null
        : FfmAssistantAmountParser.parse(update.group(2)!);
    final type = operation == 'update'
        ? FfmAssistantIntentType.updateBudget
        : FfmAssistantIntentType.archiveBudget;
    if (operation == 'update' && (amount == null || amount <= 0)) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: .7,
        clarification: 'Sebut batas Anggaran baru setelah kata “jadi”, misalnya: “ubah batas anggaran makan jadi 750 ribu”. Belum ada data yang diubah.',
      );
    }
    final candidates = await _findBudgetCandidates(targetText);
    if (candidates.length != 1) {
      final detail = candidates.isEmpty
          ? 'Aku tidak menemukan satu pos Anggaran aktif yang memenuhi syarat dengan nama “$targetText”.'
          : 'Aku menemukan ${candidates.length} pos Anggaran yang cocok: ${candidates.map((row) => row.name).join('; ')}.';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: candidates.isEmpty ? .8 : .72,
        clarification:
            '$detail Sebut nama pos yang lebih spesifik. Pos total, gabungan, nonrutin, atau di luar periode berjalan tidak dapat ditargetkan. Belum ada data yang diubah.',
      );
    }

    final target = candidates.single;
    final category =
        await (_database.select(_database.categories)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.id.equals(target.categoryId!),
            ))
            .getSingleOrNull();
    final draft = FfmAssistantDraft(
      kind: operation == 'update'
          ? FfmAssistantDraftKind.budgetUpdate
          : FfmAssistantDraftKind.budgetArchive,
      createdAt: _clock(),
      amount: amount,
      title: target.name,
      categoryName: category?.name,
      date: target.endDate,
      formValues: {
        'entity': 'budget',
        'targetId': target.id,
        'operation': operation,
        'targetSummary': target.name,
        'protectedId': target.id,
        'protectedHouseholdId': target.householdId,
        'protectedName': target.name,
        'protectedCategoryId': target.categoryId ?? '',
        'protectedCategoryIdsJson': target.categoryIdsJson,
        'protectedMonth': target.month ?? '',
        'protectedPeriodType': target.periodType,
        'protectedStartDate': target.startDate.toIso8601String(),
        'protectedEndDate': target.endDate.toIso8601String(),
        'protectedRollover': target.rollover.toString(),
        'protectedAlertPercent': target.alertPercent.toString(),
        'protectedIsActive': target.isActive.toString(),
        'protectedCreatedAt': target.createdAt.toIso8601String(),
        'protectedArchiveResult': (operation == 'archive').toString(),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'update'
          ? 'Aku menyiapkan perubahan batas satu pos Anggaran. Preview akan menghitung sisa sebelum dan sesudah; rollover, kategori, periode, transaksi, dan transfer alokasi tidak akan diubah.'
          : 'Aku menyiapkan arsip lunak satu pos Anggaran. Guard akan menolak bila ada transaksi pemakaian atau transfer alokasi. Cek preview dulu.',
    );
  }

  Future<List<EnvelopeBudget>> _findBudgetCandidates(String targetText) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where(
          (term) =>
              term.length >= 3 &&
              !const {
                'anggaran',
                'batas',
                'pos',
                'rupiah',
                'ribu',
              }.contains(term) &&
              !RegExp(r'^\d+$').hasMatch(term),
        )
        .toSet();
    if (terms.isEmpty) return const [];
    final now = DateTime(_clock().year, _clock().month, _clock().day);
    final categories =
        await (_database.select(_database.categories)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isActive.equals(true) &
                  row.type.equals('expense'),
            ))
            .get();
    final activeCategoryIds = categories.map((row) => row.id).toSet();
    final rows =
        await (_database.select(_database.envelopeBudgets)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    return rows
        .where((row) {
          final categoryIds = _budgetCategoryIds(row);
          final start = DateTime(
            row.startDate.year,
            row.startDate.month,
            row.startDate.day,
          );
          final end = DateTime(
            row.endDate.year,
            row.endDate.month,
            row.endDate.day,
          );
          return !row.id.startsWith('overall-') &&
              categoryIds.length == 1 &&
              activeCategoryIds.contains(categoryIds.single) &&
              const {
                'weekly',
                'biweekly',
                'monthly',
                'bimonthly',
                'fourmonthly',
                'fivemonthly',
              }.contains(row.periodType) &&
              !now.isBefore(start) &&
              !now.isAfter(end) &&
              terms.every(row.name.toLowerCase().contains);
        })
        .take(4)
        .toList(growable: false);
  }

  Set<String> _budgetCategoryIds(EnvelopeBudget budget) {
    try {
      final value = jsonDecode(budget.categoryIdsJson);
      if (value is! List) return const <String>{};
      return value.whereType<String>().toSet();
    } on FormatException {
      return const <String>{};
    }
  }

  Future<FfmAssistantIntent?> _parseGoalMutation(
    String rawText,
    String normalized,
  ) async {
    final update = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+(?:target|goal)(?:\s+keuangan)?\s+(.+?)\s+(?:jadi|menjadi|ke)\s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(
      r'^(?:arsip|arsipkan)\s+(?:target|goal)(?:\s+keuangan)?\s+(.+)$',
    ).firstMatch(normalized);
    if (update == null && archive == null) return null;

    final operation = update == null ? 'archive' : 'update';
    final targetText = (update?.group(1) ?? archive!.group(1)!).trim();
    final amount = update == null
        ? null
        : FfmAssistantAmountParser.parse(update.group(2)!);
    if (operation == 'update' && (amount == null || amount <= 0)) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.updateGoal,
        confidence: .7,
        clarification: 'Sebut nominal target baru setelah kata “jadi”, misalnya: “ubah target dana darurat jadi 5000000”. Belum ada data yang diubah.',
      );
    }
    final candidates = await _findGoalCandidates(targetText);
    if (candidates.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: operation == 'update'
            ? FfmAssistantIntentType.updateGoal
            : FfmAssistantIntentType.archiveGoal,
        confidence: .8,
        clarification:
            'Aku tidak menemukan satu target keuangan aktif yang cocok dengan “$targetText”. Sebut nama target yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    if (candidates.length > 1) {
      final options = candidates.take(3).map(_goalCandidateLabel).join('; ');
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: operation == 'update'
            ? FfmAssistantIntentType.updateGoal
            : FfmAssistantIntentType.archiveGoal,
        confidence: .72,
        clarification:
            'Aku menemukan ${candidates.length} target yang cocok: $options. Sebut nama target yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final draft = FfmAssistantDraft(
      kind: operation == 'update'
          ? FfmAssistantDraftKind.goalUpdate
          : FfmAssistantDraftKind.goalArchive,
      createdAt: _clock(),
      amount: amount,
      title: _goalCandidateLabel(target),
      date: target.targetDate,
      formValues: {
        'entity': 'goal',
        'targetId': target.id,
        'operation': operation,
        'oldTargetAmount': target.targetAmount.toString(),
        'currentAmount': target.currentAmount.toString(),
        'targetSummary': _goalCandidateLabel(target),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'update'
          ? 'Aku menemukan satu target dan menyiapkan perubahan dari ${_money(target.targetAmount)} menjadi ${_money(amount!)}. Cek preview dulu; belum ada data yang diubah.'
          : 'Aku menemukan satu target untuk diarsipkan. Progresnya tetap tersimpan; cek preview dulu sebelum mengonfirmasi.',
    );
  }

  Future<List<Goal>> _findGoalCandidates(String targetText) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where(
          (term) =>
              term.length >= 3 &&
              !const {
                'target',
                'goal',
                'keuangan',
                'pada',
                'tanggal',
                'ribu',
                'rupiah',
              }.contains(term) &&
              !RegExp(r'^\d+$').hasMatch(term),
        )
        .toSet();
    if (terms.isEmpty) return const [];
    final rows =
        await (_database.select(_database.goals)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isActive.equals(true),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.targetDate)]))
            .get();
    return rows
        .where((row) => terms.every(row.name.toLowerCase().contains))
        .take(4)
        .toList(growable: false);
  }

  String _goalCandidateLabel(Goal row) =>
      '${row.name} • ${_money(row.currentAmount)} dari ${_money(row.targetAmount)}';

  Future<FfmAssistantIntent?> _parseTransactionMutation(
    String rawText,
    String normalized,
  ) async {
    final update = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+transaksi\s+(.+?)\s+(?:jadi|menjadi|ke)\s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(r'^(?:arsip|arsipkan)\s+transaksi\s+(.+)$')
        .firstMatch(normalized);
    final delete = RegExp(r'^hapus\s+transaksi\s+(.+)$').firstMatch(normalized);
    if (update == null && archive == null && delete == null) return null;

    final operation = update != null
        ? 'update'
        : archive != null
        ? 'archive'
        : 'delete';
    final targetText =
        (update?.group(1) ?? archive?.group(1) ?? delete!.group(1)!).trim();
    final amount = update == null
        ? null
        : FfmAssistantAmountParser.parse(update.group(2)!);
    if (operation == 'update' && (amount == null || amount <= 0)) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.updateTransaction,
        confidence: .7,
        clarification: 'Sebut nominal baru setelah kata “jadi”, misalnya: “ubah transaksi kopi jadi 25000”. Belum ada data yang diubah.',
      );
    }
    final candidates = await _findTransactionCandidates(targetText);
    if (candidates.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: _mutationIntentType(operation),
        confidence: .8,
        clarification:
            'Aku tidak menemukan satu transaksi aktif yang cocok dengan “$targetText”. Sebut kata pada catatan atau pihak transaksi. Belum ada data yang diubah.',
      );
    }
    if (candidates.length > 1) {
      final options = candidates
          .take(3)
          .map(_transactionCandidateLabel)
          .join('; ');
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: _mutationIntentType(operation),
        confidence: .72,
        clarification:
            'Aku menemukan ${candidates.length} transaksi yang cocok: $options. Sebut kata catatan yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final kind = switch (operation) {
      'update' => FfmAssistantDraftKind.transactionUpdate,
      'archive' => FfmAssistantDraftKind.transactionArchive,
      _ => FfmAssistantDraftKind.transactionDelete,
    };
    final draft = FfmAssistantDraft(
      kind: kind,
      createdAt: _clock(),
      amount: amount,
      title: _transactionCandidateLabel(target),
      note: target.note,
      date: target.date,
      formValues: {
        'targetId': target.id,
        'operation': operation,
        'oldAmount': target.amount.abs().toString(),
        'targetSummary': _transactionCandidateLabel(target),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'update'
          ? 'Aku menemukan satu transaksi dan menyiapkan perubahan dari ${_money(target.amount.abs())} menjadi ${_money(amount!)}. Cek preview dulu; belum ada data yang diubah.'
          : operation == 'archive'
          ? 'Aku menemukan satu transaksi untuk diarsipkan. Cek preview dulu; transaksi belum dipindahkan dari daftar aktif.'
          : 'Aku menemukan satu transaksi untuk dihapus dari daftar aktif. Cek preview dulu; jejak audit lokal tetap dipertahankan.',
    );
  }

  FfmAssistantIntentType _mutationIntentType(String operation) =>
      switch (operation) {
        'update' => FfmAssistantIntentType.updateTransaction,
        'archive' => FfmAssistantIntentType.archiveTransaction,
        _ => FfmAssistantIntentType.deleteTransaction,
      };

  Future<List<Transaction>> _findTransactionCandidates(
    String targetText,
  ) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where(
          (term) =>
              term.length >= 3 &&
              !const {
                'transaksi',
                'pada',
                'tanggal',
                'ribu',
                'rupiah',
              }.contains(term) &&
              !RegExp(r'^\d+$').hasMatch(term),
        )
        .toSet();
    if (terms.isEmpty) return const [];
    final rows =
        await (_database.select(_database.transactions)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isArchived.equals(false) &
                    row.isDeleted.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.date)]))
            .get();
    return rows
        .where((row) {
          final haystack = '${row.note ?? ''} ${row.partyName ?? ''}'
              .toLowerCase();
          return terms.every(haystack.contains);
        })
        .take(4)
        .toList(growable: false);
  }

  String _transactionCandidateLabel(Transaction row) {
    final kind = row.type == 'income' ? 'pemasukan' : 'pengeluaran';
    final detail = (row.note ?? row.partyName ?? 'tanpa catatan').trim();
    final date = row.date.toIso8601String().substring(0, 10);
    return '$kind ${_money(row.amount.abs())} • $detail • $date';
  }

  String _money(int amount) =>
      'Rp${amount.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => '.')}';

  FfmAssistantDraft? _parseFinancialDraft(
    String rawText,
    String normalized,
    List<Account> accounts,
    List<Category> categories, {
    FfmAssistantDestination? currentDestination,
    ActivityLiveSnapshot? activitySnapshot,
  }) {
    final now = DateTime.now();
    final amount = FfmAssistantAmountParser.parse(normalized);
    final adminFee = _parseAdminFee(normalized);
    final createBudget = _containsAny(normalized, const [
      'atur anggaran',
      'buat anggaran',
      'tambah anggaran',
      'set anggaran',
    ]);
    if (createBudget) {
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.budget,
        createdAt: now,
        amount: amount,
        title: _draftTitle(normalized, const [
          'atur anggaran',
          'buat anggaran',
          'tambah anggaran',
          'set anggaran',
        ]),
        note: rawText.trim(),
        date: now,
      );
    }
    final masterData = _masterDataRequest(normalized);
    if (masterData != null) {
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.masterData,
        createdAt: now,
        title: _draftTitle(normalized, masterData.$2),
        categoryName: masterData.$1,
        note: rawText.trim(),
        date: now,
      );
    }
    final createProfile = _containsAny(normalized, const [
      'buat profil',
      'isi profil',
      'ubah profil',
      'perbarui profil',
      'kenalan',
    ]);
    if (createProfile) {
      final profileValues = _extractProfileValues(rawText);
      final profileNote = profileValues.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.profile,
        createdAt: now,
        title: 'Perkenalan Diri',
        note: profileNote.isEmpty ? rawText.trim() : profileNote,
        formValues: profileValues,
        date: now,
      );
    }
    final dailyNote = RegExp(
      r'^(?:catat|tulis|buat)(?:kan)?\s+(?:catatan harian|catatan)\s*[:\-]?\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    if (dailyNote != null) {
      final body = dailyNote.group(1)?.trim() ?? '';
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.dailyNote,
        createdAt: now,
        note: body,
        date: now,
        formValues: {'body': body},
      );
    }
    final explicitCreateActivity = _containsAny(normalized, const [
      'mulai aktivitas',
      'mulai kegiatan',
      'catat aktivitas',
      'buat aktivitas',
    ]);
    // Intent finansial eksplisit (pemasukan/pengeluaran/transfer) tetap menang
    // meskipun user berada di halaman Aktivitas. Page context hanya untuk
    // tie-breaker ketika maksud benar-benar ambigu, bukan untuk mengubah
    // intent eksplisit menjadi aktivitas.
    final explicitTransactionIntent = _containsAny(normalized, const [
      'pemasukan',
      'uang masuk',
      'pengeluaran',
      'uang keluar',
      'terima',
      'menerima',
      'gaji',
      'pendapatan',
      'beli',
      'belanja',
      'bayar',
      'transfer',
      'pindah uang',
      'kirim uang',
    ]);
    final modeDecision = const ActivityModeDetector().detect(rawText);
    final contextualCreateActivity =
        currentDestination == FfmAssistantDestination.activity &&
        !modeDecision.requiresClarification &&
        !explicitTransactionIntent;
    final createActivity = explicitCreateActivity || contextualCreateActivity;
    if (createActivity) {
      final title = explicitCreateActivity
          ? _draftTitle(normalized, const [
              'mulai aktivitas',
              'mulai kegiatan',
              'catat aktivitas',
              'buat aktivitas',
            ])
          : rawText.trim().replaceFirst(
              RegExp(r'^(?:saya|aku)\s+', caseSensitive: false),
              '',
            );
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.activity,
        createdAt: now,
        title: title,
        note: rawText.trim(),
        date: now,
        formValues: {
          'activityMode': modeDecision.mode.value,
          'kind': modeDecision.mode.activityKind.value,
        },
      );
    }
    final createReminder = _containsAny(normalized, const [
      'buat pengingat',
      'tambah pengingat',
      'ingatkan saya',
      'pasang pengingat',
    ]);
    
    // Detect bill reminder patterns for calendar sync
    final billReminder = _containsAny(normalized, const [
      'tagihan listrik',
      'tagihan air',
      'tagihan internet',
      'tagihan bpjs',
      'tagihan indihome',
      'tagihan pulsa',
      'tagihan cicilan',
      'tagihan pdam',
      'tagihan gas',
      'tagihan tv kabel',
      'bayar listrik',
      'bayar bpjs',
      'bayar indihome',
      'bayar pdam',
      'bayar gas',
      'bayar cicilan',
      'jatuh tempo',
      'due date',
      'tanggal jatuh tempo',
      'cicilan motor',
      'cicilan mobil',
      'cicilan rumah',
      'kredit',
      'pinjaman',
    ]);
    
    if (createReminder || billReminder) {
      final title = _draftTitle(normalized, const [
        'buat pengingat',
        'tambah pengingat',
        'ingatkan saya',
        'pasang pengingat',
        'tagihan',
        'bayar',
      ]);
      
      final note = billReminder 
          ? '${rawText.trim()}\n\n[Sinkronisasi ke kalender dan smartwatch aktif]' 
          : rawText.trim();
      
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.reminder,
        createdAt: now,
        title: title,
        note: note,
        date: now.add(const Duration(hours: 1)),
        metadata: billReminder 
            ? {'calendar_sync': true, 'is_bill_reminder': true} 
            : null,
      );
    }
    final asset = _containsAny(normalized, const [
      'tambah aset',
      'buat aset',
      'catat aset',
    ]);
    if (asset) {
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.asset,
        createdAt: now,
        amount: amount,
        title: _draftTitle(normalized, const [
          'tambah aset',
          'buat aset',
          'catat aset',
        ]),
        note: rawText.trim(),
        date: now,
      );
    }
    final createGoal = _containsAny(normalized, const [
      'target baru',
      'buat target',
      'buatkan target',
    ]);
    if (createGoal) {
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.goal,
        createdAt: now,
        amount: amount,
        title: _draftTitle(normalized, const [
          'target baru',
          'buatkan target',
          'buat target',
        ]),
        note: rawText.trim(),
        date: now.add(const Duration(days: 30)),
      );
    }
    final transfer = _containsAny(normalized, const [
      'pindahkan',
      'pindah uang',
      'transfer',
      'kirim uang',
      'geser uang',
      'cairkan',
      'isi saldo',
      'top up',
      'topup',
      'tambah saldo',
    ]);
    if (transfer) {
      final fromTo = _parseTransferAccounts(normalized, accounts);
      var from = fromTo.$1;
      var to = fromTo.$2;
      // Top-up ("isi saldo gopay", "top up gopay dari bca") menyebut tujuan
      // lebih dulu; sumber menyusul setelah kata "dari". Bila sumber tidak
      // disebut, tujuan tetap diisi dan validator meminta rekening asal —
      // tidak ditebak diam-diam.
      if (from == null || to == null) {
        from ??= _matchAccountAfterMarker(normalized, accounts, 'dari');
        final mentioned = _mentionedAccounts(normalized, accounts);
        Account? firstOther(Account? exclude) => mentioned
            .where((account) => account.id != exclude?.id)
            .firstOrNull;
        to ??= firstOther(from);
      }
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.transfer,
        createdAt: now,
        amount: amount,
        fromAccountName: from?.name,
        toAccountName: to?.name,
        adminFee: adminFee,
        note: rawText.trim(),
        date: now,
      );
    }

    final goalUsage = _containsAny(normalized, const [
      'pakai target',
      'pakai uang target',
      'pakai dana target',
      'ambil dari target',
      'tarik dari target',
      'tarik dana target',
      'tarik target',
      'gunakan target',
      'gunakan dana target',
    ]);
    if (goalUsage) {
      final goalName =
          _draftTitle(normalized, const ['target', 'dana target']) ??
          _extractAfter(normalized, const ['target', 'dana target']);
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.goalUsage,
        createdAt: now,
        amount: amount,
        goalName: goalName,
        note: rawText.trim(),
        date: now,
      );
    }
    final goalDeposit = _containsAny(normalized, const [
      'untuk target',
      'ke target',
      'buat target',
      'setor target',
      'setor ke target',
      'isi target',
      'isi ke target',
      'masukkan ke target',
      'masukan ke target',
      'tambah target',
      'tambah ke target',
      'simpan target',
      'tabung target',
      'nabung target',
      'menabung target',
      'alokasi target',
      'alokasikan target',
    ]);
    if (goalDeposit) {
      final goalName =
          _draftTitle(normalized, const [
            'untuk target',
            'ke target',
            'buat target',
            'setor target',
            'isi target',
            'target',
          ]) ??
          _extractAfter(normalized, const [
            'untuk target',
            'ke target',
            'buat target',
            'setor target',
            'isi target',
            'target',
          ]);
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.goalDeposit,
        createdAt: now,
        amount: amount,
        goalName: goalName,
        note: rawText.trim(),
        date: now,
      );
    }

    final isDebtPayment = _containsAny(normalized, const [
      'bayar hutang',
      'bayar utang',
      'cicil hutang',
      'cicil utang',
      'bayar cicilan',
      'lunasi hutang',
      'lunasi utang',
      'pelunasan hutang',
      'pelunasan utang',
    ]);
    final isReceivableReceipt = _containsAny(normalized, const [
      'terima piutang',
      'terima pembayaran piutang',
      'piutang dibayar',
      'bayar piutang',
    ]);
    if (isDebtPayment) {
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.liabilityPayment,
        createdAt: now,
        amount: amount,
        title: 'Pembayaran Hutang',
        partyName: _extractParty(normalized, const ['hutang', 'utang']),
        fromAccountName: _matchAccount(normalized, accounts)?.name,
        note: rawText.trim(),
        date: now,
        formValues: {'entity': 'liability'},
      );
    }
    if (isReceivableReceipt) {
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.receivablePayment,
        createdAt: now,
        amount: amount,
        title: 'Penerimaan Piutang',
        partyName: _extractParty(normalized, const ['piutang']),
        toAccountName: _matchAccount(normalized, accounts)?.name,
        note: rawText.trim(),
        date: now,
        formValues: {'entity': 'receivable'},
      );
    }

    final isReceivable = !isReceivableReceipt && _containsAny(normalized, const [
      'piutang',
      'pinjam uang dari saya',
      'minjam uang dari saya',
      'meminjam dari saya',
    ]);
    if (isReceivable) {
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.receivable,
        createdAt: now,
        amount: amount,
        partyName: _extractParty(normalized, const [
          'piutang ke',
          'pinjam uang',
        ]),
        note: rawText.trim(),
        date: now,
      );
    }
    final isLiability = !isDebtPayment && _containsAny(normalized, const [
      'hutang',
      'utang',
      'saya pinjam dari',
      'saya meminjam dari',
    ]);
    if (isLiability) {
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.liability,
        createdAt: now,
        amount: amount,
        partyName: _extractParty(normalized, const [
          'hutang ke',
          'utang ke',
          'pinjam dari',
        ]),
        note: rawText.trim(),
        date: now,
      );
    }

    final income = isReceivableReceipt || _containsAny(normalized, const [
      'pemasukan',
      'uang masuk',
      'terima',
      'menerima',
      'gaji',
      'pendapatan',
      'hasil panen',
      'terjual',
      'dapat uang',
      'dapet uang',
      'dikasih uang',
    ]);
    final expense = isDebtPayment || _containsAny(normalized, const [
      'pengeluaran',
      'uang keluar',
      'beli',
      'belanja',
      'bayar',
      'jajan',
      'dibeli',
      'keluar uang',
      'bayarin',
    ]);
    if (!income && !expense) return null;
    final transactionType = income && !expense ? 'income' : 'expense';
    final category = _matchCategory(normalized, categories, transactionType);
    final selectedAccount = _matchAccount(normalized, accounts);
    final merchantName = _extractMerchant(normalized);

    var categoryName = category?.name;
    if (categoryName == null && merchantName != null) {
      categoryName = _personalMemoryService.feedbackService
          .findCategoryForMerchant(merchantName);
    }

    var fromAccountName = expense ? selectedAccount?.name : null;
    if (fromAccountName == null && expense) {
      fromAccountName =
          _personalMemoryService.feedbackService.findPreferredAccount();
    }

    final slmFieldValues = <String, String>{};
    if (categoryName != null) {
      slmFieldValues['category'] = categoryName;
    }
    if (selectedAccount != null) {
      slmFieldValues['account'] = selectedAccount.name;
    } else if (fromAccountName != null) {
      slmFieldValues['account'] = fromAccountName;
    }
    return FfmAssistantDraft(
      kind: income && !expense
          ? FfmAssistantDraftKind.income
          : FfmAssistantDraftKind.expense,
      createdAt: now,
      amount: amount,
      categoryName: categoryName,
      toAccountName: income ? selectedAccount?.name : null,
      fromAccountName: fromAccountName,
      note: rawText.trim(),
      partyName: income
          ? _extractParty(normalized, const ['dari', 'sumber'])
          : _extractParty(normalized, const [
              'dipakai oleh',
              'dipakai',
              'untuk',
              'oleh',
            ]),
      merchantName: merchantName,
      location: _extractLocation(normalized),
      slmFieldValues: slmFieldValues,
      linkedActivityId: activitySnapshot?.activeSessions.lastOrNull?.id,
      date: now,
    );
  }

  FfmAssistantIntent? _parseCorrection(String rawText, String normalized) {
    final match = RegExp(
      r'^(?:ganti|ubah|koreksi)\s+(.+?)\s+(?:jadi|menjadi|ke)\s+(.+)$',
    ).firstMatch(normalized);
    if (match == null) return null;
    final oldText = match.group(1)!.trim();
    final newText = match.group(2)!.trim();
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.replaceDraftText,
      confidence: .95,
      response:
          'Siap, aku akan mengganti “$oldText” menjadi “$newText” di draft yang sedang aktif. Cek hasilnya sebelum disimpan, ya.',
    );
  }

  FfmAssistantIntent? _parseUserProfileMemory(
    String rawText,
    String normalized,
  ) {
    final match = RegExp(
      r'^(?:nama saya|panggil saya|panggil aku|ingat nama saya)\s+(.+)$',
    ).firstMatch(normalized);
    final displayName = match
        ?.group(1)
        ?.trim()
        .replaceAll(RegExp(r'[.!?]+$'), '');
    if (displayName == null || displayName.isEmpty || displayName.length > 80) {
      return null;
    }
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.teachMemory,
      confidence: .98,
      response:
          'Aku bisa mengingat bahwa kamu ingin dipanggil “$displayName”. Cek dulu lalu pilih Simpan ajaran jika sudah pas, ya.',
      teachingProposal: FfmAssistantTeachingProposal(
        kind: 'user_profile',
        triggerText: 'nama_panggilan',
        valueText: displayName,
      ),
    );
  }

  FfmAssistantIntent? _parseAliasMemory(String rawText, String normalized) {
    final match = RegExp(
      r'^(?:ingat|simpan)\s+(?:alias\s+)?(.+?)\s+(?:itu|=|sebagai)\s+(.+)$',
    ).firstMatch(normalized);
    if (match == null) return null;
    final alias = match.group(1)?.trim();
    final canonical = match.group(2)?.trim();
    if (alias == null ||
        canonical == null ||
        alias.isEmpty ||
        canonical.isEmpty) {
      return null;
    }
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.teachMemory,
      confidence: .95,
      response:
          'Aku menangkap ajaran ini: “$alias” berarti “$canonical”. Cek dulu lalu pilih Simpan ajaran kalau sudah pas, ya.',
      teachingProposal: FfmAssistantTeachingProposal(
        kind: 'alias',
        triggerText: alias,
        valueText: canonical,
      ),
    );
  }

  (Account?, Account?) _parseTransferAccounts(
    String normalized,
    List<Account> accounts,
  ) {
    final match = RegExp(r'\bdari\s+(.+?)\s+ke\s+(.+?)(?:\s+admin\b|$)')
        .firstMatch(normalized);
    if (match == null) return (null, null);
    return (
      _matchAccount(match.group(1)!, accounts),
      _matchAccount(match.group(2)!, accounts),
    );
  }

  Account? _matchAccountAfterMarker(
    String text,
    List<Account> accounts,
    String marker,
  ) {
    final match = RegExp(
      '\\b$marker\\s+([a-z0-9][a-z0-9 .&-]{1,60})',
    ).firstMatch(text);
    if (match == null) return null;
    return _matchAccount(match.group(1)!, accounts);
  }

  /// Semua rekening yang namanya disebut di teks, tanpa duplikat.
  /// Dipakai top-up/transfer yang menyebut tujuan dulu ("top up gopay
  /// ... dari bca") agar arah dana tidak terbalik.
  List<Account> _mentionedAccounts(String text, List<Account> accounts) {
    final seen = <String>{};
    final result = <Account>[];
    for (final account in accounts) {
      final name = account.name.trim().toLowerCase();
      if (name.isNotEmpty && text.contains(name) && seen.add(account.id)) {
        result.add(account);
      }
    }
    return result;
  }

  Account? _matchAccount(String text, List<Account> accounts) {
    final matches = accounts.where(
      (account) => text.contains(account.name.toLowerCase()),
    );
    if (matches.isNotEmpty) return matches.first;
    final normalizedText = text.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final typoMatches = accounts.where(
      (account) => FfmAssistantTypoNormalizer.isSafeNearMatch(
        normalizedText,
        account.name.toLowerCase(),
      ),
    );
    if (typoMatches.length == 1) return typoMatches.single;
    final trigramMatches =
        accounts
            .map((account) {
              final score = FfmAssistantTypoNormalizer.trigramSimilarity(
                normalizedText,
                account.name.toLowerCase(),
              );
              return (account, score);
            })
            .where((entry) => entry.$2 >= 0.5)
            .toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));
    if (trigramMatches.length == 1) return trigramMatches.single.$1;
    return null;
  }

  Category? _matchCategory(
    String text,
    List<Category> categories,
    String type,
  ) {
    final candidates = categories
        .where((item) => item.type == type)
        .where((item) {
          final name = item.name.toLowerCase().trim();
          return name.length > 2 && text.contains(name);
        })
        .toList(growable: false);
    if (candidates.length == 1) return candidates.single;
    if (candidates.length > 1) return null;
    final normalizedText = text.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final trigramMatches =
        categories
            .where((item) => item.type == type)
            .map((item) {
              final score = FfmAssistantTypoNormalizer.trigramSimilarity(
                normalizedText,
                item.name.toLowerCase(),
              );
              return (item, score);
            })
            .where((entry) => entry.$2 >= 0.5)
            .toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));
    if (trigramMatches.length == 1) return trigramMatches.single.$1;
    return null;
  }

  /// Ekstrak kandidat nama entitas (noun phrase) dari teks normalisasi.
  /// Mengembalikan token/2-gram selain angka, kata kerja umum, dan preposisi.
  List<String> _extractCandidateEntityTerms(String normalized) {
    final stopWords = {
      'saya',
      'aku',
      'kamu',
      'dia',
      'kami',
      'mereka',
      'ini',
      'itu',
      'yang',
      'dan',
      'atau',
      'dengan',
      'untuk',
      'dari',
      'ke',
      'di',
      'pada',
      'ada',
      'adalah',
      'akan',
      'sudah',
      'belum',
      'bisa',
      'mau',
      'mohon',
      'tolong',
      'please',
      'kira',
      'kurang',
      'lebih',
      'total',
      'semua',
      'seluruh',
      'bagian',
      'sebagian',
      'catat',
      'tambah',
      'simpan',
      'transfer',
      'bayar',
      'beli',
      'jual',
      'hutang',
      'piutang',
      'ubah',
      'edit',
      'hapus',
      'batal',
      'rekening',
      'akun',
      'bank',
      'kategori',
      'tag',
      'metode',
      'uang',
      'transaksi',
      'ribu',
      'juta',
      'rb',
      'jt',
      'rp',
      'idr',
      'pagi',
      'siang',
      'sore',
      'malam',
      'hari',
      'buka',
      'lihat',
      'cek',
      'tampilkan',
      'cari',
    };
    final tokens = normalized
        .replaceAll(RegExp(r'[0-9]+'), '')
        // Hapus "rp" sebagai kata utuh + titik seribu — JANGAN kelas [rp.]
        // yang ikut memakan huruf r/p di dalam kata ("gopay"→"goay").
        .replaceAll(RegExp(r'\brp\b'), '')
        .replaceAll('.', ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 3 && !stopWords.contains(t))
        .toList();
    final terms = <String>{};
    for (final token in tokens) {
      terms.add(token);
    }
    for (var i = 0; i < tokens.length - 1; i++) {
      final bigram = '${tokens[i]} ${tokens[i + 1]}';
      if (!stopWords.contains(tokens[i]) &&
          !stopWords.contains(tokens[i + 1])) {
        terms.add(bigram);
      }
    }
    return terms.toList()..sort((a, b) => b.length.compareTo(a.length));
  }

  /// Heuristik ringan: apakah term ini terlihat seperti nama sumber dana/kategori
  /// (bukan kata kerja/preposisi/angka umum).
  bool _looksLikeFinancialSourceTerm(String term) {
    if (term.length < 3) return false;
    final commonVerbs = {
      'catat',
      'tambah',
      'simpan',
      'transfer',
      'bayar',
      'beli',
      'jual',
      'ubah',
      'edit',
      'hapus',
      'batal',
      'kirim',
      'terima',
      'ambil',
      'tarik',
      'setor',
      'pinjam',
      'kembalikan',
      'lunasi',
    };
    final commonPrepositions = {
      'dari',
      'dengan',
      'untuk',
      'ke',
      'di',
      'pada',
      'dalam',
      'oleh',
      'karena',
      'sebagai',
      'antara',
      'sampai',
    };
    if (commonVerbs.contains(term)) return false;
    if (commonPrepositions.contains(term)) return false;
    if (RegExp(r'^\d+$').hasMatch(term)) return false;
    return true;
  }

  int? _parseAdminFee(String text) {
    final match = RegExp(r'(?:admin|biaya admin|fee)\s+(?:rp\s*)?([\w. ,]+)')
        .firstMatch(text);
    return match == null
        ? null
        : FfmAssistantAmountParser.parse(match.group(1)!);
  }

  FfmAssistantPage? _parseDestination(String normalized) =>
      FfmAssistantCatalog.findByText(normalized);

  bool _isAmbiguousLoan(String text) =>
      _containsAny(text, const ['pinjam', 'minjam', 'meminjam']) &&
      !_containsAny(text, const [
        'hutang',
        'utang',
        'piutang',
        'dari saya',
        'saya pinjam',
        'saya meminjam',
      ]);

  bool _isTransactionStats(String text) => _containsAny(text, const [
    'berapa transaksi',
    'jumlah transaksi',
    'total transaksi',
    'transaksi ada berapa',
    'ada berapa catatan',
  ]);

  bool _isWeeklyAnalysisRequest(String text) => _containsAny(text, const [
    'data minggu',
    'analisa minggu',
    'analisis minggu',
    'pengeluaran minggu',
    'pemasukan minggu',
    'minggu lalu gimana',
    'minggu ini gimana',
  ]);

  bool _isSetupRequest(String text) => _containsAny(text, const [
    'harus mulai dari mana',
    'mulai dari mana',
    'sekarang saya harus apa',
    'sekarang harus apa',
    'sekarang harus ngapain',
    'selanjutnya apa',
    'langkah selanjutnya apa',
    'pertamakali saya harus apa',
    'pertama kali saya harus apa',
    'pertama kali harus apa',
    'harus apa pertama kali',
    'baru buka aplikasi',
    'awal pakai',
    'cara pakai ffm',
    'cara menggunakan ffm',
    'setup awal',
    'pengaturan awal',
    'pertama kali pakai',
    'data utama kosong',
    'data saya kosong',
    'data kosong',
    'data utama belum ada',
    'apa yang harus diisi dulu',
    'isi data utama dulu',
    'cek data utama',
  ]);
  bool _isKnownFfmFeatureGap(String text) => _containsAny(text, const [
    'rekonsiliasi',
    'cadangan',
    'backup',
    'pemulihan',
    'export',
    'ekspor',
    'lampiran',
    'nota',
    'json',
    'ocr',
    'model lokal',
    'slm',
    'notifikasi',
    'nada dering',
    'widget',
    'pelatihan',
    'pengetahuan asisten',
  ]);

  /// Membangun konteks keuangan personal berdasarkan data aktual pengguna.
  /// Digunakan untuk memberikan respons yang lebih kontekstual dan personal.

  Future<String> _buildPersonalFinancialContext() async {
    try {
      final evidence = await _financialSnapshot.readCurrentMonth(
        householdId: AppContext.householdId,
        now: _clock(),
      );
      final income = evidence.income;
      final expenses = evidence.expenses;
      if (income == 0 && expenses == 0) {
        return 'Data keuangan bulan ini belum cukup untuk analisis personal.';
      }
      final parts = <String>[];
      if (income > 0) {
        final savingsRate = income > expenses
            ? ((income - expenses) / income * 100).round()
            : 0;
        parts.add(
          'Pemasukan bulan ini ${_formatRupiah(income)}, pengeluaran ${_formatRupiah(expenses)}.',
        );
        if (savingsRate > 0) {
          parts.add('Saving rate kamu $savingsRate%.');
          if (savingsRate < 20) {
            parts.add('(Idealnya minimal 20% untuk tabungan jangka panjang.)');
          } else {
            parts.add('(Lumayan bagus! Di atas target 20%.)');
          }
        } else {
          parts.add(
            'Cashflow bulan ini negatif — pengeluaran melebihi pemasukan.',
          );
        }
      }
      if (evidence.currentInstallments > 0) {
        final dti = income > 0
            ? (evidence.currentInstallments / income * 100).round()
            : 0;
        parts.add(
          'Cicilan aktif ${_formatRupiah(evidence.currentInstallments)}/bulan.',
        );
        if (dti > 35) {
          parts.add(
            '(Rasio cicilan $dti% dari pemasukan — cukup tinggi, idealnya di bawah 35%.)',
          );
        } else if (dti > 0) {
          parts.add('(Rasio cicilan $dti% dari pemasukan — masih aman.)');
        }
      }
      return parts.isEmpty ? '' : parts.join(' ');
    } on Object {
      return '';
    }
  }

  bool _isDraftHelpRequest(String text) => _containsAny(text, const [
    'fungsi draft',
    'draft buat apa',
    'rancangan buat apa',
    'apa itu draft',
    'apa itu rancangan',
    'kenapa ada draft',
    'kenapa ada rancangan',
  ]);

  bool _isFinancialWarningRequest(String text) => _containsAny(text, const [
    'cek anggaran',
    'cek budget',
    'anggaran hampir habis',
    'anggaran yang hampir habis',
    'apakah ada anggaran',
    'budget hampir habis',
    'mendekati batas',
    'pemakaian cepat',
    'kondisi keuangan',
    'peringatan keuangan',
    'ada peringatan',
    'ada warning',
    'anggaran aman',
    'anggaran saya',
    'budget saya',
    'arus kas saya',
  ]);

  bool _isReadRequest(String text) =>
      _containsAny(text, const ['baca', 'ulang']);

  bool _isHijriDateRequest(String text) => _containsAny(text, const [
    'hijriah',
    'hijriyah',
    'hijri',
    'hijrah',
    'islam',
    'tanggal hijri',
    'tanggal islam',
    'kalender islam',
    'tahun baru hijri',
    'awal muharram',
    'ramadhan',
    'puasa',
    'bulan puasa',
    'idul fitri',
    'lebaran',
    'syawal',
    'idul adha',
    'haji raya',
    'zulhijjah',
  ]);

  int? _parseRelativeDays(String text) {
    // Match patterns like "50 hari ke depan", "100 hari ke belakang", "7 hari kedepan"
    final forwardPattern = RegExp(
      r'(\d+)\s+hari\s+(ke\s+depan|kedepan)',
      caseSensitive: false,
    );
    final backwardPattern = RegExp(
      r'(\d+)\s+hari\s+(ke\s+belakang|kebelakang)',
      caseSensitive: false,
    );

    final forwardMatch = forwardPattern.firstMatch(text);
    if (forwardMatch != null) {
      final days = int.tryParse(forwardMatch.group(1) ?? '');
      return days;
    }

    final backwardMatch = backwardPattern.firstMatch(text);
    if (backwardMatch != null) {
      final days = int.tryParse(backwardMatch.group(1) ?? '');
      return days != null ? -days : null;
    }

    return null;
  }

  String? _parseHijriEventQuery(String text) {
    if (_containsAny(text, const [
      'tahun baru hijri',
      'awal muharram',
      '1 muharram',
    ])) {
      return 'muharram_1';
    }
    if (_containsAny(text, const ['ramadhan', 'puasa', 'bulan puasa'])) {
      return 'ramadhan_1';
    }
    if (_containsAny(text, const ['idul fitri', 'lebaran', 'syawal'])) {
      return 'syawal_1';
    }
    if (_containsAny(text, const ['idul adha', 'haji raya', 'zulhijjah'])) {
      return 'zulhijjah_10';
    }
    return null;
  }

  Future<FfmAssistantIntent> _handleHijriEventQuery(
    String rawText,
    String normalized,
    String event,
  ) async {
    final now = _clock();
    int targetHijriMonth;
    int targetHijriDay;

    switch (event) {
      case 'muharram_1':
        targetHijriMonth = 1;
        targetHijriDay = 1;
        break;
      case 'ramadhan_1':
        targetHijriMonth = 9;
        targetHijriDay = 1;
        break;
      case 'syawal_1':
        targetHijriMonth = 10;
        targetHijriDay = 1;
        break;
      case 'zulhijjah_10':
        targetHijriMonth = 12;
        targetHijriDay = 10;
        break;
      default:
        targetHijriMonth = 1;
        targetHijriDay = 1;
    }

    // Get current hijri date
    final currentHijri = await HijriCalendarService(_database)
        .convert(AppContext.householdId, now);

    // Calculate days until event
    // This is a simplified calculation - in production, use proper hijri calendar library
    final currentMonth = currentHijri.hijri.month.toInt();
    final currentDay = currentHijri.hijri.day.toInt();

    int daysUntilEvent;
    if (targetHijriMonth > currentMonth) {
      // Event is in same hijri year
      daysUntilEvent =
          ((targetHijriMonth - currentMonth) * 30 +
                  (targetHijriDay - currentDay))
              .toInt();
    } else if (targetHijriMonth < currentMonth) {
      // Event is in next hijri year
      daysUntilEvent =
          ((12 - currentMonth + targetHijriMonth) * 30 +
                  (targetHijriDay - currentDay))
              .toInt();
    } else {
      // Same month
      if (targetHijriDay >= currentDay) {
        daysUntilEvent = targetHijriDay - currentDay;
      } else {
        // Event already passed this year, next year
        daysUntilEvent = (354 + (targetHijriDay - currentDay)).toInt();
      }
    }

    String eventName;
    switch (event) {
      case 'muharram_1':
        eventName = 'Tahun Baru Hijriah (1 Muharram)';
        break;
      case 'ramadhan_1':
        eventName = 'Awal Ramadhan (1 Ramadhan)';
        break;
      case 'syawal_1':
        eventName = 'Idul Fitri (1 Syawal)';
        break;
      case 'zulhijjah_10':
        eventName = 'Idul Adha (10 Zulhijjah)';
        break;
      default:
        eventName = 'event';
    }

    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.calendarQuery,
      confidence: 1,
      response:
          '$eventName masih $daysUntilEvent hari lagi. Perhitungan ini mengikuti Kalender Hijriah FFM di perangkat kamu.',
    );
  }

  String _formatHijriDate(HijriDisplayDate date) {
    const months = <String>[
      'Muharam',
      'Safar',
      'Rabiulawal',
      'Rabiulakhir',
      'Jumadilawal',
      'Jumadilakhir',
      'Rajab',
      'Syakban',
      'Ramadan',
      'Syawal',
      'Zulkaidah',
      'Zulhijah',
    ];
    final month = date.hijri.month.clamp(1, months.length);
    return '${date.hijri.day} ${months[month - 1]} ${date.hijri.year} H';
  }

  String? _extractAfter(String text, List<String> markers) {
    for (final marker in markers) {
      final index = text.indexOf(marker);
      if (index >= 0) {
        final rest = text.substring(index + marker.length).trim();
        if (rest.isNotEmpty) return rest;
      }
    }
    return null;
  }

  String? _draftTitle(String text, List<String> markers) {
    final extracted = _extractAfter(text, markers);
    if (extracted == null) return null;
    final title = extracted
        .replaceFirst(RegExp(r'\b(?:senilai|sebesar|harga|nilai|rp)\b.*$'), '')
        .replaceFirst(RegExp(r'\b\d[\d.,]*(?:\s*(?:ribu|juta|jt))?.*$'), '')
        .trim();
    return title.isEmpty ? null : title.split(' ').map(_capitalize).join(' ');
  }

  List<String> _masterDataDraftNames(String text, List<String> markers) {
    final extracted = _extractAfter(text, markers);
    if (extracted == null) return const [];
    final cleaned = extracted
        .replaceFirst(RegExp(r'\b(?:senilai|sebesar|harga|nilai|rp)\b.*$'), '')
        .replaceFirst(RegExp(r'\b\d[\d.,]*(?:\s*(?:ribu|juta|jt))?.*$'), '')
        .trim();
    if (cleaned.isEmpty) return const [];
    return cleaned
        .split(RegExp(r'\s*(?:,|;|\bdan\b|\bserta\b)\s*'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map((item) => item.split(' ').map(_capitalize).join(' '))
        .toSet()
        .toList(growable: false);
  }

  (String, List<String>)? _masterDataRequest(String text) {
    const candidates = <(String, List<String>)>[
      (
        'profil',
        [
          'atur keluarga',
          'atur profil keluarga',
          'ubah nama keluarga',
          'edit profil',
        ],
      ),
      (
        'rekening',
        [
          'tambah rekening',
          'buat rekening',
          'tambahkan rekening',
          'buatkan rekening',
          'bikin rekening',
          'rekening baru',
        ],
      ),
      (
        'kategori',
        [
          'tambah kategori',
          'buat kategori',
          'tambahkan kategori',
          'buatkan kategori',
          'bikin kategori',
          'kategori baru',
        ],
      ),
      (
        'toko',
        [
          'tambah toko',
          'buat toko',
          'tambah tempat',
          'tambahkan toko',
          'buatkan toko',
          'bikin toko',
          'toko baru',
        ],
      ),
      (
        'tag',
        [
          'tambah tag',
          'buat tag',
          'tambahkan tag',
          'buatkan tag',
          'bikin tag',
          'tag baru',
        ],
      ),
      (
        'sumber_pemasukan',
        [
          'tambah sumber pemasukan',
          'buat sumber pemasukan',
          'tambahkan sumber pemasukan',
          'buatkan sumber pemasukan',
          'bikin sumber pemasukan',
          'sumber pemasukan baru',
        ],
      ),
    ];
    for (final candidate in candidates) {
      if (_containsAny(text, candidate.$2)) return candidate;
    }
    return null;
  }

  String _masterDataTargetName(String? target) => switch (target) {
    'profil' => 'Profil keluarga',
    'rekening' => 'Tambah rekening',
    'toko' => 'Tambah toko atau tempat',
    'tag' => 'Tambah tag',
    'sumber_pemasukan' => 'Tambah sumber pemasukan',
    _ => 'Tambah kategori',
  };

  String? _extractMerchant(String text) {
    final match = RegExp(
      r'\b(?:di|pada)\s+([a-z0-9][a-z0-9 .&-]{1,80}?)(?=\s+(?:sebesar|senilai|rp|harga|untuk|dengan|hari ini|kemarin|besok)\b|\s+[0-9]|$)',
    ).firstMatch(text);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty
        ? null
        : value.split(' ').map(_capitalize).join(' ');
  }

  /// Lokasi disamakan dengan kolom database transactions.location +
  /// form transaksi. Pola eksplisit "lokasi ..." agar tidak bentrok
  /// dengan ekstraksi merchant ("di/pada ...").
  String? _extractLocation(String text) {
    final match = RegExp(
      r'\blokas(?:i|inya)\s+([a-z0-9][a-z0-9 .&-]{1,80}?)(?=\s+(?:sebesar|senilai|rp|harga|untuk|dengan|hari ini|kemarin|besok)\b|\s+[0-9]|$)',
    ).firstMatch(text);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty
        ? null
        : value.split(' ').map(_capitalize).join(' ');
  }

  String? _extractParty(String text, List<String> markers) {
    for (final marker in markers) {
      final match = RegExp(
        '$marker\\s+([a-z ]+?)(?=\\s+(?:sebesar|senilai|rp|[0-9]|nol|satu|dua|tiga|empat|lima|enam|tujuh|delapan|sembilan|sepuluh|sebelas|seratus|seribu)|\$)',
      ).firstMatch(text);
      if (match != null && match.group(1)!.trim().isNotEmpty) {
        return match.group(1)!.trim().split(' ').map(_capitalize).join(' ');
      }
    }
    return null;
  }

  String _capitalize(String word) =>
      word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}';

  String _formatRupiah(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    return 'Rp$buffer';
  }

  Future<void> _recordGeminiUsage({
    required String code,
    required String model,
    required bool ok,
    int? httpStatus,
    Duration? latency,
    GeminiUsageMetadata? usageMetadata,
  }) async {
    try {
      await _config.saveGeminiUsage(
        code: code,
        model: model,
        ok: ok,
        at: _clock(),
        httpStatus: httpStatus,
        latency: latency,
        usageMetadata: usageMetadata,
      );
    } on Object {
      // Diagnostik tidak boleh mengubah jawaban atau memutus alur chatbot.
    }
  }

  FfmAssistantIntent _cloudError(
    String raw,
    String normalized,
    String message, {
    required String model,
    int? statusCode,
  }) => FfmAssistantIntent(
    rawText: raw,
    normalizedText: normalized,
    type: FfmAssistantIntentType.unknown,
    confidence: 0,
    response: 'Maaf, saya belum bisa menjawab itu. $message',
    clarification: 'Maaf, saya belum bisa menjawab itu. $message',
    responseOrigin: FfmAssistantResponseOrigin.cloudError,
    pluginName: 'gemini_cloud_error',
    pluginCategory: '☁ Gemini · $model',
    pluginMetadata: {'model': model, 'statusCode': statusCode},
  );

  /// Ubah pesan error teknis dari parser proposal menjadi pesan yang ramah
  /// untuk pengguna. Detail teknis asli tetap dipertahankan agar tidak
  /// menghilangkan informasi, tetapi tidak pernah dibocorkan mentah ke UX.
  String _friendlyProposalError(String technicalError) {
    final lowered = technicalError.toLowerCase();
    if (lowered.contains('jenis proposal') ||
        lowered.contains('proposal_kind') ||
        lowered.contains('master_data, transaction')) {
      return 'Aku belum paham jenis permintaan itu. Sebutkan dengan kalimat biasa, misalnya "catat pengeluaran 50 ribu untuk makan".';
    }
    if (lowered.contains('json proposal') || lowered.contains('markdown')) {
      return 'Aku menerima permintaan yang formatnya tidak bisa kubaca. Coba tulis ulang dengan kalimat biasa yang lebih sederhana.';
    }
    if (lowered.contains('objek “proposal”') || lowered.contains('objek proposal')) {
      return 'Aku belum bisa membaca isi permintaan itu. Silakan coba lagi dengan kalimat yang lebih jelas.';
    }
    return 'Aku belum bisa menangani permintaan itu dengan benar. Silakan urai ulang maksudmu dengan kalimat biasa, atau beri tahu apa yang ingin kamu lakukan dan nominalnya bila ada.';
  }

  /// Catat detail teknis kegagalan ke diagnostics tanpa memblokir alur chat.
  /// Dipakai agar pesan ramah ke user tidak menghilangkan informasi debug.
  void _logAssistantFailure({
    required String code,
    required String technical,
    required String impact,
  }) {
    unawaited(
      _diagnostics.recordException(
        code: code,
        feature: 'assistant',
        error: technical,
        impact: impact,
      ),
    );
  }

  /// Saring pesan error mentah dari Gemini Cloud sebelum tampil ke user.
  /// Error kontrak capability internal (ID capability, format argumen JSON,
  /// rentang tanggal) adalah urusan model-vs-aplikasi, bukan user, sehingga
  /// diganti pesan ramah. Pesan yang memang sudah user-friendly diteruskan.
  String _friendlyCloudError(String rawMessage) {
    final lowered = rawMessage.toLowerCase();
    final isCapabilityContract =
        lowered.contains('capability') ||
        lowered.contains('read.summary') ||
        lowered.contains('read.transactions') ||
        lowered.contains('argumen capability') ||
        lowered.contains('json request capability');
    if (!isCapabilityContract) return rawMessage;
    _logAssistantFailure(
      code: 'gemini-capability-contract',
      technical: rawMessage,
      impact: 'Gemini meminta capability baca di luar kontrak; diblokir aman.',
    );
    return 'Aku gagal membaca data pendukung untuk menjawab karena permintaan tidak diizinkan atau data tidak dapat dibaca dengan aman. Coba ulangi permintaanmu dengan kalimat yang lebih sederhana.';
  }

  FfmAssistantIntent _unknown(
    String raw,
    String normalized,
    String response, {
    FfmAssistantResponseOrigin responseOrigin =
        FfmAssistantResponseOrigin.agentOrchestrator,
  }) {
    _maybeSaveUnansweredQuestion(raw, normalized);
    final enriched = _enrichUnknownResponse(normalized, response);
    return FfmAssistantIntent(
      rawText: raw,
      normalizedText: normalized,
      type: FfmAssistantIntentType.unknown,
      confidence: 0,
      response: enriched,
      clarification: enriched,
      responseOrigin: responseOrigin,
    );
  }

  Future<void> _maybeSaveUnansweredQuestion(
    String raw,
    String normalized,
  ) async {
    final trimmed = normalized.trim();
    if (trimmed.length < 5) return;
    if (_containsAny(trimmed, const [
      'tes',
      'test',
      'ping',
      'halo',
      'hai',
      'hello',
      'hi',
      'hei',
    ])) {
      return;
    }
    if (_unsupportedQuestionHelp(trimmed) != null) {
      return;
    }
    if (_isKnownFfmFeatureGap(trimmed)) {
      return;
    }
    final existing = await _taughtMemory.findFuzzyAnswer(trimmed);
    if (existing != null) return;
    try {
      await _taughtMemory.save(
        kind: 'answer',
        triggerText: trimmed,
        valueText: 'Belum terjawab: $raw',
        metadata: {'status': 'unanswered', 'source': 'assistant_observation'},
      );
    } on Object {
      // Memory write is best-effort; never block the response.
    }
  }

  String _enrichUnknownResponse(String normalized, String base) {
    final suggestions = <String>[
      '• **Catat transaksi** — contoh: *"catat beli makan 25rb"*',
      '• **Cek ringkasan** — contoh: *"berapa saldo sekarang"*',
      '• **Buka halaman** — contoh: *"buka Anggaran"*',
    ];
    final isOutOfDomain =
        _unsupportedQuestionHelp(normalized) != null ||
        _containsAny(normalized, const [
          'cuaca',
          'harga pasar',
          'berita',
          'google',
          'internet',
          'resep',
          'olahraga',
          'film',
          'musik',
          'jodoh',
          'zodiak',
          'shio',
          'saham',
          'emas',
          'kurs',
          'bitcoin',
          'crypto',
          'trading',
          'forex',
        ]);
    if (isOutOfDomain) {
      return '$base\n\nAku khusus untuk keuangan keluarga FFM. Coba salah satu:\n${suggestions.join('\n')}';
    }
    final hasAmount = FfmAssistantAmountParser.parse(normalized) != null;
    final mentionsAccount = _containsAny(normalized, const [
      'rekening',
      'akun',
      'bank',
    ]);
    if (hasAmount && mentionsAccount) {
      return '$base\n\nKetik seperti *"catat beli sayur 50rb dari BCA"* agar aku bisa siapkan draft transaksi untuk kamu konfirmasi.';
    }
    return '$base\n\nCoba salah satu:\n${suggestions.join('\n')}';
  }

  String? _unsupportedQuestionHelp(String normalized) {
    // ── Kategori 1: Benar-benar di luar domain (butuh internet/data real-time)
    if (_containsAny(normalized, const [
      'cuaca',
      'harga pasar',
      'harga cabai',
      'berita terbaru',
      'cari di google',
      'internet',
      'resep masakan',
      'cara memasak',
      'olahraga',
      'skor bola',
      'jadwal pertandingan',
      'film',
      'musik',
      'lagu',
      'gadget terbaru',
      'hp terbaru',
      'jodoh',
      'ramalan bintang',
      'zodiak',
      'shio',
    ])) {
      return 'Untuk itu aku belum punya akses internet atau data real-time. Aku cuma bisa membaca data yang sudah tersimpan di FFM. Kalau mau, kamu bisa catat harga atau transaksi tersebut dulu sebagai draft.';
    }
    // ── Kategori 2: Terkait keuangan tapi di luar cakupan FFM
    if (_containsAny(normalized, const [
      'saham naik',
      'harga emas hari ini',
      'kurs dollar',
      'kurs rupiah',
      'bitcoin',
      'crypto',
      'trading',
      'forex',
    ])) {
      return 'Aku belum punya akses data pasar real-time. Yang bisa aku bantu adalah mencatat transaksi investasi yang sudah kamu lakukan di FFM. Kamu bisa catat pembelian emas, saham, atau aset lain sebagai aset di menu Aset.';
    }
    // ── Kategori 3: Pertanyaan personal non-keuangan
    if (_containsAny(normalized, const [
      'kabar',
      'kamu sehat',
      'kamu baik',
      'kamu sedih',
      'kamu senang',
      'umur kamu',
      'berapa umur',
      'tanggal lahir',
      'agama',
      'pacar',
      'menikah',
    ])) {
      return 'Terima kasih atas perhatiannya! Aku baik-baik saja. Aku adalah asisten keuangan lokal yang siap membantu pencatatan dan analisis keuangan keluarga. Ada yang bisa kubantu soal keuangan?';
    }
    // ── Kategori 4: Saldo bank asli
    if (_containsAny(normalized, const [
      'saldo bank asli',
      'cek saldo bank',
      'saldo rekening sekarang',
    ])) {
      return 'Aku belum terhubung langsung ke bank. Yang bisa aku baca hanya saldo dan transaksi yang sudah kamu catat atau impor ke FFM.';
    }
    // ── Kategori 5: Prediksi/Ramalan
    if (_containsAny(normalized, const [
      'ramal',
      'tebak',
      'prediksi pemasukan',
      'prediksi pengeluaran',
      'besok gajian',
    ])) {
      return 'Aku nggak mau nebak soal uang. Aku bisa bantu lihat pola dan data nyata yang sudah tercatat, tapi keputusan tetap kamu yang pegang.';
    }
    return null;
  }

  String _normalize(String text) {
    final cleaned = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9.,\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return FfmAssistantTypoNormalizer.correct(cleaned);
  }

  static final RegExp _greetingPattern = RegExp(
    r'\b(?:hallo|halo|hai|hello|hi|hei|assalamualaikum|assalamu alaikum|'
    r'selamat pagi|selamat siang|selamat sore|selamat malam|'
    r'tes|test|ping)\b',
  );

  bool _isGreetingWord(String text) => _greetingPattern.hasMatch(text);

  static final _greetingResponses = [
    'Halo! Ada yang bisa dibantu?',
    'Hai! Mau catat transaksi atau cek saldo?',
    'Halo! Silakan ketik perintahmu.',
    'Hai! Aku siap bantu.',
    'Halo! Ada yang perlu?',
    'Hai! Mau lihat data keuangan?',
    'Halo! Ketik saja apa yang perlu.',
    'Hai! Ada yang bisa kubantu?',
  ];

  String _randomGreeting() {
    final now = DateTime.now();
    final index = (now.millisecondsSinceEpoch % _greetingResponses.length)
        .toInt();
    return _greetingResponses[index];
  }

  bool _containsAny(String value, List<String> targets) =>
      targets.any(value.contains);

  /// Validates a draft from Gemini proposal against actual master data.
  /// If category/account names don't exist in the database, set them to null
  /// so the validator will flag them as missing.
  FfmAssistantDraft _validateGeminiDraft(
    FfmAssistantDraft draft,
    List<Account> accounts,
    List<Category> categories,
  ) {
    if (draft.kind != FfmAssistantDraftKind.expense &&
        draft.kind != FfmAssistantDraftKind.income &&
        draft.kind != FfmAssistantDraftKind.transfer) {
      return draft;
    }
    String? validatedCategory = draft.categoryName;
    if (validatedCategory != null && validatedCategory.isNotEmpty) {
      final matched = _matchCategory(
        validatedCategory.toLowerCase(),
        categories,
        draft.kind == FfmAssistantDraftKind.income ? 'income' : 'expense',
      );
      if (matched == null) {
        validatedCategory = null;
      } else {
        validatedCategory = matched.name;
      }
    }
    String? validatedFromAccount = draft.fromAccountName;
    if (validatedFromAccount != null && validatedFromAccount.isNotEmpty) {
      final matched = _matchAccount(
        validatedFromAccount.toLowerCase(),
        accounts,
      );
      if (matched == null) {
        validatedFromAccount = null;
      } else {
        validatedFromAccount = matched.name;
      }
    }
    String? validatedToAccount = draft.toAccountName;
    if (validatedToAccount != null && validatedToAccount.isNotEmpty) {
      final matched = _matchAccount(validatedToAccount.toLowerCase(), accounts);
      if (matched == null) {
        validatedToAccount = null;
      } else {
        validatedToAccount = matched.name;
      }
    }
    if (validatedCategory == draft.categoryName &&
        validatedFromAccount == draft.fromAccountName &&
        validatedToAccount == draft.toAccountName) {
      return draft;
    }
    return draft.copyWith(
      categoryName: validatedCategory,
      fromAccountName: validatedFromAccount,
      toAccountName: validatedToAccount,
    );
  }

  /// Generate verified facts for a query
  Future<String?> _generateVerifiedFactsForQuery(String normalized) async {
    try {
      final scope = FfmAssistantReasoningEvidencePolicy.forRequest(normalized);
      final facts = await _verifiedFactService.generateFacts(
        householdId: AppContext.householdId,
        scope: scope,
      );
      return facts.toLLMContext();
    } catch (_) {
      // If verified fact service fails, return null
      return null;
    }
  }
}

/// Hasil interpretasi yang bisa berisi satu atau banyak intent.
class _InterpretResult {
  const _InterpretResult.single(FfmAssistantIntent intent)
    : intents = const [],
      _single = intent;
  const _InterpretResult.multi(List<FfmAssistantIntent> intents)
    : _single = null,
      // ignore: prefer_initializing_formals, unnecessary_this
      this.intents = intents;

  final FfmAssistantIntent? _single;
  final List<FfmAssistantIntent> intents;

  List<FfmAssistantIntent> toList() => _single != null ? [_single] : intents;
}

abstract final class FfmAssistantAmountParser {
  static int? parse(String text) {
    final numeric = RegExp(
      r'(?:rp\s*)?(\d[\d.,]*)(?:\s*(ribu|rb|k|jt|juta|m|miliar)\b)?',
    ).allMatches(text);
    if (numeric.isNotEmpty) {
      final match = numeric.first;
      final rawNumber = match.group(1)!;
      final unit = match.group(2);
      final decimal =
          unit != null &&
          rawNumber.contains(',') &&
          !rawNumber.contains('.') &&
          rawNumber.split(',').last.length <= 2;
      final base = decimal
          ? double.tryParse(rawNumber.replaceAll(',', '.'))
          : double.tryParse(rawNumber.replaceAll(RegExp(r'[^0-9]'), ''));
      if (base != null) {
        return switch (match.group(2)) {
          'ribu' || 'rb' || 'k' => (base * 1000).round(),
          'jt' || 'juta' => (base * 1000000).round(),
          'm' || 'miliar' => (base * 1000000000).round(),
          _ => base.round(),
        };
      }
    }
    final tokens = text
        .replaceAll(RegExp(r'[^a-z\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    const digits = <String, int>{
      'nol': 0,
      'satu': 1,
      'dua': 2,
      'tiga': 3,
      'empat': 4,
      'lima': 5,
      'enam': 6,
      'tujuh': 7,
      'delapan': 8,
      'sembilan': 9,
    };

    // Parsa satu "ruas" angka tanpa skala ribuan/jutaan/miliaran di ekornya.
    // Contoh: ["dua","ratus","lima","puluh"] -> 250; ["satu","setengah"] -> 1.5.
    num parseChunkValue(List<String> words) {
      var chunkTotal = 0.0;
      for (var index = 0; index < words.length; index++) {
        final token = words[index];
        final next = index + 1 < words.length ? words[index + 1] : null;
        if (token == 'setengah') {
          chunkTotal += .5;
        } else if (digits.containsKey(token)) {
          var value = digits[token]!.toDouble();
          if (next == 'puluh') {
            value *= 10;
            index++;
          } else if (next == 'belas') {
            value += 10;
            index++;
          } else if (next == 'ratus') {
            value *= 100;
            index++;
          }
          chunkTotal += value;
        } else if (token == 'sepuluh' || token == 'sebelas') {
          chunkTotal += token == 'sepuluh' ? 10 : 11;
        } else if (token == 'seratus') {
          chunkTotal += 100;
        } else if (token == 'puluh') {
          chunkTotal += 10;
        } else if (token == 'ratus') {
          chunkTotal += 100;
        }
      }
      return chunkTotal;
    }

    var total = 0.0;
    var chunk = <String>[];
    var foundScale = false;
    var chunkHasNumeral = false;

    void flushScale(num scale) {
      final value = parseChunkValue(chunk);
      total += (value == 0 ? 1 : value) * scale;
      chunk = <String>[];
      foundScale = true;
    }

    for (var index = 0; index < tokens.length; index++) {
      final token = tokens[index];
      final next = index + 1 < tokens.length ? tokens[index + 1] : null;
      if (token == 'ribu' || token == 'seribu') {
        flushScale(1000);
      } else if (token == 'juta' || token == 'sejuta') {
        flushScale(1000000);
      } else if (token == 'miliar' || token == 'semiliar') {
        flushScale(1000000000);
      } else if (token == 'setengah' &&
          next != null &&
          const ['ribu', 'juta', 'miliar'].contains(next)) {
        chunk.add(token);
        chunkHasNumeral = true;
      } else {
        if (digits.containsKey(token) ||
            token == 'sepuluh' ||
            token == 'sebelas' ||
            token == 'seratus') {
          chunkHasNumeral = true;
        }
        chunk.add(token);
      }
    }

    final tail = parseChunkValue(chunk);
    if (!foundScale && !chunkHasNumeral) return null;
    return (total + tail).round();
  }
}

FfmAssistantDestination? _destinationForName(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final target = raw.trim().toLowerCase();
  return switch (target) {
    'summary' ||
    'ringkasan' ||
    'beranda' ||
    'home' => FfmAssistantDestination.summary,
    'transactions' ||
    'transaksi' ||
    'uang masuk' ||
    'uang keluar' => FfmAssistantDestination.transactions,
    'budget' || 'anggaran' => FfmAssistantDestination.budget,
    'analysis' || 'analisa' || 'analisis' => FfmAssistantDestination.analysis,
    'othermenu' ||
    'other_menu' ||
    'lainnya' ||
    'menu lainnya' ||
    'menu lain' => FfmAssistantDestination.otherMenu,
    'masterdata' ||
    'master_data' ||
    'data utama' ||
    'datautama' => FfmAssistantDestination.masterData,
    'assets' || 'aset' || 'kekayaan' => FfmAssistantDestination.assets,
    'goals' || 'target' || 'tujuan keuangan' => FfmAssistantDestination.goals,
    'liabilities' ||
    'hutang' ||
    'utang' ||
    'piutang' => FfmAssistantDestination.liabilities,
    'activity' || 'aktivitas' || 'jurnal' => FfmAssistantDestination.activity,
    'reminders' ||
    'pengingat' ||
    'reminder' => FfmAssistantDestination.reminders,
    'backup' || 'ekspor' || 'cadangan' => FfmAssistantDestination.backup,
    'monthlyreport' ||
    'monthly_report' ||
    'laporan bulanan' => FfmAssistantDestination.monthlyReport,
    'reconciliation' ||
    'rekonsiliasi' => FfmAssistantDestination.reconciliation,
    'appsecurity' ||
    'kunci aplikasi' ||
    'pin' => FfmAssistantDestination.appSecurity,
    'diagnostics' || 'bantuan perbaikan' => FfmAssistantDestination.diagnostics,
    'activitylog' || 'log aktivitas' => FfmAssistantDestination.activityLog,
    'recurringtransaction' ||
    'pemasukan berkala' => FfmAssistantDestination.recurringTransaction,
    'privacycenter' ||
    'pusat privasi' ||
    'privasi aplikasi' => FfmAssistantDestination.privacyCenter,
    'databasestructure' ||
    'struktur database' ||
    'tabel database' => FfmAssistantDestination.databaseStructure,
    'localmodel' ||
    'local_model' ||
    'model lokal' ||
    'model tanpa internet' ||
    'assistantprofile' ||
    'profil personalisasi' => FfmAssistantDestination.assistantProfile,
    'intelligencedashboard' ||
    'gemini' ||
    'cloud brain' => FfmAssistantDestination.intelligenceDashboard,
    _ => null,
  };
}

// ── PILAR 2: Coreference Memory ─────────────────────────────────────────────
/// Memori entitas sesi dalam satu sesi percakapan (tidak dipersistensikan).
///
/// Menyimpan entitas keuangan yang paling terakhir dirujuk pengguna sehingga
/// asisten bisa memahami kata ganti seperti *"dari situ"*, *"ke sana"*,
/// *"rekening tadi"*, *"nominal yang sama"* tanpa meminta klarifikasi ulang.
class _FfmSessionEntityMemory {
  String? lastAccountName;
  String? lastCategoryName;
  int? lastAmount;
  String? lastTransactionType; // 'income' | 'expense' | 'transfer'

  /// Perbarui memori berdasarkan draft yang baru diproses.
  void updateFromDraft({
    String? accountName,
    String? categoryName,
    int? amount,
    String? transactionType,
  }) {
    if (accountName != null && accountName.isNotEmpty) {
      lastAccountName = accountName;
    }
    if (categoryName != null && categoryName.isNotEmpty) {
      lastCategoryName = categoryName;
    }
    if (amount != null && amount > 0) lastAmount = amount;
    if (transactionType != null) lastTransactionType = transactionType;
  }

  /// Selesaikan kata rujukan dalam teks yang sudah dinormalisasi.
  ///
  /// Kata *"dari situ"*, *"ke situ"*, *"rekening tadi"* diganti dengan
  /// nama entitas yang terakhir diingat.
  String resolveCoref(String normalized) {
    var resolved = normalized;
    if (lastAccountName != null) {
      for (final ref in const [
        'dari situ',
        'ke situ',
        'ke sana',
        'dari sana',
        'rekening tadi',
        'rekening tersebut',
        'rekening itu',
        'dompet tadi',
        'dompet itu',
        'akun tadi',
        'akun itu',
      ]) {
        resolved = resolved.replaceAll(ref, lastAccountName!.toLowerCase());
      }
    }
    if (lastAmount != null) {
      for (final ref in const [
        'nominal yang sama',
        'jumlah yang sama',
        'nominal tadi',
        'jumlah tadi',
      ]) {
        resolved = resolved.replaceAll(ref, lastAmount.toString());
      }
    }
    return resolved;
  }

  bool get hasAnyEntity =>
      lastAccountName != null || lastCategoryName != null || lastAmount != null;
}
