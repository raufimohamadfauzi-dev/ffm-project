import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../assistant/data/ffm_assistant_interpreter.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../../settings/data/category_repository.dart';
import '../../../settings/presentation/pages/master_data_page.dart';
import '../../data/services/activity_speech_service.dart';
import '../../domain/activity_voice.dart';
import '../../domain/entities/activity_entity.dart';
import '../bloc/activity_bloc.dart';
import 'activity_detail_page.dart';

class ActivityPage extends StatelessWidget {
  const ActivityPage({
    super.key,
    this.initialTitle,
    this.initialCategory,
    this.initialNotes,
  });

  final String? initialTitle;
  final String? initialCategory;
  final String? initialNotes;

  @override
  Widget build(BuildContext context) {
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.activity,
      child: BlocProvider.value(
        value: getIt<ActivityBloc>()..load(),
        child: _ActivityView(
          initialTitle: initialTitle,
          initialCategory: initialCategory,
          initialNotes: initialNotes,
        ),
      ),
    );
  }
}

class _ActivityView extends StatefulWidget {
  const _ActivityView({
    this.initialTitle,
    this.initialCategory,
    this.initialNotes,
  });

  final String? initialTitle;
  final String? initialCategory;
  final String? initialNotes;

  @override
  State<_ActivityView> createState() => _ActivityViewState();
}

class _ActivityViewState extends State<_ActivityView>
    with WidgetsBindingObserver {
  String? _categoryFilterId;
  String _modeFilter = 'Semua mode';
  String _riwayatTab = 'Semua';
  final _searchController = TextEditingController();
  String _searchQuery = '';
  DateTime? _dayFilter;
  final _calculator = const ActivityDurationCalculator();
  final _voiceParser = const ActivityVoiceParser();
  final _speechService = ActivitySpeechService();
  final _interpreter = getIt<FfmAssistantInterpreter>();
  ActivityVoiceIntent? _voiceIntent;
  String _voiceText = '';
  String? _voiceError;
  String _voiceStatus = 'Siap bicara';
  bool _voiceInitialized = false;
  bool _processingFinalVoice = false;
  List<String> _voiceCategories = const [];
  Map<String, String> _activityCategoryIds = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadVoiceCategories();
    if (widget.initialTitle?.trim().isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _startSession(
            initialTitle: widget.initialTitle,
            initialCategory: widget.initialCategory,
            initialNotes: widget.initialNotes,
          );
        }
      });
    }
  }

  Future<void> _loadVoiceCategories() async {
    try {
      final categories = await getIt<CategoryRepository>().readActive(
        AppContext.householdId,
        type: 'activity',
      );
      if (mounted) {
        setState(() {
          _voiceCategories = categories.map((item) => item.name).toList();
          _activityCategoryIds = {
            for (final category in categories) category.name: category.id,
          };
        });
      }
    } catch (_) {
      // The voice form retains its fallback categories when master data is unavailable.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<ActivityBloc>().load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _speechService.stop();
    _speechService.stopSpeaking();
    super.dispose();
  }

  bool _matchesDay(DateTime value) {
    final day = _dayFilter;
    return day == null ||
        (value.year == day.year &&
            value.month == day.month &&
            value.day == day.day);
  }

  bool _matchesSearch(ActivitySessionEntity session) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    return <String?>[
      session.id,
      session.title,
      session.category,
      session.notes,
      session.activityGroupId,
      session.subjectType,
      session.subjectId,
    ].whereType<String>().any((value) => value.toLowerCase().contains(query));
  }

  bool _matchesMode(ActivitySessionEntity session) => switch (_modeFilter) {
    'Timer' => session.isTimeTracking,
    'Catatan' => session.isHistory,
    _ => true,
  };

  Future<void> _showSessionDetails(
    ActivitySessionEntity session,
    List<ActivityCheckpointEntity> checkpoints,
    List<ActivitySessionEntity> children,
  ) async {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActivityDetailPage(sessionId: session.id),
      ),
    );
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _dayFilter ?? DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _dayFilter = picked);
  }

  Future<void> _startSession({
    String? parentSessionId,
    String? parentTitle,
    String? initialTitle,
    String? initialCategory,
    String? initialNotes,
    DateTime? initialStartedAt,
    ActivityMode? initialMode,
  }) async {
    final result = await showModalBottomSheet<_SessionDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SessionForm(
        parentSessionTitle: parentTitle,
        initialTitle: initialTitle,
        initialCategory: initialCategory,
        initialNotes: initialNotes,
        initialStartedAt: initialStartedAt,
        initialMode: initialMode,
      ),
    );
    if (result == null || !mounted) return;
    await context.read<ActivityBloc>().startSession(
      title: result.title,
      category: result.category,
      categoryId: result.categoryId,
      kind: result.kind,
      mode: result.mode,
      notes: result.notes,
      startedAt: result.startedAt,
      parentSessionId: parentSessionId,
    );
  }

  Future<void> _addCheckpoint({String? sessionId}) async {
    final result = await showModalBottomSheet<_CheckpointDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CheckpointForm(),
    );
    if (result == null || !mounted) return;
    await context.read<ActivityBloc>().addCheckpoint(
      label: result.label,
      place: result.place,
      note: result.note,
      occurredAt: result.occurredAt,
      sessionId: sessionId,
    );
  }

  Future<void> _startVoiceCapture() async {
    if (!mounted) return;
    if (_speechService.isListening) {
      await _speechService.stop();
    }
    await _speechService.stopSpeaking();
    if (!await _showVoiceOnboardingIfNeeded()) return;
    setState(() {
      _voiceError = null;
      _voiceStatus = 'Menyiapkan mikrofon...';
      _voiceText = '';
    });
    if (!_voiceInitialized) {
      final initialized = await _speechService.initialize(
        onError: (message) {
          if (!mounted) return;
          setState(() {
            _voiceError = message;
            _voiceStatus = 'Voice belum siap';
          });
        },
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _voiceStatus = status);
        },
      );
      if (!initialized) {
        if (!mounted) return;
        setState(() {
          _voiceError = 'Pengenalan suara belum tersedia. Coba izinkan mikrofon atau ketik manual.';
          _voiceStatus = 'Ketik manual dulu';
        });
        return;
      }
      _voiceInitialized = true;
    }
    if (!mounted) return;
    setState(() => _voiceStatus = 'Silakan bicara...');
    await _speechService.listen(
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() {
          _voiceText = text;
          _voiceStatus = isFinal ? 'Teks sudah ditangkap' : 'Mendengarkan...';
        });
        if (isFinal && text.trim().isNotEmpty) {
          _processFinalVoice(text);
        }
      },
      onSoundLevel: (_) {},
    );
  }

  Future<bool> _showVoiceOnboardingIfNeeded() async {
    const key = 'voice_activity_onboarding_seen';
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(key) == true || !mounted) return true;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Catat aktivitas dengan suara',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bicara dengan bahasa natural, misalnya “mulai memupuk timun”. '
                'Kamu juga bisa membetulkan kategori, waktu, atau catatan. '
                'Tidak ada data yang disimpan sebelum kamu menekan Konfirmasi.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Contoh: “kategorinya pertanian”, “ganti waktunya jam 7”, atau “sudah benar”.',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Nanti saja'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Mengerti'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (accepted != true) return false;
    await preferences.setBool(key, true);
    return mounted;
  }

  Future<void> _stopVoiceCapture() async {
    await _speechService.stop();
    if (!mounted) return;
    if (_voiceText.trim().isNotEmpty) {
      await _processFinalVoice(_voiceText);
    } else {
      setState(() => _voiceStatus = 'Belum ada suara yang terbaca');
    }
  }

  Future<void> _processFinalVoice(String transcript) async {
    if (_processingFinalVoice || transcript.trim().isEmpty) return;
    _processingFinalVoice = true;
    try {
      await _speechService.stop();
      if (!mounted) return;
      await _previewVoice(transcript.trim());
    } finally {
      _processingFinalVoice = false;
    }
  }

  Future<void> _previewVoice(String transcript) async {
    final state = context.read<ActivityBloc>().state;

    if (await _interpretVoiceWithAssistant(transcript, state)) return;

    final parsed = _voiceParser.parse(
      transcript,
      activeSessions: state.activeSessions,
    );
    if (parsed.type == ActivityVoiceIntentType.confirm &&
        _voiceIntent?.canConfirm == true) {
      await _confirmVoice();
      return;
    }
    if (parsed.type == ActivityVoiceIntentType.confirm) {
      setState(() {
        _voiceIntent = null;
        _voiceText = transcript;
        _voiceError = 'Belum ada perintah aktivitas yang bisa dikonfirmasi. Bilang dulu misalnya "mulai makan" atau "selesai perjalanan".';
        _voiceStatus = 'Menunggu perintah aktivitas';
      });
      _speechService.speak(
        'Belum ada perintah aktivitas yang menunggu konfirmasi. Bilang dulu aktivitas yang mau dicatat ya.',
      );
      return;
    }
    if (parsed.type == ActivityVoiceIntentType.cancel) {
      await _cancelVoice();
      return;
    }

    // Jika parser lokal tidak mengenali (unknown), coba fallback ke Gemini
    if (parsed.type == ActivityVoiceIntentType.unknown) {
      await _fallbackToGemini(transcript);
      return;
    }

    // Jika start, langsung buka form draft aktivitas agar pengguna dapat melihat & mengoreksi
    if (parsed.type == ActivityVoiceIntentType.start &&
        parsed.targetTitle != null) {
      if (!mounted) return;
      await _startSession(
        initialTitle: parsed.targetTitle,
        initialCategory: parsed.category.isNotEmpty ? parsed.category : null,
        initialNotes:
            (transcript.trim().toLowerCase() != parsed.targetTitle!.toLowerCase())
                ? transcript.trim()
                : null,
        initialStartedAt: parsed.startedAt,
      );
      return;
    }

    var intent = parsed;
    if (intent.type == ActivityVoiceIntentType.note &&
        intent.targetSessionId == null) {
      if (state.activeSessions.length == 1) {
        final session = state.activeSessions.single;
        intent = intent.copyWith(
          targetSessionId: session.id,
          targetTitle: session.title,
        );
      } else {
        if (!mounted) return;
        await _startSession(
          initialTitle: intent.targetTitle ?? transcript,
          initialCategory: intent.category.isNotEmpty ? intent.category : null,
          initialNotes: transcript,
        );
        return;
      }
    }
    setState(() {
      _voiceIntent = intent;
      _voiceText = transcript;
      _voiceError = null;
      _voiceStatus = 'Cek dulu hasilnya sebelum disimpan';
    });
    if (!mounted) return;
    await context.read<ActivityBloc>().recordVoiceIntent(
      intent,
      status: ActivityVoiceStatus.preview,
    );
    await _speakVoicePreview(intent);
  }

  Future<bool> _interpretVoiceWithAssistant(
    String transcript,
    ActivityState state,
  ) async {
    try {
      final interpretation = await _interpreter.interpret(
        transcript,
        currentDestination: FfmAssistantDestination.activity,
        activitySnapshot: ActivityLiveSnapshot(
          activeSessions: state.activeSessions,
        ),
      );
      final proposal = interpretation.draft;
      if (proposal?.kind != FfmAssistantDraftKind.activity ||
          proposal?.title?.trim().isEmpty != false) {
        return false;
      }

      if (!mounted) return true;
      setState(() {
        _voiceText = transcript;
        _voiceStatus = 'Membuka form draft dari LLM...';
        _voiceError = null;
      });

      final modeVal = proposal!.formValues['mode'] ?? proposal.formValues['activityKind'];
      await _startSession(
        initialTitle: proposal.title!.trim(),
        initialCategory: proposal.categoryName?.trim(),
        initialNotes: proposal.note,
        initialStartedAt: proposal.date,
        initialMode: modeVal == 'history' || modeVal == 'catatan'
            ? ActivityMode.history
            : ActivityMode.timeTracking,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _fallbackToGemini(String transcript) async {
    setState(() {
      _voiceStatus = 'Memproses via asisten...';
      _voiceError = null;
    });
    try {
      final state = context.read<ActivityBloc>().state;
      final intent = await _interpreter.interpret(
        transcript,
        currentDestination: FfmAssistantDestination.activity,
        activitySnapshot: ActivityLiveSnapshot(
          activeSessions: state.activeSessions,
        ),
      );
      if (!mounted) return;

      // Jika intent mengandung draft proposal aktivitas, buka form draft langsung agar bisa dikoreksi
      if (intent.draft?.kind == FfmAssistantDraftKind.activity &&
          intent.draft?.title?.trim().isNotEmpty == true) {
        final proposal = intent.draft!;
        final modeVal =
            proposal.formValues['mode'] ?? proposal.formValues['activityKind'];
        await _startSession(
          initialTitle: proposal.title!.trim(),
          initialCategory: proposal.categoryName?.trim(),
          initialNotes: proposal.note,
          initialStartedAt: proposal.date,
          initialMode: modeVal == 'history' || modeVal == 'catatan'
              ? ActivityMode.history
              : ActivityMode.timeTracking,
        );
        if (!mounted) return;
        setState(() {
          _voiceIntent = null;
          _voiceText = transcript;
          _voiceError = null;
          _voiceStatus = 'Draft dibuka di form';
        });
        return;
      }

      // Jika tidak ada draft/destination, tampilkan error
      final response = intent.response ?? intent.clarification;
      setState(() {
        _voiceIntent = null;
        _voiceText = transcript;
        _voiceError =
            response ??
            'Perintah tidak dikenali. Coba ulangi dengan kata lain.';
        _voiceStatus = 'Tidak dikenali';
      });
      if (response != null) {
        _speechService.speak(response);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _voiceIntent = null;
        _voiceText = transcript;
        _voiceError = 'Gagal memproses: ${e.toString()}';
        _voiceStatus = 'Error';
      });
    }
  }

  Future<void> _speakVoicePreview(ActivityVoiceIntent intent) async {
    final target = intent.targetTitle == null
        ? ''
        : ' untuk ${intent.targetTitle}';
    final detail = intent.type == ActivityVoiceIntentType.startChild
        ? ' di dalam ${intent.parentTitle}'
        : '';
    final checkpoint =
        intent.type == ActivityVoiceIntentType.checkpoint &&
            intent.checkpointLabel != null
        ? '. Update: ${intent.checkpointLabel}'
        : '';
    final message = intent.ambiguityReason == null
        ? '${intent.actionLabel}$target$detail$checkpoint. Kalau sudah benar, bilang OK.'
        : intent.ambiguityReason!;
    try {
      await _speechService.speak(message);
    } catch (_) {
      // TTS hanya membantu mengulang hasil; preview teks tetap bisa dipakai.
    }
  }

  Future<void> _editVoiceText() async {
    final edited = await showDialog<String>(
      context: context,
      builder: (_) => _VoiceTextEditor(initialText: _voiceText),
    );
    if (edited == null || edited.trim().isEmpty || !mounted) return;
    await _previewVoice(edited.trim());
  }

  Future<void> _confirmVoice() async {
    final intent = _voiceIntent;
    if (intent == null) return;
    if (!intent.canConfirm) {
      setState(
        () => _voiceError = intent.ambiguityReason ?? 'Hasilnya belum lengkap.',
      );
      return;
    }
    setState(() {
      _voiceStatus = 'Menyimpan perintah...';
      _voiceError = null;
    });
    try {
      await context.read<ActivityBloc>().executeVoiceIntent(intent);
      if (!mounted) return;
      setState(() {
        _voiceIntent = null;
        _voiceText = '';
        _voiceStatus = 'Selesai disimpan';
      });
      await _speechService.speak(
        'Oke, ${intent.actionLabel.toLowerCase()} sudah disimpan.',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${intent.actionLabel} sudah disimpan.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _voiceError = error.toString().replaceFirst('Bad state: ', '');
        _voiceStatus = 'Belum disimpan';
      });
      await context.read<ActivityBloc>().recordVoiceIntent(
        intent,
        status: ActivityVoiceStatus.failed,
        resultMessage: _voiceError,
      );
    }
  }

  Future<void> _cancelVoice() async {
    final intent = _voiceIntent;
    if (intent != null) {
      await context.read<ActivityBloc>().recordVoiceIntent(
        intent,
        status: ActivityVoiceStatus.cancelled,
        resultMessage: 'Dibatalkan pengguna.',
      );
    }
    if (!mounted) return;
    setState(() {
      _voiceIntent = null;
      _voiceText = '';
      _voiceError = null;
      _voiceStatus = 'Dibatalkan';
    });
    await _speechService.stopSpeaking();
  }

  void _selectVoiceTarget(String? sessionId) {
    if (sessionId == null || _voiceIntent == null) return;
    ActivitySessionEntity? session;
    for (final item in context.read<ActivityBloc>().state.activeSessions) {
      if (item.id == sessionId) {
        session = item;
        break;
      }
    }
    if (session == null) return;
    final selectedSession = session;
    setState(() {
      _voiceIntent = _voiceIntent!.copyWith(
        targetSessionId: selectedSession.id,
        targetTitle: selectedSession.title,
        clearAmbiguity: true,
      );
    });
    final updated = _voiceIntent;
    if (updated != null) _speakVoicePreview(updated);
  }

  Future<void> _confirmArchiveSession(ActivitySessionEntity session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Arsipkan aktivitas?'),
        content: Text(
          '“${session.title}” akan disembunyikan dari daftar aktif/tersimpan di halaman ini. '
          'Data tidak dihapus, namun saat ini tidak ada tampilan khusus untuk membuka kembali aktivitas yang diarsipkan. '
          'Gunakan “Hapus permanen” jika kamu yakin tidak membutuhkannya lagi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Arsipkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<ActivityBloc>().archiveSession(session.id);
  }

  Future<void> _confirmDeleteSession(ActivitySessionEntity session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus aktivitas permanen?'),
        content: Text(
          '“${session.title}” dan seluruh update aktivitasnya akan dihapus dari perangkat. Tindakan ini tidak bisa dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus permanen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<ActivityBloc>().deleteSessionPermanently(session.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Aktivitas dan semua update sudah dihapus.'),
      ),
    );
  }

  Future<void> _editSession(ActivitySessionEntity session) async {
    final result = await showModalBottomSheet<_SessionDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SessionForm(
        initialTitle: session.title,
        initialCategory: session.category,
        initialNotes: session.notes,
        initialStartedAt: session.startedAt,
        initialMode: session.effectiveMode,
      ),
    );
    if (result == null || !mounted) return;
    final updated = session.copyWith(
      title: result.title,
      category: result.category,
      categoryId: result.categoryId,
      kind: result.kind,
      notes: result.notes,
      startedAt: result.startedAt,
      endedAt: session.isHistory ? result.startedAt : session.endedAt,
      updatedAt: DateTime.now(),
    );
    await context.read<ActivityBloc>().saveSession(updated);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ActivityBloc, ActivityState>(
      listenWhen: (previous, current) => previous.error != current.error,
      listener: (context, state) {
        final error = state.error;
        if (error == null) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Catat Aktivitas'),
          actions: [
            IconButton(
              tooltip: 'Cara kerja aktivitas',
              icon: const Icon(Icons.info_outline),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(
                  title: Text('Catat aktivitas harian'),
                  content: Text(
                    'Pakai Mulai sesi untuk melacak perjalanan atau pekerjaan dari awal sampai selesai. Tekan Update aktivitas setiap kali kegiatan berubah, misalnya sampai pasar, bertemu seseorang, atau pindah ke kebun. Ketuk kartu untuk melihat rincian dan durasi tiap update. Semua data disimpan lokal di perangkat.',
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton(
              heroTag: 'activity_vn_fab',
              onPressed: _startVoiceCapture,
              tooltip: 'Bicara / Voice Note aktivitas',
              backgroundColor:
                  Theme.of(context).colorScheme.secondaryContainer,
              foregroundColor:
                  Theme.of(context).colorScheme.onSecondaryContainer,
              child: Icon(
                _processingFinalVoice ? Icons.hourglass_empty : Icons.mic,
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton.extended(
              heroTag: 'activity_timer_fab',
              onPressed: () => _startSession(initialMode: ActivityMode.timeTracking),
              tooltip: 'Mulai aktivitas dengan timer berjalan',
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              icon: const Icon(Icons.timer_outlined),
              label: const Text('Mulai Timer'),
            ),
            const SizedBox(width: 8),
            FloatingActionButton.extended(
              heroTag: 'activity_note_fab',
              onPressed: () => _startSession(initialMode: ActivityMode.history),
              tooltip: 'Catat kejadian atau riwayat selesai',
              backgroundColor: Colors.purple.shade700,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Catat Riwayat'),
            ),
          ],
        ),
        body: BlocBuilder<ActivityBloc, ActivityState>(
          builder: (context, state) {
            if (state.loading &&
                state.sessions.isEmpty &&
                state.entries.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            return RefreshIndicator(
              onRefresh: context.read<ActivityBloc>().load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                children: [
                  const AppHelpBanner(
                    title: 'Waktu kamu bisa dilacak',
                    message: 'Mulai satu aktivitas, lalu tekan Update aktivitas setiap kali ada perubahan. Aktivitas di dalamnya punya timer sendiri. Kalau aplikasi ditutup paksa, sesi aktif tetap tersimpan dan dilanjutkan saat aplikasi dibuka lagi.',

                    icon: Icons.timeline_outlined,
                  ),
                  const SizedBox(height: 16),
                  _VoiceActivityCard(
                    intent: _voiceIntent,
                    text: _voiceText,
                    status: _voiceStatus,
                    error: _voiceError,
                    isListening: _speechService.isListening,
                    activeSessions: state.activeSessions,
                    activityCategories: _voiceCategories,
                    onListen: _startVoiceCapture,
                    onStop: _stopVoiceCapture,
                    onEdit: _editVoiceText,
                    onSpeak: _voiceIntent == null
                        ? null
                        : () => _speakVoicePreview(_voiceIntent!),
                    onSelectTarget: _selectVoiceTarget,
                    onCategoryChanged: (category) {
                      if (_voiceIntent == null) return;
                      setState(() {
                        _voiceIntent = _voiceIntent!.copyWith(
                          category: category,
                          categoryId: _activityCategoryIds[category],
                        );
                      });
                    },
                    onConfirm: _confirmVoice,
                    onCancel: _cancelVoice,
                  ),
                  const SizedBox(height: 16),
                  AppCard(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DropdownButton<String?>(
                          value: _categoryFilterId,
                          underline: const SizedBox.shrink(),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Semua kategori'),
                            ),
                            ..._voiceCategories.map(
                              (name) => DropdownMenuItem<String?>(
                                value: _activityCategoryIds[name],
                                child: Text(name),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _categoryFilterId = value),
                        ),
                        OutlinedButton.icon(
                          onPressed: _pickDay,
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                            _dayFilter == null
                                ? 'Semua tanggal'
                                : _dateOnly(_dayFilter!),
                          ),
                        ),
                        if (_dayFilter != null)
                          IconButton(
                            tooltip: 'Hapus filter tanggal',
                            onPressed: () => setState(() => _dayFilter = null),
                            icon: const Icon(Icons.clear),
                          ),
                        DropdownButton<String>(
                          value: _modeFilter,
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(
                              value: 'Semua mode',
                              child: Text('Semua mode'),
                            ),
                            DropdownMenuItem(
                              value: 'Timer',
                              child: Text('Timer'),
                            ),
                            DropdownMenuItem(
                              value: 'Catatan',
                              child: Text('Catatan'),
                            ),
                          ],
                          onChanged: (value) => setState(
                            () => _modeFilter = value ?? 'Semua mode',
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              hintText: 'Cari...',
                              isDense: true,
                              prefixIcon: Icon(Icons.search, size: 18),
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                            ),
                            onChanged: (value) =>
                                setState(() => _searchQuery = value),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (state.habitSuggestions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _HabitSuggestionsCard(
                      suggestions: state.habitSuggestions,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Builder(
                    builder: (context) {
                      final visibleActiveSessions = state.activeSessions
                          .where(
                            (session) =>
                                (_categoryFilterId == null ||
                                    session.categoryId == _categoryFilterId) &&
                                _matchesDay(session.startedAt) &&
                                _matchesMode(session) &&
                                _matchesSearch(session),
                          )
                          .toList();
                      final visibleSessions = state.sessions
                          .where(
                            (session) =>
                                session.status !=
                                    ActivitySessionStatus.active &&
                                !session.isArchived &&
                                (_categoryFilterId == null ||
                                    session.categoryId == _categoryFilterId) &&
                                _matchesDay(session.startedAt) &&
                                _matchesMode(session) &&
                                _matchesSearch(session) &&
                                (_riwayatTab == 'Semua'
                                    ? true
                                    : (_riwayatTab == 'Timer'
                                        ? session.isTimeTracking
                                        : session.isHistory)),
                          )
                          .toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (state.activeSessions.isNotEmpty) ...[
                            if (visibleActiveSessions.isNotEmpty) ...[
                              _SectionTitle(
                                title: 'Sedang berjalan',
                                count: visibleActiveSessions.length,
                              ),
                              for (final session in visibleActiveSessions)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _ActiveSessionCard(
                                    session: session,
                                    checkpoints:
                                        state.checkpoints[session.id] ??
                                        const [],
                                    calculator: _calculator,
                                    onCheckpoint: () =>
                                        _addCheckpoint(sessionId: session.id),
                                    onFinish: () => context
                                        .read<ActivityBloc>()
                                        .finishSession(sessionId: session.id),
                                    onStartChild: () => _startSession(
                                      parentSessionId: session.id,
                                      parentTitle: session.title,
                                    ),
                                    onTogglePriority: () => context
                                        .read<ActivityBloc>()
                                        .togglePriority(session.id),
                                    onEdit: () => _editSession(session),
                                  ),
                                ),
                            ] else
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _FilteredEmptyHint(
                                  message:
                                      'Ada aktivitas yang sedang berjalan, tapi tidak cocok dengan filter yang dipilih.',
                                ),
                              ),
                            const SizedBox(height: 8),
                          ],
                          _SectionTitle(
                            title: 'Riwayat Aktivitas',
                            count: visibleSessions.length,
                          ),
                          const SizedBox(height: 6),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final tab in ['Semua', 'Timer', 'Catatan'])
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(
                                        tab == 'Timer'
                                            ? '⏱️ Timer'
                                            : (tab == 'Catatan'
                                                ? '📝 Catatan'
                                                : 'Semua'),
                                      ),
                                      selected: _riwayatTab == tab,
                                      onSelected: (selected) {
                                        if (selected) {
                                          setState(() => _riwayatTab = tab);
                                        }
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (visibleSessions.isEmpty)
                            const AppEmptyState(
                              icon: Icons.timeline_outlined,
                              title: 'Belum ada aktivitas',
                              message: 'Mulai satu aktivitas, lalu isi update setiap kali berpindah atau melakukan sesuatu.',
                            )
                          else
                            for (final session in visibleSessions)
                              _SessionCard(
                                session: session,
                                checkpoints:
                                    state.checkpoints[session.id] ?? const [],
                                calculator: _calculator,
                                onOpen: () => _showSessionDetails(
                                  session,
                                  state.checkpoints[session.id] ?? const [],
                                  state.sessions
                                      .where(
                                        (child) =>
                                            child.parentSessionId == session.id,
                                      )
                                      .toList(),
                                ),
                                onArchive: () =>
                                    _confirmArchiveSession(session),
                                onDelete: () => _confirmDeleteSession(session),
                                onEdit: () => _editSession(session),
                                onTogglePriority: () => context
                                    .read<ActivityBloc>()
                                    .togglePriority(session.id),
                              ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilteredEmptyHint extends StatelessWidget {
  const _FilteredEmptyHint({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      children: [
        Icon(
          Icons.filter_alt_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    ),
  );
}

class _HabitSuggestionsCard extends StatelessWidget {
  const _HabitSuggestionsCard({required this.suggestions});
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      color: scheme.tertiaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_outlined, color: scheme.onTertiaryContainer),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Kebiasaan yang kuterbaca',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Cara asisten mengenali kebiasaan',
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Kebiasaan yang kuterbaca'),
                    content: const Text(
                      'Asisten merangkum pola dari aktivitas yang kamu catat berulang kali dan menyimpannya sebagai ingatan rutinitas. '
                      'Ingatan ini bisa kamu tinjau, setujui, atau hapus lewat ikon Memori Pribadi di halaman asisten. '
                      'Asisten hanya menebak pola; tidak ada klaim finansial yang dibuat dari data ini.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Mengerti'),
                      ),
                    ],
                  ),
                ),
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final suggestion in suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.circle,
                    size: 6,
                    color: scheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(suggestion)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActiveSessionCard extends StatelessWidget {
  const _ActiveSessionCard({
    required this.session,
    required this.checkpoints,
    required this.calculator,
    required this.onCheckpoint,
    required this.onFinish,
    required this.onStartChild,
    this.onTogglePriority,
    this.onEdit,
  });
  final ActivitySessionEntity session;
  final List<ActivityCheckpointEntity> checkpoints;
  final ActivityDurationCalculator calculator;
  final VoidCallback onCheckpoint;
  final VoidCallback onFinish;
  final VoidCallback onStartChild;
  final VoidCallback? onTogglePriority;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      color: scheme.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                child: const Icon(Icons.play_arrow),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  session.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              _LiveDurationText(
                startedAt: session.startedAt,
                calculator: calculator,
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (onTogglePriority != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    session.priority > 0
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: session.priority > 0 ? Colors.amber : scheme.onPrimaryContainer,
                  ),
                  tooltip: session.priority > 0
                      ? 'Prioritas aktif (klik untuk lepas)'
                      : 'Tandai sebagai prioritas',
                  onPressed: onTogglePriority,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text('Dimulai ${_dateTime(session.startedAt)} • masih berjalan'),
          if (checkpoints.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final checkpoint in checkpoints)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${checkpoint.label}${checkpoint.place == null ? '' : ' — ${checkpoint.place}'} (${_time(checkpoint.occurredAt)})',
                ),
              ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onCheckpoint,
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Update aktivitas'),
              ),
              OutlinedButton.icon(
                onPressed: onStartChild,
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Tambah di dalam'),
              ),
              FilledButton.icon(
                onPressed: onFinish,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Selesai'),
              ),
              if (onEdit != null)
                IconButton.outlined(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit aktivitas',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveDurationText extends StatefulWidget {
  const _LiveDurationText({
    required this.startedAt,
    required this.calculator,
    required this.style,
  });

  final DateTime startedAt;
  final ActivityDurationCalculator calculator;
  final TextStyle style;

  @override
  State<_LiveDurationText> createState() => _LiveDurationTextState();
}

class _LiveDurationTextState extends State<_LiveDurationText>
    with WidgetsBindingObserver {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _startTicker();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _ticker?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    widget.calculator.format(DateTime.now().difference(widget.startedAt)),
    style: widget.style,
  );
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.checkpoints,
    required this.calculator,
    required this.onOpen,
    required this.onArchive,
    required this.onDelete,
    this.onEdit,
    this.onTogglePriority,
  });
  final ActivitySessionEntity session;
  final List<ActivityCheckpointEntity> checkpoints;
  final ActivityDurationCalculator calculator;
  final VoidCallback onOpen;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onTogglePriority;

  @override
  Widget build(BuildContext context) {
    final isPriority = session.priority > 0;
    final isNote = session.isHistory;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final modeBadgeColor = isDark ? scheme.onSurface : Colors.teal.shade900;
    final priorityBadgeColor = isDark ? const Color(0xFFFFD180) : Colors.amber.shade900;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: isPriority
                ? Colors.amber.withValues(alpha: 0.2)
                : (isNote ? Colors.purple.withValues(alpha: 0.15) : null),
            foregroundColor: isPriority
                ? Colors.amber.shade900
                : (isNote ? Colors.purple.shade800 : null),
            child: Icon(
              isNote
                  ? Icons.edit_note_outlined
                  : (session.status == ActivitySessionStatus.completed
                      ? Icons.check
                      : (isPriority ? Icons.star_rounded : Icons.timer_outlined)),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  session.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isNote
                      ? Colors.purple.withValues(alpha: 0.12)
                      : Colors.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isNote ? '📝 Catatan' : '⏱️ Timer',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: modeBadgeColor,
                  ),
                ),
              ),
              if (isPriority) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber.shade700, width: 0.8),
                  ),
                  child: Text(
                    '⭐ Prioritas',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: priorityBadgeColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(
                isNote
                    ? '${session.category} • ${_dateTime(session.startedAt)}'
                    : '${session.category} • ${_dateTime(session.startedAt)} • ${calculator.format(session.durationAt())}${checkpoints.isEmpty ? '' : ' • ${checkpoints.length} update'}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              if (isNote && session.notes?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(
                  session.notes!.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
          onTap: onOpen,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onTogglePriority != null)
                IconButton(
                  icon: Icon(
                    isPriority ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: isPriority ? Colors.amber : null,
                  ),
                  tooltip: isPriority
                      ? 'Prioritas aktif (klik untuk lepas)'
                      : 'Tandai sebagai prioritas',
                  onPressed: onTogglePriority,
                ),
              PopupMenuButton<String>(
                tooltip: 'Kelola aktivitas',
                onSelected: (value) {
                  if (value == 'edit') onEdit?.call();
                  if (value == 'priority') onTogglePriority?.call();
                  if (value == 'archive') onArchive();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  if (onEdit != null)
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit aktivitas'),
                      ),
                    ),
                  PopupMenuItem(
                    value: 'priority',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(isPriority ? Icons.star_outline : Icons.star),
                      title: Text(isPriority ? 'Lepas prioritas' : 'Jadikan prioritas'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'archive',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.archive_outlined),
                      title: Text('Arsipkan'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_forever_outlined),
                      title: Text('Hapus permanen'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionDraft {
  const _SessionDraft(
    this.title,
    this.category,
    this.categoryId,
    this.mode,
    this.notes,
    this.startedAt,
  );
  final String title;
  final String category;
  final String? categoryId;
  final ActivityMode mode;
  ActivityKind get kind => mode.activityKind;
  final String? notes;
  final DateTime startedAt;
}

class _SessionForm extends StatefulWidget {
  const _SessionForm({
    this.parentSessionTitle,
    this.initialTitle,
    this.initialCategory,
    this.initialNotes,
    this.initialStartedAt,
    this.initialMode,
  });

  final String? parentSessionTitle;
  final String? initialTitle;
  final String? initialCategory;
  final String? initialNotes;
  final DateTime? initialStartedAt;
  final ActivityMode? initialMode;

  @override
  State<_SessionForm> createState() => _SessionFormState();
}

class _SessionFormState extends State<_SessionForm> {
  late final TextEditingController _title;
  late final TextEditingController _category;
  late final TextEditingController _notes;
  DateTime _startedAt = DateTime.now();
  ActivityMode _mode = ActivityMode.timeTracking;
  final _categoryRepository = getIt<CategoryRepository>();
  final _formSpeechService = ActivitySpeechService();
  bool _isListeningFormVoice = false;
  List<String> _activityCategories = [];
  Map<String, String> _activityCategoryIds = const {};
  String? _selectedCategory;
  bool _loadingCategories = true;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initialTitle ?? '');
    _category = TextEditingController(
      text: widget.initialCategory?.trim().isNotEmpty == true
          ? widget.initialCategory
          : '',
    );
    _selectedCategory = widget.initialCategory?.trim().isNotEmpty == true
        ? widget.initialCategory
        : null;
    _notes = TextEditingController(text: widget.initialNotes ?? '');
    if (widget.initialStartedAt != null) _startedAt = widget.initialStartedAt!;
    if (widget.initialMode != null) _mode = widget.initialMode!;
    _notes = TextEditingController(text: widget.initialNotes ?? '');
    _loadActivityCategories();
  }

  Future<void> _captureFormVoice() async {
    if (_isListeningFormVoice) {
      await _formSpeechService.stop();
      if (mounted) setState(() => _isListeningFormVoice = false);
      return;
    }
    final initialized = await _formSpeechService.initialize(
      onError: (msg) {
        if (!mounted) return;
        setState(() => _isListeningFormVoice = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Suara belum terdeteksi: $msg')),
        );
      },
    );
    if (!initialized) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pengenalan suara belum tersedia.')),
      );
      return;
    }
    if (mounted) setState(() => _isListeningFormVoice = true);
    await _formSpeechService.listen(
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() {
          _title.text = text;
          if (isFinal) _isListeningFormVoice = false;
        });
      },
    );
  }

  Future<void> _loadActivityCategories() async {
    try {
      final categories = await _categoryRepository.readActive(
        AppContext.householdId,
        type: 'activity',
      );

      if (!mounted) return;

      setState(() {
        _activityCategories = categories.map((c) => c.name).toList();
        _activityCategoryIds = {
          for (final category in categories) category.name: category.id,
        };
        _loadingCategories = false;

        // Saat dibuka dari draft asisten, initialCategory bisa jadi tidak lagi
        // valid di Data Utama. Jika tidak cocok, jangan biarkan pilihan basi,
        // kembalikan ke kategori aktif pertama (atau kosong bila memang tidak ada).
        final selectedStillValid = _selectedCategory != null &&
            _activityCategories.contains(_selectedCategory);
        if (_selectedCategory == null || !selectedStillValid) {
          if (_activityCategories.isNotEmpty) {
            _selectedCategory = _activityCategories.first;
            _category.text = _selectedCategory!;
          } else {
            _selectedCategory = null;
            _category.clear();
          }
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _activityCategories = [];
        _loadingCategories = false;
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _category.dispose();
    _notes.dispose();
    _formSpeechService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: 16,
      right: 16,
      top: 16,
      bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: ListView(
      shrinkWrap: true,
      children: [
        Text(
          widget.parentSessionTitle == null
              ? 'Mulai sesi aktivitas'
              : 'Tambah aktivitas di dalamnya',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        if (widget.parentSessionTitle != null) ...[
          const SizedBox(height: 6),
          Text('Induk: ${widget.parentSessionTitle}'),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _mode = ActivityMode.timeTracking),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: _mode == ActivityMode.timeTracking
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _mode == ActivityMode.timeTracking
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: _mode == ActivityMode.timeTracking ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            color: _mode == ActivityMode.timeTracking
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '⏱️ Pakai Timer',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: _mode == ActivityMode.timeTracking
                                  ? Theme.of(context).colorScheme.onPrimaryContainer
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Lacak durasi berjalan',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: _mode == ActivityMode.timeTracking
                              ? Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8)
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _mode = ActivityMode.history),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: _mode == ActivityMode.history
                        ? Colors.purple.withValues(alpha: 0.15)
                        : Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _mode == ActivityMode.history
                          ? Colors.purple.shade700
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: _mode == ActivityMode.history ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.edit_note_outlined,
                            color: _mode == ActivityMode.history
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '📝 Catat Saja',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: _mode == ActivityMode.history
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Kejadian sekali catat',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: _mode == ActivityMode.history
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _title,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Nama aktivitas',
            hintText: 'Misalnya ke pasar lalu ke kebun',
            prefixIcon: Icon(
              Icons.directions_run_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            suffixIcon: IconButton(
              icon: Icon(_isListeningFormVoice ? Icons.mic : Icons.mic_none),
              color: _isListeningFormVoice
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
              tooltip: _isListeningFormVoice
                  ? 'Stop dengar'
                  : 'Bicara nama aktivitas (Voice)',
              onPressed: _captureFormVoice,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_loadingCategories)
          const Center(child: CircularProgressIndicator())
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: InputDecoration(
                  labelText: 'Kategori aktivitas',
                  hintText: 'Pilih kategori aktivitas',
                  prefixIcon: Icon(
                    Icons.category_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: _activityCategories
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(
                          item,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCategory = value;
                    _category.text = value ?? '';
                  });
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  final result = await Navigator.of(context).push<String>(
                    MaterialPageRoute(
                      builder: (_) => const MasterDataPage(
                        assistantTab: 0,
                        returnOnCreate: true,
                      ),
                    ),
                  );
                  if (result != null && mounted) {
                    await _loadActivityCategories();
                    final categories = await _categoryRepository.readActive(
                      AppContext.householdId,
                      type: 'activity',
                    );
                    if (!mounted) return;
                    final newCategory = categories.firstWhere(
                      (c) => c.id == result,
                      orElse: () => categories.first,
                    );
                    setState(() {
                      _selectedCategory = newCategory.name;
                      _category.text = newCategory.name;
                    });
                  }
                },
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Tambah kategori baru di Data Utama'),
              ),
            ],
          ),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
              initialDate: _startedAt,
            );
            if (picked == null || !mounted) return;
            setState(
              () => _startedAt = DateTime(
                picked.year,
                picked.month,
                picked.day,
                _startedAt.hour,
                _startedAt.minute,
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_month_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _mode == ActivityMode.timeTracking
                            ? 'Mulai pada'
                            : 'Tanggal & waktu kejadian',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _dateTime(_startedAt),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Catatan (opsional)',
            hintText: 'Keterangan tambahan jika ada',
            prefixIcon: Icon(
              Icons.notes_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _mode == ActivityMode.history
                  ? Colors.purple.shade700
                  : Theme.of(context).colorScheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              if (_title.text.trim().isEmpty) return;
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(
                context,
                _SessionDraft(
                  _title.text.trim(),
                  _category.text.trim(),
                  _activityCategoryIds[_selectedCategory],
                  _mode,
                  _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                  _startedAt,
                ),
              );
            },
            icon: Icon(
              _mode == ActivityMode.history
                  ? Icons.check_circle_outline
                  : Icons.play_arrow_rounded,
            ),
            label: Text(
              _mode == ActivityMode.history
                  ? 'Simpan Catatan'
                  : widget.parentSessionTitle == null
                  ? 'Mulai Aktivitas Sekarang'
                  : 'Mulai Aktivitas Anak',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    ),
  );
}

class _CheckpointDraft {
  const _CheckpointDraft(this.label, this.place, this.note, this.occurredAt);
  final String label;
  final String? place;
  final String? note;
  final DateTime occurredAt;
}

class _CheckpointForm extends StatefulWidget {
  const _CheckpointForm();
  @override
  State<_CheckpointForm> createState() => _CheckpointFormState();
}

class _CheckpointFormState extends State<_CheckpointForm> {
  final _label = TextEditingController();
  final _place = TextEditingController();
  final _note = TextEditingController();
  @override
  void dispose() {
    _label.dispose();
    _place.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: 16,
      right: 16,
      top: 16,
      bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: ListView(
      shrinkWrap: true,
      children: [
        const Text(
          'Update aktivitas',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _label,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Sudah sampai/menjalankan apa?',
            hintText: 'Misalnya sampai pasar',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _place,
          decoration: const InputDecoration(labelText: 'Lokasi (opsional)'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _note,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            if (_label.text.trim().isEmpty) return;
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(
              context,
              _CheckpointDraft(
                _label.text.trim(),
                _place.text.trim().isEmpty ? null : _place.text.trim(),
                _note.text.trim().isEmpty ? null : _note.text.trim(),
                DateTime.now(),
              ),
            );
          },
          child: const Text('Simpan update'),
        ),
      ],
    ),
  );
}

String _two(int value) => value.toString().padLeft(2, '0');
String _time(DateTime value) =>
    '${_two(value.hour)}:${_two(value.minute)}:${_two(value.second)}';
String _dateOnly(DateTime value) =>
    '${_two(value.day)}/${_two(value.month)}/${value.year}';
String _dateTime(DateTime value) =>
    '${_two(value.day)}/${_two(value.month)}/${value.year} ${_time(value)}';

class _VoiceActivityCard extends StatelessWidget {
  const _VoiceActivityCard({
    required this.intent,
    required this.text,
    required this.status,
    required this.error,
    required this.isListening,
    required this.activeSessions,
    required this.activityCategories,
    required this.onListen,
    required this.onStop,
    required this.onEdit,
    required this.onSpeak,
    required this.onSelectTarget,
    required this.onCategoryChanged,
    required this.onConfirm,
    required this.onCancel,
  });

  final ActivityVoiceIntent? intent;
  final String text;
  final String status;
  final String? error;
  final bool isListening;
  final List<ActivitySessionEntity> activeSessions;
  final List<String> activityCategories;
  final VoidCallback onListen;
  final VoidCallback onStop;
  final VoidCallback onEdit;
  final VoidCallback? onSpeak;
  final ValueChanged<String?> onSelectTarget;
  final ValueChanged<String> onCategoryChanged;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final needsTarget =
        intent != null &&
        intent!.targetSessionId == null &&
        (intent!.type == ActivityVoiceIntentType.finish ||
            intent!.type == ActivityVoiceIntentType.checkpoint ||
            intent!.type == ActivityVoiceIntentType.note);
    final categories = activityCategories.toList()..sort();
    return AppCard(
      color: scheme.secondaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.record_voice_over_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Ngobrol soal aktivitas',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Bantuan voice',
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(
                    title: Text('Voice Aktivitas'),
                    content: Text(
                      'Bicara natural, misalnya “mulai memupuk timun”, '
                      '“kategorinya pertanian”, “ganti waktunya jam 7”, '
                      'atau “sudah benar”. Hasil selalu ditampilkan dan '
                      'dibacakan dulu. Aksi baru disimpan setelah kamu '
                      'menekan Konfirmasi atau mengucapkan OK.',
                    ),
                  ),
                ),
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Bicara santai, cek teksnya, lalu konfirmasi. Tidak ada aksi yang jalan diam-diam.',
            style: TextStyle(color: scheme.onSecondaryContainer),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: isListening ? onStop : onListen,
                icon: Icon(isListening ? Icons.stop : Icons.mic_none),
                label: Text(isListening ? 'Stop dengar' : 'Bicara'),
              ),
              const SizedBox(width: 8),
              Text(status, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          if (text.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('“$text”'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit teks'),
                ),
                OutlinedButton.icon(
                  onPressed: onSpeak,
                  icon: const Icon(Icons.volume_up_outlined),
                  label: const Text('Bacakan lagi'),
                ),
              ],
            ),
          ],
          if (intent != null) ...[
            const Divider(height: 24),
            Text(
              'Aksi yang akan dilakukan: ${intent!.actionLabel}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (intent!.targetTitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Aktivitas: ${intent!.targetTitle}'),
              ),
            if (intent!.parentTitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Induk: ${intent!.parentTitle}'),
              ),
            if (intent!.checkpointLabel != null &&
                intent!.type == ActivityVoiceIntentType.checkpoint)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Update: ${intent!.checkpointLabel}'),
              ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: categories.contains(intent!.category)
                  ? intent!.category
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Kategori aktivitas',
                border: OutlineInputBorder(),
              ),
              items: categories
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) onCategoryChanged(value);
              },
            ),
            if (needsTarget && activeSessions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                activeSessions.length == 1
                    ? 'Pilih aktivitas tujuan sebelum lanjut.'
                    : 'Ada beberapa aktivitas aktif. Pilih yang mau diupdate atau diselesaikan.',
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: intent!.targetSessionId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Pilih aktivitas tujuan',
                  border: OutlineInputBorder(),
                ),
                items: activeSessions
                    .map(
                      (session) => DropdownMenuItem(
                        value: session.id,
                        child: Text(session.title),
                      ),
                    )
                    .toList(),
                onChanged: onSelectTarget,
              ),
            ],
            if (intent!.ambiguityReason != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  intent!.ambiguityReason!,
                  style: TextStyle(color: scheme.error),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(onPressed: onCancel, child: const Text('Batal')),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: intent!.canConfirm ? onConfirm : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Konfirmasi'),
                ),
              ],
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
    );
  }
}

class _VoiceTextEditor extends StatefulWidget {
  const _VoiceTextEditor({required this.initialText});

  final String initialText;

  @override
  State<_VoiceTextEditor> createState() => _VoiceTextEditorState();
}

class _VoiceTextEditorState extends State<_VoiceTextEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Perbaiki teks voice'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLines: 4,
      decoration: const InputDecoration(
        hintText: 'Contoh: makan selesai',
        border: OutlineInputBorder(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Pakai teks ini'),
      ),
    ],
  );
}
