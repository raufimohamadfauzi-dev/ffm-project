import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../data/services/activity_speech_service.dart';
import '../../domain/activity_voice.dart';
import '../../domain/entities/activity_entity.dart';
import '../bloc/activity_bloc.dart';
import '../../../daily_notes/presentation/widgets/daily_notes_section.dart';
import '../../../tasks/presentation/widgets/tasks_section.dart';
import '../../../routines/presentation/widgets/routines_section.dart';
import '../../../schedule/presentation/widgets/schedule_section.dart';

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
      child: BlocProvider(
        create: (_) => getIt<ActivityBloc>()..load(),
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
  Timer? _ticker;
  String _typeFilter = 'Semua';
  DateTime? _dayFilter;
  final _calculator = const ActivityDurationCalculator();
  final _voiceParser = const ActivityVoiceParser();
  final _speechService = ActivitySpeechService();
  ActivityVoiceIntent? _voiceIntent;
  String _voiceText = '';
  String? _voiceError;
  String _voiceStatus = 'Siap bicara';
  bool _voiceInitialized = false;
  bool _processingFinalVoice = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final activityState = context.read<ActivityBloc>().state;
      if (activityState.activeSessions.isNotEmpty) setState(() {});
    });
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<ActivityBloc>().load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  bool _matchesDay(DateTime value) {
    final day = _dayFilter;
    return day == null ||
        (value.year == day.year &&
            value.month == day.month &&
            value.day == day.day);
  }

  Future<void> _showSessionDetails(
    ActivitySessionEntity session,
    List<ActivityCheckpointEntity> checkpoints,
    List<ActivitySessionEntity> children,
  ) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                session.title,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${session.category} • ${_dateOnly(session.startedAt)}${session.parentSessionId == null ? '' : ' • aktivitas di dalam sesi lain'}',
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _DetailMetric(
                      label: 'Mulai',
                      value: _time(session.startedAt),
                    ),
                  ),
                  Expanded(
                    child: _DetailMetric(
                      label: 'Selesai',
                      value: session.endedAt == null
                          ? 'Berjalan'
                          : _time(session.endedAt!),
                    ),
                  ),
                  Expanded(
                    child: _DetailMetric(
                      label: 'Durasi',
                      value: _calculator.format(session.durationAt()),
                    ),
                  ),
                ],
              ),
              if (children.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Aktivitas di dalamnya',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                for (final child in children)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      child.status == ActivitySessionStatus.active
                          ? Icons.play_circle_outline
                          : Icons.check_circle_outline,
                    ),
                    title: Text(child.title),
                    subtitle: Text(
                      '${_dateTime(child.startedAt)} • ${_calculator.format(child.durationAt())}${child.endedAt == null ? ' • berjalan' : ''}',
                    ),
                  ),
              ],
              if (session.notes?.isNotEmpty == true) ...[
                const SizedBox(height: 14),
                Text(session.notes!),
              ],
              const SizedBox(height: 18),
              const Text(
                'Update aktivitas',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (checkpoints.isEmpty)
                const Text(
                  'Belum ada update. Tekan Update aktivitas saat ada perubahan.',
                )
              else
                for (var index = 0; index < checkpoints.length; index++)
                  _CheckpointDetailTile(
                    checkpoint: checkpoints[index],
                    previous: index == 0
                        ? session.startedAt
                        : checkpoints[index - 1].occurredAt,
                    calculator: _calculator,
                  ),
            ],
          ),
        ),
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
  }) async {
    final result = await showModalBottomSheet<_SessionDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SessionForm(
        parentSessionTitle: parentTitle,
        initialTitle: initialTitle,
        initialCategory: initialCategory,
        initialNotes: initialNotes,
      ),
    );
    if (result == null || !mounted) return;
    await context.read<ActivityBloc>().startSession(
      title: result.title,
      category: result.category,
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
      _previewVoice(transcript.trim());
    } finally {
      _processingFinalVoice = false;
    }
  }

  void _previewVoice(String transcript) {
    final state = context.read<ActivityBloc>().state;
    final parsed = _voiceParser.parse(
      transcript,
      activeSessions: state.activeSessions,
    );
    if (parsed.type == ActivityVoiceIntentType.confirm &&
        _voiceIntent?.canConfirm == true) {
      _confirmVoice();
      return;
    }
    if (parsed.type == ActivityVoiceIntentType.confirm) {
      setState(() {
        _voiceIntent = null;
        _voiceText = transcript;
        _voiceError = 'Belum ada perintah aktivitas yang bisa dikonfirmasi. Bilang dulu misalnya “mulai makan” atau “selesai perjalanan”.';
        _voiceStatus = 'Menunggu perintah aktivitas';
      });
      _speechService.speak(
        'Belum ada perintah aktivitas yang menunggu konfirmasi. Bilang dulu aktivitas yang mau dicatat ya.',
      );
      return;
    }
    if (parsed.type == ActivityVoiceIntentType.cancel) {
      _cancelVoice();
      return;
    }
    var intent = parsed;
    if (intent.type == ActivityVoiceIntentType.note &&
        intent.targetSessionId == null &&
        state.activeSessions.length == 1) {
      final session = state.activeSessions.single;
      intent = intent.copyWith(
        targetSessionId: session.id,
        targetTitle: session.title,
      );
    }
    setState(() {
      _voiceIntent = intent;
      _voiceText = transcript;
      _voiceError = null;
      _voiceStatus = 'Cek dulu hasilnya sebelum disimpan';
    });
    context.read<ActivityBloc>().recordVoiceIntent(
      intent,
      status: ActivityVoiceStatus.preview,
    );
    _speakVoicePreview(intent);
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
    _previewVoice(edited.trim());
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
          title: const Text('Aktivitas & Jurnal'),
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
        floatingActionButton: PopupMenuButton<String>(
          tooltip: 'Tambah aktivitas',
          onSelected: (value) {
            if (value == 'session') _startSession();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'session',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.timer_outlined),
                title: Text('Mulai sesi aktivitas'),
                subtitle: Text(
                  'Timer dan update berjalan dari awal sampai selesai',
                ),
              ),
            ),
          ],
          child: const FloatingActionButton.extended(
            heroTag: 'activity_add_fab',
            onPressed: null,
            icon: Icon(Icons.add),
            label: Text('Tambah'),
          ),
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
                    onListen: _startVoiceCapture,
                    onStop: _stopVoiceCapture,
                    onEdit: _editVoiceText,
                    onSpeak: _voiceIntent == null
                        ? null
                        : () => _speakVoicePreview(_voiceIntent!),
                    onSelectTarget: _selectVoiceTarget,
                    onConfirm: _confirmVoice,
                    onCancel: _cancelVoice,
                  ),
                  const SizedBox(height: 16),
                  const DailyNotesSection(),
                  const SizedBox(height: 16),
                  const TasksSection(),
                  const SizedBox(height: 16),
                  const RoutinesSection(),
                  const SizedBox(height: 16),
                  const ScheduleSection(),
                  const SizedBox(height: 16),
                  AppCard(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DropdownButton<String>(
                          value: _typeFilter,
                          underline: const SizedBox.shrink(),
                          items:
                              const [
                                    'Semua',
                                    'Perjalanan',
                                    'Belanja',
                                    'Pekerjaan',
                                    'Keluarga',
                                    'Lainnya',
                                  ]
                                  .map(
                                    (item) => DropdownMenuItem(
                                      value: item,
                                      child: Text(item),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) =>
                              setState(() => _typeFilter = value ?? 'Semua'),
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Builder(
                    builder: (context) {
                      final visibleActiveSessions = state.activeSessions
                          .where(
                            (session) =>
                                (_typeFilter == 'Semua' ||
                                    session.category == _typeFilter) &&
                                _matchesDay(session.startedAt),
                          )
                          .toList();
                      final visibleSessions = state.sessions
                          .where(
                            (session) =>
                                session.status !=
                                    ActivitySessionStatus.active &&
                                (_typeFilter == 'Semua' ||
                                    session.category == _typeFilter) &&
                                _matchesDay(session.startedAt),
                          )
                          .toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                      state.checkpoints[session.id] ?? const [],
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
                                ),
                              ),
                            const SizedBox(height: 8),
                          ],
                          _SectionTitle(
                            title: 'Aktivitas tersimpan',
                            count: visibleSessions.length,
                          ),
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
                                onArchive: () => context
                                    .read<ActivityBloc>()
                                    .archiveSession(session.id),
                                onDelete: () => _confirmDeleteSession(session),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        const SizedBox(width: 8),
        Chip(label: Text('$count')),
      ],
    ),
  );
}

class _ActiveSessionCard extends StatelessWidget {
  const _ActiveSessionCard({
    required this.session,
    required this.checkpoints,
    required this.calculator,
    required this.onCheckpoint,
    required this.onFinish,
    required this.onStartChild,
  });
  final ActivitySessionEntity session;
  final List<ActivityCheckpointEntity> checkpoints;
  final ActivityDurationCalculator calculator;
  final VoidCallback onCheckpoint;
  final VoidCallback onFinish;
  final VoidCallback onStartChild;

  @override
  Widget build(BuildContext context) {
    final duration = session.durationAt();
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
              Text(
                calculator.format(duration),
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
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
                label: const Text('Update posisi'),
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
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.checkpoints,
    required this.calculator,
    required this.onOpen,
    required this.onArchive,
    required this.onDelete,
  });
  final ActivitySessionEntity session;
  final List<ActivityCheckpointEntity> checkpoints;
  final ActivityDurationCalculator calculator;
  final VoidCallback onOpen;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          child: Icon(
            session.status == ActivitySessionStatus.completed
                ? Icons.check
                : Icons.timer_outlined,
          ),
        ),
        title: Text(
          session.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${session.category} • ${_dateTime(session.startedAt)} • ${calculator.format(session.durationAt())}${checkpoints.isEmpty ? '' : ' • ${checkpoints.length} update'}',
        ),
        onTap: onOpen,
        trailing: PopupMenuButton<String>(
          tooltip: 'Kelola aktivitas',
          onSelected: (value) {
            if (value == 'archive') onArchive();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'archive',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.archive_outlined),
                title: Text('Arsipkan'),
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_forever_outlined),
                title: Text('Hapus permanen'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SessionDraft {
  const _SessionDraft(this.title, this.category, this.notes, this.startedAt);
  final String title;
  final String category;
  final String? notes;
  final DateTime startedAt;
}

class _SessionForm extends StatefulWidget {
  const _SessionForm({
    this.parentSessionTitle,
    this.initialTitle,
    this.initialCategory,
    this.initialNotes,
  });

  final String? parentSessionTitle;
  final String? initialTitle;
  final String? initialCategory;
  final String? initialNotes;
  @override
  State<_SessionForm> createState() => _SessionFormState();
}

class _SessionFormState extends State<_SessionForm> {
  late final TextEditingController _title;
  late final TextEditingController _category;
  late final TextEditingController _notes;
  DateTime _startedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initialTitle ?? '');
    _category = TextEditingController(
      text: widget.initialCategory?.trim().isNotEmpty == true
          ? widget.initialCategory
          : 'Perjalanan',
    );
    _notes = TextEditingController(text: widget.initialNotes ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _category.dispose();
    _notes.dispose();
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
        TextField(
          controller: _title,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nama aktivitas',
            hintText: 'Misalnya ke pasar lalu ke kebun',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _category,
          decoration: const InputDecoration(
            labelText: 'Jenis aktivitas',
            hintText: 'Perjalanan, kerja, belanja, atau lainnya',
          ),
        ),
        const SizedBox(height: 10),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mulai pada'),
          subtitle: Text(_dateTime(_startedAt)),
          trailing: const Icon(Icons.schedule),
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
        ),
        TextField(
          controller: _notes,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _SessionDraft(
                _title.text.trim(),
                _category.text.trim().isEmpty
                    ? 'Lainnya'
                    : _category.text.trim(),
                _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                _startedAt,
              ),
            );
          },
          child: Text(
            widget.parentSessionTitle == null
                ? 'Mulai sekarang'
                : 'Mulai aktivitas anak',
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

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 3),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
    ],
  );
}

class _CheckpointDetailTile extends StatelessWidget {
  const _CheckpointDetailTile({
    required this.checkpoint,
    required this.previous,
    required this.calculator,
  });
  final ActivityCheckpointEntity checkpoint;
  final DateTime previous;
  final ActivityDurationCalculator calculator;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.flag_outlined),
    title: Text(checkpoint.label),
    subtitle: Text(
      [
        _dateTime(checkpoint.occurredAt),
        'selang ${calculator.format(checkpoint.occurredAt.difference(previous))}',
        if (checkpoint.place?.isNotEmpty == true) checkpoint.place!,
        if (checkpoint.note?.isNotEmpty == true) checkpoint.note!,
      ].join(' • '),
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
    required this.onListen,
    required this.onStop,
    required this.onEdit,
    required this.onSpeak,
    required this.onSelectTarget,
    required this.onConfirm,
    required this.onCancel,
  });

  final ActivityVoiceIntent? intent;
  final String text;
  final String status;
  final String? error;
  final bool isListening;
  final List<ActivitySessionEntity> activeSessions;
  final VoidCallback onListen;
  final VoidCallback onStop;
  final VoidCallback onEdit;
  final VoidCallback? onSpeak;
  final ValueChanged<String?> onSelectTarget;
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
                      'Contoh: “mulai makan”, “makan selesai”, “mulai makan di dalam perjalanan”, atau “update perjalanan sampai pasar”. Hasil selalu ditampilkan dan dibacakan dulu. Aksi baru disimpan setelah kamu menekan Konfirmasi atau mengucapkan OK.',
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
