import 'package:flutter/material.dart';

import '../../domain/ffm_assistant_models.dart';
import '../../data/ffm_assistant_draft_feedback_service.dart';
import '../../../activity/domain/entities/activity_entity.dart';

/// Dialog mandiri untuk memperbaiki draft yang masih berada di sesi chat.
/// Tidak menyimpan data; caller wajib memvalidasi lalu meneruskan ke form.
/// Sekarang juga mencatat perubahan untuk feedback ke LLM.
class FfmAssistantDraftEditDialog extends StatefulWidget {
  const FfmAssistantDraftEditDialog({
    super.key,
    required this.draft,
    required this.feedbackService,
  });

  final FfmAssistantDraft draft;
  final FfmAssistantDraftFeedbackService feedbackService;

  @override
  State<FfmAssistantDraftEditDialog> createState() =>
      _FfmAssistantDraftEditDialogState();
}

class _FfmAssistantDraftEditDialogState
    extends State<FfmAssistantDraftEditDialog> {
  late final TextEditingController _amountController;
  late final TextEditingController _titleController;
  late final TextEditingController _fromController;
  late final TextEditingController _toController;
  late final TextEditingController _categoryController;
  late final TextEditingController _goalController;
  late final TextEditingController _noteController;
  late final TextEditingController _incomeSourceController;
  late final TextEditingController _tagsController;
  late ActivityMode _activityMode;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.draft.amount?.toString() ?? '',
    );
    _titleController = TextEditingController(text: widget.draft.title ?? '');
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
    _incomeSourceController = TextEditingController(
      text: widget.draft.formValues['incomeSource'] ?? '',
    );
    _tagsController = TextEditingController(
      text: widget.draft.formValues['tags'] ?? '',
    );
    _activityMode =
        ActivityMode.tryParse(
          widget.draft.formValues['activityMode'] ??
              widget.draft.formValues['kind'],
        ) ??
        ActivityMode.timeTracking;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _titleController.dispose();
    _fromController.dispose();
    _toController.dispose();
    _categoryController.dispose();
    _goalController.dispose();
    _noteController.dispose();
    _incomeSourceController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  String? _textOrNull(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  void _save() {
    final amountText = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final amount = amountText.isEmpty ? null : int.tryParse(amountText);
    final goalName = _textOrNull(_goalController);
    final title = _isGoalContribution
        ? (widget.draft.kind == FfmAssistantDraftKind.goalDeposit
            ? 'Setor Target ${goalName ?? ''}'.trim()
            : 'Pakai Target ${goalName ?? ''}'.trim())
        : _textOrNull(_titleController);
    final editedDraft = FfmAssistantDraft(
      kind: widget.draft.kind,
      createdAt: widget.draft.createdAt,
      amount: amount,
      title: title,
      partyName: widget.draft.partyName,
      fromAccountName: _textOrNull(_fromController),
      toAccountName: _textOrNull(_toController),
      categoryName: _textOrNull(_categoryController),
      adminFee: widget.draft.adminFee,
      goalName: goalName,
      note: _textOrNull(_noteController),
      date: widget.draft.date,
      linkedActivityId: widget.draft.linkedActivityId,
      formValues: {
        ...widget.draft.formValues,
        if (widget.draft.kind == FfmAssistantDraftKind.activity)
          'activityMode': _activityMode.value,
        if (widget.draft.kind == FfmAssistantDraftKind.activity)
          'kind': _activityMode.activityKind.value,
        if (widget.draft.kind == FfmAssistantDraftKind.activity)
          'modeNeedsConfirmation': 'false',
        if (widget.draft.kind == FfmAssistantDraftKind.income)
          'incomeSource': _textOrNull(_incomeSourceController) ?? '',
        if (widget.draft.kind == FfmAssistantDraftKind.income ||
            widget.draft.kind == FfmAssistantDraftKind.expense)
          'tags': _textOrNull(_tagsController) ?? '',
      },
      merchantName: widget.draft.merchantName,
      slmFieldValues: widget.draft.slmFieldValues,
    );

    // Record the draft edit for LLM feedback
    widget.feedbackService.recordDraftEdit(
      originalDraft: widget.draft,
      editedDraft: editedDraft,
      timestamp: DateTime.now(),
    );

    Navigator.of(context).pop(editedDraft);
  }

  bool get _isTransaction => switch (widget.draft.kind) {
    FfmAssistantDraftKind.income ||
    FfmAssistantDraftKind.expense ||
    FfmAssistantDraftKind.transfer => true,
    _ => false,
  };

  bool get _isGoalContribution =>
      widget.draft.kind == FfmAssistantDraftKind.goalDeposit ||
      widget.draft.kind == FfmAssistantDraftKind.goalUsage;

  bool get _isActivityDraft =>
      widget.draft.kind == FfmAssistantDraftKind.activity ||
      widget.draft.kind == FfmAssistantDraftKind.activityEdit;

  bool get _showsAmount =>
      _isTransaction ||
      _isGoalContribution ||
      widget.draft.amount != null ||
      switch (widget.draft.kind) {
        FfmAssistantDraftKind.goal ||
        FfmAssistantDraftKind.budget ||
        FfmAssistantDraftKind.asset ||
        FfmAssistantDraftKind.liability ||
        FfmAssistantDraftKind.receivable => true,
        _ => false,
      };

  String _draftTypeLabel() => switch (widget.draft.kind) {
    FfmAssistantDraftKind.income => 'Pemasukan',
    FfmAssistantDraftKind.expense => 'Pengeluaran',
    FfmAssistantDraftKind.transfer => 'Transfer Dana',
    FfmAssistantDraftKind.goalDeposit => 'Setor Target',
    FfmAssistantDraftKind.goalUsage => 'Pakai Target',
    FfmAssistantDraftKind.goal => 'Target Keuangan',
    FfmAssistantDraftKind.masterData => 'Data Utama',
    FfmAssistantDraftKind.activity => 'Aktivitas',
    FfmAssistantDraftKind.activityEdit => 'Ubah Aktivitas',
    FfmAssistantDraftKind.budget => 'Anggaran',
    FfmAssistantDraftKind.asset => 'Aset',
    FfmAssistantDraftKind.liability => 'Hutang',
    FfmAssistantDraftKind.receivable => 'Piutang',
    _ => 'Draft',
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.draft.kind == FfmAssistantDraftKind.masterData
          ? 'Ubah Draft Data Utama'
          : widget.draft.kind == FfmAssistantDraftKind.goalDeposit
          ? 'Ubah Draft Setor Target'
          : widget.draft.kind == FfmAssistantDraftKind.goalUsage
          ? 'Ubah Draft Pakai Target'
          : widget.draft.kind == FfmAssistantDraftKind.goal
          ? 'Ubah Draft Target Keuangan'
          : 'Ubah draft di chat',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.secondaryContainer.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Jenis draft: ${_draftTypeLabel()}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
                fontSize: 12,
              ),
            ),
          ),
          if (!_isTransaction && !_isGoalContribution) ...[
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: widget.draft.kind == FfmAssistantDraftKind.masterData
                    ? 'Nama ${widget.draft.categoryName ?? 'data'}'
                    : widget.draft.kind == FfmAssistantDraftKind.goal
                    ? 'Nama target'
                    : 'Nama/Judul',
                hintText: widget.draft.kind == FfmAssistantDraftKind.goal
                    ? 'Contoh: Dana Darurat, Liburan'
                    : null,
              ),
            ),
            if (widget.draft.kind == FfmAssistantDraftKind.masterData)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: const Icon(Icons.dataset_outlined, size: 18),
                    label: Text(
                      'Data Utama: ${widget.draft.categoryName ?? '-'}',
                    ),
                  ),
                ),
              ),
          ],
          if (widget.draft.kind == FfmAssistantDraftKind.goalDeposit ||
              widget.draft.kind == FfmAssistantDraftKind.goalUsage)
            TextField(
              controller: _goalController,
              decoration: const InputDecoration(
                labelText: 'Target keuangan',
                hintText: 'Contoh: Dana Darurat, Liburan',
              ),
            ),
          if (_showsAmount)
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: widget.draft.kind == FfmAssistantDraftKind.goalDeposit
                    ? 'Nominal setor (Rp)'
                    : widget.draft.kind == FfmAssistantDraftKind.goalUsage
                    ? 'Nominal pakai (Rp)'
                    : widget.draft.kind == FfmAssistantDraftKind.goal
                    ? 'Target nominal (Rp)'
                    : 'Nominal (Rp)',
                hintText: 'Contoh: 500000',
              ),
            ),
          if (widget.draft.kind == FfmAssistantDraftKind.expense ||
              widget.draft.kind == FfmAssistantDraftKind.transfer ||
              widget.draft.kind == FfmAssistantDraftKind.goalDeposit)
            TextField(
              controller: _fromController,
              decoration: InputDecoration(
                labelText: widget.draft.kind == FfmAssistantDraftKind.goalDeposit
                    ? 'Rekening sumber dana (opsional)'
                    : 'Rekening asal',
                hintText: 'Contoh: BCA, Tunai, ShopeePay',
              ),
            ),
          if (widget.draft.kind == FfmAssistantDraftKind.income ||
              widget.draft.kind == FfmAssistantDraftKind.transfer ||
              widget.draft.kind == FfmAssistantDraftKind.goalUsage)
            TextField(
              controller: _toController,
              decoration: InputDecoration(
                labelText: widget.draft.kind == FfmAssistantDraftKind.goalUsage
                    ? 'Rekening tujuan dana (opsional)'
                    : 'Rekening tujuan',
                hintText: 'Contoh: BCA, Tunai, ShopeePay',
              ),
            ),
          if (widget.draft.kind == FfmAssistantDraftKind.activity) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<ActivityMode>(
              initialValue: _activityMode,
              decoration: const InputDecoration(labelText: 'Mode aktivitas'),
              items: ActivityMode.values
                  .map(
                    (mode) =>
                        DropdownMenuItem(value: mode, child: Text(mode.label)),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) setState(() => _activityMode = value);
              },
            ),
          ],
          if (widget.draft.kind == FfmAssistantDraftKind.income ||
              widget.draft.kind == FfmAssistantDraftKind.expense ||
              widget.draft.kind == FfmAssistantDraftKind.budget ||
              _isActivityDraft)
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(
                labelText: 'Kategori',
                hintText: 'Contoh: Makanan, Transportasi',
              ),
            ),
          if (widget.draft.kind == FfmAssistantDraftKind.income)
            TextField(
              controller: _incomeSourceController,
              decoration: const InputDecoration(
                labelText: 'Sumber pemasukan (gaji, usaha, dll)',
                hintText: 'Contoh: Gaji bulanan, Usaha toko, dll',
              ),
            ),
          if (widget.draft.kind == FfmAssistantDraftKind.income ||
              widget.draft.kind == FfmAssistantDraftKind.expense)
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: 'Tags (opsional)',
                hintText: 'Contoh: penting, rutin, dll',
              ),
            ),
          TextField(
            controller: _noteController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Catatan',
              hintText: 'Tambahan keterangan ringkas',
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
      FilledButton(onPressed: _save, child: const Text('Pakai perubahan')),
    ],
  );
}
