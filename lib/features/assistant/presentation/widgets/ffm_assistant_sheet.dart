import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../activity/data/repositories/activity_repository.dart';
import '../../../activity/data/services/activity_speech_service.dart';
import '../../../activity/domain/entities/activity_entity.dart';
import '../../../activity/domain/activity_voice.dart';
import '../../../activity/presentation/bloc/activity_bloc.dart';
import '../../data/ffm_assistant_capability_adapters.dart';
import '../../domain/ffm_assistant_capability_executor.dart';
import '../../data/ffm_assistant_chat_history_repository.dart';
import '../../data/ffm_assistant_interpreter.dart';
import '../../data/ffm_assistant_report_service.dart';
import '../../data/ffm_assistant_chat_export_service.dart';
import '../../data/ffm_assistant_response_feedback_repository.dart';
import '../../data/ffm_assistant_slm_follow_up_service.dart';
import '../../data/ffm_assistant_memory_repository.dart';
import '../../data/ffm_assistant_unanswered_question_repository.dart';
import '../../data/ffm_local_model_service.dart';
import '../../domain/ffm_assistant_action_plan.dart';
import '../../domain/ffm_assistant_action_planner.dart';
import '../../domain/ffm_assistant_draft_validator.dart';
import '../../domain/ffm_assistant_feedback_context.dart';
import '../../domain/ffm_assistant_models.dart';
import '../../domain/ffm_assistant_proactive_service.dart';
import '../../data/ffm_assistant_user_model_service.dart';
import '../../data/ffm_personal_memory_service.dart';
import 'chat/ffm_assistant_draft_preview.dart';
import 'chat/ffm_json_expandable.dart';
import 'chat/ffm_assistant_message_card.dart';
import 'ffm_memory_nudge_card.dart';
import 'gemini_header.dart';
import 'gemini_typing_indicator.dart';
import 'ffm_assistant_page_context.dart';
import 'ffm_agent_status_indicator.dart';
import '../../data/ffm_image_helper.dart';
import 'ffm_assistant_draft_edit_dialog.dart';
import 'ffm_assistant_message_correction_dialog.dart';
import 'ffm_assistant_markdown_text.dart';
import '../pages/ffm_memory_viewer_page.dart';

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
  FfmAssistantDestination? currentDestination,
  FfmAssistantPageContextSnapshot? currentPageContext,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => FfmAssistantSheet(
      onIntent: onIntent,
      onIntents: onIntents,
      session: session,
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
    this.currentDestination,
    this.currentPageContext,
  });

  final FfmAssistantIntentHandler onIntent;
  final FfmAssistantIntentBatchHandler onIntents;
  final FfmAssistantChatSession session;
  final FfmAssistantDestination? currentDestination;
  final FfmAssistantPageContextSnapshot? currentPageContext;

  @override
  State<FfmAssistantSheet> createState() => _FfmAssistantSheetState();
}

class _FfmAssistantSheetState extends State<FfmAssistantSheet> {
  final _controller = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _imageHelper = FfmImageHelper();
  final _historyRepository = FfmAssistantChatHistoryRepository();
  final _actionPlanController = FfmAssistantActionPlanController();
  final _actionPlanner = const FfmAssistantActionPlanner();
  late final _capabilityExecutor = FfmAssistantCapabilityExecutor(
    controller: _actionPlanController,
    handlers: getIt<FfmAssistantCapabilityAdapterRegistry>().handlers,
    readTransaction: <T>(action) => getIt<AppDatabase>().transaction(action),
    onPlanProgress: (_) {
      if (mounted) setState(() {});
    },
  );
  final _proactiveService = const FfmAssistantProactiveSuggestionService();
  final _slmFollowUpService = getIt<FfmAssistantSlmFollowUpService>();
  final _speech = ActivitySpeechService();
  final _interpreter = getIt<FfmAssistantInterpreter>();
  final _agentStatus = getIt.isRegistered<FfmAgentStatusController>()
      ? getIt<FfmAgentStatusController>()
      : FfmAgentStatusController();
  final _modelService = getIt<FfmLocalModelService>();
  final _chatExportService = FfmAssistantChatExportService();
  final _memoryRepository = getIt<FfmAssistantMemoryRepository>();
  final _responseFeedbackRepository =
      getIt<FfmAssistantResponseFeedbackRepository>();
  final _unansweredRepository =
      getIt<FfmAssistantUnansweredQuestionRepository>();
  final _activityRepository = getIt<ActivityRepository>();
  final _activityVoiceParser = const ActivityVoiceParser();
  final Set<String> _savedTeachingKeys = <String>{};
  final Set<String> _confirmedActivityKeys = <String>{};
  var _submitting = false;
  var _activeProcessLabel = 'Menyiapkan permintaan...';
  File? _pendingImage;
  var _navigatingFromChat = false;
  var _modelReady = false;
  var _modelChecking = true;
  var _isFullScreen = true;
  String? _modelStatusError;
  var _listening = false;
  var _followLatestMessages = true;
  var _showScrollToBottom = false;
  List<String> _slmFollowUpSuggestions = const <String>[];
  var _followUpGeneration = 0;
  String? _speakingEntryKey;
  String? _pausedEntryKey;
  String? _speakingSessionId;
  String? _pausedSpeechSessionId;
  var _listeningSession = 0;
  StreamSubscription<ActivitySpeechPlaybackState>? _speechStateSubscription;
  Future<void>? _historyRestoreFuture;

  // Personal Memory Mode
  late final _personalMemoryService = FfmPersonalMemoryService(
    getIt<FfmAssistantMemoryRepository>(),
  );
  FfmPersonalMemoryInsight? _pendingMemoryNudge;
  var _memoryCount = 0;

  List<FfmAssistantChatEntry> get _entries => widget.session.entries;

  void _setActiveProcess(String message) {
    if (mounted) setState(() => _activeProcessLabel = message);
    _agentStatus.working(message);
  }

  FfmAssistantProcessTrace _traceFor(
    FfmAssistantIntent intent,
    Duration elapsed, {
    required bool hasImage,
  }) {
    final origin = intent.responseOrigin;
    final visionFailure = intent.visionFailure;
    final sourceEvent = switch (origin) {
      FfmAssistantResponseOrigin.agentOrchestrator => const (
        label: 'Agent Orkestrator menyelesaikan rute lokal',
        detail: 'Jawaban berasal dari aturan, katalog, atau query lokal yang sesuai.',
      ),
      FfmAssistantResponseOrigin.localSlm => const (
        label: 'SLM lokal mengembalikan proposal valid',
        detail: 'Proposal tetap divalidasi FFM sebelum ditampilkan.',
      ),
      FfmAssistantResponseOrigin.localFallback => const (
        label: 'SLM lokal belum menghasilkan proposal yang dapat dipakai',
        detail:
            'FFM menampilkan fallback lokal tanpa membuat atau mengubah data.',
      ),
    };
    return FfmAssistantProcessTrace(
      origin: origin,
      elapsed: elapsed,
      fallbackReason: origin == FfmAssistantResponseOrigin.localFallback
          ? visionFailure?.traceLabel ?? 'Proposal visi ditolak validator'
          : null,
      events: [
        FfmAssistantProcessEvent(
          label: hasImage
              ? 'Lampiran diterima untuk dianalisis'
              : 'Permintaan diterima untuk dirutekan',
          elapsed: Duration.zero,
        ),
        FfmAssistantProcessEvent(
          label: visionFailure?.traceLabel ?? sourceEvent.label,
          detail: visionFailure == null ? sourceEvent.detail : 'FFM menampilkan fallback lokal tanpa membuat atau mengubah data.',
          elapsed: elapsed,
        ),
      ],
    );
  }

  String _completedProcessLabel(FfmAssistantIntent intent) =>
      switch (intent.responseOrigin) {
        FfmAssistantResponseOrigin.localSlm =>
          'Jawaban dibantu SLM lokal dan siap diperiksa.',
        FfmAssistantResponseOrigin.localFallback =>
          'SLM lokal belum memberi hasil valid; fallback siap diperiksa.',
        FfmAssistantResponseOrigin.agentOrchestrator =>
          'Agent Orkestrator menyelesaikan jawaban lokal.',
      };

  void _showTechnicalDetails(FfmAssistantIntent intent) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (dialogContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FfmJsonExpandable(intent: intent, initiallyExpanded: true),
        ),
      ),
    );
  }

  void _appendEntry(FfmAssistantChatEntry entry) {
    _entries.add(entry);
    unawaited(_historyRepository.save(_entries));
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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateLatestMessagePreference);
    _speechStateSubscription = _speech.playbackStates.listen(_onSpeechState);
    _historyRestoreFuture = _restoreChatHistory();
    _refreshModelStatus();
    _refreshMemoryCount();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToEnd(force: true, animated: false),
    );
  }

  Future<void> _refreshModelStatus() async {
    try {
      final installed = await _modelService.getInstalled();
      if (!mounted) return;
      setState(() {
        _modelReady =
            installed?.isVerified == true && installed?.projectorPath != null;
        _modelChecking = false;
        _modelStatusError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _modelReady = false;
        _modelChecking = false;
        _modelStatusError = 'Status model tidak dapat dibaca';
      });
    }
  }

  Future<void> _refreshMemoryCount() async {
    final all = await _personalMemoryService.readAll();
    if (!mounted) return;
    setState(() => _memoryCount = all.length);
  }

  Future<void> _refreshSlmFollowUpSuggestions() async {
    final generation = ++_followUpGeneration;
    if (!_modelReady || _submitting || !_entries.any((entry) => entry.isUser)) {
      if (mounted && _slmFollowUpSuggestions.isNotEmpty) {
        setState(() => _slmFollowUpSuggestions = const <String>[]);
      }
      return;
    }
    final suggestions = await _slmFollowUpService.generateForConversation(
      List<FfmAssistantChatEntry>.of(_entries),
    );
    if (!mounted || generation != _followUpGeneration || _submitting) return;
    setState(() => _slmFollowUpSuggestions = suggestions);
  }

  void _checkForMemoryNudge(String userMessage) {
    if (userMessage.trim().isEmpty) return;
    final insight = _personalMemoryService.extractFromMessage(userMessage);
    if (insight != null && mounted) {
      setState(() => _pendingMemoryNudge = insight);
    }
  }

  Future<void> _saveMemoryNudge() async {
    final insight = _pendingMemoryNudge;
    if (insight == null) return;
    setState(() => _pendingMemoryNudge = null);
    await _personalMemoryService.saveApproved(insight);
    await _refreshMemoryCount();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Aku sudah mengingatnya!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openLocalModelPage() async {
    await _handleIntent(
      FfmAssistantIntent(
        rawText: 'siapkan AI lokal',
        normalizedText: 'siapkan ai lokal',
        type: FfmAssistantIntentType.openPage,
        destination: FfmAssistantDestination.localModel,
        confidence: 1,
        response: 'Aku buka Model Asisten Lokal supaya kamu bisa memilih download GitHub atau impor bundle offline.',
      ),
    );
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
    super.dispose();
  }

  Future<void> _stagePendingImage(bool fromCamera) async {
    await _historyRestoreFuture;
    if (_submitting) return;
    final file = fromCamera
        ? await _imageHelper.pickFromCamera()
        : await _imageHelper.pickFromGallery();
    if (file == null || !mounted) return;
    final chatFile = await _imageHelper.copyToPrivateChatStorage(file);
    if (!mounted) return;
    setState(() => _pendingImage = chatFile);
    _inputFocusNode.requestFocus();
  }

  Future<void> _executeReadPlan(String planId) async {
    _agentStatus.working('Membaca data yang diperlukan secara lokal...');
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
      _agentStatus.failed('Pembacaan data belum selesai.');
      setState(() {
        widget.session.lastAssistantText = message;
        _appendEntry(FfmAssistantChatEntry(isUser: false, text: message));
      });
      _scrollToEnd();
      return;
    }
    _agentStatus.done('Data dibaca; jawaban siap diperiksa.');
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
    _agentStatus.working('Menyimpan perubahan yang sudah kamu konfirmasi...');
    final plan = await _capabilityExecutor.execute(planId);
    if (!mounted || plan == null) return;
    final failed = plan.steps.where(
      (step) => step.status == FfmAssistantActionStepStatus.failed,
    );
    if (plan.status != FfmAssistantActionPlanStatus.completed ||
        failed.isNotEmpty) {
      final detail = failed.isEmpty
          ? 'Perubahan tidak dijalankan.'
          : failed.first.error ?? 'Perubahan tidak dapat diverifikasi.';
      final message =
          'Perubahan ${subject.toLowerCase()} tidak selesai. $detail';
      _agentStatus.failed('Perubahan ${subject.toLowerCase()} belum selesai.');
      setState(() {
        widget.session.lastAssistantText = message;
        _appendEntry(FfmAssistantChatEntry(isUser: false, text: message));
        _queuedIntents.remove(intent);
      });
      _scrollToEnd();
      return;
    }
    final verify = plan.steps.where(
      (step) =>
          step.capabilityId == 'verify.transaction_mutation' ||
          step.capabilityId == 'verify.activity_mutation',
    );
    final message = verify.isEmpty
        ? 'Perubahan ${subject.toLowerCase()} selesai dan sudah dicatat secara lokal.'
        : verify.first.result ??
              'Perubahan ${subject.toLowerCase()} selesai dan telah diverifikasi.';
    _agentStatus.done(
      'Perubahan ${subject.toLowerCase()} selesai dan terverifikasi.',
    );
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
    final File? stagedImage = _pendingImage;
    final hasImage = stagedImage != null;
    if ((text.isEmpty && !hasImage) || _submitting) return;
    final displayText = text.isEmpty && hasImage ? 'Gambar dilampirkan' : text;
    setState(() {
      _submitting = true;
      _followUpGeneration++;
      _slmFollowUpSuggestions = const <String>[];
      _appendEntry(
        FfmAssistantChatEntry(
          isUser: true,
          text: displayText,
          imagePath: stagedImage?.path,
          createdAt: DateTime.now(),
        ),
      );
      _controller.clear();
      _pendingImage = null;
    });
    _scrollToEnd(force: true);
    _checkForMemoryNudge(text);
    if (hasImage) {
      final stopwatch = Stopwatch()..start();
      _setActiveProcess('Meneruskan lampiran ke visi SLM lokal...');
      try {
        final intent = await _interpreter.interpret(
          text,
          imagePath: stagedImage.path,
          currentDestination: widget.currentDestination,
          pageContext: FfmAssistantScreenContextPolicy.forPrompt(
            destination: widget.currentDestination,
            snapshot: widget.currentPageContext,
          ),
          capabilityIds: widget.currentPageContext?.capabilityIds ?? const [],
        );
        stopwatch.stop();
        if (!mounted) return;
        final processTrace = _traceFor(
          intent,
          stopwatch.elapsed,
          hasImage: true,
        );
        final readPlanIds = <String>[];
        setState(() {
          String response = intent.response ?? intent.clarification ?? '';
          if (response.isEmpty) {
            if (intent.responseMode == FfmAssistantResponseMode.localModel &&
                intent.type == FfmAssistantIntentType.help) {
              response = 'Aku mengerti ini terkait literasi keuangan keluarga. (Jawaban SLM offline akan muncul di sini).';
            } else if (intent.draft != null) {
              response =
                  'Aku sudah memahami permintaannya. Cek draft ini dulu, ya.';
            } else {
              response = 'Struk sudah aku baca.';
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
          }
          widget.session.lastAssistantText = response;
          _appendEntry(
            FfmAssistantChatEntry(
              isUser: false,
              text: response,
              intent: intent,
              review: review,
              processTrace: processTrace,
              createdAt: DateTime.now(),
            ),
          );
          if (intent.needsClarification) {
            widget.session.pendingDialog = FfmAssistantPendingDialog(
              originalRequest: text,
              prompt: intent.clarification ?? response,
              missingFields: _pendingFieldsFor(intent),
              draft: intent.draft,
            );
          }
          if (!intent.needsClarification &&
              (intent.destination != null || intent.draft != null)) {
            _queuedIntents.add(intent);
          }
        });
        for (final planId in readPlanIds) {
          await _executeReadPlan(planId);
        }
        if (readPlanIds.isEmpty) {
          _agentStatus.done(_completedProcessLabel(intent));
        }
        if (intent.type == FfmAssistantIntentType.unknown) {
          await _unansweredRepository.record(
            rawQuestion: text,
            pageContext: widget.currentDestination?.name,
          );
        }
      } catch (_) {
        _agentStatus.failed('Gambar belum berhasil dipahami.');
        if (!mounted) return;
        setState(
          () => _appendEntry(
            const FfmAssistantChatEntry(
              isUser: false,
              text: 'Maaf, aku tidak bisa memproses foto ini. Coba foto ulang atau pastikan fitur AI lokal sudah terpasang.',
            ),
          ),
        );
        _scrollToEnd();
      } finally {
        if (mounted) setState(() => _submitting = false);
        unawaited(_refreshSlmFollowUpSuggestions());
        _scrollToEnd(force: true);
      }
      return;
    }
    final stopwatch = Stopwatch()..start();
    _setActiveProcess('Merutekan permintaan melalui Agent Orkestrator...');
    try {
      if (_tryReviseActiveDraft(text)) return;
      if (await _tryHandleActivityRequest(text)) return;
      final pending = widget.session.pendingDialog;
      final conversationHistory = _buildRecentConversationHistory();
      final lastAssistant = widget.session.lastAssistantText;
      final intents = pending == null
          ? await _interpreter.interpretMany(
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
            )
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
      if (!mounted) return;
      final readPlanIds = <String>[];
      setState(() {
        for (final intent in intents) {
          String response = intent.response ?? intent.clarification ?? '';
          if (response.isEmpty) {
            if (intent.responseMode == FfmAssistantResponseMode.localModel &&
                intent.type == FfmAssistantIntentType.help) {
              response = 'Aku mengerti ini terkait literasi keuangan keluarga. (Jawaban SLM offline akan muncul di sini).';
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
          }
          widget.session.lastAssistantText = response;
          final processTrace = _traceFor(
            intent,
            stopwatch.elapsed,
            hasImage: false,
          );
          _appendEntry(
            FfmAssistantChatEntry(
              isUser: false,
              text: response,
              intent: intent,
              review: review,
              processTrace: processTrace,
            ),
          );
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
      if (readPlanIds.isEmpty) {
        _agentStatus.done(
          intents.length == 1
              ? _completedProcessLabel(intents.single)
              : 'Agent Orkestrator menyelesaikan ${intents.length} respons.',
        );
      }
      if (intents.any(
        (intent) => intent.type == FfmAssistantIntentType.unknown,
      )) {
        await _unansweredRepository.record(
          rawQuestion: text,
          pageContext: widget.currentDestination?.name,
        );
      }
    } catch (_) {
      _agentStatus.failed('Permintaan belum berhasil diproses.');
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
      if (mounted) setState(() => _submitting = false);
      unawaited(_refreshSlmFollowUpSuggestions());
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
      'local-household',
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
    final sessions = await _activityRepository.getSessions('local-household');
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
    final sessions = await _activityRepository.getSessions('local-household');
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

  Future<void> _openAttachmentPicker() async {
    final choice = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Ambil foto struk'),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Pilih gambar dari galeri'),
              onTap: () => Navigator.of(sheetContext).pop(false),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    await _stagePendingImage(choice);
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
                    ScaffoldMessenger.of(this.context).showSnackBar(
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
        ..activeDraftIntent = null;
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
    final shouldNavigate =
        (intent.destination != null || intent.draft != null) &&
        intent.type != FfmAssistantIntentType.confirm &&
        !directMutation;
    final isCurrentPageCheck =
        intent.destination != null &&
        intent.destination == widget.currentDestination &&
        intent.draft == null;

    final plan = _actionPlanner.planFor(intent);
    if (plan != null) {
      if (intent.draft != null) {
        _actionPlanController.markAwaitingConfirmation(plan.id);
      } else {
        _actionPlanController.complete(plan.id);
      }
    }

    if (directMutation && plan != null && intent.draft != null) {
      final confirmed = await _confirmDirectMutation(intent.draft!);
      if (!confirmed) {
        _actionPlanController.cancel(plan.id);
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
      Navigator.of(context).pop();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await handler(intent);
      return;
    }
    await widget.onIntent(intent);
    if (mounted) setState(() => _queuedIntents.remove(intent));
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

  Future<void> _openQueuedDrafts() async {
    final intents = List<FfmAssistantIntent>.of(_queuedIntents);
    if (intents.length < 2) return;
    setState(_queuedIntents.clear);
    final handler = widget.onIntents;
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await handler(intents);
  }

  bool _tryReviseActiveDraft(String text) {
    final review = widget.session.activeDraftReview;
    final sourceIntent = widget.session.activeDraftIntent;
    if (review == null || sourceIntent == null) return false;
    final normalized = text.toLowerCase().trim();
    if (!RegExp(r'\b(ubah|ganti|revisi|koreksi)\b').hasMatch(normalized)) {
      return false;
    }
    final nextDraft = _draftFromTextRevision(review.draft, normalized);
    if (nextDraft == null) return false;
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
      _appendEntry(
        FfmAssistantChatEntry(
          isUser: false,
          text: revisedIntent.response!,
          intent: revisedIntent,
          understanding: 'Kamu meminta revisi untuk draft yang sedang aktif.',
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
      r'(rekening asal|asal|rekening tujuan|tujuan|kategori|target|catatan|judul|nama)\s*(?:jadi|ke)\s+(.+)$',
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
    if (before.goalName != after.goalName) {
      return 'target diubah menjadi ${after.goalName}.';
    }
    return 'draft diperbarui.';
  }

  Future<void> _editActiveDraft(FfmAssistantIntent intent) async {
    final review = widget.session.activeDraftReview;
    if (review == null) return;
    final nextDraft = await showDialog<FfmAssistantDraft>(
      context: context,
      builder: (_) => FfmAssistantDraftEditDialog(draft: review.draft),
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

  void _cancelActiveDraft() {
    setState(() {
      widget.session
        ..activeDraftReview = null
        ..activeDraftIntent = null;
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
      _scrollToEnd();
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
    final recent = _entries.length > 5
        ? _entries.sublist(_entries.length - 5)
        : _entries;
    final lines = <String>[];
    for (final entry in recent) {
      final role = entry.isUser ? 'Pengguna' : 'Asisten';
      final text = entry.text.trim();
      if (text.isNotEmpty && !text.startsWith('Gambar dilampirkan')) {
        // Ambil baris pertama atau maksimal 100 karakter agar konteks tetap ringkas
        final snippet = text.split('\n').first.trim();
        lines.add('$role: $snippet');
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
    final proactiveSuggestion = _proactiveService.suggest(
      destination: widget.currentDestination,
      modelReady: _modelReady,
      hasConversation: _entries.any((entry) => entry.isUser),
    );

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
                modelChecking: _modelChecking,
                modelReady: _modelReady,
                modelStatusError: _modelStatusError,
                onRefreshModelStatus: _refreshModelStatus,
                memoryCount: _memoryCount,
                onOpenMemory: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => const FfmMemoryViewerPage(),
                        fullscreenDialog: true,
                      ),
                    )
                    .then((_) => _refreshMemoryCount()),
              ),
              Divider(
                height: 1,
                color: isDark
                    ? const Color(0xFF2E2A26)
                    : const Color(0xFFE8E0D0),
              ),
              if (!_modelChecking && !_modelReady)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Card(
                    margin: EdgeInsets.zero,
                    color: theme.colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.memory_outlined,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'AI lokal belum siap. Unduh SLM dari GitHub atau impor bundle offline yang sudah dibagikan.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: _submitting ? null : _openLocalModelPage,
                            child: const Text('Siapkan'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (proactiveSuggestion != null && _modelReady)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.lightbulb_outline,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(
                        proactiveSuggestion.message,
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: TextButton(
                        onPressed: _submitting
                            ? null
                            : () =>
                                  _submit(proactiveSuggestion.suggestedPrompt),
                        child: const Text('Coba'),
                      ),
                    ),
                  ),
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
                          );
                        }
                        final entry = _entries[index];
                        final opensCurrentPage =
                            entry.intent?.destination != null &&
                            entry.intent!.destination ==
                                widget.currentDestination &&
                            entry.intent!.draft == null;
                        return FfmAssistantMessageCard(
                          entry: entry,
                          onSpeak: entry.isUser
                              ? null
                              : () => _toggleSpeakFor(index, entry),
                          isSpeaking:
                              _speakingEntryKey == _speechKeyFor(index, entry),
                          onIntent:
                              entry.intent == null ||
                                  entry.intent!.needsTeachingApproval ||
                                  (entry.intent!.destination == null &&
                                      entry.intent!.draft == null &&
                                      entry.intent!.type !=
                                          FfmAssistantIntentType.exportReport &&
                                      entry.intent!.type !=
                                          FfmAssistantIntentType.confirm)
                              ? null
                              : () => _handleIntent(entry.intent!),
                          primaryActionLabel:
                              _isDirectMutation(entry.intent?.draft)
                              ? 'Konfirmasi'
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
                              ? () => _editActiveDraft(entry.intent!)
                              : null,
                          onCancelDraft:
                              entry.intent?.draft != null &&
                                  entry.review != null
                              ? _cancelActiveDraft
                              : null,
                          onCopyFeedback: entry.isUser
                              ? null
                              : () => _showFeedbackActions(entry),
                          onShowTechnical: entry.intent == null
                              ? null
                              : () => _showTechnicalDetails(entry.intent!),
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
              if (_queuedIntents.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: FilledButton.tonalIcon(
                    onPressed: _submitting ? null : _openQueuedDrafts,
                    icon: const Icon(Icons.playlist_add_check),
                    label: Text(
                      'Periksa ${_queuedIntents.length} rancangan dari beberapa perintah',
                    ),
                  ),
                ),
              if (!_submitting &&
                  _modelReady &&
                  _slmFollowUpSuggestions.length == 3)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Memory Nudge Card (muncul jika ada fakta yang terdeteksi)
                      if (_pendingMemoryNudge != null)
                        FfmMemoryNudgeCard(
                          insight: _pendingMemoryNudge!,
                          onSave: _saveMemoryNudge,
                          onDismiss: () =>
                              setState(() => _pendingMemoryNudge = null),
                        ),
                      // Follow-up suggestion chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            for (final suggestion in _slmFollowUpSuggestions)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ActionChip(
                                  avatar: const Icon(
                                    Icons.lightbulb_outline,
                                    size: 14,
                                    color: Color(0xFF00727A),
                                  ),
                                  label: Text(
                                    suggestion,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  onPressed: () {
                                    _controller.text = suggestion;
                                    _controller
                                        .selection = TextSelection.fromPosition(
                                      TextPosition(offset: suggestion.length),
                                    );
                                    _inputFocusNode.requestFocus();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (_pendingImage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            _pendingImage!,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 72,
                              height: 72,
                              color: theme.colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                        Positioned(
                          top: -8,
                          right: -8,
                          child: GestureDetector(
                            onTap: () => setState(() => _pendingImage = null),
                            child: Container(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.error,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.colorScheme.surface,
                                  width: 2,
                                ),
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, _) {
                      final canSend =
                          !_submitting &&
                          (value.text.trim().isNotEmpty ||
                              _pendingImage != null);
                      return Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF292724)
                              : const Color(0xFFF4F1EA),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF403C37)
                                : const Color(0xFFE1DAD0),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? .18 : .06,
                              ),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
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
                              onPressed: _submitting ? null : _toggleListening,
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
                                  hintText: 'Tulis perintah atau pertanyaan…',
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Lampirkan foto',
                              onPressed: _submitting
                                  ? null
                                  : _openAttachmentPicker,
                              icon: const Icon(Icons.attach_file),
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
