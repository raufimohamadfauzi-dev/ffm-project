import 'package:flutter/material.dart';

import '../../domain/ffm_assistant_models.dart';
import '../../data/ffm_assistant_draft_feedback_service.dart';
import '../../../activity/domain/entities/activity_entity.dart';
import '../../../transaction/data/services/receipt_import_models.dart';

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
  late final TextEditingController _receiptNumberController;
  late final TextEditingController _receiptPaidAmountController;
  late final TextEditingController _receiptChangeAmountController;
  late final TextEditingController _taxController;
  late final TextEditingController _discountController;
  late List<ReceiptOcrItem> _items;
  late String _budgetPeriod;
  late final List<String> _tags;
  late String? _fromAccount;
  late String? _toAccount;
  late DateTime? _date;
  late TimeOfDay? _time; // only used for reminder drafts
  late ActivityMode _activityMode;
  late FfmAssistantDraftKind _selectedKind;

  @override
  void initState() {
    super.initState();
    _selectedKind = widget.draft.kind;
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
    // For reminder drafts, preserve the time-of-day separately so changing
    // date doesn't reset the time and vice-versa.
    _time = widget.draft.kind == FfmAssistantDraftKind.reminder && widget.draft.date != null
        ? TimeOfDay.fromDateTime(widget.draft.date!)
        : null;
    _activityMode =
        ActivityMode.tryParse(
          widget.draft.formValues['activityMode'] ??
              widget.draft.formValues['kind'],
        ) ??
        ActivityMode.timeTracking;

    _items = List<ReceiptOcrItem>.from(widget.draft.items);
    _receiptNumberController = TextEditingController(
      text: widget.draft.receiptNumber ??
          widget.draft.formValues['receiptNumber'] ??
          widget.draft.formValues['receipt_number'] ??
          '',
    );
    _receiptPaidAmountController = TextEditingController(
      text: widget.draft.receiptPaidAmount?.toString() ??
          widget.draft.formValues['receiptPaidAmount'] ??
          widget.draft.formValues['paid_amount'] ??
          '',
    );
    _receiptChangeAmountController = TextEditingController(
      text: widget.draft.receiptChangeAmount?.toString() ??
          widget.draft.formValues['receiptChangeAmount'] ??
          widget.draft.formValues['change_amount'] ??
          '',
    );
    _taxController = TextEditingController(
      text: widget.draft.tax?.toString() ??
          widget.draft.formValues['tax'] ??
          widget.draft.formValues['pajak'] ??
          '',
    );
    _discountController = TextEditingController(
      text: widget.draft.discount?.toString() ??
          widget.draft.formValues['discount'] ??
          widget.draft.formValues['diskon'] ??
          '',
    );
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
    _receiptNumberController.dispose();
    _receiptPaidAmountController.dispose();
    _receiptChangeAmountController.dispose();
    _taxController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  void _recalculateAmountFromItems() {
    if (_items.isEmpty) return;
    final subtotal = _items.fold<int>(0, (sum, i) => sum + i.calculatedTotal);
    final taxText = _taxController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final tax = taxText.isEmpty ? 0 : (int.tryParse(taxText) ?? 0);
    final discountText = _discountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final discount = discountText.isEmpty ? 0 : (int.tryParse(discountText) ?? 0);
    final total = subtotal + tax - discount;
    if (total > 0) {
      _amountController.text = total.toString();
    }
  }

  void _addItem() {
    setState(() {
      _items.add(const ReceiptOcrItem(name: '', price: 0, quantity: 1));
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _recalculateAmountFromItems();
    });
  }

  void _updateItem(int index, ReceiptOcrItem updated) {
    setState(() {
      _items[index] = updated;
      _recalculateAmountFromItems();
    });
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
    final rawAmountText = _amountController.text.trim();
    if (rawAmountText.contains('-')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nominal tidak boleh negatif.')),
      );
      return;
    }
    final amountText = rawAmountText.replaceAll(RegExp(r'[^0-9]'), '');
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
    final isIncome = _selectedKind == FfmAssistantDraftKind.income;
    final isExpense = _selectedKind == FfmAssistantDraftKind.expense;
    final fromAcc = isIncome
        ? null
        : (_fromAccount?.trim().isNotEmpty == true
            ? _fromAccount!.trim()
            : _toAccount?.trim());
    final toAcc = isExpense
        ? null
        : (_toAccount?.trim().isNotEmpty == true
            ? _toAccount!.trim()
            : _fromAccount?.trim());

    final receiptNumber = _textOrNull(_receiptNumberController);
    final receiptPaidAmountText = _receiptPaidAmountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final receiptPaidAmount = receiptPaidAmountText.isEmpty ? null : int.tryParse(receiptPaidAmountText);
    final receiptChangeAmountText = _receiptChangeAmountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final receiptChangeAmount = receiptChangeAmountText.isEmpty ? null : int.tryParse(receiptChangeAmountText);
    final taxText = _taxController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final tax = taxText.isEmpty ? null : int.tryParse(taxText);
    final discountText = _discountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final discount = discountText.isEmpty ? null : int.tryParse(discountText);

    final validItems = _items.where((i) => i.name.trim().isNotEmpty).toList(growable: false);

    final newFormValues = Map<String, String>.from(widget.draft.formValues);
    if (_selectedKind == FfmAssistantDraftKind.budget) {
      newFormValues['periodType'] = _budgetPeriod;
    }
    if (_isDebtOrReceivable) {
      if (partyName != null) {
        newFormValues['partyName'] = partyName;
      } else {
        newFormValues.remove('partyName');
      }
      if (monthlyInstallment.isNotEmpty) {
        newFormValues['monthlyInstallment'] = monthlyInstallment;
      }
      if (_date != null) {
        newFormValues['dueDate'] = _date!.toIso8601String();
      }
    }
    if (_selectedKind == FfmAssistantDraftKind.goal && _date != null) {
      newFormValues['targetDate'] = _date!.toIso8601String();
    }
    if (_selectedKind == FfmAssistantDraftKind.activity) {
      newFormValues['activityMode'] = _activityMode.value;
      newFormValues['kind'] = _activityMode.activityKind.value;
      newFormValues['modeNeedsConfirmation'] = 'false';
    }
    if (_selectedKind == FfmAssistantDraftKind.income) {
      if (partyName != null) {
        newFormValues['incomeSource'] = partyName;
      } else {
        newFormValues.remove('incomeSource');
      }
    }
    if (_selectedKind == FfmAssistantDraftKind.income ||
        _selectedKind == FfmAssistantDraftKind.expense) {
      if (_tags.isNotEmpty) {
        newFormValues['tags'] = _tags.join(', ');
      } else {
        newFormValues.remove('tags');
      }
    }
    if (_isTransaction) {
      if (merchantName != null) {
        newFormValues['merchant'] = merchantName;
      } else {
        newFormValues.remove('merchant');
      }
      if (location != null) {
        newFormValues['location'] = location;
      } else {
        newFormValues.remove('location');
      }
      if (partyName != null) {
        newFormValues['party'] = partyName;
      } else {
        newFormValues.remove('party');
      }
    }
    if (receiptNumber != null && receiptNumber.isNotEmpty) {
      newFormValues['receiptNumber'] = receiptNumber;
    } else {
      newFormValues.remove('receiptNumber');
    }
    if (receiptPaidAmount != null) {
      newFormValues['receiptPaidAmount'] = receiptPaidAmount.toString();
    } else {
      newFormValues.remove('receiptPaidAmount');
    }
    if (receiptChangeAmount != null) {
      newFormValues['receiptChangeAmount'] = receiptChangeAmount.toString();
    } else {
      newFormValues.remove('receiptChangeAmount');
    }
    if (tax != null) {
      newFormValues['tax'] = tax.toString();
    } else {
      newFormValues.remove('tax');
    }
    if (discount != null) {
      newFormValues['discount'] = discount.toString();
    } else {
      newFormValues.remove('discount');
    }

    // For reminder drafts, combine the chosen date and time-of-day.
    DateTime? effectiveDate = _date ?? widget.draft.date;
    if (_selectedKind == FfmAssistantDraftKind.reminder &&
        effectiveDate != null &&
        _time != null) {
      effectiveDate = DateTime(
        effectiveDate.year,
        effectiveDate.month,
        effectiveDate.day,
        _time!.hour,
        _time!.minute,
      );
    }

    final editedDraft = FfmAssistantDraft(
      kind: _selectedKind,
      createdAt: widget.draft.createdAt,
      amount: amount,
      title: title,
      partyName: partyName,
      fromAccountName: fromAcc,
      toAccountName: toAcc,
      categoryName: _textOrNull(_categoryController),
      adminFee: _selectedKind == FfmAssistantDraftKind.transfer
          ? adminFee
          : widget.draft.adminFee,
      goalName: goalName,
      note: _textOrNull(_noteController),
      date: effectiveDate,
      linkedActivityId: widget.draft.linkedActivityId,
      items: validItems,
      receiptNumber: receiptNumber,
      receiptPaidAmount: receiptPaidAmount,
      receiptChangeAmount: receiptChangeAmount,
      tax: tax,
      discount: discount,
      formValues: newFormValues,
      merchantName: merchantName,
      location: location,
      slmFieldValues: widget.draft.slmFieldValues,
      // Preserve cycle-specific metadata that is not edited in this dialog
      metadata: widget.draft.metadata,
      commodityOrBusinessType: widget.draft.commodityOrBusinessType,
      targetHarvestDate: widget.draft.targetHarvestDate,
      initialCapital: widget.draft.initialCapital,
      estimatedInflow: widget.draft.estimatedInflow,
      dailyLivingBudget: widget.draft.dailyLivingBudget,
      dailyOperationalBudget: widget.draft.dailyOperationalBudget,
      cycleProfileType: widget.draft.cycleProfileType,
    );

    // Record the draft edit for LLM feedback
    widget.feedbackService.recordDraftEdit(
      originalDraft: widget.draft,
      editedDraft: editedDraft,
      timestamp: DateTime.now(),
    );

    Navigator.of(context).pop(editedDraft);
  }

  bool get _isTransaction => switch (_selectedKind) {
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

  String _draftTypeLabel() => switch (_selectedKind) {
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
      _selectedKind == FfmAssistantDraftKind.masterData
          ? 'Ubah Draft Data Utama'
          : _selectedKind == FfmAssistantDraftKind.goalDeposit
          ? 'Ubah Draft Setor Target'
          : _selectedKind == FfmAssistantDraftKind.goalUsage
          ? 'Ubah Draft Pakai Target'
          : _selectedKind == FfmAssistantDraftKind.goal
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Jenis draft: ${_draftTypeLabel()}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                    fontSize: 12,
                  ),
                ),
                if (widget.draft.kind == FfmAssistantDraftKind.expense ||
                    widget.draft.kind == FfmAssistantDraftKind.income) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<FfmAssistantDraftKind>(
                      segments: const [
                        ButtonSegment(
                          value: FfmAssistantDraftKind.expense,
                          label: Text('Pengeluaran'),
                          icon: Icon(Icons.arrow_upward, size: 16),
                        ),
                        ButtonSegment(
                          value: FfmAssistantDraftKind.income,
                          label: Text('Pemasukan'),
                          icon: Icon(Icons.arrow_downward, size: 16),
                        ),
                      ],
                      selected: {_selectedKind},
                      onSelectionChanged: (newSelection) {
                        setState(() {
                          _selectedKind = newSelection.first;
                          if (_selectedKind == FfmAssistantDraftKind.income &&
                              _toAccount == null) {
                            _toAccount = _fromAccount;
                          } else if (_selectedKind ==
                                  FfmAssistantDraftKind.expense &&
                              _fromAccount == null) {
                            _fromAccount = _toAccount;
                          }
                        });
                      },
                    ),
                  ),
                ],
              ],
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
          if (_selectedKind == FfmAssistantDraftKind.expense ||
              _selectedKind == FfmAssistantDraftKind.transfer ||
              _selectedKind == FfmAssistantDraftKind.goalDeposit ||
              _selectedKind == FfmAssistantDraftKind.liabilityPayment)
            _accountField(
              initial: _fromAccount,
              onChanged: (value) => setState(() => _fromAccount = value),
              label:
                  _selectedKind == FfmAssistantDraftKind.goalDeposit
                  ? 'Rekening sumber dana'
                  : _selectedKind == FfmAssistantDraftKind.liabilityPayment
                  ? 'Rekening sumber bayar'
                  : 'Rekening asal',
              hint: 'Pilih rekening yang terdaftar, atau Belum terlacak',
            ),
          if (_selectedKind == FfmAssistantDraftKind.income ||
              _selectedKind == FfmAssistantDraftKind.transfer ||
              _selectedKind == FfmAssistantDraftKind.goalUsage ||
              _selectedKind == FfmAssistantDraftKind.receivablePayment)
            _accountField(
              initial: _toAccount,
              onChanged: (value) => setState(() => _toAccount = value),
              label:
                  _selectedKind == FfmAssistantDraftKind.goalUsage
                  ? 'Rekening tujuan dana'
                  : _selectedKind == FfmAssistantDraftKind.receivablePayment
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
                    ? 'Tanggal pengingat'
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
          // Reminder-only: dedicated time picker so changing the date doesn't
          // reset the hour/minute and the full scheduledAt is visible.
          if (widget.draft.kind == FfmAssistantDraftKind.reminder)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time_outlined),
              title: const Text('Jam pengingat'),
              subtitle: Text(
                _time == null
                    ? 'Belum diisi (akan pakai 00:00)'
                    : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')} WIB',
              ),
              trailing: TextButton(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _time ?? TimeOfDay.now(),
                    helpText: 'Pilih jam pengingat',
                  );
                  if (picked != null && mounted) {
                    setState(() => _time = picked);
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
          if (_selectedKind == FfmAssistantDraftKind.income)
            TextField(
              controller: _partyController,
              decoration: const InputDecoration(
                labelText: 'Sumber pemasukan',
                hintText: 'Contoh: Gaji, Usaha',
              ),
            ),
          if (_selectedKind == FfmAssistantDraftKind.expense)
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
          if (_isTransaction) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Rincian Item Belanja (${_items.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addItem,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Tambah Item'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                  if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'Belum ada item belanja terinci. Tambahkan jika ingin mencatat struk secara mendetail.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  else ...[
                    const SizedBox(height: 4),
                    ..._items.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final item = entry.value;
                      return _DraftReceiptItemRow(
                        key: ValueKey('receipt_item_$idx'),
                        item: item,
                        index: idx,
                        onChanged: (updated) => _updateItem(idx, updated),
                        onDeleted: () => _removeItem(idx),
                      );
                    }),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text(
                  'Detail Nota / Struk (Opsional)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                children: [
                  TextField(
                    controller: _receiptNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Nomor Struk / Faktur',
                      hintText: 'Contoh: INV-20240901',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _taxController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Pajak / PPN (Rp)',
                            hintText: '0',
                          ),
                          onChanged: (_) => _recalculateAmountFromItems(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _discountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Diskon (Rp)',
                            hintText: '0',
                          ),
                          onChanged: (_) => _recalculateAmountFromItems(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _receiptPaidAmountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Uang Dibayar (Rp)',
                            hintText: 'Contoh: 100000',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _receiptChangeAmountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Kembalian (Rp)',
                            hintText: 'Contoh: 15000',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
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

class _DraftReceiptItemRow extends StatelessWidget {
  const _DraftReceiptItemRow({
    super.key,
    required this.item,
    required this.index,
    required this.onChanged,
    required this.onDeleted,
  });

  final ReceiptOcrItem item;
  final int index;
  final ValueChanged<ReceiptOcrItem> onChanged;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: item.name,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Nama Barang',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) => onChanged(item.copyWith(name: val)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                tooltip: 'Hapus Item',
                onPressed: onDeleted,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: item.quantity == 1 ? '1' : item.quantity.toString(),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Qty',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    final qty = double.tryParse(val.replaceAll(',', '.')) ?? 1.0;
                    onChanged(item.copyWith(quantity: qty));
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: TextFormField(
                  initialValue: item.price.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Harga (Rp)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    final p = int.tryParse(val.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                    onChanged(item.copyWith(price: p));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Rp${item.calculatedTotal}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
