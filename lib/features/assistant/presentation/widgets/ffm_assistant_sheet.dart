import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../activity/data/services/activity_speech_service.dart';
import '../../data/ffm_assistant_interpreter.dart';
import '../../domain/ffm_assistant_models.dart';

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
  FfmAssistantDestination? currentDestination,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => FfmAssistantSheet(
    onIntent: onIntent,
    onIntents: onIntents,
    currentDestination: currentDestination,
  ),
);

class FfmAssistantSheet extends StatefulWidget {
  const FfmAssistantSheet({
    super.key,
    required this.onIntent,
    required this.onIntents,
    this.currentDestination,
  });

  final FfmAssistantIntentHandler onIntent;
  final FfmAssistantIntentBatchHandler onIntents;
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
  final _entries = <_AssistantChatEntry>[
    const _AssistantChatEntry(
      isUser: false,
      text: 'Hai, aku Asisten FFM. Mau cek data, pindah halaman, atau siapin draft? Tulis santai aja. Contoh: “Ada berapa transaksi bulan ini?”',
    ),
  ];
  var _submitting = false;
  var _listening = false;
  String? _lastAssistantText;
  final _queuedIntents = <FfmAssistantIntent>[];

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
      _entries.add(_AssistantChatEntry(isUser: true, text: text));
      _controller.clear();
    });
    _scrollToEnd();
    try {
      final intents = await _interpreter.interpretMany(
        text,
        currentDestination: widget.currentDestination,
      );
      if (!mounted) return;
      setState(() {
        for (final intent in intents) {
          final response =
              intent.response ??
              intent.clarification ??
              'Aku sudah memahami permintaannya. Cek draft ini dulu, ya.';
          _lastAssistantText = response;
          _entries.add(
            _AssistantChatEntry(isUser: false, text: response, intent: intent),
          );
          if (intent.destination != null || intent.draft != null) {
            _queuedIntents.add(intent);
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _entries.add(
          const _AssistantChatEntry(
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

  Future<void> _handleIntent(FfmAssistantIntent intent) async {
    if (intent.type == FfmAssistantIntentType.readLastResponse) {
      await _speech.speak(
        _lastAssistantText ?? 'Belum ada jawaban untuk dibaca.',
      );
      return;
    }
    if (intent.type == FfmAssistantIntentType.cancel) {
      if (!mounted) return;
      setState(
        () => _entries.add(
          const _AssistantChatEntry(
            isUser: false,
            text: 'Oke, tidak ada draft dari Asisten yang akan disimpan.',
          ),
        ),
      );
      return;
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

  Future<void> _openQueuedDrafts() async {
    final intents = List<FfmAssistantIntent>.of(_queuedIntents);
    if (intents.length < 2) return;
    final handler = widget.onIntents;
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await handler(intents);
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
                      onIntent: entry.intent == null
                          ? null
                          : () => _handleIntent(entry.intent!),
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
  });

  final _AssistantChatEntry entry;
  final VoidCallback? onSpeak;
  final VoidCallback? onIntent;

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
                  _DraftPreview(draft: intent!.draft!),
                ],
                if (!isUser && (onSpeak != null || onIntent != null)) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (onSpeak != null)
                        TextButton.icon(
                          onPressed: onSpeak,
                          icon: const Icon(Icons.volume_up_outlined, size: 18),
                          label: const Text('Bacakan'),
                        ),
                      if (onIntent != null &&
                          intent!.type != FfmAssistantIntentType.unknown &&
                          intent.type != FfmAssistantIntentType.listPages)
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
                                ? 'Lanjutkan'
                                : 'Buka & cek',
                          ),
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
  const _DraftPreview({required this.draft});

  final FfmAssistantDraft draft;

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
      child: Text(parts.join(' • ')),
    );
  }

  static String _draftLabel(FfmAssistantDraftKind kind) => switch (kind) {
    FfmAssistantDraftKind.income => 'Draft pemasukan',
    FfmAssistantDraftKind.expense => 'Draft pengeluaran',
    FfmAssistantDraftKind.transfer => 'Draft transfer',
    FfmAssistantDraftKind.goalDeposit => 'Draft setor target',
    FfmAssistantDraftKind.goalUsage => 'Draft pakai target',
    FfmAssistantDraftKind.liability => 'Draft hutang',
    FfmAssistantDraftKind.receivable => 'Draft piutang',
  };

  static String _rupiah(int amount) =>
      'Rp${amount.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (match) => '.')}';
}

class _AssistantChatEntry {
  const _AssistantChatEntry({
    required this.isUser,
    required this.text,
    this.intent,
  });

  final bool isUser;
  final String text;
  final FfmAssistantIntent? intent;
}
