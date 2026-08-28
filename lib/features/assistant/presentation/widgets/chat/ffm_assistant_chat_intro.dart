import 'package:flutter/material.dart';

/// Contoh cepat yang hanya mengisi kolom pesan; tidak membuat data apa pun.
typedef FfmAssistantQuickPrompt = ({String label, String text, IconData icon});

/// Saran cepat kontekstual yang ditampilkan setelah jawaban asisten.
typedef FfmAssistantSuggestion = ({String label, String text, IconData icon});

/// Pengantar singkat dan contoh cepat pada halaman Asisten.
///
/// Saat [compact] true (percakapan sudah dimulai), pengantar menyusut menjadi
/// satu aksi "Contoh" agar tidak mengurangi ruang membaca riwayat.
class FfmAssistantChatIntro extends StatelessWidget {
  const FfmAssistantChatIntro({
    super.key,
    required this.examples,
    required this.onFillExample,
    this.compact = false,
  });

  final List<FfmAssistantQuickPrompt> examples;
  final ValueChanged<String> onFillExample;
  final bool compact;

  static const double _minTouchTarget = 44;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (compact) {
      return Semantics(
        button: true,
        label: 'Lihat contoh permintaan',
        child: ActionChip(
          avatar: const Icon(Icons.bolt_outlined, size: 18),
          label: const Text('Contoh'),
          onPressed: () => _openExamplesBottomSheet(context),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            'Kamu bisa memberi satu permintaan atau beberapa sekaligus dalam '
            'satu pesan. Ketuk contoh untuk mengisi kolom pesan.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
          child: Row(
            children: [
              for (final prompt in examples) ...[
                _ExampleChip(
                  prompt: prompt,
                  onTap: () => onFillExample(prompt.text),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _openExamplesBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              'Contoh permintaan',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Contoh hanya mengisi kolom pesan. Data tidak dibuat sampai '
              'kamu menyetujui draft.',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final prompt in examples) ...[
              _ExampleChip(
                prompt: prompt,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onFillExample(prompt.text);
                },
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExampleChip extends StatelessWidget {
  const _ExampleChip({required this.prompt, required this.onTap});

  final FfmAssistantQuickPrompt prompt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Contoh: ${prompt.label}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: FfmAssistantChatIntro._minTouchTarget,
        ),
        child: ActionChip(
          avatar: Icon(prompt.icon, size: 18),
          label: Text(prompt.label),
          onPressed: onTap,
          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        ),
      ),
    );
  }
}

/// Saran cepat kontekstual setelah asisten menjawab.
///
/// Ditampilkan ringkas di bawah kartu jawaban dan hanya mengisi kolom pesan
/// lewat [onFillExample].
class FfmAssistantContextualSuggestions extends StatelessWidget {
  const FfmAssistantContextualSuggestions({
    super.key,
    required this.suggestions,
    required this.onFillExample,
  });

  final List<FfmAssistantSuggestion> suggestions;
  final ValueChanged<String> onFillExample;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              'Lanjutkan:',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(width: 8),
            for (final suggestion in suggestions) ...[
              Semantics(
                button: true,
                label: 'Saran: ${suggestion.label}',
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: FfmAssistantChatIntro._minTouchTarget,
                  ),
                  child: ActionChip(
                    avatar: Icon(suggestion.icon, size: 16),
                    label: Text(suggestion.label),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                    onPressed: () => onFillExample(suggestion.text),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pertanyaan klarifikasi untuk bagian yang ambigu, ditampilkan di chat.
///
/// Menyajikan pilihan aman bila tersedia; tidak menebak nilai pengguna.
class FfmAssistantAmbiguousClarification extends StatelessWidget {
  const FfmAssistantAmbiguousClarification({
    super.key,
    required this.question,
    required this.safeChoices,
    required this.onSelectChoice,
  });

  final String question;
  final List<String> safeChoices;
  final ValueChanged<String> onSelectChoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(question, style: theme.textTheme.bodyMedium),
              if (safeChoices.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final choice in safeChoices)
                      Semantics(
                        button: true,
                        label: 'Pilih: $choice',
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: FfmAssistantChatIntro._minTouchTarget,
                          ),
                          child: OutlinedButton(
                            onPressed: () => onSelectChoice(choice),
                            child: Text(choice),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}