import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/audit_logger.dart';
import '../../../../core/database/app_context.dart';
import '../../../activity/data/repositories/activity_repository.dart';
import '../../../activity/data/services/activity_speech_service.dart';
import '../../../activity/domain/entities/activity_entity.dart';
import '../../../activity/domain/activity_voice.dart';
import '../../../activity/domain/services/activity_application_service.dart';
import '../../../activity/presentation/bloc/activity_bloc.dart';
import '../../../activity/presentation/widgets/activity_live_bar.dart';
import '../../../settings/data/account_repository.dart';
import '../../data/ffm_assistant_capability_adapters.dart';
import '../../data/ffm_assistant_autonomy_repository.dart';
import '../../domain/ffm_assistant_capability_executor.dart';
import '../../data/ffm_assistant_chat_history_repository.dart';
import '../../data/ffm_assistant_interpreter.dart';
import '../../data/ffm_assistant_proposal_json_service.dart';
import '../../data/ffm_assistant_proactive_cooldown.dart';
import '../../data/ffm_assistant_report_service.dart';
import '../../data/ffm_assistant_chat_export_service.dart';
import '../../data/ffm_assistant_response_feedback_repository.dart';
import '../../data/ffm_assistant_memory_repository.dart';
import '../../data/ffm_memory_learning_service.dart';
import '../../domain/ffm_memory_candidate.dart';
import '../../domain/ffm_memory_type.dart';

import '../../data/ffm_assistant_unanswered_question_repository.dart';
import '../../domain/ffm_assistant_action_plan.dart';
import '../../domain/ffm_assistant_action_planner.dart';
import '../../domain/ffm_assistant_draft_validator.dart';
import '../../domain/ffm_assistant_work_item.dart';
import '../../domain/ffm_assistant_feedback_context.dart';
import '../../domain/ffm_assistant_models.dart';
import '../../domain/ffm_assistant_proactive_service.dart';
import '../../data/ffm_assistant_user_model_service.dart';
import '../../data/ffm_personal_context_provider.dart';
import '../../data/ffm_personal_memory_service.dart';
import '../../data/ffm_assistant_intent_classification_service.dart';
import '../../../../core/network/supabase_config.dart';
import '../../../../core/network/supabase_service.dart';
import 'chat/ffm_assistant_draft_preview.dart';

import 'chat/ffm_assistant_message_card.dart';
import 'chat/ffm_streaming_text_controller.dart';
import 'gemini_header.dart';
import 'gemini_typing_indicator.dart';
import 'ffm_assistant_page_context.dart';
import 'ffm_assistant_draft_edit_dialog.dart';
import 'ffm_assistant_message_correction_dialog.dart';
import '../pages/agent_inbox_page.dart';
import '../../data/ffm_assistant_insight_repository.dart';
import '../../domain/ffm_assistant_insight.dart';
import 'ffm_assistant_markdown_text.dart';
import 'ffm_assistant_global_launcher.dart';
import '../pages/ffm_memory_viewer_page.dart';
import '../../../settings/presentation/pages/supabase_setup_page.dart';

typedef FfmAssistantIntentHandler = Future<void> Function(
  FfmAssistantIntent intent,
);

typedef FfmAssistantIntentBatchHandler = Future<void> Function(
  List<FfmAssistantIntent> intents,
);

Future<void> showFfmAssistantSheet(
  BuildContext context, {
  required FfmAssistantIntentHandler onIntent,
  required FfmAssistantIntentBatchHandler onIntents,
  required FfmAssistantChatSession session,
  ValueNotifier<FfmAssistantLauncherState>? launcherState,
  FfmAssistantDestination? currentDestination,
  FfmAssistantPageContextSnapshot? currentPageContext,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => FfmAssistantSheet(
      onIntent: onIntent,
      onIntents: onIntents,
      session: session,
      launcherState: launcherState,
      currentDestination: currentDestination,
      currentPageContext: currentPageContext,
    ),
  ),
);

class FfmAssistantSheet extends StatefulWidget {
  const FfmAssistantSheet({
    super.key,
    required this.onIntent,
    required this.onIntents,
    required this.session,
    this.launcherState,
    this.currentDestination,
    this.currentPageContext,
  });

  final FfmAssistantIntentHandler onIntent;
  final FfmAssistantIntentBatchHandler onIntents;
  final FfmAssistantChatSession session;
  final ValueNotifier<FfmAssistantLauncherState>? launcherState;
  final FfmAssistantDestination? currentDestination;
  final FfmAssistantPageContextSnapshot? currentPageContext;

  @override
  State<FfmAssistantSheet> createState() => _FfmAssistantSheetState();
}

class _FfmAssistantSheetState extends State<FfmAssistantSheet> {
  final _controller = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();

  final _historyRepository = FfmAssistantChatHistoryRepository();
  final _actionPlanController = FfmAssistantActionPlanController();
  final _actionPlanner = const FfmAssistantActionPlanner();
  late final _capabilityExecutor = FfmAssistantCapabilityExecutor(
    controller: _actionPlanController,
    handlers: getIt<FfmAssistantCapabilityAdapterRegistry>().handlers,
    readTransaction: <T>(action) => getIt<AppDatabase>().transaction(action),
    onPlanRecorded: getIt<FfmAssistantAutonomyRepository>().recordPlan,
    onToolExecution:
        getIt<FfmAssistantAutonomyRepository>().recordToolExecution,
    onPlanProgress: (plan) {
      final running = plan.steps.where(
        (step) => step.status == FfmAssistantActionStepStatus.running,
      );
      final completed = plan.steps.where(
        (step) => step.status == FfmAssistantActionStepStatus.completed,
      );
      if (running.isNotEmpty) {
        _setActiveProcess(
          'Menjalankan ${_capabilityLabel(running.first.capabilityId)}...',
        );
      } else if (completed.isNotEmpty) {
        _setActiveProcess(
          '${_capabilityLabel(completed.last.capabilityId)} selesai.',
        );
      }
      if (mounted) setState(() {});
    },
  );
  final _proactiveService = const FfmAssistantProactiveSuggestionService();
  final _proactiveCooldown = FfmAssistantProactiveCooldown();
  final _speech = ActivitySpeechService();
  final _interpreter = getIt<FfmAssistantInterpreter>();
  final _chatExportService = FfmAssistantChatExportService();
  final _memoryRepository = getIt<FfmAssistantMemoryRepository>();
  final _memoryLearning = getIt<FfmMemoryLearningService>();
  final _responseFeedbackRepository =
      getIt<FfmAssistantResponseFeedbackRepository>();
  final _unansweredRepository =
      getIt<FfmAssistantUnansweredQuestionRepository>();
  final _activityRepository = getIt<ActivityRepository>();
  final _activityVoiceParser = const ActivityVoiceParser();
  final Set<String> _savedTeachingKeys = <String>{};
  final Set<String> _confirmedActivityKeys = <String>{};
  final Stopwatch _processStopwatch = Stopwatch();
  final List<FfmAssistantProcessEvent> _activeProcessEvents =
      <FfmAssistantProcessEvent>[];
  var _submitting = false;
  var _activeProcessLabel = 'Menyiapkan permintaan...';
  var _navigatingFromChat = false;
  var _cloudReady = false;
  var _cloudChecking = true;
  final _isFullScreen = true;
  String? _cloudStatusError;
  String? _cloudModel;
  FfmAssistantRoutingMode _routingMode = FfmAssistantRoutingMode.geminiCloud;
  var _listening = false;
  var _followLatestMessages = true;
  var _showScrollToBottom = false;
  final _technicalDetailsExpanded = <int>{};
  FfmAssistantProactiveSuggestion? _proactiveSuggestion;
  var _proactiveSuggestionGeneration = 0;
  String? _speakingEntryKey;
  String? _pausedEntryKey;
  String? _speakingSessionId;
  String? _pausedSpeechSessionId;
  var _listeningSession = 0;
  StreamSubscription<ActivitySpeechPlaybackState>? _speechStateSubscription;
  Future<void>? _historyRestoreFuture;
  var _historyWasRestored = false;

  // Streaming state
  final _streamingController = FfmStreamingTextController();

  FfmAssistantChatEntry? _streamingEntry;
  String _streamingVisibleText = '';
  StreamSubscription<String>? _streamingSubscription;

  // Personal Memory Mode
  late final _personalMemoryService = getIt<FfmPersonalMemoryService>();
  late final _intentClassificationService =
      getIt<FfmAssistantIntentClassificationService>();
  var _memoryCount = 0;
  var _inboxCount = 0;

  List<FfmAssistantChatEntry> get _entries => widget.session.entries;
  List<FfmAssistantDraftQueueItem> get _draftQueue => widget.session.draftQueue;

  void _setActiveProcess(String message) {
    _activeProcessLabel = message;
    _activeProcessEvents.add(
      FfmAssistantProcessEvent(
        label: message,
        elapsed: _processStopwatch.elapsed,
      ),
    );
    if (mounted) setState(() {});
  }

  FfmAssistantProcessTrace _traceFor(
    FfmAssistantIntent intent,
    Duration elapsed,
  ) {
    final origin = intent.responseOrigin;
    final pluginName = intent.pluginName;
    final pluginCategory = intent.pluginCategory;
    final usedReadCapability =
        intent.pluginMetadata?['usedReadCapability'] as String?;

    final sourceEvent = switch (origin) {
      FfmAssistantResponseOrigin.agentOrchestrator =>
        pluginName != null
            ? (
                label:
                    '$pluginCategory Plugin: ${_pluginDisplayName(pluginName)} selesai',
                detail: 'Data dibaca langsung dari database lokal. Tidak ada koneksi internet.',
              )
            : const (
                label: 'Data lokal FFM menyelesaikan permintaan',
                detail: 'Jawaban berasal dari aturan, katalog, atau query lokal yang sesuai.',
              ),
      FfmAssistantResponseOrigin.localSlm => const (
        label: 'Agent lokal menyusun jawaban terarah',
        detail: 'Jawaban hanya dirangkai dari konteks terbatas dan tidak mengubah data.',
      ),
      FfmAssistantResponseOrigin.localFallback => const (
        label: 'Agent memakai fallback deterministik',
        detail: 'FFM memakai aturan aman tanpa membuat atau mengubah data secara otomatis.',
      ),
      FfmAssistantResponseOrigin.geminiCloud => (
        label: 'Gemini Cloud mengembalikan jawaban',
        detail: 'Jawaban dibuat oleh model Gemini yang diuji dan dipilih.',
      ),
      FfmAssistantResponseOrigin.cloudError => (
        label: 'Gemini Cloud gagal merespons',
        detail:
            'Tidak ada jawaban lokal yang disamarkan sebagai jawaban Gemini.',
      ),
    };

    final intentLabel = _intentLabel(intent);
    final capabilityDetail = usedReadCapability != null
        ? _readCapabilityDetail(usedReadCapability, intent)
        : null;
    final tokenUsage =
        intent.pluginMetadata?['tokenUsage'] as Map<String, dynamic>?;

    return FfmAssistantProcessTrace(
      origin: origin,
      elapsed: elapsed,
      fallbackReason: origin == FfmAssistantResponseOrigin.localFallback
          ? 'Proposal visi ditolak validator'
          : origin == FfmAssistantResponseOrigin.cloudError
          ? 'Request Gemini gagal atau belum diverifikasi'
          : null,
      pluginName: pluginName,
      pluginCategory: pluginCategory,
      tokenUsage: tokenUsage,
      events: [
        FfmAssistantProcessEvent(
          label: 'Memahami: $intentLabel',
          detail:
              'Confidence: ${(intent.confidence * 100).toStringAsFixed(0)}%',
          elapsed: Duration.zero,
        ),
        ..._activeProcessEvents,
        if (usedReadCapability != null)
          FfmAssistantProcessEvent(
            label: _geminiReadCapabilityLabel(usedReadCapability),
            detail: capabilityDetail,
            elapsed: _processStopwatch.elapsed,
          ),
        FfmAssistantProcessEvent(
          label: sourceEvent.label,
          detail: sourceEvent.detail,
          elapsed: _processStopwatch.elapsed,
        ),
      ],
    );
  }

  static String _intentLabel(FfmAssistantIntent intent) {
    if (intent.draft != null) {
      final draft = intent.draft!;
      final kind = switch (draft.kind) {
        FfmAssistantDraftKind.expense => 'Pengeluaran',
        FfmAssistantDraftKind.income => 'Pemasukan',
        FfmAssistantDraftKind.transfer => 'Transfer',
        FfmAssistantDraftKind.activity => 'Aktivitas',
        FfmAssistantDraftKind.goal => 'Target',
        FfmAssistantDraftKind.budget => 'Anggaran',
        FfmAssistantDraftKind.liability => 'Hutang',
        FfmAssistantDraftKind.masterData => 'Data Utama',
        FfmAssistantDraftKind.accountDelete => 'Hapus Rekening',
        FfmAssistantDraftKind.categoryDelete => 'Hapus Kategori',
        FfmAssistantDraftKind.tagDelete => 'Hapus Tag',
        FfmAssistantDraftKind.merchantDelete => 'Hapus Toko',
        FfmAssistantDraftKind.incomeSourceDelete => 'Hapus Sumber Pemasukan',
        _ => draft.kind.name,
      };
      return 'Menyusun draft $kind${draft.amount != null ? ' Rp ${draft.amount}' : ''}';
    }
    return switch (intent.type) {
      FfmAssistantIntentType.openPage => 'Membuka halaman',
      FfmAssistantIntentType.queryData => 'Menjawab pertanyaan data',
      FfmAssistantIntentType.transactionStats => 'Menganalisis transaksi',
      FfmAssistantIntentType.weeklyAnalysis => 'Analisis mingguan',
      FfmAssistantIntentType.financialWarnings => 'Peringatan keuangan',
      FfmAssistantIntentType.help => 'Menjawab pertanyaan umum',
      FfmAssistantIntentType.calendarQuery => 'Informasi kalender',
      FfmAssistantIntentType.teachMemory => 'Menyimpan pengajaran',
      FfmAssistantIntentType.confirm => 'Konfirmasi aksi',
      FfmAssistantIntentType.unknown => 'Memproses permintaan',
      _ => 'Memproses permintaan',
    };
  }

  static String _readCapabilityDetail(
    String capabilityId,
    FfmAssistantIntent intent,
  ) {
    final draftKind = intent.draft?.kind.name ?? '-';
    return switch (capabilityId) {
      'read.summary' => 'Total transaksi bulan berjalan untuk konteks jawaban.',
      'read.transactions' => 'Daftar transaksi terbaru (max 8) untuk analisis.',
      'read.accounts' => 'Daftar rekening dan saldo untuk referensi.',
      'read.budget' => 'Posisi anggaran terkini untuk perbandingan.',
      'read.categories' =>
        'Daftar kategori aktif untuk validasi draft $draftKind.',
      'read.goals' => 'Target keuangan untuk konteks perencanaan.',
      'read.activity' => 'Sesi aktivitas aktif untuk konteks.',
      _ => 'Data lokal terverifikasi untuk konteks jawaban.',
    };
  }

  static String _geminiReadCapabilityLabel(String capabilityId) =>
      switch (capabilityId) {
        'read.summary' => 'Membaca ringkasan transaksi bulan ini',
        'read.transactions' => 'Membaca transaksi terbaru (maks 8 item)',
        'read.accounts' => 'Membaca daftar rekening dan saldo',
        'read.budget' => 'Membaca anggaran dan posisi terkini',
        'read.categories' => 'Membaca daftar kategori aktif',
        'read.goals' => 'Membaca target keuangan',
        'read.activity' => 'Membaca sesi aktivitas aktif',
        _ => 'Membaca data lokal terverifikasi',
      };

  static String _pluginDisplayName(String pluginName) => switch (pluginName) {
    'balance_sense' => 'Saldo & Rekening',
    'transaction_sense' => 'Ringkasan Transaksi',
    'budget_sense' => 'Anggaran',
    'debt_sense' => 'Hutang',
    'asset_sense' => 'Aset',
    'goal_sense' => 'Target Tabungan',
    'user_habits_profile' => 'Profil & Kebiasaan',
    'receivable_sense' => 'Piutang',
    'recurring_transaction_sense' => 'Transaksi Berulang',
    'daily_notes_sense' => 'Catatan Harian',
    'task_sense' => 'Daftar Tugas',
    'schedule_sense' => 'Agenda & Jadwal',
    'routine_sense' => 'Rutinitas Harian',
    'top_merchant_sense' => 'Analisis Merchant',
    'activity_report_sense' => 'Laporan Aktivitas',
    'live_activity_sense' => 'Live Activity (Layar)',
    'quick_note_actuator' => 'Quick Note Cepat',
    'activity_context_logic' => 'Konteks & Durasi Sesi',
    'activity_guard' => 'Pengaman Aktivitas',
    'zakat_logic' => 'Kalkulator Zakat',
    'financial_health_logic' => 'Kesehatan Keuangan',
    'budget_guard_logic' => 'Budget Guard',
    'loan_affordability_logic' => 'Kemampuan Pinjaman',
    'spending_pace_logic' => 'Laju Pengeluaran',
    'holistic_awareness' => 'Potret 360°',
    'emergency_fund_logic' => 'Dana Darurat',
    'debt_snowball_logic' => 'Strategi Bebas Hutang',
    'saving_rate_logic' => 'Rasio Menabung',
    _ => pluginName,
  };


  void _appendProcessEventsToTrace(
    FfmAssistantProcessTrace trace,
    int initialEventCount,
  ) {
    final newEvents = _activeProcessEvents
        .skip(initialEventCount)
        .toList(growable: false);
    if (newEvents.isEmpty) return;
    trace.events.insertAll(trace.events.length - 1, newEvents);
  }

  void _appendEntry(FfmAssistantChatEntry entry) {
    _entries.add(entry);
    unawaited(_historyRepository.save(_entries));
    unawaited(_refreshProactiveSuggestion());

    // Start streaming for assistant text responses
    if (!entry.isUser && entry.text.isNotEmpty) {
      _startStreaming(entry);
    }
  }

  void _startStreaming(FfmAssistantChatEntry entry) {
    _streamingSubscription?.cancel();
    _streamingEntry = entry;
    _streamingVisibleText = '';
    _streamingController.startStreaming(entry.text);
    _streamingSubscription = _streamingController.textStream.listen((text) {
      if (mounted) {
        setState(() {
          _streamingVisibleText = text;
        });
        // Clean up when streaming completes
        if (_streamingController.isComplete) {
          setState(() {
            _streamingEntry = null;
            _streamingVisibleText = '';
          });
        }
      }
    });
  }

  /// Tahap 1 pendekatan hybrid: aktifkan pipeline pembelajaran memori dari
  /// tiap giliran chat. Kandidat disimpan ke database lokal; yang butuh
  /// persetujuan menunggu review, pola otomatis langsung aktif.
  Future<void> _learnFromTurn({
    required String userQuery,
    String? assistantResponse,
  }) async {
    try {
      final existingRecords = await _memoryRepository.readActive();
      final existing = existingRecords.map(_recordToCandidate).toList();
      final candidates = await _memoryLearning.extractCandidates(
        userQuery: userQuery,
        assistantResponse: assistantResponse,
        usedMemories: const [],
      );
      final validated = _memoryLearning.validateCandidates(
        candidates,
        existing,
      );
      if (validated.isEmpty) return;
      await _memoryLearning.promoteCandidates(
        candidates: validated,
        requireApproval: true,
      );
    } on Object {
      // Pembelajaran bersifat best-effort; jangan ganggu alur chat.
    }
  }

  FfmMemoryCandidate _recordToCandidate(FfmAssistantMemoryRecord record) {
    final type = FfmMemoryType.values.firstWhere(
      (type) => type.name.toLowerCase() == record.kind.toLowerCase(),
      orElse: () => FfmMemoryType.working,
    );
    final rawConfidence = record.metadata['confidence'];
    return FfmMemoryCandidate(
      id: record.id,
      type: type,
      key: record.triggerText,
      value: record.valueText,
      evidence: FfmMemoryEvidence(
        source: FfmMemorySource.userExplicit,
        sourceId: record.source,
        createdAt: record.createdAt,
        updatedAt: record.updatedAt ?? record.createdAt,
        confidence: rawConfidence is num
            ? rawConfidence.toDouble().clamp(0, 1).toDouble()
            : 0.5,
        approved: record.metadata['approved'] == true,
      ),
    );
  }

  void _updateWorkingContextAfterTurn({
    required String userQuery,
    required List<FfmAssistantIntent> intents,
  }) {
    final provider = FfmPersonalContextProvider.maybeInstance;
    if (provider == null || intents.isEmpty) return;
    final primary = intents.last;
    provider.updateAfterTurn(
      userQuery: userQuery,
      // Manager menyimpan marker aman, bukan isi respons maupun draft.
      assistantResponse: primary.type.name,
      extractedEntities: {
        'intent': primary.type.name,
        if (primary.destination != null) 'topic': primary.destination!.name,
      },
    );
  }

  Future<void> _refreshProactiveSuggestion() async {
    final generation = ++_proactiveSuggestionGeneration;
    final candidate = _proactiveService.suggest(
      destination: widget.currentDestination,
      modelReady: _cloudReady,
      hasConversation: _entries.any((entry) => entry.isUser),
    );
    if (candidate == null || !_cloudReady) {
      if (mounted && _proactiveSuggestion != null) {
        setState(() => _proactiveSuggestion = null);
      }
      return;
    }
    final mayShow = await _proactiveCooldown.mayShow(candidate);
    if (!mounted ||
        generation != _proactiveSuggestionGeneration ||
        _entries.any((entry) => entry.isUser)) {
      return;
    }
    if (!mayShow) {
      if (_proactiveSuggestion != null) {
        setState(() => _proactiveSuggestion = null);
      }
      return;
    }
    await _proactiveCooldown.markShown(candidate);
    if (!mounted || generation != _proactiveSuggestionGeneration) return;
    setState(() => _proactiveSuggestion = candidate);
  }

  Future<void> _restoreChatHistory() async {
    final restored = await _historyRepository.load();
    if (!mounted) return;
    if (restored.isEmpty) {
      await _historyRepository.save(_entries);
      return;
    }
    if (_entries.length != 1) return;
    setState(() {
      _entries
        ..clear()
        ..addAll(restored);
      _historyWasRestored = true;
      String? lastAssistantText;
      for (final entry in restored.reversed) {
        if (!entry.isUser) {
          lastAssistantText = entry.text;
          break;
        }
      }
      widget.session.lastAssistantText = lastAssistantText;
    });
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    setState(() {
      _followLatestMessages = true;
      _showScrollToBottom = false;
    });
  }

  List<FfmAssistantIntent> get _queuedIntents => widget.session.queuedIntents;

  final _supabaseConfig = SupabaseConfig();
  final _supabase = SupabaseService();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateLatestMessagePreference);
    _speechStateSubscription = _speech.playbackStates.listen(_onSpeechState);
    _historyRestoreFuture = _restoreChatHistory();
    _refreshCloudStatus();
    _loadRoutingMode();
    unawaited(_loadAutonomyPolicy());
    _refreshMemoryCount();
    _refreshInboxCount();
    unawaited(_refreshProactiveSuggestion());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _historyRestoreFuture;
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scrollController.hasClients) return;
      _scrollToEnd(force: true, animated: false);
      _checkAndInitiateGreetings();
    });
  }

  void _checkAndInitiateGreetings() {
    _checkAndInitiateProactiveGreeting();
    _checkAndInitiateContextualGreeting();
  }

  void _checkAndInitiateContextualGreeting() {
    if (_historyWasRestored || _entries.length > 1) return;
    // Jika hanya ada pesan welcome bawaan, ganti dengan yang kontekstual.
    final greeting = _interpreter.getContextualGreeting(
      widget.currentDestination,
    );
    setState(() {
      _entries.clear();
      _appendEntry(FfmAssistantChatEntry(isUser: false, text: greeting));
      widget.session.lastAssistantText = greeting;
    });
  }

  void _checkAndInitiateProactiveGreeting() {
    final launcherState = widget.launcherState?.value;
    if (launcherState != null &&
        launcherState.hasNotification &&
        launcherState.notificationReason != null) {
      final reason = launcherState.notificationReason!;
      if (reason.startsWith('long_running_session:')) {
        final title = reason.split(':').last;
        final message =
            'Halo! Sesi aktivitas “$title” sepertinya sudah berjalan sangat lama (lebih dari 12 jam). Apakah kamu lupa mematikannya?';
        setState(() {
          widget.session.lastAssistantText = message;
          _appendEntry(FfmAssistantChatEntry(isUser: false, text: message));
        });
        _scrollToEnd();
      }
    }
  }

  Future<void> _loadRoutingMode() async {
    try {
      final mode = await _supabaseConfig.getLlmMode();
      if (!mounted) return;
      setState(() {
        _routingMode = mode == 'agent'
            ? FfmAssistantRoutingMode.agent
            : FfmAssistantRoutingMode.geminiCloud;
      });
    } on Object {
      // Gemini Cloud adalah default untuk obrolan cerdas.
    }
  }

  Future<void> _loadAutonomyPolicy() async {
    final policy = await getIt<FfmAssistantAutonomyRepository>().loadPolicy();
    if (policy != null) _capabilityExecutor.setAutonomyPolicy(policy);
  }

  Future<void> _refreshCloudStatus() async {
    try {
      final key = await _supabaseConfig.getGeminiKey();
      final model = await _supabaseConfig.getGeminiModel();
      final verified = await _supabaseConfig.isGeminiVerified();
      if (!mounted) return;
      setState(() {
        _cloudModel = model?.trim().isEmpty == true ? null : model?.trim();
        _cloudReady =
            verified &&
            key != null &&
            key.trim().isNotEmpty &&
            model != null &&
            model.trim().isNotEmpty;
        _cloudChecking = false;
        _cloudStatusError = _cloudReady
            ? null
            : 'Gemini Cloud belum diuji di Pengaturan';
      });
      unawaited(_refreshProactiveSuggestion());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cloudModel = null;
        _cloudReady = false;
        _cloudChecking = false;
        _cloudStatusError = 'Status Gemini Cloud tidak dapat dibaca';
      });
      unawaited(_refreshProactiveSuggestion());
    }
  }

  void _openGeminiSetup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SupabaseSetupPage()),
    ).then((_) => _refreshCloudStatus());
  }

  Future<void> _refreshMemoryCount() async {
    final all = await _personalMemoryService.readAll();
    if (!mounted) return;
    setState(() => _memoryCount = all.length);
  }

  Future<void> _refreshInboxCount() async {
    try {
      final repo = FfmAssistantInsightRepository(getIt<AppDatabase>());
      final active = await repo.getActiveInsights(
        householdId: AppContext.householdId,
      );
      final unread = active
          .where((i) => i.status == FfmAssistantInsightStatus.newInsight)
          .length;
      if (!mounted) return;
      setState(() => _inboxCount = unread);
    } catch (_) {}
  }

  void _checkForMemoryNudge(String userMessage) {
    if (userMessage.trim().isEmpty) return;
    _personalMemoryService.extractFromMessage(userMessage);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateLatestMessagePreference);
    _controller.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    _speechStateSubscription?.cancel();
    _speech.cancel();
    _speech.cancelSpeaking();
    _streamingSubscription?.cancel();
    _streamingController.dispose();
    super.dispose();
  }

  Future<void> _executeReadPlan(String planId) async {
    _setActiveProcess('Membaca data yang diperlukan secara lokal...');
    final plan = await _capabilityExecutor.execute(planId);
    if (!mounted || plan == null) return;
    if (plan.status == FfmAssistantActionPlanStatus.failed ||
        plan.status == FfmAssistantActionPlanStatus.blocked ||
        plan.status == FfmAssistantActionPlanStatus.blockedByBudget) {
      final completed = plan.steps
          .where(
            (step) => step.status == FfmAssistantActionStepStatus.completed,
          )
          .map((step) => _capabilityLabel(step.capabilityId))
          .toList(growable: false);
      final failed = plan.steps.where(
        (step) => step.status == FfmAssistantActionStepStatus.failed,
      );
      final failedStep = failed.isEmpty ? null : failed.first;
      final failureLabel = failedStep == null
          ? (plan.blockedReason == null
                ? 'batas proses'
                : 'batas proses (${plan.blockedReason})')
          : _capabilityLabel(failedStep.capabilityId);
      final partial = completed.isEmpty
          ? 'Belum ada hasil langkah yang berhasil.'
          : 'Hasil yang sudah berhasil: ${completed.join(', ')}.';
      final detail = failedStep?.error;
      final message =
          'Proses berhenti pada $failureLabel. $partial${detail == null || detail.isEmpty ? '' : ' Detail: $detail'} Tidak ada perubahan data yang dijalankan.';
      setState(() {
        widget.session.lastAssistantText = message;
        _appendEntry(FfmAssistantChatEntry(isUser: false, text: message));
      });
      _scrollToEnd();
      return;
    }
    setState(() {});
  }

  String _capabilityLabel(String capabilityId) {
    final value = capabilityId.replaceFirst(
      RegExp(r'^(read|draft|mutate|verify)\\.'),
      '',
    );
    return value.replaceAll('_', ' ');
  }

  bool _isDirectMutation(FfmAssistantDraft? draft) => switch (draft?.kind) {
    FfmAssistantDraftKind.transactionUpdate ||
    FfmAssistantDraftKind.transactionArchive ||
    FfmAssistantDraftKind.transactionDelete ||
    FfmAssistantDraftKind.activityArchive ||
    FfmAssistantDraftKind.activityDelete => true,
    _ => false,
  };

  Future<void> _executeDirectMutationPlan(
    FfmAssistantIntent intent,
    String planId,
  ) async {
    final isActivity = intent.draft?.formValues['entity'] == 'activity_session';
    final subject = isActivity ? 'Aktivitas' : 'Transaksi';
    final plan = await _capabilityExecutor.execute(planId);
    if (!mounted || plan == null) return;
    final failed = plan.steps.where(
      (step) => step.status == FfmAssistantActionStepStatus.failed,
    );
    if (plan.status != FfmAssistantActionPlanStatus.completed ||
        failed.isNotEmpty) {
      final failureLabel = failed.isEmpty
          ? (plan.blockedReason == null
                ? 'batas proses'
                : 'batas proses (${plan.blockedReason})')
          : _capabilityLabel(failed.first.capabilityId);
      final detail =
          failed.first.error ?? 'Perubahan tidak dapat diverifikasi.';
      final message =
          'Perubahan ${subject.toLowerCase()} tidak selesai ($failureLabel). $detail';
      setState(() {
        widget.session.lastAssistantText = message;
        _appendEntry(FfmAssistantChatEntry(isUser: false, text: message));
      });
      _scrollToEnd();
      return;
    }
    final verify = plan.steps.where(
      (step) => step.status == FfmAssistantActionStepStatus.completed,
    );
    final message = verify.isEmpty
        ? 'Perubahan ${subject.toLowerCase()} selesai dan sudah dicatat secara lokal.'
        : verify.first.result ??
              'Perubahan ${subject.toLowerCase()} selesai dan telah diverifikasi.';
    setState(() {
      widget.session.lastAssistantText = message;
      _appendEntry(FfmAssistantChatEntry(isUser: false, text: message));
      _queuedIntents.remove(intent);
      widget.session
        ..activeDraftReview = null
        ..activeDraftIntent = null;
    });
    _scrollToEnd();
  }

  Future<bool> _confirmDraftInChat(FfmAssistantDraft draft) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(FfmAssistantDraftPreview.draftLabel(draft.kind)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FfmAssistantDraftPreview(
                    draft: draft,
                    review: widget.session.activeDraftReview,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Belum ada data yang disimpan. Konfirmasi untuk melanjutkan ke form resmi dan periksa kembali sebelum simpan.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Konfirmasi & lanjutkan'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _confirmDirectMutation(FfmAssistantDraft draft) async {
    final operation = draft.formValues['operation'] ?? 'perubahan';
    final isActivity = draft.formValues['entity'] == 'activity_session';
    final target =
        draft.formValues['targetSummary'] ?? draft.title ?? 'transaksi ini';
    final detail = switch (operation) {
      'update' =>
        'Nominal lama ${draft.formValues['oldAmount'] ?? '-'} akan diubah menjadi ${draft.amount ?? '-'}.',
      'archive' =>
        isActivity
            ? 'Aktivitas dipindahkan dari daftar aktif ke arsip.'
            : 'Transaksi dipindahkan dari daftar aktif ke arsip.',
      'delete' =>
        isActivity
            ? 'Aktivitas beserta checkpoint dan catatan terkait akan dihapus permanen.'
            : 'Transaksi dihapus dari daftar aktif. Jejak audit lokal tetap tersimpan.',
      _ => 'Perubahan akan diterapkan ke transaksi ini.',
    };
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Konfirmasi perubahan data'),
            content: Text(
              '$target\n\n$detail\n\nLanjutkan hanya jika preview ini benar.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Konfirmasi'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _submit([String? overrideText]) async {
    await _historyRestoreFuture;
    final text = (overrideText ?? _controller.text).trim();
    if (text.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _processStopwatch
        ..reset()
        ..start();
      _activeProcessEvents.clear();
      _appendEntry(
        FfmAssistantChatEntry(
          isUser: true,
          text: text,
          createdAt: DateTime.now(),
        ),
      );
      _controller.clear();
    });
    _scrollToEnd(force: true);
    _checkForMemoryNudge(text);

    // Cek intent spesifik sebelum interpreter (tag vs draft confusion)
    final specificIntent = _intentClassificationService.classifySpecificIntent(
      text,
    );
    if (specificIntent != null) {
      final explanation = _intentClassificationService.getIntentExplanation(
        specificIntent,
        text,
      );
      if (explanation != null) {
        // Log atau gunakan penjelasan untuk debugging
        debugPrint('Intent Classification: $explanation');
      }
    }

    final stopwatch = Stopwatch()..start();
    _setActiveProcess(
      _routingMode == FfmAssistantRoutingMode.geminiCloud
          ? 'Tahap 1/2: Gemini Cloud memahami permintaan...'
          : 'Tahap 1/2: Menyiapkan konteks Agent...',
    );
    try {
      if (_routingMode == FfmAssistantRoutingMode.geminiCloud && !_cloudReady) {
        stopwatch.stop();
        setState(() {
          _appendEntry(
            FfmAssistantChatEntry(
              isUser: false,
              text:
                  'Koneksi Gemini Cloud belum aktif atau belum diverifikasi.\n\n'
                  '• Untuk mengobrol secara alami, hubungkan internet dan pasang API Key Gemini.\n'
                  '• Dapatkan API Key gratis di:\n'
                  '  [Google AI Studio (aistudio.google.com)](https://aistudio.google.com/)\n\n'
                  '• Untuk mencatat transaksi secara offline, silakan gunakan tombol input manual di halaman utama.\n\n'
                  'Ikuti juga update & tutorial di media sosial:\n'
                  '• YouTube: [YouTube @clipsmartt](https://youtube.com/@clipsmartt?si=T4-4Zja6FZlcgdDe)\n'
                  '• TikTok: [TikTok @clip.smarts](https://www.tiktok.com/@clip.smarts?_r=1&_t=ZS-997Uzi7kXma)',
              createdAt: DateTime.now(),
            ),
          );
          _submitting = false;
        });
        _scrollToEnd();
        return;
      }
      if (_tryReviseActiveDraft(text)) return;
      if (await _tryHandleActivityRequest(text)) return;
      final pending = widget.session.pendingDialog;
      if (pending != null) {
        _setActiveProcess('Tahap 1/2: Menyiapkan jawaban dialog tertunda...');
      }
      final conversationHistory = _buildRecentConversationHistory();
      final lastAssistant = widget.session.lastAssistantText;
      final activitySnapshot = getIt.isRegistered<ActivityBloc>()
          ? getIt<ActivityBloc>().state.toSnapshot()
          : null;
      FfmAssistantUnderstandingResult? understanding;
      final intents = pending == null
          ? ((understanding = await _interpreter.interpretMany(
              text,
              currentDestination: widget.currentDestination,
              pageContext: FfmAssistantScreenContextPolicy.forPrompt(
                destination: widget.currentDestination,
                snapshot: widget.currentPageContext,
              ),
              lastAssistantMessage: lastAssistant,
              conversationHistory: conversationHistory,
              capabilityIds:
                  widget.currentPageContext?.capabilityIds ?? const [],
              activitySnapshot: activitySnapshot,
              routingMode: _routingMode,
              activeDraft: widget.session.activeDraftIntent?.draft,
            )).intents)
          : await _interpreter.resolvePendingDialog(
              text,
              pending,
              currentDestination: widget.currentDestination,
              pageContext: FfmAssistantScreenContextPolicy.forPrompt(
                destination: widget.currentDestination,
                snapshot: widget.currentPageContext,
              ),
              capabilityIds:
                  widget.currentPageContext?.capabilityIds ?? const [],
            );
      stopwatch.stop();
      _setActiveProcess('Tahap 2/2: Memvalidasi hasil & menyusun respons...');

      if (!mounted) return;
      final readPlanIds = <String>[];
      final traceSnapshots = <(FfmAssistantProcessTrace, int)>[];
      setState(() {
        for (final intent in intents) {
          String response = intent.response ?? intent.clarification ?? '';
          if (response.isEmpty) {
            if (intent.responseMode == FfmAssistantResponseMode.localModel &&
                intent.type == FfmAssistantIntentType.help) {
              response = 'Aku memahami permintaanmu. Gemini belum menghasilkan jawaban yang dapat dipakai.';
            } else if (intent.draft != null) {
              response =
                  'Aku sudah memahami permintaannya. Cek draft ini dulu, ya.';
            } else {
              response = 'Permintaanmu sedang diproses.';
            }
          }
          final actionPlan = _actionPlanner.planFor(intent);
          if (actionPlan != null) {
            _actionPlanController.register(actionPlan);
            if (!actionPlan.hasMutation) readPlanIds.add(actionPlan.id);
          }
          final review = intent.draft == null
              ? null
              : FfmAssistantDraftReview(
                  draft: intent.draft!,
                  version: 1,
                  issues: FfmAssistantDraftValidator.validate(intent.draft!),
                );
          if (review != null) {
            widget.session
              ..activeDraftReview = review
              ..activeDraftIntent = intent;
            final workItem = understanding?.workItems
                .where((item) => identical(item.sourceIntent, intent))
                .firstOrNull;
            _enqueueDraft(intent, review, workItem: workItem);
          }
          widget.session.lastAssistantText = response;
          final traceEventCount = _activeProcessEvents.length;
          final processTrace = _traceFor(intent, stopwatch.elapsed);
          _appendEntry(
            FfmAssistantChatEntry(
              isUser: false,
              text: response,
              intent: intent,
              review: review,
              processTrace: processTrace,
              verifiedFacts: intent.verifiedFacts,
              analysisResults: intent.analysisResults,
            ),
          );
          traceSnapshots.add((processTrace, traceEventCount));
          if (intent.needsClarification) {
            widget.session.pendingDialog = FfmAssistantPendingDialog(
              originalRequest: pending?.originalRequest ?? text,
              prompt: intent.clarification ?? response,
              missingFields: _pendingFieldsFor(intent),
              draft: intent.draft ?? pending?.draft,
            );
          } else if (pending != null) {
            widget.session.pendingDialog = null;
          }
          if (!intent.needsClarification &&
              (intent.destination != null || intent.draft != null)) {
            _queuedIntents.add(intent);
          }
        }
      });
      for (final planId in readPlanIds) {
        await _executeReadPlan(planId);
      }
      for (final snapshot in traceSnapshots) {
        _appendProcessEventsToTrace(snapshot.$1, snapshot.$2);
      }
      if (intents.any(
        (intent) => intent.type == FfmAssistantIntentType.unknown,
      )) {
        await _unansweredRepository.record(
          rawQuestion: text,
          pageContext: widget.currentDestination?.name,
        );
      }
      _updateWorkingContextAfterTurn(userQuery: text, intents: intents);
      unawaited(
        _learnFromTurn(
          userQuery: text,
          assistantResponse: intents.last.response,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _appendEntry(
          const FfmAssistantChatEntry(
            isUser: false,
            text: 'Maaf, aku belum bisa memproses itu. Coba ulangi dengan kalimat lebih singkat, ya.',
          ),
        ),
      );
    } finally {
      _processStopwatch.stop();
      if (mounted) setState(() => _submitting = false);
      _scrollToEnd(force: true);
    }
  }

  bool _looksLikeActivityCommand(String normalized) {
    if (widget.currentDestination != FfmAssistantDestination.activity) {
      return normalized.contains('aktivitas') ||
          normalized.contains('kegiatan') ||
          normalized.contains('perjalanan');
    }
    return RegExp(
      r'\b(mulai|jalankan|selesai|beres|hentikan|stop|update|sampai|tiba|durasi|berapa lama|riwayat|cari)\b',
    ).hasMatch(normalized);
  }

  Future<bool> _tryHandleActivityRequest(String text) async {
    final normalized = text.toLowerCase().trim();
    // Pada mode Gemini, semua percakapan Aktivitas masuk ke Gemini dulu.
    // Proposal aktivitasnya tetap divalidasi dan dieksekusi oleh Agent.
    if (_routingMode == FfmAssistantRoutingMode.geminiCloud) {
      return false;
    }
    if (!_looksLikeActivityCommand(normalized)) return false;
    if (RegExp(r'\b(berapa lama|durasi)\b').hasMatch(normalized)) {
      await _answerActivityDuration(normalized);
      return true;
    }
    if (RegExp(r'\b(riwayat|cari)\b').hasMatch(normalized)) {
      await _answerActivityHistory(normalized);
      return true;
    }
    final active = await _activityRepository.getActiveSessions(
      AppContext.householdId,
    );
    final activityIntent = _activityVoiceParser.parse(
      text,
      activeSessions: active,
    );
    if (activityIntent.type == ActivityVoiceIntentType.note) return false;
    final response = activityIntent.canConfirm
        ? '${activityIntent.actionLabel}: ${_activityIntentDetail(activityIntent)}. Cek dulu, lalu tekan Konfirmasi aktivitas. Belum ada aktivitas yang disimpan atau diubah.'
        : activityIntent.ambiguityReason ??
              'Aku belum cukup paham aktivitas yang dimaksud. Tidak ada perubahan yang dibuat.';
    if (!mounted) return true;
    setState(() {
      widget.session.lastAssistantText = response;
      _appendEntry(
        FfmAssistantChatEntry(
          isUser: false,
          text: response,
          activityIntent: activityIntent,
          understanding: activityIntent.canConfirm
              ? 'Kamu ingin ${activityIntent.actionLabel.toLowerCase()}. Aku menunggu konfirmasi sebelum mengubah riwayat Aktivitas.'
              : 'Aku perlu penjelasan tambahan sebelum menyentuh Aktivitas.',
        ),
      );
    });
    _scrollToEnd();
    return true;
  }

  String _activityIntentDetail(
    ActivityVoiceIntent intent,
  ) => switch (intent.type) {
    ActivityVoiceIntentType.start => intent.targetTitle ?? 'aktivitas baru',
    ActivityVoiceIntentType.startChild =>
      '${intent.targetTitle ?? 'aktivitas baru'} di dalam ${intent.parentTitle ?? 'aktivitas induk'}',
    ActivityVoiceIntentType.finish => intent.targetTitle ?? 'aktivitas aktif',
    ActivityVoiceIntentType.checkpoint =>
      '${intent.checkpointLabel ?? 'update'} pada ${intent.targetTitle ?? 'aktivitas aktif'}',
    ActivityVoiceIntentType.note => intent.checkpointLabel ?? 'catatan',
    _ => 'aktivitas',
  };

  String _activityKey(ActivityVoiceIntent intent) =>
      '${intent.type.name}:${intent.targetSessionId ?? intent.parentSessionId ?? intent.targetTitle}:${intent.checkpointLabel ?? ''}:${intent.normalizedText}';

  Future<void> _confirmActivityIntent(ActivityVoiceIntent intent) async {
    final key = _activityKey(intent);
    if (!intent.canConfirm || _confirmedActivityKeys.contains(key)) return;
    try {
      await ActivityBloc(_activityRepository).executeVoiceIntent(intent);
      if (!mounted) return;
      final response = switch (intent.type) {
        ActivityVoiceIntentType.start =>
          'Sip, aktivitas ${intent.targetTitle} sudah dimulai.',
        ActivityVoiceIntentType.startChild =>
          'Sip, aktivitas ${intent.targetTitle} sudah dimulai di dalam ${intent.parentTitle}.',
        ActivityVoiceIntentType.finish =>
          'Sip, aktivitas ${intent.targetTitle} sudah diselesaikan.',
        ActivityVoiceIntentType.checkpoint =>
          'Sip, update “${intent.checkpointLabel}” sudah masuk ke aktivitas ${intent.targetTitle}.',
        _ => 'Sip, aktivitas sudah diperbarui.',
      };
      setState(() {
        _confirmedActivityKeys.add(key);
        widget.session.lastAssistantText = response;
        _appendEntry(FfmAssistantChatEntry(isUser: false, text: response));
      });
      _scrollToEnd();
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _appendEntry(
          const FfmAssistantChatEntry(
            isUser: false,
            text: 'Aktivitas belum berubah. Coba cek lagi nama aktivitas dan konfirmasi ulang.',
          ),
        ),
      );
    }
  }

  Future<void> _answerActivityDuration(String normalized) async {
    final sessions = await _activityRepository.getSessions(
      AppContext.householdId,
    );
    final query = normalized
        .replaceAll(RegExp(r'\b(berapa lama|durasi|aktivitas|kegiatan)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final matches = query.isEmpty
        ? sessions.where((item) => item.status.name == 'active').toList()
        : sessions
              .where((item) => item.title.toLowerCase().contains(query))
              .toList();
    final response = matches.isEmpty
        ? 'Aku belum menemukan aktivitas yang cocok untuk dihitung durasinya.'
        : matches
              .take(3)
              .map(
                (item) =>
                    '${item.title}: ${ActivityDurationCalculator().format(item.durationAt())}${item.status.name == 'active' ? ' dan masih berjalan' : ''}',
              )
              .join('\n');
    if (!mounted) return;
    setState(() {
      widget.session.lastAssistantText = response;
      _appendEntry(FfmAssistantChatEntry(isUser: false, text: response));
    });
    _scrollToEnd();
  }

  Future<void> _answerActivityHistory(String normalized) async {
    final sessions = await _activityRepository.getSessions(
      AppContext.householdId,
    );
    final query = normalized
        .replaceAll(RegExp(r'\b(riwayat|cari|aktivitas|kegiatan)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final matches = query.isEmpty
        ? sessions
        : sessions
              .where((item) => item.title.toLowerCase().contains(query))
              .toList();
    final response = matches.isEmpty
        ? 'Belum ada riwayat aktivitas yang cocok.'
        : 'Riwayat yang kutemukan:\n${matches.take(5).map((item) => '• ${item.title} — ${ActivityDurationCalculator().format(item.durationAt())}${item.status.name == 'active' ? ' (masih berjalan)' : ''}').join('\n')}';
    if (!mounted) return;
    setState(() {
      widget.session.lastAssistantText = response;
      _appendEntry(FfmAssistantChatEntry(isUser: false, text: response));
    });
    _scrollToEnd();
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      _listeningSession++;
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final ready = await _speech.initialize(
      onError: (message) {
        _listeningSession++;
        if (!mounted) return;
        setState(() => _listening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mikrofon belum siap: $message')),
        );
      },
      onStatus: (status) {
        if (status != 'done' && status != 'notListening') return;
        _listeningSession++;
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!ready || !mounted) return;
    setState(() => _listening = true);
    final session = ++_listeningSession;
    var finalSubmitted = false;
    await _speech.listen(
      onResult: (text, isFinal) {
        if (!mounted || session != _listeningSession) return;
        setState(() => _controller.text = text);
        if (!isFinal || finalSubmitted || text.trim().isEmpty) return;
        finalSubmitted = true;
        _listeningSession++;
        setState(() => _listening = false);
        _submit(text);
      },
    );
  }

  String _speechKeyFor(int index, FfmAssistantChatEntry entry) =>
      '$index:${identityHashCode(entry)}';

  Future<void> _toggleSpeakFor(int index, FfmAssistantChatEntry entry) async {
    final key = _speechKeyFor(index, entry);
    if (_speakingEntryKey == key) {
      await _speech.stopSpeaking(sessionId: _speakingSessionId);
      if (mounted) {
        setState(() {
          _speakingEntryKey = null;
          _pausedEntryKey = key;
          _pausedSpeechSessionId = _speakingSessionId;
          _speakingSessionId = null;
        });
      }
      return;
    }

    final resumed = _pausedEntryKey == key && await _speech.resumeSpeaking();
    final sessionId = resumed
        ? _pausedSpeechSessionId
        : await _speech.speak(entry.text);
    if (mounted) {
      setState(() {
        if (resumed || sessionId != null) {
          _speakingEntryKey = key;
          _pausedEntryKey = null;
          _speakingSessionId = sessionId;
          _pausedSpeechSessionId = null;
        }
      });
    }
  }

  void _onSpeechState(ActivitySpeechPlaybackState state) {
    if (!mounted || state.sessionId != _speakingSessionId) return;
    switch (state.status) {
      case ActivitySpeechPlaybackStatus.started:
        return;
      case ActivitySpeechPlaybackStatus.stopped:
        setState(() {
          _pausedEntryKey = _speakingEntryKey;
          _pausedSpeechSessionId = _speakingSessionId;
          _speakingEntryKey = null;
          _speakingSessionId = null;
        });
        return;
      case ActivitySpeechPlaybackStatus.completed:
      case ActivitySpeechPlaybackStatus.error:
        setState(() {
          _speakingEntryKey = null;
          _pausedEntryKey = null;
          _speakingSessionId = null;
          _pausedSpeechSessionId = null;
        });
    }
  }

  Future<void> _openVoicePicker() async {
    final voices = await _speech.availableVoices();
    final selectedName = await _speech.selectedVoiceName();
    if (!mounted) return;
    if (voices.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Suara perangkat belum tersedia'),
          content: const Text(
            'FFM hanya memakai suara Bahasa Indonesia yang sudah terpasang di perangkat dan tidak membutuhkan internet. Tambahkan suara di Setelan Android → Text-to-speech output, lalu buka ulang FFM.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Mengerti'),
            ),
          ],
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (dialogContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pilih suara bacaan',
              style: Theme.of(dialogContext).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Hanya suara Bahasa Indonesia yang tersedia secara lokal di perangkat ini.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: RadioGroup<String>(
                groupValue: selectedName,
                onChanged: (name) async {
                  if (name == null) return;
                  final selected = await _speech.selectVoice(name);
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  if (selected && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Suara $name dipilih.')),
                    );
                  }
                },
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: voices.length,
                  itemBuilder: (context, index) {
                    final voice = voices[index];
                    return RadioListTile<String>(
                      value: voice.name,
                      contentPadding: EdgeInsets.zero,
                      title: Text(voice.label),
                      subtitle: Text(voice.locale),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleIntent(FfmAssistantIntent intent) async {
    if (_navigatingFromChat) return;
    if (intent.type == FfmAssistantIntentType.exportReport) {
      await _showReportPreview(intent);
      return;
    }
    if (intent.type == FfmAssistantIntentType.readLastResponse) {
      await _speech.speak(
        widget.session.lastAssistantText ?? 'Belum ada jawaban untuk dibaca.',
      );
      return;
    }
    if (intent.type == FfmAssistantIntentType.cancel) {
      widget.session
        ..pendingDialog = null
        ..activeDraftReview = null
        ..activeDraftIntent = null
        ..activeDraftQueueId = null;
      _queuedIntents.clear();
      _draftQueue.clear();
      if (!mounted) return;
      setState(
        () => _appendEntry(
          const FfmAssistantChatEntry(
            isUser: false,
            text: 'Oke, tidak ada draft dari Asisten yang akan disimpan.',
          ),
        ),
      );
      return;
    }
    if (intent.draft != null) {
      final review = widget.session.activeDraftReview;
      if (review == null) return;
      if (!review.canContinue) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lengkapi dulu bagian yang ditandai di draft chat.'),
          ),
        );
        return;
      }
      intent = intent.copyWith(draft: review.draft);
    }
    final directMutation = _isDirectMutation(intent.draft);
    final plan = _actionPlanner.planFor(intent);
    if (intent.draft != null && !directMutation) {
      final confirmed = await _confirmDraftInChat(intent.draft!);
      if (!confirmed) {
        if (plan != null) {
          _actionPlanController.cancel(plan.id);
          unawaited(
            getIt<FfmAssistantAutonomyRepository>().recordApprovalDecision(
              runId: plan.id,
              status: FfmAssistantApprovalStatus.rejected,
              reason: 'Draft dibatalkan pengguna.',
            ),
          );
        }
        if (mounted) setState(() => _queuedIntents.remove(intent));
        return;
      }
    }
    final shouldNavigate =
        (intent.destination != null || intent.draft != null) &&
        intent.type != FfmAssistantIntentType.confirm &&
        !directMutation;
    final isCurrentPageCheck =
        intent.destination != null &&
        intent.destination == widget.currentDestination &&
        intent.draft == null;

    if (plan != null) {
      if (intent.draft != null) {
        _actionPlanController.markAwaitingConfirmation(plan.id);
        unawaited(
          getIt<FfmAssistantAutonomyRepository>().recordApprovalRequest(plan),
        );
      } else {
        _actionPlanController.complete(plan.id);
      }
    }

    if (directMutation && plan != null && intent.draft != null) {
      final confirmed = await _confirmDirectMutation(intent.draft!);
      if (!confirmed) {
        _actionPlanController.cancel(plan.id);
        unawaited(
          getIt<FfmAssistantAutonomyRepository>().recordApprovalDecision(
            runId: plan.id,
            status: FfmAssistantApprovalStatus.rejected,
            reason: 'Mutasi dibatalkan pengguna.',
          ),
        );
        if (mounted) {
          setState(() => _queuedIntents.remove(intent));
        }
        return;
      }
      final executable = _actionPlanController.confirm(plan.id);
      if (executable == null ||
          executable.status != FfmAssistantActionPlanStatus.executing) {
        if (mounted) {
          setState(
            () => _appendEntry(
              const FfmAssistantChatEntry(
                isUser: false,
                text: 'Konfirmasi tidak dapat diterapkan ke draft transaksi ini. Tidak ada data yang diubah.',
              ),
            ),
          );
        }
        return;
      }
      unawaited(
        getIt<FfmAssistantAutonomyRepository>().recordApprovalDecision(
          runId: plan.id,
          status: FfmAssistantApprovalStatus.approved,
        ),
      );
      await _executeDirectMutationPlan(intent, plan.id);
      return;
    }

    if (shouldNavigate) {
      if (isCurrentPageCheck) {
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }
      final handler = widget.onIntent;
      setState(() {
        _navigatingFromChat = true;
        _queuedIntents.remove(intent);
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await handler(intent);
      return;
    }
    await widget.onIntent(intent);
    if (mounted) setState(() => _queuedIntents.remove(intent));
  }

  Future<void> _handleEntryIntent(FfmAssistantChatEntry entry) async {
    final intent = entry.intent;
    if (intent == null) return;

    _selectDraftFromEntry(entry);
    await _handleIntent(intent);
  }

  void _selectDraftFromEntry(FfmAssistantChatEntry entry) {
    final review = entry.review;
    final intent = entry.intent;
    if (review == null || intent == null) return;
    // Setiap kartu draft membawa review-nya sendiri. Ini mencegah draft paling
    // akhir menimpa draft yang dipilih pengguna dari pesan sebelumnya.
    setState(() {
      widget.session
        ..activeDraftReview = review
        ..activeDraftIntent = intent
        ..activeDraftQueueId = _queueItemFor(intent)?.id;
    });
  }

  FfmAssistantDraftQueueItem? _queueItemFor(FfmAssistantIntent intent) {
    for (final item in _draftQueue.reversed) {
      if (identical(item.intent, intent) ||
          (item.intent.rawText == intent.rawText &&
              item.intent.draft?.kind == intent.draft?.kind)) {
        return item;
      }
    }
    return null;
  }

  bool get _activeDraftIsOpeningForm {
    final id = widget.session.activeDraftQueueId;
    if (id == null) return false;
    return _draftQueue.where((item) => item.id == id).firstOrNull?.status ==
        FfmAssistantDraftQueueStatus.openingForm;
  }

  void _enqueueDraft(
    FfmAssistantIntent intent,
    FfmAssistantDraftReview review, {
    FfmAssistantWorkItem? workItem,
  }) {
    final workItemMissing = workItem == null
        ? const <String>[]
        : [
            ...workItem.unknownFields,
            ...workItem.ambiguousFields.map((field) => field.name),
          ];
    final id =
        'draft-${review.draft.createdAt.microsecondsSinceEpoch}-${_draftQueue.length + 1}';
    _draftQueue.add(
      FfmAssistantDraftQueueItem(
        id: id,
        intent: intent,
        review: review,
        targetDestination: intent.destination,
        createdAt: review.draft.createdAt,
        status: review.canContinue
            ? FfmAssistantDraftQueueStatus.ready
            : FfmAssistantDraftQueueStatus.needsClarification,
        knownFieldCount:
            workItem?.knownFields.length ?? _knownDraftFieldCount(review.draft),
        missingFields: <String>{
          ..._missingFieldsForReview(review),
          ...workItemMissing,
        }.toList(),
        warningCount: _warningCountForReview(review),
      ),
    );
    widget.session.activeDraftQueueId = id;
  }

  void _replaceActiveQueueItem({
    required FfmAssistantIntent intent,
    required FfmAssistantDraftReview review,
    FfmAssistantDraftQueueStatus? status,
  }) {
    final id = widget.session.activeDraftQueueId;
    if (id == null) return;
    final index = _draftQueue.indexWhere((item) => item.id == id);
    if (index < 0) return;
    _draftQueue[index] = _draftQueue[index].copyWith(
      intent: intent,
      review: review,
      knownFieldCount: _knownDraftFieldCount(review.draft),
      missingFields: _missingFieldsForReview(review),
      warningCount: _warningCountForReview(review),
      status:
          status ??
          (review.canContinue
              ? FfmAssistantDraftQueueStatus.ready
              : FfmAssistantDraftQueueStatus.needsClarification),
    );
  }

  List<String> _missingFieldsForReview(FfmAssistantDraftReview review) => review
      .issues
      .where((issue) => issue.blocksContinuation)
      .map((issue) => issue.field ?? issue.code)
      .toSet()
      .toList();

  int _warningCountForReview(FfmAssistantDraftReview review) => review.issues
      .where(
        (issue) =>
            issue.severity == FfmAssistantDraftIssueSeverity.warning ||
            issue.severity == FfmAssistantDraftIssueSeverity.conflict,
      )
      .length;

  int _knownDraftFieldCount(FfmAssistantDraft draft) => <Object?>[
    draft.amount,
    draft.title,
    draft.fromAccountName,
    draft.toAccountName,
    draft.categoryName,
    draft.goalName,
    draft.partyName,
    draft.date,
    draft.note,
  ].where((value) => value?.toString().trim().isNotEmpty == true).length;

  Future<void> _editDraftFromEntry(FfmAssistantChatEntry entry) async {
    final intent = entry.intent;
    if (intent == null) return;
    _selectDraftFromEntry(entry);
    await _editActiveDraft(intent);
  }

  void _cancelDraftFromEntry(FfmAssistantChatEntry entry) {
    _selectDraftFromEntry(entry);
    _cancelActiveDraft(entry.intent);
  }

  Future<void> _shareFile(String path, String? format) async {
    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File tidak lagi tersedia di perangkat.'),
          ),
        );
      }
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        subject: 'File dari Asisten FFM${format == null ? '' : ' ($format)'}',
      ),
    );
  }

  Future<void> _showReportPreview(FfmAssistantIntent intent) async {
    final now = DateTime.now();
    final isPreviousMonth = intent.normalizedText.contains('bulan lalu');
    final base = DateTime(now.year, now.month - (isPreviousMonth ? 1 : 0), 1);
    final request = FfmAssistantReportRequest(
      from: base,
      to: DateTime(base.year, base.month + 1, 1),
      reportStyle: intent.normalizedText.contains('cashflow')
          ? 'cashflow ringkas'
          : 'ringkas dan praktis',
    );
    try {
      final report = await getIt<FfmAssistantReportService>().prepare(request);
      if (!mounted) return;
      final format = await showDialog<FfmAssistantExportFormat>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Preview dan format laporan'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: FfmAssistantMarkdownText(
                text:
                    '${report.previewMarkdown}\n\nPilih format untuk membuat file lokal. Data default disaring dan belum dibagikan ke mana pun.',
                color: Theme.of(dialogContext).colorScheme.onSurface,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Batal'),
            ),
            OutlinedButton(
              onPressed: () =>
                  Navigator.of(dialogContext)
                      .pop(FfmAssistantExportFormat.json),
              child: const Text('JSON'),
            ),
            OutlinedButton(
              onPressed: () =>
                  Navigator.of(dialogContext)
                      .pop(FfmAssistantExportFormat.markdown),
              child: const Text('Markdown'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(FfmAssistantExportFormat.pdf),
              child: const Text('PDF'),
            ),
          ],
        ),
      );
      if (format == null || !mounted) return;
      final result = await _chatExportService.create(
        FfmAssistantExportRequest(report: report, format: format),
      );
      if (!mounted) return;
      final label = switch (format) {
        FfmAssistantExportFormat.json => 'JSON',
        FfmAssistantExportFormat.markdown => 'Markdown',
        FfmAssistantExportFormat.pdf => 'PDF',
      };
      final text =
          'File $label berhasil dibuat secara lokal: ${result.fileName}. Ketuk Bagikan jika ingin mengirimkannya ke aplikasi lain.';
      setState(() {
        widget.session.lastAssistantText = text;
        _appendEntry(
          FfmAssistantChatEntry(
            isUser: false,
            text: text,
            filePath: result.file.path,
            fileFormat: label,
          ),
        );
      });
      _scrollToEnd();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        widget.session.lastAssistantText =
            'File laporan belum dapat dibuat: $error';
        _appendEntry(
          FfmAssistantChatEntry(
            isUser: false,
            text: widget.session.lastAssistantText!,
          ),
        );
      });
    }
  }

  String _teachingKey(FfmAssistantTeachingProposal proposal) =>
      '${proposal.kind}\u0000${proposal.triggerText}\u0000${proposal.valueText}'
          .toLowerCase();

  Future<void> _approveTeaching(FfmAssistantIntent intent) async {
    final proposal = intent.teachingProposal;
    if (proposal == null) return;
    final key = _teachingKey(proposal);
    if (_savedTeachingKeys.contains(key)) return;
    try {
      if (proposal.kind == 'user_profile') {
        await FfmAssistantUserModelService(_memoryRepository).saveApproved(
          kind: 'profile',
          key: proposal.triggerText,
          value: proposal.valueText,
        );
      } else {
        await _memoryRepository.save(
          kind: proposal.kind,
          triggerText: proposal.triggerText,
          valueText: proposal.valueText,
          source: 'chat_approved',
        );
      }
      unawaited(
        _supabase.saveMemory(
          content: '${proposal.triggerText}: ${proposal.valueText}',
          category: proposal.kind,
          metadata: const {'source': 'chat_approved'},
        ),
      );
      if (!mounted) return;
      setState(() {
        _savedTeachingKeys.add(key);
        widget.session.lastAssistantText = 'Sip, ajaran ini sudah kusimpan lokal di perangkat. Kamu bisa mengubah atau mengarsipkannya di Pengetahuan Asisten.';
        _appendEntry(
          FfmAssistantChatEntry(
            isUser: false,
            text: widget.session.lastAssistantText!,
          ),
        );
      });
      _scrollToEnd();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajaran belum tersimpan. Coba lagi, ya.')),
      );
    }
  }

  List<String> _pendingFieldsFor(FfmAssistantIntent intent) {
    final draft = intent.draft;
    if (draft == null) {
      if (intent.clarification?.contains('pemasukan atau pengeluaran') ==
          true) {
        return const ['jenis transaksi'];
      }
      return const ['detail jawaban'];
    }
    final fields = <String>[];
    if (!draft.hasAmount) fields.add('nominal');
    if (draft.kind == FfmAssistantDraftKind.transfer &&
        (draft.fromAccountName == null || draft.toAccountName == null)) {
      fields.add('rekening asal dan tujuan');
    }
    if (draft.kind == FfmAssistantDraftKind.income &&
        draft.toAccountName == null) {
      fields.add('rekening tujuan atau Belum terlacak');
    }
    if (draft.kind == FfmAssistantDraftKind.expense &&
        draft.fromAccountName == null) {
      fields.add('rekening sumber atau Belum terlacak');
    }
    return fields.isEmpty ? const ['detail jawaban'] : fields;
  }

  FfmAssistantDraftQueueItem? _matchReferencedDraft(String text) {
    if (_draftQueue.length < 2) return null;
    final normalized = text.toLowerCase();
    final yangMatch = RegExp(
      r'\byang\s+([^,.;!?]+?)(?=\s+(?:ubah|ganti|revisi|koreksi|jadi)\b|,|\.|$|;)',
    ).firstMatch(normalized);
    final reference = yangMatch?.group(1)?.trim() ?? '';
    if (reference.isEmpty) return null;
    FfmAssistantDraftQueueItem? best;
    for (final item in _draftQueue) {
      final draft = item.review.draft;
      final candidates = <String?>[
        draft.title,
        draft.goalName,
        draft.categoryName,
        draft.partyName,
        draft.merchantName,
        draft.note,
      ];
      if (candidates.any(
        (c) =>
            c != null &&
            c.trim().isNotEmpty &&
            reference.length >= 3 &&
            c.toLowerCase().contains(reference),
      )) {
        if (best != null) return null; // ambigu: lebih dari satu cocok
        best = item;
      }
    }
    return best;
  }

  bool _tryReviseActiveDraft(String text) {
    // Saat ada banyak draft sekaligus, deteksi draft mana yang dimaksud dari
    // kalimat koreksi (mis. "yang beras ubah jadi 80rb" / "yang Dana Darurat").
    final referenced = _matchReferencedDraft(text);
    if (referenced != null) {
      widget.session
        ..activeDraftReview = referenced.review
        ..activeDraftIntent = referenced.intent
        ..activeDraftQueueId = referenced.id;
    }
    final review = widget.session.activeDraftReview;
    final sourceIntent = widget.session.activeDraftIntent;
    if (review == null || sourceIntent == null) return false;
    final normalized = text.toLowerCase().trim();
    final looksLikeProposalJson = text.contains(
      FfmAssistantProposalJsonService.formatVersion,
    );
    if (!looksLikeProposalJson &&
        !RegExp(r'\b(ubah|ganti|revisi|koreksi)\b').hasMatch(normalized)) {
      return false;
    }
    if (_activeDraftIsOpeningForm) {
      setState(
        () => _appendEntry(
          const FfmAssistantChatEntry(
            isUser: false,
            text: 'Draft ini sedang dibuka di form. Kembali tanpa menyimpan dulu, lalu koreksi draft agar versinya tidak tertukar.',
          ),
        ),
      );
      return true;
    }
    FfmAssistantDraft? nextDraft;
    String? jsonError;
    if (looksLikeProposalJson) {
      final parsed = FfmAssistantProposalJsonService.parse(
        text,
        createdAt: review.draft.createdAt,
      );
      jsonError = parsed.error;
      nextDraft = parsed.draft;
      if (nextDraft != null && nextDraft.kind != review.draft.kind) {
        jsonError =
            'Jenis JSON (${nextDraft.kind.name}) berbeda dari draft aktif (${review.draft.kind.name}).';
        nextDraft = null;
      }
      if (nextDraft != null) {
        nextDraft = nextDraft.copyWith(
          linkedActivityId: review.draft.linkedActivityId,
          formValues: {...review.draft.formValues, ...nextDraft.formValues},
        );
      }
      if (nextDraft == null) {
        setState(
          () => _appendEntry(
            FfmAssistantChatEntry(
              isUser: false,
              text:
                  '${jsonError ?? 'JSON tidak berisi draft yang dapat dipakai.'} Draft aktif belum berubah.',
            ),
          ),
        );
        return true;
      }
    } else {
      nextDraft = _draftFromTextRevision(review.draft, normalized);
    }
    if (nextDraft == null) return false;
    _personalMemoryService.feedbackService.recordDraftEdit(
      originalDraft: review.draft,
      editedDraft: nextDraft,
      timestamp: DateTime.now(),
    );
    final nextReview = review.revise(
      nextDraft: nextDraft,
      nextIssues: FfmAssistantDraftValidator.validate(nextDraft),
      changeSummary: _revisionSummary(review.draft, nextDraft),
    );
    final revisedIntent = sourceIntent.copyWith(
      draft: nextDraft,
      response:
          'Sip, ${nextReview.changeSummary} Cek versi ${nextReview.version} ini dulu, ya.',
    );
    setState(() {
      widget.session
        ..activeDraftReview = nextReview
        ..activeDraftIntent = revisedIntent;
      _replaceActiveQueueItem(intent: revisedIntent, review: nextReview);
      _appendEntry(
        FfmAssistantChatEntry(
          isUser: false,
          text: revisedIntent.response!,
          intent: revisedIntent,
          understanding: looksLikeProposalJson
              ? 'Kamu mengirim JSON koreksi untuk draft yang sedang aktif.'
              : 'Kamu meminta revisi untuk draft yang sedang aktif.',
          review: nextReview,
        ),
      );
    });
    _scrollToEnd();
    return true;
  }

  FfmAssistantDraft? _draftFromTextRevision(
    FfmAssistantDraft draft,
    String normalized,
  ) {
    final amountMatch = RegExp(
      r'(?:nominal|jumlah|nilai|jadi)\s*(?:rp\.?\s*)?([\d.,]+)\s*(ribu|rb|k|juta|jt)?',
    ).firstMatch(normalized);
    if (amountMatch != null) {
      final amount = _parseRupiah(amountMatch.group(1)!, amountMatch.group(2));
      if (amount != null) return draft.copyWith(amount: amount);
    }
    final fieldMatch = RegExp(
      r'(rekening asal|asal|rekening tujuan|tujuan|kategori|target|catatan|judul|nama|pihak|pemberi hutang|pemberi pinjaman|peminjam|sumber|toko|tempat|lokasi|cicilan|periode)\s*(?:jadi|ke)\s+(.+)$',
    ).firstMatch(normalized);
    if (fieldMatch == null) return null;
    final field = fieldMatch.group(1)!;
    final value = fieldMatch.group(2)!.trim();
    if (value.isEmpty) return null;
    return switch (field) {
      'rekening asal' || 'asal' => draft.copyWith(fromAccountName: value),
      'rekening tujuan' || 'tujuan' => draft.copyWith(toAccountName: value),
      'kategori' => draft.copyWith(categoryName: value),
      'target' => draft.copyWith(goalName: value),
      'catatan' => draft.copyWith(note: value),
      'judul' || 'nama' => draft.copyWith(title: value),
      'pihak' ||
      'pemberi hutang' ||
      'pemberi pinjaman' ||
      'peminjam' ||
      'sumber' =>
        draft.copyWith(
          partyName: value,
          formValues: {
            ...draft.formValues,
            'party': value,
            'partyName': value,
            if (draft.kind == FfmAssistantDraftKind.income)
              'incomeSource': value,
          },
        ),
      'toko' || 'tempat' => draft.copyWith(
        merchantName: value,
        formValues: {...draft.formValues, 'merchant': value},
      ),
      'lokasi' => draft.copyWith(
        location: value,
        formValues: {...draft.formValues, 'location': value},
      ),
      'cicilan' => draft.copyWith(
        formValues: {...draft.formValues, 'monthlyInstallment': value},
      ),
      'periode' => draft.copyWith(
        formValues: {
          ...draft.formValues,
          'periodType': switch (value.toLowerCase()) {
            'mingguan' || 'weekly' => 'weekly',
            'per dua minggu' || 'biweekly' => 'biweekly',
            'tidak rutin' || 'nonrecurring' => 'nonrecurring',
            _ => 'monthly',
          },
        },
      ),
      _ => null,
    };
  }

  int? _parseRupiah(String raw, String? unit) {
    final plain = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final base = int.tryParse(plain);
    if (base == null) return null;
    return switch (unit) {
      'ribu' || 'rb' || 'k' => base * 1000,
      'juta' || 'jt' => base * 1000000,
      _ => base,
    };
  }

  String _revisionSummary(FfmAssistantDraft before, FfmAssistantDraft after) {
    if (before.amount != after.amount) {
      return 'nominal diubah dari ${FfmAssistantDraftPreview.rupiah(before.amount ?? 0)} menjadi ${FfmAssistantDraftPreview.rupiah(after.amount ?? 0)}.';
    }
    if (before.fromAccountName != after.fromAccountName) {
      return 'rekening asal diubah menjadi ${after.fromAccountName}.';
    }
    if (before.toAccountName != after.toAccountName) {
      return 'rekening tujuan diubah menjadi ${after.toAccountName}.';
    }
    if (before.categoryName != after.categoryName) {
      return 'kategori diubah menjadi ${after.categoryName}.';
    }
    if (before.partyName != after.partyName) {
      return 'pihak diubah menjadi ${after.partyName}.';
    }
    if (before.merchantName != after.merchantName) {
      return 'toko/tempat diubah menjadi ${after.merchantName}.';
    }
    if (before.location != after.location) {
      return 'lokasi diubah menjadi ${after.location}.';
    }
    if (before.goalName != after.goalName) {
      return 'target diubah menjadi ${after.goalName}.';
    }
    if (before.formValues['monthlyInstallment'] !=
        after.formValues['monthlyInstallment']) {
      return 'cicilan diubah menjadi ${after.formValues['monthlyInstallment']}.';
    }
    if (before.formValues['periodType'] != after.formValues['periodType']) {
      return 'periode anggaran diubah menjadi ${after.formValues['periodType']}.';
    }
    return 'draft diperbarui.';
  }

  Future<List<String>> _loadAccountNames() async {
    try {
      final rows = await AccountRepository(
        getIt<AppDatabase>(),
        AuditLogger(getIt<AppDatabase>()),
      ).readActive(AppContext.householdId);
      return rows.map((row) => row.name).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _editActiveDraft(FfmAssistantIntent intent) async {
    final review = widget.session.activeDraftReview;
    if (review == null) return;
    if (_activeDraftIsOpeningForm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kembali dari form tanpa menyimpan dulu sebelum mengoreksi draft.',
          ),
        ),
      );
      return;
    }
    final accounts = await _loadAccountNames();
    if (!mounted) return;
    final nextDraft = await showDialog<FfmAssistantDraft>(
      context: context,
      builder: (_) => FfmAssistantDraftEditDialog(
        draft: review.draft,
        feedbackService: _personalMemoryService.feedbackService,
        accounts: accounts,
      ),
    );
    if (nextDraft == null || !mounted) return;
    final nextReview = review.revise(
      nextDraft: nextDraft,
      nextIssues: FfmAssistantDraftValidator.validate(nextDraft),
      changeSummary: _revisionSummary(review.draft, nextDraft),
    );
    final revisedIntent = intent.copyWith(
      draft: nextDraft,
      response:
          'Sip, ${nextReview.changeSummary} Cek versi ${nextReview.version} ini dulu, ya.',
    );
    setState(() {
      widget.session
        ..activeDraftReview = nextReview
        ..activeDraftIntent = revisedIntent;
      _replaceActiveQueueItem(intent: revisedIntent, review: nextReview);
      _appendEntry(
        FfmAssistantChatEntry(
          isUser: false,
          text: revisedIntent.response!,
          intent: revisedIntent,
          understanding: 'Kamu mengubah field draft lewat form review.',
          review: nextReview,
        ),
      );
    });
    _scrollToEnd();
  }

  void _cancelActiveDraft([FfmAssistantIntent? intent]) {
    if (_activeDraftIsOpeningForm) {
      setState(
        () => _appendEntry(
          const FfmAssistantChatEntry(
            isUser: false,
            text: 'Draft sedang dibuka di form sehingga belum dapat dibatalkan. Kembali dari form tanpa menyimpan terlebih dahulu.',
          ),
        ),
      );
      return;
    }
    setState(() {
      if (intent != null) _queuedIntents.remove(intent);
      final id = widget.session.activeDraftQueueId;
      if (id != null) {
        final index = _draftQueue.indexWhere((item) => item.id == id);
        if (index >= 0) {
          _draftQueue[index] = _draftQueue[index].copyWith(
            status: FfmAssistantDraftQueueStatus.cancelled,
          );
        }
      }
      widget.session
        ..activeDraftReview = null
        ..activeDraftIntent = null
        ..activeDraftQueueId = null;
      _appendEntry(
        const FfmAssistantChatEntry(
          isUser: false,
          text: 'Draft aktif sudah dibatalkan. Tidak ada data yang disimpan.',
        ),
      );
    });
  }

  FfmAssistantFeedbackContext? _feedbackContextFor(
    FfmAssistantChatEntry entry,
  ) {
    if (entry.isUser) return null;
    final index = _entries.indexOf(entry);
    if (index < 1) return null;
    for (var cursor = index - 1; cursor >= 0; cursor--) {
      final candidate = _entries[cursor];
      if (candidate.isUser && candidate.text.trim().isNotEmpty) {
        return FfmAssistantFeedbackContext(
          userQuestion: candidate.text,
          assistantAnswer: entry.text,
        );
      }
    }
    return null;
  }

  Future<void> _showFeedbackActions(FfmAssistantChatEntry entry) async {
    final feedback = _feedbackContextFor(entry);
    if (feedback == null) return;
    final kind = await showDialog<FfmAssistantResponseFeedbackKind>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tinjau jawaban Asisten'),
        content: const Text(
          'Pilih masalahnya. Laporan akan disanitasi dan masuk Pusat Pengetahuan untuk review; tidak langsung menjadi knowledge.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext)
                    .pop(FfmAssistantResponseFeedbackKind.unhelpful),
            child: const Text('Tidak membantu'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext)
                    .pop(FfmAssistantResponseFeedbackKind.incomplete),
            child: const Text('Kurang lengkap'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext)
                    .pop(FfmAssistantResponseFeedbackKind.incorrect),
            child: const Text('Keliru'),
          ),
        ],
      ),
    );
    if (kind == null) return;
    final saved = await _responseFeedbackRepository.record(
      questionText: feedback.userQuestion,
      responseText: feedback.assistantAnswer,
      kind: kind,
      pageContext: widget.currentDestination?.name,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved == null
              ? 'Feedback belum dapat disimpan. Coba periksa kembali pesannya.'
              : 'Feedback tersimpan untuk ditinjau di Pusat Pengetahuan.',
        ),
      ),
    );
  }

  Future<void> _copyEntryText(FfmAssistantChatEntry entry) async {
    await Clipboard.setData(ClipboardData(text: entry.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          entry.isUser
              ? 'Pesan kamu sudah disalin.'
              : 'Jawaban Asisten sudah disalin.',
        ),
      ),
    );
  }

  Future<void> _correctMessageFromEntry(FfmAssistantChatEntry entry) async {
    final feedback = _feedbackContextFor(entry);
    if (feedback == null) return;
    final correction = await showDialog<FfmAssistantMessageCorrection>(
      context: context,
      builder: (_) => FfmAssistantMessageCorrectionDialog(
        originalMessage: feedback.userQuestion,
      ),
    );
    if (correction == null || !mounted) return;
    if (correction.rememberLocally) {
      try {
        await _memoryRepository.save(
          kind: 'alias',
          triggerText: feedback.userQuestion,
          valueText: correction.correctedText,
          source: 'chat_message_correction',
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Koreksi diproses, tapi belum bisa diingat lokal.'),
          ),
        );
      }
    }
    if (!mounted) return;
    _submit(correction.correctedText);
  }

  Future<void> _correctUserMessage(FfmAssistantChatEntry entry) async {
    final correction = await showDialog<FfmAssistantMessageCorrection>(
      context: context,
      builder: (_) =>
          FfmAssistantMessageCorrectionDialog(originalMessage: entry.text),
    );
    if (correction == null || !mounted) return;
    if (correction.rememberLocally) {
      try {
        await _memoryRepository.save(
          kind: 'alias',
          triggerText: entry.text,
          valueText: correction.correctedText,
          source: 'chat_message_correction',
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pesan diperbaiki, tapi alias lokal belum tersimpan.',
            ),
          ),
        );
      }
    }
    if (!mounted) return;
    await _submit(correction.correctedText);
  }

  Future<void> _confirmResetSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset chat?'),
        content: const Text(
          'Riwayat chat dan antrean perintah yang belum dibuka akan dihapus. Data keuangan tidak ikut berubah.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset chat'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(widget.session.reset);
      await _historyRepository.clear();
      await _historyRepository.save(_entries);
      FfmPersonalContextProvider.maybeInstance?.clearWorkingContext();
      _scrollToEnd();
    }
  }

  Future<void> _openUpdateCheckpointFromLiveBar(
    ActivitySessionEntity session,
  ) async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Update Checkpoint untuk ${session.title}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Contoh: Rest Area KM 120, Masuk Tol, dsb.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogCtx).pop(controller.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (label == null || label.isEmpty || !mounted) return;

    if (getIt.isRegistered<ActivityApplicationService>()) {
      final res = await getIt<ActivityApplicationService>().addCheckpoint(
        operationId: '${DateTime.now().millisecondsSinceEpoch}-cp',
        sessionId: session.id,
        label: label,
        source: ActivityEntrySource.assistant,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(res.message)));
    }
  }

  Future<void> _finishSessionFromLiveBar(ActivitySessionEntity session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Selesaikan ${session.title}?'),
        content: const Text(
          'Sesi aktivitas ini akan ditutup dan durasinya direkam.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Selesaikan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    if (getIt.isRegistered<ActivityApplicationService>()) {
      final res = await getIt<ActivityApplicationService>().finishSession(
        operationId: '${DateTime.now().millisecondsSinceEpoch}-finish',
        sessionId: session.id,
        source: ActivityEntrySource.assistant,
        forceCloseChildren: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(res.message)));
    }
  }

  void _updateLatestMessagePreference() {
    if (!_scrollController.hasClients) return;
    final distanceToEnd =
        _scrollController.position.maxScrollExtent - _scrollController.offset;
    final followLatest = distanceToEnd < 88;
    final showScrollControl = distanceToEnd > 200;
    if (_followLatestMessages == followLatest &&
        _showScrollToBottom == showScrollControl) {
      return;
    }
    if (mounted) {
      setState(() {
        _followLatestMessages = followLatest;
        _showScrollToBottom = showScrollControl;
      });
    }
  }

  String? _buildRecentConversationHistory() {
    if (_entries.isEmpty) return null;
    final recent = _entries.length > 8
        ? _entries.sublist(_entries.length - 8)
        : _entries;
    final lines = <String>[];
    for (final entry in recent) {
      final role = entry.isUser ? 'Pengguna' : 'Asisten';
      final text = entry.text.trim();
      if (text.isNotEmpty) {
        final snippet = text.split('\n').take(3).join(' ').trim();
        final truncated = snippet.length > 200
            ? '${snippet.substring(0, 200)}...'
            : snippet;
        lines.add('$role: $truncated');
      }
      if (entry.intent?.draft != null) {
        final draft = entry.intent!.draft!;
        lines.add('  [Draft: ${draft.kind.name} Rp ${draft.amount}]');
      }
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  void _scrollToEnd({bool force = true, bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || (!force && !_followLatestMessages)) {
        return;
      }
      final offset = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(offset);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentPage = widget.currentDestination == null
        ? null
        : FfmAssistantCatalog.findByDestination(widget.currentDestination!);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: isDark
          ? const Color(0xFF1E1B18)
          : const Color(0xFFFDFCF9),
      body: SafeArea(
        child: Material(
          color: isDark ? const Color(0xFF1E1B18) : const Color(0xFFFDFCF9),
          child: Column(
            children: [
              GeminiHeader(
                currentPage: currentPage,
                isFullScreen: _isFullScreen,
                showFullscreenToggle: false,
                onToggleFullScreen: () {},
                onOpenVoicePicker: _openVoicePicker,
                onResetChat: _confirmResetSession,
                onClose: () => Navigator.of(context).pop(),
                cloudChecking: _cloudChecking,
                cloudReady: _cloudReady,
                cloudStatusError: _cloudStatusError,
                cloudModel: _cloudModel,
                onRefreshCloudStatus: _refreshCloudStatus,
                onSetupGemini: _openGeminiSetup,
                memoryCount: _memoryCount,
                onOpenMemory: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => const FfmMemoryViewerPage(),
                        fullscreenDialog: true,
                      ),
                    )
                    .then((_) => _refreshMemoryCount()),
                inboxCount: _inboxCount,
                onOpenInbox: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => const AgentInboxPage(),
                        fullscreenDialog: true,
                      ),
                    )
                    .then((_) => _refreshInboxCount()),
              ),
              Divider(
                height: 1,
                color: isDark
                    ? const Color(0xFF2E2A26)
                    : const Color(0xFFE8E0D0),
              ),
              Expanded(
                child: Stack(
                  children: [
                    ListView.separated(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 76),
                      itemCount: _entries.length + (_submitting ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, index) {
                        if (_submitting && index == _entries.length) {
                          return GeminiTypingIndicator(
                            message: _activeProcessLabel,
                            steps: _activeProcessEvents
                                .map((e) => '${e.label} (T+${e.elapsed.inMilliseconds} ms)')
                                .toList(),
                            currentStepIndex: _activeProcessEvents.isNotEmpty
                                ? _activeProcessEvents.length - 1
                                : 0,
                          );
                        }
                        final entry = _entries[index];
                        final opensCurrentPage =
                            entry.intent?.destination != null &&
                            entry.intent!.destination ==
                                widget.currentDestination &&
                            entry.intent!.draft == null;
                        final isStreamingThis =
                            identical(_streamingEntry, entry) &&
                            _streamingController.isStreaming;
                        return FfmAssistantMessageCard(
                          entry: entry,
                          visibleText: isStreamingThis
                              ? _streamingVisibleText
                              : null,
                          isStreaming: isStreamingThis,
                          onSpeak: entry.isUser
                              ? null
                              : () => _toggleSpeakFor(index, entry),
                          isSpeaking:
                              _speakingEntryKey == _speechKeyFor(index, entry),
                          onIntent:
                              entry.intent?.responseOrigin ==
                                  FfmAssistantResponseOrigin.cloudError
                              ? () => _submit(entry.intent!.rawText)
                              : entry.intent?.needsTeachingApproval ?? false
                              ? () => _approveTeaching(entry.intent!)
                              : entry.intent == null ||
                                    (entry.intent!.destination == null &&
                                        entry.intent!.draft == null &&
                                        entry.intent!.type !=
                                            FfmAssistantIntentType
                                                .exportReport &&
                                        entry.intent!.type !=
                                            FfmAssistantIntentType.confirm)
                              ? null
                              : () => _handleEntryIntent(entry),
                          primaryActionLabel:
                              entry.intent?.needsTeachingApproval ?? false
                              ? 'Simpan ajaran'
                              : entry.intent?.responseOrigin ==
                                    FfmAssistantResponseOrigin.cloudError
                              ? 'Coba lagi'
                              : entry.intent?.draft != null
                              ? 'Tinjau & konfirmasi'
                              : opensCurrentPage
                              ? 'Cek halaman'
                              : entry.intent?.destination != null
                              ? 'Buka'
                              : 'Lanjut',
                          onApproveTeaching:
                              entry.intent?.needsTeachingApproval ?? false
                              ? () => _approveTeaching(entry.intent!)
                              : null,
                          teachingSaved: entry.intent?.teachingProposal == null
                              ? false
                              : _savedTeachingKeys.contains(
                                  _teachingKey(entry.intent!.teachingProposal!),
                                ),
                          review: entry.review,
                          onEditDraft:
                              entry.intent?.draft != null &&
                                  entry.review != null
                              ? () => _editDraftFromEntry(entry)
                              : null,
                          onCancelDraft:
                              entry.intent?.draft != null &&
                                  entry.review != null
                              ? () => _cancelDraftFromEntry(entry)
                              : null,
                          onCopyFeedback: entry.isUser
                              ? null
                              : () => _showFeedbackActions(entry),
                          onToggleTechnicalDetails: entry.intent == null
                              ? null
                              : () {
                                  setState(() {
                                    if (_technicalDetailsExpanded.contains(index)) {
                                      _technicalDetailsExpanded.remove(index);
                                    } else {
                                      _technicalDetailsExpanded.add(index);
                                    }
                                  });
                                },
                          showTechnicalDetails: _technicalDetailsExpanded.contains(index),
                          onRetryGemini:
                              entry.intent?.responseOrigin ==
                                  FfmAssistantResponseOrigin.cloudError
                              ? () => _submit(entry.intent!.rawText)
                              : null,
                          onCopyText: () => _copyEntryText(entry),
                          onShareFile: entry.filePath == null
                              ? null
                              : () => _shareFile(
                                  entry.filePath!,
                                  entry.fileFormat,
                                ),
                          onCorrectMessage: entry.isUser
                              ? () => _correctUserMessage(entry)
                              : () => _correctMessageFromEntry(entry),
                          onConfirmActivity:
                              entry.activityIntent?.canConfirm ?? false
                              ? () => _confirmActivityIntent(
                                  entry.activityIntent!,
                                )
                              : null,
                          activityConfirmed: entry.activityIntent == null
                              ? false
                              : _confirmedActivityKeys.contains(
                                  _activityKey(entry.activityIntent!),
                                ),
                          actionPlan: entry.intent == null
                              ? null
                              : _actionPlanController.get(
                                  _actionPlanner.planFor(entry.intent!)?.id ??
                                      '',
                                ),
                          onActivityFinish: (sessionId) =>
                              _submit('selesai aktivitas $sessionId'),
                          onActivityUpdate: (sessionId) =>
                              _submit('update aktivitas $sessionId: '),
                          onActivityChat: (sessionId) =>
                              _submit('cek aktivitas $sessionId'),
                        );
                      },
                    ),
                    Positioned(
                      right: 18,
                      bottom: 14,
                      child: AnimatedOpacity(
                        opacity: _showScrollToBottom ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: IgnorePointer(
                          ignoring: !_showScrollToBottom,
                          child: Semantics(
                            button: true,
                            label: 'Lompat ke pesan terbaru',
                            child: FloatingActionButton.small(
                              heroTag: 'ffm-assistant-scroll-bottom',
                              tooltip: 'Pesan terbaru',
                              onPressed: () => _scrollToEnd(force: true),
                              child: const Icon(Icons.arrow_downward_rounded),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_submitting) const LinearProgressIndicator(minHeight: 2),
              if (getIt.isRegistered<ActivityBloc>())
                BlocBuilder<ActivityBloc, ActivityState>(
                  bloc: getIt<ActivityBloc>(),
                  builder: (context, actState) {
                    final snapshot = actState.toSnapshot();
                    if (!snapshot.hasActiveSessions) {
                      return const SizedBox.shrink();
                    }
                    return ActivityLiveBar(
                      snapshot: snapshot,
                      onUpdateCheckpoint: (session) =>
                          _openUpdateCheckpointFromLiveBar(session),
                      onFinishSession: (session) =>
                          _finishSessionFromLiveBar(session),
                    );
                  },
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, _) {
                      final canSend =
                          !_submitting && value.text.trim().isNotEmpty;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF111111)
                                  : const Color(0xFFFFFFFF),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF666666)
                                    : const Color(0xFF000000),
                                width: 2.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: isDark ? .30 : .12,
                                  ),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                IconButton(
                                  tooltip: _listening
                                      ? 'Berhenti dengar'
                                      : 'Bicara ke Asisten',
                                  onPressed: _submitting
                                      ? null
                                      : _toggleListening,
                                  icon: Icon(
                                    _listening ? Icons.stop : Icons.mic_none,
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _controller,
                                    focusNode: _inputFocusNode,
                                    minLines: 1,
                                    maxLines: 5,
                                    textInputAction: TextInputAction.newline,
                                    onTap: _scrollToEnd,
                                    decoration: const InputDecoration(
                                      hintText:
                                          'Tulis perintah atau pertanyaan…',
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(
                                        vertical: 13,
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                    right: 5,
                                    bottom: 5,
                                  ),
                                  child: IconButton.filled(
                                    tooltip: 'Kirim',
                                    onPressed: canSend ? _submit : null,
                                    icon: const Icon(Icons.arrow_upward),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
