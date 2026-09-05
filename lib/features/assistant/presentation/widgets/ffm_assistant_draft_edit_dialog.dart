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
    this.accounts = const [],
  });

  final FfmAssistantDraft draft;
  final FfmAssistantDraftFeedbackService feedbackService;

  /// Daftar nama rekening aktif (Data Utama) untuk dropdown sumber/tujuan.
  final List<String> accounts;

  @override
  State<FfmAssistantDraftEditDialog> createState() =>
      _FfmAssistantDraftEditDialogState();
}

class _FfmAssistantDraftEditDialogState
    extends State<FfmAssistantDraftEditDialog> {
  late final TextEditingController _amountController;
  late final TextEditingController _titleController;
  late final TextEditingController _categoryController;
  late final TextEditingController _goalController;
  late final TextEditingController _noteController;
  late final TextEditingController _merchantController;
  late final TextEditingController _locationController;
  late final TextEditingController _partyController;
  late final TextEditingController _adminFeeController;
  late final TextEditingController _tagsController;
  late final TextEditingController _monthlyInstallmentController;
  late String _budgetPeriod;
  late final List<String> _tags;
  late String? _fromAccount;
  late String? _toAccount;
  late DateTime? _date;
  late ActivityMode _activityMode;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.draft.amount?.toString() ?? '',
    );
    _titleController = TextEditingController(text: widget.draft.title ?? '');
    _categoryController = TextEditingController(
      text: widget.draft.categoryName ?? '',
    );
    _goalController = TextEditingController(text: widget.draft.goalName ?? '');
    _noteController = TextEditingController(text: widget.draft.note ?? '');
    _merchantController = TextEditingController(
      text:
          widget.draft.merchantName ??
          widget.draft.formValues['merchant'] ??
          widget.draft.formValues['merchantName'] ??
          '',
    );
    _locationController = TextEditingController(
      text:
          widget.draft.location ??
          widget.draft.formValues['location'] ??
          '',
    );
    _partyController = TextEditingController(
      text:
          widget.draft.partyName ??
          widget.draft.formValues['incomeSource'] ??
          widget.draft.formValues['party'] ??
          widget.draft.formValues['partyName'] ??
          widget.draft.formValues['lender'] ??
          widget.draft.formValues['borrower'] ??
          '',
    );
    _adminFeeController = TextEditingController(
      text:
          widget.draft.adminFee?.toString() ??
          widget.draft.formValues['adminFee'] ??
          '',
    );
    _monthlyInstallmentController = TextEditingController(
      text:
          widget.draft.formValues['monthlyInstallment'] ??
          widget.draft.formValues['cicilan'] ??
          '',
    );
    _budgetPeriod = widget.draft.formValues['periodType'] ?? 'monthly';
    _tagsController = TextEditingController(
      text: widget.draft.formValues['tags'] ?? '',
    );
    _tags = _csvValues(_tagsController);
    _fromAccount = widget.draft.fromAccountName?.trim();
    _toAccount = widget.draft.toAccountName?.trim();
    _date = widget.draft.date;
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
    _categoryController.dispose();
    _goalController.dispose();
    _noteController.dispose();
    _merchantController.dispose();
    _locationController.dispose();
    _partyController.dispose();
    _adminFeeController.dispose();
    _monthlyInstallmentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  String? _textOrNull(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  List<String> _csvValues(TextEditingController controller) {
    return controller.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  void _syncTagsText() {
    _tagsController.text = _tags.join(', ');
  }

  void _addTag(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return;
    final normalized = value.toLowerCase();
    if (_tags.any((item) => item.toLowerCase() == normalized)) return;
    setState(() {
      _tags.add(value);
      _syncTagsText();
    });
  }

  void _removeTag(String value) {
    setState(() {
      _tags.removeWhere((item) => item.toLowerCase() == value.toLowerCase());
      _syncTagsText();
    });
  }

  void _save() {
    final amountText = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final amount = amountText.isEmpty ? null : int.tryParse(amountText);
    final adminFeeText = _adminFeeController.text.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final adminFee = adminFeeText.isEmpty
        ? widget.draft.adminFee
        : int.tryParse(adminFeeText);
    final goalName = _textOrNull(_goalController);
    final title = _isGoalContribution
        ? (widget.draft.kind == FfmAssistantDraftKind.goalDeposit
            ? 'Setor Target ${goalName ?? ''}'.trim()
            : 'Pakai Target ${goalName ?? ''}'.trim())
        : _textOrNull(_titleController);
    final merchantName = _isTransaction
        ? _textOrNull(_merchantController)
        : widget.draft.merchantName;
    final location = _isTransaction
        ? _textOrNull(_locationController)
        : widget.draft.location;
    final monthlyInstallment = _monthlyInstallmentController.text.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    // Kolom pihak tunggal untuk transaksi maupun hutang/piutang (partyName)
    // agar sinkron dengan database transactions, liabilities, dan receivables.
    final partyName = (_isTransaction || _isDebtOrReceivable)
        ? _textOrNull(_partyController)
        : widget.draft.partyName;
    final editedDraft = FfmAssistantDraft(
      kind: widget.draft.kind,
      createdAt: widget.draft.createdAt,
      amount: amount,
      title: title,
      partyName: partyName,
      fromAccountName:
          _fromAccount?.trim().isNotEmpty == true ? _fromAccount!.trim() : null,
      toAccountName:
          _toAccount?.trim().isNotEmpty == true ? _toAccount!.trim() : null,
      categoryName: _textOrNull(_categoryController),
      adminFee: widget.draft.kind == FfmAssistantDraftKind.transfer
          ? adminFee
          : widget.draft.adminFee,
      goalName: goalName,
      note: _textOrNull(_noteController),
      date: _date ?? widget.draft.date,
      linkedActivityId: widget.draft.linkedActivityId,
      formValues: {
        ...widget.draft.formValues,
        if (widget.draft.kind == FfmAssistantDraftKind.budget)
          'periodType': _budgetPeriod,
        if (_isDebtOrReceivable && partyName != null) 'partyName': partyName,
        if (_isDebtOrReceivable && monthlyInstallment.isNotEmpty)
          'monthlyInstallment': monthlyInstallment,
        if (_isDebtOrReceivable && _date != null)
          'dueDate': _date!.toIso8601String(),
        if (widget.draft.kind == FfmAssistantDraftKind.goal && _date != null)
          'targetDate': _date!.toIso8601String(),
        if (widget.draft.kind == FfmAssistantDraftKind.activity)
          'activityMode': _activityMode.value,
        if (widget.draft.kind == FfmAssistantDraftKind.activity)
          'kind': _activityMode.activityKind.value,
        if (widget.draft.kind == FfmAssistantDraftKind.activity)
          'modeNeedsConfirmation': 'false',
        if (widget.draft.kind == FfmAssistantDraftKind.income &&
            partyName != null)
          'incomeSource': partyName,
        if (widget.draft.kind == FfmAssistantDraftKind.income ||
            widget.draft.kind == FfmAssistantDraftKind.expense)
          'tags': _tags.join(', '),
        if (_isTransaction && merchantName != null) 'merchant': merchantName,
        if (_isTransaction && location != null) 'location': location,
        if (_isTransaction && partyName != null) 'party': partyName,
      },
      merchantName: merchantName ?? widget.draft.merchantName,
      location: location ?? widget.draft.location,
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

  bool get _isDebtOrReceivable => switch (widget.draft.kind) {
    FfmAssistantDraftKind.liability ||
    FfmAssistantDraftKind.liabilityPayment ||
    FfmAssistantDraftKind.receivable ||
    FfmAssistantDraftKind.receivablePayment => true,
    _ => false,
  };

  bool get _showsDate =>
      _isTransaction ||
      _isDebtOrReceivable ||
      widget.draft.kind == FfmAssistantDraftKind.goal ||
      widget.draft.kind == FfmAssistantDraftKind.reminder ||
      _isActivityDraft;

  bool get _isGoalContribution =>
      widget.draft.kind == FfmAssistantDraftKind.goalDeposit ||
      widget.draft.kind == FfmAssistantDraftKind.goalUsage;

  bool get _isActivityDraft =>
      widget.draft.kind == FfmAssistantDraftKind.activity ||
      widget.draft.kind == FfmAssistantDraftKind.activityEdit;

  /// Menyusun daftar opsi rekening untuk dropdown. Nilai draft yang belum ada
  /// di Data Utama tetap disertakan supaya tidak hilang saat koreksi.
  List<String> _accountOptions(String? current, List<String> source) {
    final result = <String>[];
    for (final name in source) {
      if (!result.contains(name)) result.add(name);
    }
    if (current != null &&
        current.trim().isNotEmpty &&
        !result.contains(current)) {
      result.add(current);
    }
    return result;
  }

  Widget _accountField({
    required String? initial,
    required ValueChanged<String?> onChanged,
    required String label,
    required String hint,
  }) {
    final options = _accountOptions(initial, widget.accounts);
    return DropdownButtonFormField<String?>(
      initialValue: initial?.trim().isNotEmpty == true ? initial!.trim() : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Belum terlacak'),
        ),
        ...options.map(
          (name) => DropdownMenuItem<String?>(value: name, child: Text(name)),
        ),
      ],
      onChanged: (value) => onChanged(value),
    );
  }

  bool get _showsAmount =>
      _isTransaction ||
      _isGoalContribution ||
      widget.draft.amount != null ||
      switch (widget.draft.kind) {
        FfmAssistantDraftKind.goal ||
        FfmAssistantDraftKind.budget ||
        FfmAssistantDraftKind.asset ||
        FfmAssistantDraftKind.liability ||
        FfmAssistantDraftKind.liabilityPayment ||
        FfmAssistantDraftKind.receivable ||
        FfmAssistantDraftKind.receivablePayment => true,
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
    FfmAssistantDraftKind.liabilityPayment => 'Pembayaran Hutang',
    FfmAssistantDraftKind.receivable => 'Piutang',
    FfmAssistantDraftKind.receivablePayment => 'Penerimaan Piutang',
    FfmAssistantDraftKind.reminder => 'Pengingat / Alarm',
    FfmAssistantDraftKind.cashFlowProfile => 'Profil Arus Kas / Siklus Tani',
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
              widget.draft.kind == FfmAssistantDraftKind.goalDeposit ||
              widget.draft.kind == FfmAssistantDraftKind.liabilityPayment)
            _accountField(
              initial: _fromAccount,
              onChanged: (value) => setState(() => _fromAccount = value),
              label:
                  widget.draft.kind == FfmAssistantDraftKind.goalDeposit
                  ? 'Rekening sumber dana'
                  : widget.draft.kind == FfmAssistantDraftKind.liabilityPayment
                  ? 'Rekening sumber bayar'
                  : 'Rekening asal',
              hint: 'Pilih rekening yang terdaftar, atau Belum terlacak',
            ),
          if (widget.draft.kind == FfmAssistantDraftKind.income ||
              widget.draft.kind == FfmAssistantDraftKind.transfer ||
              widget.draft.kind == FfmAssistantDraftKind.goalUsage ||
              widget.draft.kind == FfmAssistantDraftKind.receivablePayment)
            _accountField(
              initial: _toAccount,
              onChanged: (value) => setState(() => _toAccount = value),
              label:
                  widget.draft.kind == FfmAssistantDraftKind.goalUsage
                  ? 'Rekening tujuan dana'
                  : widget.draft.kind == FfmAssistantDraftKind.receivablePayment
                  ? 'Rekening tujuan terima'
                  : 'Rekening tujuan',
              hint: 'Pilih rekening yang terdaftar, atau Belum terlacak',
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
          // Kolom transaksi disamakan dengan form resmi + database:
          // merchant, lokasi, tanggal, pihak, biaya admin (transfer).
          if (widget.draft.kind == FfmAssistantDraftKind.income ||
              widget.draft.kind == FfmAssistantDraftKind.expense)
            TextField(
              controller: _merchantController,
              decoration: const InputDecoration(
                labelText: 'Toko / tempat (opsional)',
                hintText: 'Contoh: Indomaret, Pasar',
              ),
            ),
          if (widget.draft.kind == FfmAssistantDraftKind.income ||
              widget.draft.kind == FfmAssistantDraftKind.expense)
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Lokasi (opsional)',
                hintText: 'Misalnya pasar, rumah, atau kantor',
              ),
            ),
          if (_showsDate)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(
                _isTransaction
                    ? 'Tanggal kejadian'
                    : _isDebtOrReceivable
                    ? 'Tanggal jatuh tempo'
                    : widget.draft.kind == FfmAssistantDraftKind.goal
                    ? 'Target tanggal tercapai'
                    : widget.draft.kind == FfmAssistantDraftKind.reminder
                    ? 'Waktu pengingat'
                    : 'Tanggal aktivitas',
              ),
              subtitle: Text(
                _date == null
                    ? 'Belum diisi'
                    : '${_date!.day.toString().padLeft(2, '0')}/${_date!.month.toString().padLeft(2, '0')}/${_date!.year}',
              ),
              trailing: TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    initialDate: _date ?? DateTime.now(),
                    helpText: _isDebtOrReceivable
                        ? 'Pilih tanggal jatuh tempo'
                        : widget.draft.kind == FfmAssistantDraftKind.goal
                        ? 'Pilih target tanggal tercapai'
                        : widget.draft.kind == FfmAssistantDraftKind.reminder
                        ? 'Pilih tanggal pengingat'
                        : 'Pilih tanggal transaksi',
                  );
                  if (picked != null && mounted) {
                    setState(() => _date = picked);
                  }
                },
                child: const Text('Ganti'),
              ),
            ),
          if (widget.draft.kind == FfmAssistantDraftKind.budget) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _budgetPeriod,
              decoration: const InputDecoration(labelText: 'Periode anggaran'),
              items: const [
                DropdownMenuItem(value: 'monthly', child: Text('Bulanan')),
                DropdownMenuItem(value: 'weekly', child: Text('Mingguan')),
                DropdownMenuItem(value: 'biweekly', child: Text('Per Dua Minggu')),
                DropdownMenuItem(value: 'nonrecurring', child: Text('Tidak Rutin')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _budgetPeriod = value);
              },
            ),
          ],
          if (widget.draft.kind == FfmAssistantDraftKind.transfer)
            TextField(
              controller: _adminFeeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Biaya admin (opsional, Rp)',
                hintText: 'Contoh: 2500',
                helperText:
                    'Dipisahkan sebagai pengeluaran dari rekening asal.',
              ),
            ),
          if (widget.draft.kind == FfmAssistantDraftKind.income)
            TextField(
              controller: _partyController,
              decoration: const InputDecoration(
                labelText: 'Sumber pemasukan',
                hintText: 'Contoh: Gaji, Usaha',
              ),
            ),
          if (widget.draft.kind == FfmAssistantDraftKind.expense)
            TextField(
              controller: _partyController,
              decoration: const InputDecoration(
                labelText: 'Dipakai oleh (opsional)',
                hintText: 'Contoh: Ayah, Ibu',
              ),
            ),
          if (widget.draft.kind == FfmAssistantDraftKind.liability)
            TextField(
              controller: _partyController,
              decoration: const InputDecoration(
                labelText: 'Pemberi pinjaman / nama pihak',
                hintText: 'Contoh: Bank Mandiri, Teman, Keluarga',
              ),
            ),
          if (widget.draft.kind == FfmAssistantDraftKind.receivable)
            TextField(
              controller: _partyController,
              decoration: const InputDecoration(
                labelText: 'Peminjam / nama pihak',
                hintText: 'Contoh: Budi, Saudara, Karyawan',
              ),
            ),
          if (widget.draft.kind == FfmAssistantDraftKind.liability ||
              widget.draft.kind == FfmAssistantDraftKind.receivable)
            TextField(
              controller: _monthlyInstallmentController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cicilan per bulan (opsional, Rp)',
                hintText: 'Contoh: 500000',
              ),
            ),
          if (widget.draft.kind == FfmAssistantDraftKind.income ||
              widget.draft.kind == FfmAssistantDraftKind.expense)
            _MultiValueEditor(
              label: 'Tags (opsional)',
              hint: 'Tambah tag',
              values: _tags,
              onAdd: _addTag,
              onRemove: _removeTag,
              controller: _tagsController,
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

class _MultiValueEditor extends StatelessWidget {
  const _MultiValueEditor({
    required this.label,
    required this.hint,
    required this.values,
    required this.onAdd,
    required this.onRemove,
    required this.controller,
  });

  final String label;
  final String hint;
  final List<String> values;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            suffixIcon: IconButton(
              onPressed: () {
                onAdd(controller.text);
                controller.clear();
              },
              icon: const Icon(Icons.add_circle_outline),
            ),
          ),
          onSubmitted: (value) {
            onAdd(value);
            controller.clear();
          },
        ),
        if (values.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: values
                .map(
                  (value) => Chip(
                    label: Text(value),
                    onDeleted: () => onRemove(value),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }
}
