import 'package:flutter/material.dart';

import '../../domain/ffm_assistant_models.dart';

/// Dialog mandiri untuk mengajarkan jawaban/alur dari konteks kartu chat.
///
/// Tidak menyimpan apa pun; pemanggil tetap harus menyetujui dan menyimpan
/// proposal melalui repository memori lokal.
class FfmAssistantQuickTeachDialog extends StatefulWidget {
  const FfmAssistantQuickTeachDialog({
    super.key,
    required this.initialQuestion,
    required this.currentAnswer,
  });

  final String initialQuestion;
  final String currentAnswer;

  @override
  State<FfmAssistantQuickTeachDialog> createState() =>
      _FfmAssistantQuickTeachDialogState();
}

class _FfmAssistantQuickTeachDialogState
    extends State<FfmAssistantQuickTeachDialog> {
  late final TextEditingController _questionController;
  final _answerController = TextEditingController();
  var _kind = 'answer';

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController(text: widget.initialQuestion);
  }

  @override
  void dispose() {
    _questionController.dispose();
    _answerController.dispose();
    super.dispose();
  }

  void _save() {
    final question = _questionController.text.trim();
    final answer = _answerController.text.trim();
    if (question.isEmpty || answer.isEmpty) return;
    Navigator.of(context).pop(
      FfmAssistantTeachingProposal(
        kind: _kind,
        triggerText: question,
        valueText: answer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ajarkan jawaban yang benar'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Isi jawaban atau alur yang seharusnya dipakai Asisten. Ini hanya disimpan lokal setelah kamu menekan Simpan ajaran.',
          ),
          const SizedBox(height: 12),
          Text(
            'Jawaban sebelumnya:\n${widget.currentAnswer}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Jenis ajaran'),
            items: const [
              DropdownMenuItem(value: 'answer', child: Text('Jawaban')),
              DropdownMenuItem(value: 'flow', child: Text('Alur')),
            ],
            onChanged: (value) => setState(() => _kind = value ?? 'answer'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _questionController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Pertanyaan/pemicu'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _answerController,
            minLines: 3,
            maxLines: 7,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Jawaban atau alur yang benar',
              hintText: 'Contoh: Di Data Utama ada rekening, kategori, toko, tag, sumber pemasukan, dan profil keluarga.',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Batal'),
      ),
      FilledButton(onPressed: _save, child: const Text('Simpan ajaran')),
    ],
  );
}
