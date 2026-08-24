import 'package:flutter/material.dart';

/// Gaya v54: JSON hasil LLM selalu ditempel dan ditinjau pengguna; tidak ada
/// unggahan atau pengiriman data diam-diam dari perangkat.
class AssistantTrainingImportDialog extends StatefulWidget {
  const AssistantTrainingImportDialog({super.key});

  @override
  State<AssistantTrainingImportDialog> createState() =>
      _AssistantTrainingImportDialogState();
}

class _AssistantTrainingImportDialogState
    extends State<AssistantTrainingImportDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final content = _controller.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tempel JSON knowledge pack dulu.')),
      );
      return;
    }
    Navigator.pop(context, content);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Impor knowledge pack'),
      content: SizedBox(
        width: 560,
        child: TextField(
          controller: _controller,
          minLines: 10,
          maxLines: 16,
          decoration: const InputDecoration(
            alignLabelWithHint: true,
            labelText: 'Tempel JSON dari LLM atau backup memori',
            hintText: '{"formatVersion":"ffm-assistant-knowledge-v1", ...}',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Tinjau')),
      ],
    );
  }
}
