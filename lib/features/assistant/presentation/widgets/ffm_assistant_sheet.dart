import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../../../../core/di/injection.dart';
import '../../../activity/data/repositories/activity_repository.dart';
import '../../../activity/data/services/activity_speech_service.dart';
import '../../../activity/domain/entities/activity_entity.dart';
import '../../../activity/domain/activity_voice.dart';
import '../../../activity/presentation/bloc/activity_bloc.dart';
import '../../../transaction/data/services/receipt_ocr_service.dart';
import '../../../transaction/presentation/pages/receipt_scan_page.dart';
import '../../../transaction/presentation/pages/transaction_pages.dart';
import '../../data/ffm_assistant_interpreter.dart';
import '../../data/ffm_assistant_learning_repository.dart';
import '../../data/ffm_assistant_memory_repository.dart';
import '../../data/ffm_assistant_unanswered_question_repository.dart';
import '../../domain/ffm_assistant_draft_validator.dart';
import '../../domain/ffm_assistant_feedback_context.dart';
import '../../domain/ffm_assistant_models.dart';
import 'ffm_assistant_draft_edit_dialog.dart';
import 'ffm_assistant_quick_teach_dialog.dart';

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
  final _learningRepository = getIt<FfmAssistantLearningRepository>();
  final _memoryRepository = getIt<FfmAssistantMemoryRepository>();
  final _unansweredRepository =
      getIt<FfmAssistantUnansweredQuestionRepository>();
  final _activityRepository = getIt<ActivityRepository>();
  final _activityVoiceParser = const ActivityVoiceParser();
  final Set<String> _savedTeachingKeys = <String>{};
  final Set<String> _savedLearningKeys = <String>{};
  final Set<String> _confirmedActivityKeys = <String>{};
  var _submitting = false;
  var _listening = false;

  List<FfmAssistantChatEntry> get _entries => widget.session.entries;
  List<FfmAssistantIntent> get _queuedIntents => widget.session.queuedIntents;

  @override
  void dispose() {
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
          if (intent.destination != null || intent.draft != null) {
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

  Future<void> _scanReceiptFromAssistant() async {
    if (_submitting) return;
    final navigator = Navigator.of(context);
    final result = await navigator.push<ReceiptOcrResult>(
      MaterialPageRoute(builder: (_) => const ReceiptScanPage()),
    );
    if (result == null || !mounted) return;

    final total = result.total ?? result.itemsTotal;
    final itemLabel = result.items.isEmpty
        ? 'belum ada item yang dikenali'
        : '${result.items.length} item terbaca';
    setState(() {
      _entries
        ..add(
          const FfmAssistantChatEntry(
            isUser: true,
            text: 'Aku pilih foto nota untuk dibaca.',
          ),
        )
        ..add(
          FfmAssistantChatEntry(
            isUser: false,
            text:
                'Sip, OCR membaca $itemLabel${total > 0 ? ' dengan total Rp$total' : ''}. Aku buka draft transaksi supaya kamu bisa cek rekening, kategori, item, dan nominal sebelum simpan.',
          ),
        );
      widget.session.lastAssistantText = _entries.last.text;
    });
    _scrollToEnd();

    navigator.pop();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => TransactionFormPage(initialScan: result),
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

  String _learningKey(FfmAssistantIntent intent) =>
      '${intent.type.name}\u0000${intent.rawText}'.toLowerCase();

  Iterable<String> _protectedTermsFor(FfmAssistantDraft draft) => [
    draft.fromAccountName,
    draft.toAccountName,
    draft.partyName,
    draft.categoryName,
    draft.goalName,
    draft.title,
  ].whereType<String>();

  Future<void> _saveLearningExample(FfmAssistantIntent intent) async {
    final draft = intent.draft;
    if (draft == null) return;
    final key = _learningKey(intent);
    if (_savedLearningKeys.contains(key)) return;
    final sanitized = FfmAssistantLearningSanitizer.sanitize(
      intent.rawText,
      protectedTerms: _protectedTermsFor(draft),
    );
    if (sanitized.isEmpty) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bantu Asisten belajar?'),
        content: Text(
          'Yang disimpan cuma contoh teranonimkan ini:\n\n“$sanitized”\n\nNominal dan nama tertentu disamarkan. Ini tidak menyimpan transaksi atau draft.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Jangan simpan'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Simpan contoh'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await _learningRepository.saveApproved(
        rawText: intent.rawText,
        intent: intent.type,
        protectedTerms: _protectedTermsFor(draft),
        source: 'draft_preview_approved',
      );
      if (!mounted) return;
      setState(() => _savedLearningKeys.add(key));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contoh teranonimkan disimpan untuk Pusat Latihan.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contoh belajar belum tersimpan.')),
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

  Future<void> _quickTeachFromEntry(FfmAssistantChatEntry entry) async {
    final feedback = _feedbackContextFor(entry);
    if (feedback == null) return;
    final proposal = await showDialog<FfmAssistantTeachingProposal>(
      context: context,
      builder: (_) => FfmAssistantQuickTeachDialog(
        initialQuestion: feedback.userQuestion,
        currentAnswer: feedback.assistantAnswer,
      ),
    );
    if (proposal == null || !mounted) return;
    final key = _teachingKey(proposal);
    if (_savedTeachingKeys.contains(key)) return;
    try {
      await _memoryRepository.save(
        kind: proposal.kind,
        triggerText: proposal.triggerText,
        valueText: proposal.valueText,
        source: 'chat_quick_teach',
      );
      if (!mounted) return;
      setState(() {
        _savedTeachingKeys.add(key);
        _entries.add(
          const FfmAssistantChatEntry(
            isUser: false,
            text: 'Sip, koreksi jawaban tadi sudah kusimpan lokal. Kamu bisa ubah atau arsipkan nanti di Pusat Latihan Asisten.',
          ),
        );
      });
      _scrollToEnd();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Koreksi jawaban belum tersimpan.')),
      );
    }
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

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
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
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
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
                            'Asisten FFM Lokal',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            currentPage == null
                                ? 'Paham teks & suara • data tetap di perangkat'
                                : 'Lagi di ${currentPage.name} • data tetap di perangkat',
                          ),
                        ],
                      ),
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
                          : () => _speech.speak(entry.text),
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
                      onSaveLearningExample:
                          entry.intent?.draft != null &&
                              !(entry.intent?.needsClarification ?? true) &&
                              !(entry.intent?.needsTeachingApproval ?? false)
                          ? () => _saveLearningExample(entry.intent!)
                          : null,
                      learningExampleSaved: entry.intent == null
                          ? false
                          : _savedLearningKeys.contains(
                              _learningKey(entry.intent!),
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
                      onQuickTeach: entry.isUser
                          ? null
                          : () => _quickTeachFromEntry(entry),
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
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: _submitting ? null : _openQueuedDrafts,
                      icon: const Icon(Icons.playlist_add_check),
                      label: Text(
                        'Buka ${_queuedIntents.length} draft satu per satu',
                      ),
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
                        tooltip: 'Foto nota dengan OCR',
                        onPressed: _submitting
                            ? null
                            : _scanReceiptFromAssistant,
                        icon: const Icon(Icons.document_scanner_outlined),
                      ),
                      const SizedBox(width: 8),
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
    this.onIntent,
    this.onApproveTeaching,
    this.teachingSaved = false,
    this.onSaveLearningExample,
    this.learningExampleSaved = false,
    this.review,
    this.onEditDraft,
    this.onCancelDraft,
    this.onCopyFeedback,
    this.onCopyText,
    this.onQuickTeach,
    this.onConfirmActivity,
    this.activityConfirmed = false,
  });

  final FfmAssistantChatEntry entry;
  final VoidCallback? onSpeak;
  final VoidCallback? onIntent;
  final VoidCallback? onApproveTeaching;
  final bool teachingSaved;
  final VoidCallback? onSaveLearningExample;
  final bool learningExampleSaved;
  final FfmAssistantDraftReview? review;
  final VoidCallback? onEditDraft;
  final VoidCallback? onCancelDraft;
  final VoidCallback? onCopyFeedback;
  final VoidCallback? onCopyText;
  final VoidCallback? onQuickTeach;
  final VoidCallback? onConfirmActivity;
  final bool activityConfirmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = entry.isUser;
    final intent = entry.intent;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primary
                : theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isUser && entry.understanding != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: .72),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.psychology_alt_outlined,
                          size: 17,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Yang aku pahami: ${entry.understanding}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  entry.text,
                  style: TextStyle(
                    color: isUser
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                if (intent?.draft != null) ...[
                  const SizedBox(height: 10),
                  _DraftPreview(draft: intent!.draft!, review: review),
                ],
                if (onCopyText != null ||
                    (!isUser &&
                        (onSpeak != null ||
                            onIntent != null ||
                            onApproveTeaching != null ||
                            onSaveLearningExample != null ||
                            onEditDraft != null ||
                            onCancelDraft != null ||
                            onCopyFeedback != null ||
                            onQuickTeach != null ||
                            onConfirmActivity != null))) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (onCopyText != null)
                        TextButton.icon(
                          onPressed: onCopyText,
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          label: Text(isUser ? 'Salin pesan' : 'Salin jawaban'),
                        ),
                      if (onSpeak != null)
                        TextButton.icon(
                          onPressed: onSpeak,
                          icon: const Icon(Icons.volume_up_outlined, size: 18),
                          label: const Text('Bacakan'),
                        ),
                      if (onIntent != null &&
                          intent!.type != FfmAssistantIntentType.unknown &&
                          intent.type != FfmAssistantIntentType.listPages &&
                          (review?.canContinue ?? true))
                        FilledButton.tonalIcon(
                          onPressed: onIntent,
                          icon: Icon(
                            intent.destination == null
                                ? Icons.check_circle_outline
                                : Icons.open_in_new,
                            size: 18,
                          ),
                          label: Text(
                            intent.destination == null
                                ? 'Lanjut ke form'
                                : 'Buka & cek',
                          ),
                        ),
                      if (onConfirmActivity != null)
                        FilledButton.tonalIcon(
                          onPressed: activityConfirmed
                              ? null
                              : onConfirmActivity,
                          icon: Icon(
                            activityConfirmed
                                ? Icons.check_circle_outline
                                : Icons.play_circle_outline,
                            size: 18,
                          ),
                          label: Text(
                            activityConfirmed
                                ? 'Aktivitas tersimpan'
                                : 'Konfirmasi aktivitas',
                          ),
                        ),
                      if (onEditDraft != null)
                        TextButton.icon(
                          onPressed: onEditDraft,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Koreksi nominal/draft'),
                        ),
                      if (onCancelDraft != null)
                        TextButton.icon(
                          onPressed: onCancelDraft,
                          icon: const Icon(Icons.close_outlined, size: 18),
                          label: const Text('Batal draft'),
                        ),
                      if (onApproveTeaching != null)
                        FilledButton.tonalIcon(
                          onPressed: teachingSaved ? null : onApproveTeaching,
                          icon: Icon(
                            teachingSaved
                                ? Icons.bookmark_added_outlined
                                : Icons.bookmark_add_outlined,
                            size: 18,
                          ),
                          label: Text(
                            teachingSaved
                                ? 'Ajaran tersimpan'
                                : 'Simpan ajaran',
                          ),
                        ),
                      if (onSaveLearningExample != null)
                        TextButton.icon(
                          onPressed: learningExampleSaved
                              ? null
                              : onSaveLearningExample,
                          icon: const Icon(Icons.school_outlined, size: 18),
                          label: Text(
                            learningExampleSaved
                                ? 'Contoh tersimpan'
                                : 'Bantu Asisten belajar',
                          ),
                        ),
                      if (onCopyFeedback != null)
                        TextButton.icon(
                          onPressed: onCopyFeedback,
                          icon: const Icon(Icons.copy_all_outlined, size: 18),
                          label: const Text('Salin konteks'),
                        ),
                      if (onQuickTeach != null)
                        TextButton.icon(
                          onPressed: onQuickTeach,
                          icon: const Icon(Icons.edit_note_outlined, size: 18),
                          label: const Text('Ajarkan Asisten'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DraftPreview extends StatelessWidget {
  const _DraftPreview({required this.draft, this.review});

  final FfmAssistantDraft draft;
  final FfmAssistantDraftReview? review;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      _draftLabel(draft.kind),
      if (draft.amount != null) _rupiah(draft.amount!),
      if (draft.fromAccountName != null) 'dari ${draft.fromAccountName}',
      if (draft.toAccountName != null) 'ke ${draft.toAccountName}',
      if (draft.partyName != null) 'pihak: ${draft.partyName}',
      if (draft.goalName != null) 'target: ${draft.goalName}',
      if (draft.adminFee != null && draft.adminFee! > 0)
        'admin ${_rupiah(draft.adminFee!)}',
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
          Text(parts.join(' • ')),
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
}
