import 'package:flutter/material.dart';

/// Hasil koreksi jawaban asisten yang diisi oleh pengguna.
class FfmAssistantAnswerCorrectionResult {
  const FfmAssistantAnswerCorrectionResult({
    required this.correctedText,
    this.topic,
  });

  final String correctedText;
  final String? topic;
}

/// Dialog untuk membenarkan jawaban asisten yang salah atau kurang tepat.
///
/// Pengguna dapat mengetikkan fakta atau aturan yang benar, yang kemudian
/// disimpan permanen ke memori asisten lokal sehingga asisten tidak mengulangi kesalahan.
class FfmAssistantAnswerCorrectionDialog extends StatefulWidget {
  const FfmAssistantAnswerCorrectionDialog({
    super.key,
    required this.userQuestion,
    required this.assistantAnswer,
  });

  final String userQuestion;
  final String assistantAnswer;

  @override
  State<FfmAssistantAnswerCorrectionDialog> createState() =>
      _FfmAssistantAnswerCorrectionDialogState();
}

class _FfmAssistantAnswerCorrectionDialogState
    extends State<FfmAssistantAnswerCorrectionDialog> {
  late final TextEditingController _correctionController;
  late final TextEditingController _topicController;

  @override
  void initState() {
    super.initState();
    _correctionController = TextEditingController();
    _topicController = TextEditingController();
  }

  @override
  void dispose() {
    _correctionController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _correctionController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.edit_note_rounded, color: colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Benarkan Jawaban Asisten',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ajari asisten fakta atau aturan yang benar. Koreksi ini disimpan secara permanen di memori lokal HP Anda agar asisten tidak mengulangi kesalahan.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              // Pertanyaan Pengguna
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pertanyaan Anda:',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.userQuestion,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Input Koreksi
              TextField(
                controller: _correctionController,
                minLines: 3,
                maxLines: 6,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Jawaban / Fakta yang Benar *',
                  hintText:
                      'Contoh: Tabel database untuk transaksi bernama "transactions", dan rekening bernama "accounts".',
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: colorScheme.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Input Topik / Kategori (Opsional)
              TextField(
                controller: _topicController,
                decoration: const InputDecoration(
                  labelText: 'Topik / Kata Kunci (Opsional)',
                  hintText: 'Contoh: tabel_database, rekening, atau ekspor',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Tersimpan permanen secara aman di database lokal HP Anda.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.outline,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: _canSubmit
              ? () {
                  Navigator.of(context).pop(
                    FfmAssistantAnswerCorrectionResult(
                      correctedText: _correctionController.text.trim(),
                      topic: _topicController.text.trim().isNotEmpty
                          ? _topicController.text.trim()
                          : null,
                    ),
                  );
                }
              : null,
          icon: const Icon(Icons.save_rounded, size: 18),
          label: const Text('Simpan Koreksi'),
        ),
      ],
    );
  }
}
