import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../../../../core/di/injection.dart';
import '../../../activity/data/repositories/activity_repository.dart';
import '../../../activity/data/services/activity_speech_service.dart';
import '../../../activity/domain/entities/activity_entity.dart';
import '../../../activity/domain/activity_voice.dart';
import '../../../activity/presentation/bloc/activity_bloc.dart';
import '../../data/ffm_assistant_interpreter.dart';
import '../../data/ffm_assistant_learning_repository.dart';
import '../../data/ffm_assistant_memory_repository.dart';
import '../../data/ffm_assistant_unanswered_question_repository.dart';
import '../../domain/ffm_assistant_draft_validator.dart';
import '../../domain/ffm_assistant_feedback_context.dart';
import '../../domain/ffm_assistant_models.dart';
import 'ffm_assistant_draft_edit_dialog.dart';
import 'ffm_assistant_message_correction_dialog.dart';

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
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => FfmAssistantSheet(
    onIntent: onIntent,
    onIntents: onIntents,
    session: session,
    currentDestination: currentDestination,
  ),
);

class FfmAssistantSheet extends StatefulWidget {
  const FfmAssistantSheet({
    super.key,
    required this.onIntent,
    required this.onIntents,
    required this.session,
    this.currentDestination,
  });

  final FfmAssistantIntentHandler onIntent;
  final FfmAssistantIntentBatchHandler onIntents;
  final FfmAssistantChatSession session;
  final FfmAssistantDestination? currentDestination;

  @override
  State<FfmAssistantSheet> createState() => _FfmAssistantSheetState();
}

class _FfmAssistantSheetState extends State<FfmAssistantSheet> {
  final _controller = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _speech = ActivitySpeechService();
  final _interpreter = getIt<FfmAssistantInterpreter>();
  final _memoryRepository = getIt<FfmAssistantMemoryRepository>();
  final _unansweredRepository =
      getIt<FfmAssistantUnansweredQuestionRepository>();
  final _activityRepository = getIt<ActivityRepository>();
  final _activityVoiceParser = const ActivityVoiceParser();
  final Set<String> _savedTeachingKeys = <String>{};
  final Set<String> _confirmedActivityKeys = <String>{};
  var _submitting = false;
  var _listening = false;
  var _followLatestMessages = true;
  String? _speakingEntryKey;
  String? _pausedEntryKey;

  List<FfmAssistantChatEntry> get _entries => widget.session.entries;
  List<FfmAssistantIntent> get _queuedIntents => widget.session.queuedIntents;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateLatestMessagePreference);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToEnd(force: true),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateLatestMessagePreference);
    _controller.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    _speech.cancel();
    _speech.stopSpeaking();
    super.dispose();
  }

  Future<void> _submit([String? rawText]) async {
    final text = (rawText ?? _controller.text).trim();
    if (text.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _entries.add(FfmAssistantChatEntry(isUser: true, text: text));
      _controller.clear();
    });
    _scrollToEnd();
    try {
      if (_tryReviseActiveDraft(text)) return;
      if (await _tryHandleActivityRequest(text)) return;
      final pending = widget.session.pendingDialog;
      final intents = pending == null
          ? await _interpreter.interpretMany(
              text,
              currentDestination: widget.currentDestination,
            )
          : await _interpreter.resolvePendingDialog(
              text,
              pending,
              currentDestination: widget.currentDestination,
            );
      if (!mounted) return;
      setState(() {
        for (final intent in intents) {
          final response =
              intent.response ??
              intent.clarification ??
              'Aku sudah memahami permintaannya. Cek draft ini dulu, ya.';
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
          _entries.add(
            FfmAssistantChatEntry(
              isUser: false,
              text: response,
              intent: intent,
              understanding: _understandingFor(intent),
              review: review,
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
      if (intents.any(
        (intent) => intent.type == FfmAssistantIntentType.unknown,
      )) {
        await _unansweredRepository.record(
          rawQuestion: text,
          pageContext: widget.currentDestination?.name,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _entries.add(
          const FfmAssistantChatEntry(
            isUser: false,
            text: 'Maaf, aku belum bisa memproses itu. Coba ulangi dengan kalimat lebih singkat, ya.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
      _scrollToEnd();
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
      _entries.add(
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
        _entries.add(FfmAssistantChatEntry(isUser: false, text: response));
      });
      _scrollToEnd();
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _entries.add(
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
      _entries.add(FfmAssistantChatEntry(isUser: false, text: response));
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
      _entries.add(FfmAssistantChatEntry(isUser: false, text: response));
    });
    _scrollToEnd();
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final ready = await _speech.initialize(
      onError: (message) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mikrofon belum siap: $message')),
        );
      },
      onStatus: (status) {
        if (!mounted || status != 'done' && status != 'notListening') return;
        setState(() => _listening = false);
      },
    );
    if (!ready || !mounted) return;
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() => _controller.text = text);
        if (isFinal) _submit(text);
      },
    );
  }

  String _speechKeyFor(int index, FfmAssistantChatEntry entry) =>
      '$index:${identityHashCode(entry)}';

  Future<void> _toggleSpeakFor(int index, FfmAssistantChatEntry entry) async {
    final key = _speechKeyFor(index, entry);
    final speaking = await _speech.isSpeaking();
    if (speaking && _speakingEntryKey == key) {
      await _speech.stopSpeaking();
      if (mounted) {
        setState(() {
          _speakingEntryKey = null;
          _pausedEntryKey = key;
        });
      }
      return;
    }

    final resumed = _pausedEntryKey == key && await _speech.resumeSpeaking();
    if (!resumed) await _speech.speak(entry.text);
    if (mounted) {
      setState(() {
        _speakingEntryKey = key;
        _pausedEntryKey = null;
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
        () => _entries.add(
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
    final shouldNavigate =
        (intent.destination != null || intent.draft != null) &&
        intent.type != FfmAssistantIntentType.confirm;
    if (shouldNavigate) {
      final handler = widget.onIntent;
      setState(() => _queuedIntents.remove(intent));
      Navigator.of(context).pop();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await handler(intent);
      return;
    }
    await widget.onIntent(intent);
    if (mounted) setState(() => _queuedIntents.remove(intent));
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
      await _memoryRepository.save(
        kind: proposal.kind,
        triggerText: proposal.triggerText,
        valueText: proposal.valueText,
        source: 'chat_approved',
      );
      if (!mounted) return;
      setState(() {
        _savedTeachingKeys.add(key);
        widget.session.lastAssistantText = 'Sip, ajaran ini sudah kusimpan lokal di perangkat. Kamu bisa mengubah atau mengarsipkannya di Pusat Latihan Asisten.';
        _entries.add(
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
      _entries.add(
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
      return 'nominal diubah dari ${_DraftPreview._rupiah(before.amount ?? 0)} menjadi ${_DraftPreview._rupiah(after.amount ?? 0)}.';
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
      _entries.add(
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
      _entries.add(
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

  Future<void> _copyFeedbackContext(FfmAssistantChatEntry entry) async {
    final feedback = _feedbackContextFor(entry);
    if (feedback == null) return;
    final sanitizedQuestion = FfmAssistantLearningSanitizer.sanitize(
      feedback.userQuestion,
    );
    final sanitizedAnswer = FfmAssistantLearningSanitizer.sanitize(
      feedback.assistantAnswer,
    );
    final safeFeedback = FfmAssistantFeedbackContext(
      userQuestion: sanitizedQuestion,
      assistantAnswer: sanitizedAnswer,
    );
    await Clipboard.setData(
      ClipboardData(text: safeFeedback.buildTrainingSeed()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Konteks aman disalin. Tempel ke ChatGPT bila perlu.'),
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
      _scrollToEnd();
    }
  }

  void _updateLatestMessagePreference() {
    if (!_scrollController.hasClients) return;
    final distanceToEnd =
        _scrollController.position.maxScrollExtent - _scrollController.offset;
    _followLatestMessages = distanceToEnd < 88;
  }

  void _scrollToEnd({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || (!force && !_followLatestMessages)) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String _understandingFor(FfmAssistantIntent intent) {
    final page = intent.destination == null
        ? null
        : FfmAssistantCatalog.findByDestination(intent.destination!);
    final draft = intent.draft;
    if (intent.type == FfmAssistantIntentType.unknown) {
      return 'Belum yakin dengan maksudnya. Tidak ada aksi yang akan dijalankan.';
    }
    if (intent.type == FfmAssistantIntentType.listPages) {
      return 'Kamu mau tahu jumlah dan daftar halaman FFM.';
    }
    if (intent.type == FfmAssistantIntentType.transactionStats) {
      final time = intent.normalizedText.contains('hari ini')
          ? 'hari ini'
          : intent.normalizedText.contains('minggu ini')
          ? 'minggu ini'
          : 'bulan ini';
      return 'Kamu mau cek jumlah transaksi $time.';
    }
    if (intent.type == FfmAssistantIntentType.financialWarnings) {
      return 'Kamu mau cek kondisi anggaran dan arus kas.';
    }
    if (intent.type == FfmAssistantIntentType.openPage && page != null) {
      return 'Kamu mau pindah ke ${page.name}.';
    }
    if (draft != null) {
      final details = <String>[
        _DraftPreview._draftLabel(draft.kind).replaceFirst('Draft ', ''),
        if (draft.amount != null) _DraftPreview._rupiah(draft.amount!),
        if (draft.fromAccountName != null) 'dari ${draft.fromAccountName}',
        if (draft.toAccountName != null) 'ke ${draft.toAccountName}',
      ];
      return 'Kamu mau buat ${details.join(' • ')}.';
    }
    if (intent.type == FfmAssistantIntentType.cancel) {
      return 'Kamu mau membatalkan draft yang sedang dibahas.';
    }
    if (intent.type == FfmAssistantIntentType.readLastResponse) {
      return 'Kamu mau jawaban terakhir dibacakan lagi.';
    }
    if (intent.needsTeachingApproval) {
      return 'Kamu ingin aku menyimpan ajaran lokal setelah kamu menyetujuinya.';
    }
    if (page != null) return 'Kamu sedang menanyakan ${page.name}.';
    return 'Aku memahami permintaan ini sebagai ${intent.type.name}.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final sheetHeight = (mediaQuery.size.height * .78).clamp(
      380.0,
      mediaQuery.size.height - keyboardInset - mediaQuery.padding.top,
    );
    final currentPage = widget.currentDestination == null
        ? null
        : FfmAssistantCatalog.findByDestination(widget.currentDestination!);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: SizedBox(
          height: sheetHeight,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 10, 6),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.auto_awesome_outlined,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Asisten FFM',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            currentPage == null
                                ? 'Teks & suara • tetap di perangkat'
                                : '${currentPage.name} • tetap di perangkat',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Pilih suara bacaan',
                      onPressed: _openVoicePicker,
                      icon: const Icon(Icons.record_voice_over_outlined),
                    ),
                    IconButton(
                      tooltip: 'Reset chat',
                      onPressed: _confirmResetSession,
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      tooltip: 'Tutup asisten',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: _entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    final entry = _entries[index];
                    return _AssistantMessageCard(
                      entry: entry,
                      onSpeak: entry.isUser
                          ? null
                          : () => _toggleSpeakFor(index, entry),
                      isSpeaking:
                          _speakingEntryKey == _speechKeyFor(index, entry),
                      onIntent:
                          entry.intent == null ||
                              entry.intent!.needsTeachingApproval
                          ? null
                          : () => _handleIntent(entry.intent!),
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
                          entry.intent?.draft != null && entry.review != null
                          ? () => _editActiveDraft(entry.intent!)
                          : null,
                      onCancelDraft:
                          entry.intent?.draft != null && entry.review != null
                          ? _cancelActiveDraft
                          : null,
                      onCopyFeedback: entry.isUser
                          ? null
                          : () => _copyFeedbackContext(entry),
                      onCopyText: () => _copyEntryText(entry),
                      onCorrectMessage: entry.isUser
                          ? () => _correctUserMessage(entry)
                          : () => _correctMessageFromEntry(entry),
                      onConfirmActivity:
                          entry.activityIntent?.canConfirm ?? false
                          ? () => _confirmActivityIntent(entry.activityIntent!)
                          : null,
                      activityConfirmed: entry.activityIntent == null
                          ? false
                          : _confirmedActivityKeys.contains(
                              _activityKey(entry.activityIntent!),
                            ),
                    );
                  },
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
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton.filledTonal(
                        tooltip: _listening
                            ? 'Berhenti dengar'
                            : 'Bicara ke Asisten',
                        onPressed: _submitting ? null : _toggleListening,
                        icon: Icon(_listening ? Icons.stop : Icons.mic_none),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _inputFocusNode,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _submit(),
                          onTap: _scrollToEnd,
                          decoration: const InputDecoration(
                            hintText: 'Tulis perintah atau pertanyaan…',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Kirim',
                        onPressed: _submitting ? null : _submit,
                        icon: const Icon(Icons.arrow_upward),
                      ),
                    ],
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

class _AssistantMessageCard extends StatelessWidget {
  const _AssistantMessageCard({
    required this.entry,
    this.onSpeak,
    this.isSpeaking = false,
    this.onIntent,
    this.onApproveTeaching,
    this.teachingSaved = false,
    this.review,
    this.onEditDraft,
    this.onCancelDraft,
    this.onCopyFeedback,
    this.onCopyText,
    this.onCorrectMessage,
    this.onConfirmActivity,
    this.activityConfirmed = false,
  });

  final FfmAssistantChatEntry entry;
  final VoidCallback? onSpeak;
  final bool isSpeaking;
  final VoidCallback? onIntent;
  final VoidCallback? onApproveTeaching;
  final bool teachingSaved;
  final FfmAssistantDraftReview? review;
  final VoidCallback? onEditDraft;
  final VoidCallback? onCancelDraft;
  final VoidCallback? onCopyFeedback;
  final VoidCallback? onCopyText;
  final VoidCallback? onCorrectMessage;
  final VoidCallback? onConfirmActivity;
  final bool activityConfirmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = entry.isUser;
    final intent = entry.intent;
    final isUnknown = !isUser && intent?.type == FfmAssistantIntentType.unknown;
    final bubbleColor = isUser
        ? theme.colorScheme.primary
        : isUnknown
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.secondaryContainer;
    final onBubbleColor = isUser
        ? theme.colorScheme.onPrimary
        : isUnknown
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.onSecondaryContainer;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isUser
                ? constraints.maxWidth * .76
                : constraints.maxWidth * .88,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bubbleColor,
              border: isUnknown
                  ? Border.all(
                      color: theme.colorScheme.tertiary.withValues(alpha: .7),
                    )
                  : null,
              borderRadius: isUser
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(5),
                    )
                  : const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(5),
                      bottomRight: Radius.circular(18),
                    ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isUser && entry.understanding != null) ...[
                    _AssistantUnderstandingDisclosure(
                      text: entry.understanding!,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (isUnknown) ...[
                    Semantics(
                      label: 'Belum ada jawaban tetap. Pertanyaan tersimpan untuk pembaruan.',
                      child: Row(
                        children: [
                          Icon(
                            Icons.school_outlined,
                            size: 17,
                            color: theme.colorScheme.onTertiaryContainer,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Belum ada jawaban tetap — tersimpan untuk pembaruan',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onTertiaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  _ReadableChatText(text: entry.text, color: onBubbleColor),
                  if (intent?.draft != null) ...[
                    const SizedBox(height: 10),
                    _DraftPreview(draft: intent!.draft!, review: review),
                  ],
                  if (onCopyText != null ||
                      onSpeak != null ||
                      onIntent != null ||
                      onConfirmActivity != null) ...[
                    const SizedBox(height: 8),
                    _AssistantMessageToolbar(
                      isUser: isUser,
                      hasPrimaryAction:
                          onIntent != null &&
                          intent!.type != FfmAssistantIntentType.unknown &&
                          intent.type != FfmAssistantIntentType.listPages &&
                          (review?.canContinue ?? true),
                      primaryActionLabel: intent?.destination == null
                          ? 'Lanjut'
                          : 'Buka',
                      onPrimaryAction: onIntent,
                      onConfirmActivity: onConfirmActivity,
                      activityConfirmed: activityConfirmed,
                      onCopyText: onCopyText,
                      onSpeak: onSpeak,
                      isSpeaking: isSpeaking,
                      onCorrectMessage: onCorrectMessage,
                      onCopyFeedback: onCopyFeedback,
                      onEditDraft: onEditDraft,
                      onCancelDraft: onCancelDraft,
                      onApproveTeaching: onApproveTeaching,
                      teachingSaved: teachingSaved,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantUnderstandingDisclosure extends StatefulWidget {
  const _AssistantUnderstandingDisclosure({required this.text});

  final String text;

  @override
  State<_AssistantUnderstandingDisclosure> createState() =>
      _AssistantUnderstandingDisclosureState();
}

class _AssistantUnderstandingDisclosureState
    extends State<_AssistantUnderstandingDisclosure> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              Icon(
                Icons.psychology_alt_outlined,
                size: 17,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _expanded
                      ? 'Yang aku pahami: ${widget.text}'
                      : 'Yang aku pahami',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _AssistantMessageMenuAction {
  correct,
  copyFeedback,
  editDraft,
  cancelDraft,
  approveTeaching,
}

class _AssistantMessageToolbar extends StatelessWidget {
  const _AssistantMessageToolbar({
    required this.isUser,
    required this.hasPrimaryAction,
    required this.primaryActionLabel,
    this.onPrimaryAction,
    this.onConfirmActivity,
    required this.activityConfirmed,
    this.onCopyText,
    this.onSpeak,
    required this.isSpeaking,
    this.onCorrectMessage,
    this.onCopyFeedback,
    this.onEditDraft,
    this.onCancelDraft,
    this.onApproveTeaching,
    required this.teachingSaved,
  });

  final bool isUser;
  final bool hasPrimaryAction;
  final String primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final VoidCallback? onConfirmActivity;
  final bool activityConfirmed;
  final VoidCallback? onCopyText;
  final VoidCallback? onSpeak;
  final bool isSpeaking;
  final VoidCallback? onCorrectMessage;
  final VoidCallback? onCopyFeedback;
  final VoidCallback? onEditDraft;
  final VoidCallback? onCancelDraft;
  final VoidCallback? onApproveTeaching;
  final bool teachingSaved;

  @override
  Widget build(BuildContext context) {
    final hasMoreActions =
        onCorrectMessage != null ||
        onCopyFeedback != null ||
        onEditDraft != null ||
        onCancelDraft != null ||
        onApproveTeaching != null;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      children: [
        if (hasPrimaryAction)
          Tooltip(
            message: 'Buka arahan ini. Data belum disimpan otomatis.',
            child: FilledButton.tonalIcon(
              onPressed: onPrimaryAction,
              icon: const Icon(Icons.open_in_new, size: 17),
              label: Text(primaryActionLabel),
            ),
          ),
        if (onConfirmActivity != null)
          Tooltip(
            message: activityConfirmed
                ? 'Aktivitas ini sudah dikonfirmasi.'
                : 'Simpan aktivitas hanya setelah kamu setuju.',
            child: FilledButton.tonalIcon(
              onPressed: activityConfirmed ? null : onConfirmActivity,
              icon: Icon(
                activityConfirmed
                    ? Icons.check_circle_outline
                    : Icons.play_circle_outline,
                size: 17,
              ),
              label: Text(activityConfirmed ? 'Tersimpan' : 'Konfirmasi'),
            ),
          ),
        if (!isUser && onSpeak != null)
          Tooltip(
            message: isSpeaking
                ? 'Hentikan bacaan. Ketuk Dengarkan lagi untuk melanjutkan.'
                : 'Dengarkan jawaban. Ketuk lagi untuk berhenti.',
            child: IconButton(
              onPressed: onSpeak,
              icon: Icon(
                isSpeaking
                    ? Icons.stop_circle_outlined
                    : Icons.volume_up_outlined,
              ),
            ),
          ),
        if (onCopyText != null)
          Tooltip(
            message: isUser ? 'Salin pesan' : 'Salin jawaban',
            child: IconButton(
              onPressed: onCopyText,
              icon: const Icon(Icons.copy_outlined),
            ),
          ),
        if (hasMoreActions)
          Tooltip(
            message: 'Aksi lainnya',
            child: PopupMenuButton<_AssistantMessageMenuAction>(
              icon: const Icon(Icons.more_horiz),
              tooltip: 'Aksi lainnya',
              onSelected: (action) {
                switch (action) {
                  case _AssistantMessageMenuAction.correct:
                    onCorrectMessage?.call();
                    return;
                  case _AssistantMessageMenuAction.copyFeedback:
                    onCopyFeedback?.call();
                    return;
                  case _AssistantMessageMenuAction.editDraft:
                    onEditDraft?.call();
                    return;
                  case _AssistantMessageMenuAction.cancelDraft:
                    onCancelDraft?.call();
                    return;
                  case _AssistantMessageMenuAction.approveTeaching:
                    onApproveTeaching?.call();
                    return;
                }
              },
              itemBuilder: (context) => [
                if (onCorrectMessage != null)
                  const PopupMenuItem(
                    value: _AssistantMessageMenuAction.correct,
                    child: _AssistantMenuLabel(
                      icon: Icons.spellcheck_outlined,
                      label: 'Benarkan & kirim ulang',
                    ),
                  ),
                if (onEditDraft != null)
                  const PopupMenuItem(
                    value: _AssistantMessageMenuAction.editDraft,
                    child: _AssistantMenuLabel(
                      icon: Icons.edit_outlined,
                      label: 'Koreksi draft',
                    ),
                  ),
                if (onCancelDraft != null)
                  const PopupMenuItem(
                    value: _AssistantMessageMenuAction.cancelDraft,
                    child: _AssistantMenuLabel(
                      icon: Icons.close_outlined,
                      label: 'Batalkan draft',
                    ),
                  ),
                if (onApproveTeaching != null)
                  PopupMenuItem(
                    value: _AssistantMessageMenuAction.approveTeaching,
                    enabled: !teachingSaved,
                    child: _AssistantMenuLabel(
                      icon: teachingSaved
                          ? Icons.bookmark_added_outlined
                          : Icons.bookmark_add_outlined,
                      label: teachingSaved
                          ? 'Ajaran tersimpan'
                          : 'Simpan ajaran',
                    ),
                  ),
                if (onCopyFeedback != null)
                  const PopupMenuItem(
                    value: _AssistantMessageMenuAction.copyFeedback,
                    child: _AssistantMenuLabel(
                      icon: Icons.copy_all_outlined,
                      label: 'Salin bahan perbaikan',
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AssistantMenuLabel extends StatelessWidget {
  const _AssistantMenuLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
  );
}

class _ReadableChatText extends StatelessWidget {
  const _ReadableChatText({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final paragraphs = text
        .split(RegExp(r'\n\s*\n'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < paragraphs.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          Text(
            paragraphs[index],
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: color, height: 1.42),
          ),
        ],
      ],
    );
  }
}

class _DraftPreview extends StatelessWidget {
  const _DraftPreview({required this.draft, this.review});

  final FfmAssistantDraft draft;
  final FfmAssistantDraftReview? review;

  @override
  Widget build(BuildContext context) {
    final fields = <MapEntry<String, String>>[
      MapEntry('Jenis', _draftLabel(draft.kind).replaceFirst('Draft ', '')),
      MapEntry('Nama atau judul', draft.title ?? 'Belum diisi'),
      if (draft.amount != null) MapEntry('Nominal', _rupiah(draft.amount!)),
      if (draft.fromAccountName != null)
        MapEntry('Sumber dana', draft.fromAccountName!),
      if (draft.toAccountName != null)
        MapEntry('Tujuan dana', draft.toAccountName!),
      if (draft.categoryName != null)
        MapEntry('Bagian Data Utama', draft.categoryName!),
      ...draft.formValues.entries.map(
        (field) => MapEntry(
          _formFieldLabel(field.key),
          _formFieldValue(field.key, field.value),
        ),
      ),
      if (draft.partyName != null) MapEntry('Pihak', draft.partyName!),
      if (draft.goalName != null) MapEntry('Target', draft.goalName!),
      if (draft.adminFee != null && draft.adminFee! > 0)
        MapEntry('Biaya admin', _rupiah(draft.adminFee!)),
      if (draft.note != null) MapEntry('Catatan', draft.note!),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rancangan yang akan dibuka',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          ...fields.map(
            (field) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 108, child: Text(field.key)),
                  Expanded(
                    child: Text(
                      field.value,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Belum ada data yang disimpan. Kamu masih bisa koreksi atau membatalkan rancangan ini.',
          ),
          if (review != null) ...[
            const SizedBox(height: 8),
            Text(
              'Versi ${review!.version}${review!.canContinue ? ' • siap dicek di form' : ' • masih perlu dilengkapi'}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            for (final issue in review!.issues)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• ${issue.message}'),
              ),
          ],
        ],
      ),
    );
  }

  static String _draftLabel(FfmAssistantDraftKind kind) => switch (kind) {
    FfmAssistantDraftKind.income => 'Draft pemasukan',
    FfmAssistantDraftKind.expense => 'Draft pengeluaran',
    FfmAssistantDraftKind.transfer => 'Draft transfer',
    FfmAssistantDraftKind.goalDeposit => 'Draft setor target',
    FfmAssistantDraftKind.goalUsage => 'Draft pakai target',
    FfmAssistantDraftKind.goal => 'Draft target keuangan',
    FfmAssistantDraftKind.liability => 'Draft hutang',
    FfmAssistantDraftKind.receivable => 'Draft piutang',
    FfmAssistantDraftKind.asset => 'Draft aset',
    FfmAssistantDraftKind.budget => 'Draft anggaran',
    FfmAssistantDraftKind.masterData => 'Draft Data Utama',
    FfmAssistantDraftKind.reminder => 'Draft pengingat',
    FfmAssistantDraftKind.activity => 'Draft aktivitas',
  };

  static String _rupiah(int amount) =>
      'Rp${amount.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (match) => '.')}';

  static String _formFieldLabel(String field) => switch (field) {
    'type' => 'Jenis kategori',
    'defaultBudgetPeriod' => 'Saran periode',
    'accountType' => 'Jenis rekening',
    'openingBalance' => 'Saldo awal',
    'details' => 'Keterangan',
    _ => field,
  };

  static String _formFieldValue(String field, String value) =>
      switch ('$field:$value') {
        'type:income' => 'Pemasukan',
        'type:expense' => 'Pengeluaran',
        'defaultBudgetPeriod:none' => 'Tidak ada',
        'defaultBudgetPeriod:weekly' => 'Mingguan',
        'defaultBudgetPeriod:monthly' => 'Bulanan',
        'accountType:cash' => 'Tunai',
        'accountType:bank' => 'Bank',
        'accountType:ewallet' => 'E-Wallet',
        _ => value,
      };
}
