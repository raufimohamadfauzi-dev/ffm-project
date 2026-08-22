import 'package:flutter/material.dart';

import '../../domain/ffm_assistant_models.dart';

/// Dialog mandiri untuk memperbaiki draft yang masih berada di sesi chat.
/// Tidak menyimpan data; caller wajib memvalidasi lalu meneruskan ke form.
class FfmAssistantDraftEditDialog extends StatefulWidget {
  const FfmAssistantDraftEditDialog({super.key, required this.draft});

  final FfmAssistantDraft draft;

  @override
  State<FfmAssistantDraftEditDialog> createState() =>
      _FfmAssistantDraftEditDialogState();
}

class _FfmAssistantDraftEditDialogState
    extends State<FfmAssistantDraftEditDialog> {
  late final TextEditingController _amountController;
  late final TextEditingController _fromController;
  late final TextEditingController _toController;
  late final TextEditingController _categoryController;
  late final TextEditingController _goalController;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.draft.amount?.toString() ?? '',
    );
    _fromController = TextEditingController(
      text: widget.draft.fromAccountName ?? '',
    );
    _toController = TextEditingController(
      text: widget.draft.toAccountName ?? '',
    );
    _categoryController = TextEditingController(
      text: widget.draft.categoryName ?? '',
    );
    _goalController = TextEditingController(text: widget.draft.goalName ?? '');
    _noteController = TextEditingController(text: widget.draft.note ?? '');
  }

  @override
  void dispose() {
    _amountController.dispose();
    _fromController.dispose();
    _toController.dispose();
    _categoryController.dispose();
    _goalController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String? _textOrNull(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  void _save() {
    final amountText = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final amount = amountText.isEmpty ? null : int.tryParse(amountText);
    Navigator.of(context).pop(
      FfmAssistantDraft(
        kind: widget.draft.kind,
        createdAt: widget.draft.createdAt,
        amount: amount,
        title: widget.draft.title,
        partyName: widget.draft.partyName,
        fromAccountName: _textOrNull(_fromController),
        toAccountName: _textOrNull(_toController),
        categoryName: _textOrNull(_categoryController),
        adminFee: widget.draft.adminFee,
        goalName: _textOrNull(_goalController),
        note: _textOrNull(_noteController),
        date: widget.draft.date,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ubah draft di chat'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Nominal (Rp)'),
          ),
          TextField(
            controller: _fromController,
            decoration: const InputDecoration(labelText: 'Rekening asal'),
          ),
          TextField(
            controller: _toController,
            decoration: const InputDecoration(labelText: 'Rekening tujuan'),
          ),
          TextField(
            controller: _categoryController,
            decoration: const InputDecoration(labelText: 'Kategori'),
          ),
          TextField(
            controller: _goalController,
            decoration: const InputDecoration(labelText: 'Target keuangan'),
          ),
          TextField(
            controller: _noteController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Catatan'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Batal'),
      ),
      FilledButton(onPressed: _save, child: const Text('Pakai perubahan')),
    ],
  );
}
