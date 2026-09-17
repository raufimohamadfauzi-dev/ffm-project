import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../../activity/domain/entities/activity_entity.dart';
import '../../../reminder/data/services/reminder_sound_picker.dart';
import '../../../reminder/domain/entities/reminder_entity.dart';
import '../../../transaction/data/services/receipt_import_models.dart';
import '../../data/ffm_assistant_draft_feedback_service.dart';
import '../../domain/ffm_assistant_draft_validator.dart';
import '../../domain/ffm_assistant_models.dart';

/// Dialog mandiri untuk memperbaiki draft yang masih berada di sesi chat.
/// Tidak menyimpan data; caller wajib memvalidasi lalu meneruskan ke form.
/// Sekarang juga mencatat perubahan untuk feedback ke LLM.
class FfmAssistantDraftEditDialog extends StatefulWidget {
  const FfmAssistantDraftEditDialog({
    super.key,
    required this.draft,
    required this.feedbackService,
    this.accounts = const [],
    this.masterTags = const [],
    this.parties = const [],
  });

  final FfmAssistantDraft draft;
  final FfmAssistantDraftFeedbackService feedbackService;

  /// Daftar nama rekening aktif (Data Utama) untuk dropdown sumber/tujuan.
  final List<String> accounts;

  /// Daftar nama tag Data Utama (opsional, jika kosong dimuat dari AppDatabase).
  final List<String> masterTags;

  /// Daftar nama pihak Data Utama (opsional, jika kosong dimuat dari AppDatabase).
  final List<String> parties;

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
  late final TextEditingController _meterNameController;
  late final TextEditingController _meterNumberController;
  late List<ReceiptOcrItem> _items;
  late String _budgetPeriod;
  late final List<String> _tags;
  late List<String> _masterTags;
  late List<String> _parties;
  List<Category> _masterCategories = const [];
  List<String> _masterMerchants = const [];
  late String? _fromAccount;
  late String? _toAccount;
  late DateTime? _date;
  late TimeOfDay? _time; // only used for reminder drafts
  String? _soundUri;
  String? _soundName;
  late ReminderRecurrenceType _recurrence;
  late ReminderMode _mode;
  late List<int> _weekday;
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
      text: widget.draft.location ?? widget.draft.formValues['location'] ?? '',
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

    final initialTagsList = <String>[];
    if (widget.draft.tags != null && widget.draft.tags!.trim().isNotEmpty) {
      initialTagsList.addAll(
        widget.draft.tags!
            .split(',')
            .map((s) => s.trim().replaceAll('#', ''))
            .where((s) => s.isNotEmpty),
      );
    }
    if (widget.draft.newTags != null &&
        widget.draft.newTags!.trim().isNotEmpty) {
      initialTagsList.addAll(
        widget.draft.newTags!
            .split(',')
            .map((s) => s.trim().replaceAll('#', ''))
            .where((s) => s.isNotEmpty),
      );
    }
    final formTags = widget.draft.formValues['tags']?.toString();
    if (formTags != null && formTags.trim().isNotEmpty) {
      initialTagsList.addAll(
        formTags
            .split(',')
            .map((s) => s.trim().replaceAll('#', ''))
            .where((s) => s.isNotEmpty),
      );
    }
    final formNewTags = widget.draft.formValues['newTags']?.toString();
    if (formNewTags != null && formNewTags.trim().isNotEmpty) {
      initialTagsList.addAll(
        formNewTags
            .split(',')
            .map((s) => s.trim().replaceAll('#', ''))
            .where((s) => s.isNotEmpty),
      );
    }
    _tags = initialTagsList.map((t) => t.toLowerCase()).toSet().toList();
    _tagsController = TextEditingController();

    _masterTags = List<String>.from(widget.masterTags);
    _parties = List<String>.from(widget.parties);
    if (_masterTags.isEmpty || _parties.isEmpty) {
      _loadMasterData();
    }

    _fromAccount = widget.draft.fromAccountName?.trim();
    _toAccount = widget.draft.toAccountName?.trim();
    _date = widget.draft.date;
    // For reminder drafts, preserve the time-of-day separately so changing
    // date doesn't reset the time and vice-versa.
    _time =
        widget.draft.kind == FfmAssistantDraftKind.reminder &&
            widget.draft.date != null
        ? TimeOfDay.fromDateTime(widget.draft.date!)
        : null;

    final draftRecurrence =
        widget.draft.recurrenceType ??
        (widget.draft.formValues['recurrence'] != null ||
                widget.draft.formValues['recurrenceType'] != null
            ? ReminderRecurrenceTypeX.fromStorage(
                (widget.draft.formValues['recurrence'] ??
                        widget.draft.formValues['recurrenceType'])
                    .toString(),
              )
            : null);
    _recurrence = draftRecurrence ?? ReminderRecurrenceType.once;

    _mode =
        widget.draft.reminderMode ??
        ReminderModeX.fromStorage(
          widget.draft.formValues['reminderMode']?.toString() ??
              widget.draft.formValues['mode']?.toString(),
        );

    final initialWeekdaysRaw = widget.draft.weekdays.isNotEmpty
        ? widget.draft.weekdays
        : widget.draft.formValues['weekdays'];
    _weekday = initialWeekdaysRaw is List
        ? initialWeekdaysRaw
              .map((e) => int.tryParse(e.toString()))
              .whereType<int>()
              .toList()
        : <int>[];

    if (widget.draft.kind == FfmAssistantDraftKind.reminder) {
      final now = DateTime.now();
      if (_date == null) {
        _date = now.add(const Duration(hours: 1));
        _time = TimeOfDay.fromDateTime(_date!);
      } else if (_time != null) {
        var combined = DateTime(
          _date!.year,
          _date!.month,
          _date!.day,
          _time!.hour,
          _time!.minute,
        );
        if (combined.isBefore(now)) {
          combined = combined.add(const Duration(days: 1));
          _date = combined;
          _time = TimeOfDay.fromDateTime(combined);
        }
      }
    }

    _soundUri =
        widget.draft.soundUri ??
        widget.draft.formValues['soundUri']?.toString();
    _soundName =
        widget.draft.soundName ??
        widget.draft.formValues['soundName']?.toString();
    _activityMode =
        ActivityMode.tryParse(
          widget.draft.formValues['activityMode'] ??
              widget.draft.formValues['kind'],
        ) ??
        ActivityMode.timeTracking;

    _items = List<ReceiptOcrItem>.from(widget.draft.items);
    _receiptNumberController = TextEditingController(
      text:
          widget.draft.receiptNumber ??
          widget.draft.formValues['receiptNumber'] ??
          widget.draft.formValues['receipt_number'] ??
          '',
    );
    _receiptPaidAmountController = TextEditingController(
      text:
          widget.draft.receiptPaidAmount?.toString() ??
          widget.draft.formValues['receiptPaidAmount'] ??
          widget.draft.formValues['paid_amount'] ??
          '',
    );
    _receiptChangeAmountController = TextEditingController(
      text:
          widget.draft.receiptChangeAmount?.toString() ??
          widget.draft.formValues['receiptChangeAmount'] ??
          widget.draft.formValues['change_amount'] ??
          '',
    );
    _taxController = TextEditingController(
      text:
          widget.draft.tax?.toString() ??
          widget.draft.formValues['tax'] ??
          widget.draft.formValues['pajak'] ??
          '',
    );
    _discountController = TextEditingController(
      text:
          widget.draft.discount?.toString() ??
          widget.draft.formValues['discount'] ??
          widget.draft.formValues['diskon'] ??
          '',
    );
    _meterNameController = TextEditingController(
      text:
          widget.draft.formValues['proposedMeterName']?.toString() ??
          widget.draft.formValues['meterName']?.toString() ??
          '',
    );
    _meterNumberController = TextEditingController(
      text:
          widget.draft.formValues['meterNumber']?.toString() ??
          widget.draft.formValues['idpel']?.toString() ??
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
    _meterNameController.dispose();
    _meterNumberController.dispose();
    super.dispose();
  }

  void _recalculateAmountFromItems() {
    if (_items.isEmpty) return;
    final subtotal = _items.fold<int>(0, (sum, i) => sum + i.calculatedTotal);
    final taxText = _taxController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final tax = taxText.isEmpty ? 0 : (int.tryParse(taxText) ?? 0);
    final discountText = _discountController.text.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final discount = discountText.isEmpty
        ? 0
        : (int.tryParse(discountText) ?? 0);
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

  List<String> _categoriesForCurrentKind() {
    if (_masterCategories.isEmpty) return const [];
    final targetType = _selectedKind == FfmAssistantDraftKind.income
        ? 'income'
        : _selectedKind == FfmAssistantDraftKind.expense
        ? 'expense'
        : _isActivityDraft
        ? 'activity'
        : null;
    if (targetType == null) {
      return _masterCategories.map((c) => c.name.trim()).toList();
    }
    return _masterCategories
        .where((c) => c.type == targetType)
        .map((c) => c.name.trim())
        .where((n) => n.isNotEmpty)
        .toList();
  }

  Future<void> _loadMasterData() async {
    if (!getIt.isRegistered<AppDatabase>()) return;
    try {
      final db = getIt<AppDatabase>();
      final tagsFuture = _masterTags.isEmpty
          ? (db.select(db.tags)
                  ..where(
                    (t) =>
                        t.householdId.equals(AppContext.householdId) &
                        t.isArchived.equals(false),
                  )
                  ..orderBy([(t) => OrderingTerm.asc(t.name)]))
                .get()
          : Future.value(const <Tag>[]);
      final partiesFuture = _parties.isEmpty
          ? (db.select(db.transactionParties)
                  ..where(
                    (t) =>
                        t.householdId.equals(AppContext.householdId) &
                        t.isArchived.equals(false),
                  )
                  ..orderBy([(t) => OrderingTerm.asc(t.name)]))
                .get()
          : Future.value(const <TransactionParty>[]);
      final categoriesFuture =
          (db.select(db.categories)
                ..where(
                  (c) =>
                      c.householdId.equals(AppContext.householdId) &
                      c.isActive.equals(true),
                )
                ..orderBy([(c) => OrderingTerm.asc(c.name)]))
              .get();
      final merchantsFuture =
          (db.select(db.merchants)
                ..where(
                  (m) =>
                      m.householdId.equals(AppContext.householdId) &
                      m.isActive.equals(true),
                )
                ..orderBy([(m) => OrderingTerm.asc(m.name)]))
              .get();

      final results = await Future.wait([
        tagsFuture,
        partiesFuture,
        categoriesFuture,
        merchantsFuture,
      ]);
      if (!mounted) return;
      final tags = results[0] as List<Tag>;
      final parties = results[1] as List<TransactionParty>;
      final categories = results[2] as List<Category>;
      final merchants = results[3] as List<Merchant>;
      setState(() {
        if (_masterTags.isEmpty && tags.isNotEmpty) {
          _masterTags = tags
              .map((t) => t.name.trim().toLowerCase())
              .where((n) => n.isNotEmpty)
              .toList();
        }
        if (_parties.isEmpty && parties.isNotEmpty) {
          _parties = parties
              .map((p) => p.name.trim())
              .where((n) => n.isNotEmpty)
              .toSet()
              .toList();
        }
        _masterCategories = categories;
        _masterMerchants = merchants
            .map((m) => m.name.trim())
            .where((n) => n.isNotEmpty)
            .toSet()
            .toList();
      });
    } catch (_) {}
  }

  void _addTag(String raw) {
    final value = raw.trim().replaceAll('#', '');
    if (value.isEmpty) return;
    final normalized = value.toLowerCase();
    if (_tags.any((item) => item.toLowerCase() == normalized)) return;
    setState(() {
      _tags.add(normalized);
    });
  }

  void _removeTag(String value) {
    final normalized = value.trim().replaceAll('#', '').toLowerCase();
    setState(() {
      _tags.removeWhere((item) => item.toLowerCase() == normalized);
    });
  }

  Future<void> _showAddNewTagDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Tag Baru'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Contoh: operasional, belanja, darurat',
            labelText: 'Nama Tag',
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (val) {
            final clean = val.trim().replaceAll('#', '').toLowerCase();
            if (clean.isNotEmpty) Navigator.of(ctx).pop(clean);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final clean = controller.text
                  .trim()
                  .replaceAll('#', '')
                  .toLowerCase();
              if (clean.isNotEmpty) Navigator.of(ctx).pop(clean);
            },
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      _addTag(result);
    }
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
    if (isExpense && _tags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pilih atau tambahkan minimal 1 tag untuk transaksi pengeluaran.',
          ),
        ),
      );
      return;
    }
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
    final receiptPaidAmountText = _receiptPaidAmountController.text.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final receiptPaidAmount = receiptPaidAmountText.isEmpty
        ? null
        : int.tryParse(receiptPaidAmountText);
    final receiptChangeAmountText = _receiptChangeAmountController.text
        .replaceAll(RegExp(r'[^0-9]'), '');
    final receiptChangeAmount = receiptChangeAmountText.isEmpty
        ? null
        : int.tryParse(receiptChangeAmountText);
    final taxText = _taxController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final tax = taxText.isEmpty ? null : int.tryParse(taxText);
    final discountText = _discountController.text.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final discount = discountText.isEmpty ? null : int.tryParse(discountText);

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
    final meterName = _textOrNull(_meterNameController);
    final meterNumber = _textOrNull(_meterNumberController);
    if (meterName != null) {
      newFormValues['proposedMeterName'] = meterName;
      newFormValues['meterName'] = meterName;
    } else {
      newFormValues.remove('proposedMeterName');
      newFormValues.remove('meterName');
    }
    if (meterNumber != null) {
      newFormValues['meterNumber'] = meterNumber;
    } else {
      newFormValues.remove('meterNumber');
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
    if (_selectedKind == FfmAssistantDraftKind.reminder) {
      if (title == null || title.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Judul pengingat wajib diisi.')),
        );
        return;
      }
      if (_recurrence == ReminderRecurrenceType.weekly && _weekday.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pilih minimal satu hari untuk pengulangan mingguan.',
            ),
          ),
        );
        return;
      }
      if (effectiveDate != null && effectiveDate.isBefore(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pilih waktu pengingat yang masih akan datang.'),
          ),
        );
        return;
      }
      newFormValues['reminderMode'] = _mode.storageValue;
      newFormValues['mode'] = _mode.storageValue;
      newFormValues['recurrence'] = _recurrence.storageValue;
      newFormValues['recurrenceType'] = _recurrence.storageValue;
      newFormValues['weekdays'] = _weekday.join(',');
      if (_time != null) {
        newFormValues['time'] =
            '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}';
      }
      if (effectiveDate != null) {
        newFormValues['targetDate'] =
            '${effectiveDate.year}-${effectiveDate.month.toString().padLeft(2, '0')}-${effectiveDate.day.toString().padLeft(2, '0')}';
      }
      if (_soundUri != null && _soundUri!.isNotEmpty) {
        newFormValues['soundUri'] = _soundUri!;
      } else {
        newFormValues.remove('soundUri');
      }
      if (_soundName != null && _soundName!.isNotEmpty) {
        newFormValues['soundName'] = _soundName!;
      } else {
        newFormValues.remove('soundName');
      }
    }

    final existingDraftTags = (widget.draft.tags ?? '')
        .split(',')
        .map((s) => s.trim().replaceAll('#', '').toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    final initialNewTags = (widget.draft.newTags ?? '')
        .split(',')
        .map((s) => s.trim().replaceAll('#', '').toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    final masterTagSet = _masterTags
        .map((m) => m.trim().replaceAll('#', '').toLowerCase())
        .where((m) => m.isNotEmpty)
        .toSet();

    final customNewTags = _tags.where((t) {
      final tagLower = t.trim().replaceAll('#', '').toLowerCase();
      if (initialNewTags.contains(tagLower)) return true;
      if (existingDraftTags.contains(tagLower)) return false;
      if (masterTagSet.contains(tagLower)) return false;
      return true;
    }).toList();

    final effectiveNewTags = customNewTags.isNotEmpty
        ? customNewTags.join(', ')
        : (widget.draft.newTags != null &&
                _tags.any((t) => initialNewTags.contains(t.toLowerCase()))
            ? widget.draft.newTags
            : null);
    if (effectiveNewTags != null && effectiveNewTags.trim().isNotEmpty) {
      newFormValues['newTags'] = effectiveNewTags;
    } else {
      newFormValues.remove('newTags');
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
      parentSessionId: widget.draft.parentSessionId,
      activityMode: widget.draft.activityMode,
      scheduledAt: widget.draft.scheduledAt,
      sourceId: widget.draft.sourceId,
      source: widget.draft.source,
      recurringTransactionId: widget.draft.recurringTransactionId,
      newTags: effectiveNewTags,
      newMerchant: widget.draft.newMerchant,
      items: List<ReceiptOcrItem>.unmodifiable(_items),
      receiptNumber: receiptNumber,
      receiptPaidAmount: receiptPaidAmount,
      receiptChangeAmount: receiptChangeAmount,
      receiptRawText: widget.draft.receiptRawText,
      tax: tax,
      discount: discount,
      attachmentPaths: widget.draft.attachmentPaths,
      tags: _tags.isNotEmpty ? _tags.join(', ') : null,
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
      soundUri: _soundUri,
      soundName: _soundName,
      reminderMode: _selectedKind == FfmAssistantDraftKind.reminder
          ? _mode
          : widget.draft.reminderMode,
      recurrenceType: _selectedKind == FfmAssistantDraftKind.reminder
          ? _recurrence
          : widget.draft.recurrenceType,
      weekdays: _selectedKind == FfmAssistantDraftKind.reminder
          ? _weekday
          : widget.draft.weekdays,
    );

    if (_isTransaction) {
      const blockingCodes = {
        'transfer_same_account',
        'admin_fee_invalid',
        'receipt_adjustment_invalid',
        'receipt_payment_invalid',
        'receipt_total_mismatch',
        'receipt_item_invalid',
        'receipt_items_required',
        'receipt_payment_mismatch',
      };
      final blockingIssue = FfmAssistantDraftValidator.validate(editedDraft)
          .where((issue) => blockingCodes.contains(issue.code))
          .firstOrNull;
      if (blockingIssue != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(blockingIssue.message)));
        return;
      }
    }

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

  bool get _isDebtOrReceivable => switch (_selectedKind) {
    FfmAssistantDraftKind.liability ||
    FfmAssistantDraftKind.liabilityPayment ||
    FfmAssistantDraftKind.receivable ||
    FfmAssistantDraftKind.receivablePayment => true,
    _ => false,
  };

  DateTime _effectiveReminderDate() {
    final now = DateTime.now();
    DateTime base =
        _date ?? widget.draft.date ?? now.add(const Duration(hours: 1));
    final time = _time ?? TimeOfDay.fromDateTime(base);
    return DateTime(base.year, base.month, base.day, time.hour, time.minute);
  }

  String _formatReminderDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _pickReminderDateTime() async {
    final effectiveDate = _effectiveReminderDate();
    final pickedDate = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDate: effectiveDate.isBefore(DateTime.now())
          ? DateTime.now()
          : effectiveDate,
      helpText: 'Pilih tanggal pengingat',
    );
    if (!mounted || pickedDate == null) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.fromDateTime(effectiveDate),
      helpText: 'Pilih jam pengingat',
    );
    if (!mounted || pickedTime == null) return;
    setState(() {
      _date = pickedDate;
      _time = pickedTime;
    });
  }

  bool get _showsDate =>
      _isTransaction ||
      _isDebtOrReceivable ||
      _selectedKind == FfmAssistantDraftKind.goal ||
      _isActivityDraft;

  bool get _isGoalContribution =>
      _selectedKind == FfmAssistantDraftKind.goalDeposit ||
      _selectedKind == FfmAssistantDraftKind.goalUsage;

  bool get _isActivityDraft =>
      _selectedKind == FfmAssistantDraftKind.activity ||
      _selectedKind == FfmAssistantDraftKind.activityEdit;

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
    String? helperText,
  }) {
    final options = _accountOptions(initial, widget.accounts);
    return DropdownButtonFormField<String?>(
      initialValue: initial?.trim().isNotEmpty == true ? initial!.trim() : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
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
      switch (_selectedKind) {
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
              color: Theme.of(context).colorScheme.secondaryContainer
                  .withValues(alpha: .45),
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
          if (_selectedKind == FfmAssistantDraftKind.reminder) ...[
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Judul pengingat'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Catatan tambahan (opsional)',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Waktu mulai'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_formatReminderDateTime(_effectiveReminderDate())),
                  HijriDateLabel(date: _effectiveReminderDate()),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit_calendar),
                onPressed: _pickReminderDateTime,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ReminderRecurrenceType>(
              initialValue: _recurrence,
              decoration: const InputDecoration(labelText: 'Pengulangan'),
              items: ReminderRecurrenceType.values
                  .map(
                    (item) =>
                        DropdownMenuItem(value: item, child: Text(item.label)),
                  )
                  .toList(),
              onChanged: (value) => setState(
                () => _recurrence = value ?? ReminderRecurrenceType.once,
              ),
            ),
            if (_recurrence == ReminderRecurrenceType.weekly) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pilih Hari Pengulangan',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  children: List.generate(7, (index) {
                    final dayNumber = index + 1;
                    final isSelected = _weekday.contains(dayNumber);
                    const labels = [
                      'Sen',
                      'Sel',
                      'Rab',
                      'Kam',
                      'Jum',
                      'Sab',
                      'Min',
                    ];
                    return FilterChip(
                      label: Text(labels[index]),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            if (!_weekday.contains(dayNumber)) {
                              _weekday.add(dayNumber);
                            }
                          } else {
                            _weekday.remove(dayNumber);
                          }
                        });
                      },
                    );
                  }),
                ),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<ReminderMode>(
              initialValue: _mode,
              decoration: const InputDecoration(labelText: 'Tipe pengingat'),
              items: ReminderMode.values
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item == ReminderMode.alarm
                                ? Icons.alarm_rounded
                                : Icons.notifications_none_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(item.label),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _mode = value ?? ReminderMode.notification),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.music_note_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Nada notifikasi',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _soundName ?? 'Bawaan FFM',
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              final selection =
                                  await getIt<ReminderSoundPicker>().pick(
                                    currentUri: _soundUri,
                                  );
                              if (!mounted || selection == null) return;
                              setState(() {
                                _soundUri = selection.uri;
                                _soundName = selection.name;
                              });
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Nada dering belum bisa dipilih: $e',
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(
                            Icons.folder_open_outlined,
                            size: 18,
                          ),
                          label: const Text('Pilih nada'),
                        ),
                      ),
                      if (_soundUri != null) ...[
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          tooltip: 'Kembalikan ke nada bawaan',
                          onPressed: () {
                            setState(() {
                              _soundUri = null;
                              _soundName = null;
                            });
                          },
                          icon: const Icon(Icons.restart_alt_rounded),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ] else if (!_isTransaction && !_isGoalContribution) ...[
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: _selectedKind == FfmAssistantDraftKind.masterData
                    ? 'Nama ${widget.draft.categoryName ?? 'data'}'
                    : _selectedKind == FfmAssistantDraftKind.goal
                    ? 'Nama target'
                    : 'Nama/Judul',
                hintText: _selectedKind == FfmAssistantDraftKind.goal
                    ? 'Contoh: Dana Darurat, Liburan'
                    : null,
              ),
            ),
            if (_selectedKind == FfmAssistantDraftKind.masterData)
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
          if (_isGoalContribution)
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
                labelText: _selectedKind == FfmAssistantDraftKind.goalDeposit
                    ? 'Nominal setor (Rp)'
                    : _selectedKind == FfmAssistantDraftKind.goalUsage
                    ? 'Nominal pakai (Rp)'
                    : _selectedKind == FfmAssistantDraftKind.goal
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
              label: _selectedKind == FfmAssistantDraftKind.goalDeposit
                  ? 'Rekening sumber dana'
                  : _selectedKind == FfmAssistantDraftKind.liabilityPayment
                  ? 'Rekening sumber bayar'
                  : _selectedKind == FfmAssistantDraftKind.expense
                  ? 'Rekening sumber pengeluaran'
                  : 'Rekening asal',
              hint: 'Pilih rekening yang terdaftar, atau Belum terlacak',
              helperText: _selectedKind == FfmAssistantDraftKind.expense
                  ? 'Pengeluaran akan mengurangi saldo rekening ini.'
                  : null,
            ),
          if (_selectedKind == FfmAssistantDraftKind.income ||
              _selectedKind == FfmAssistantDraftKind.transfer ||
              _selectedKind == FfmAssistantDraftKind.goalUsage ||
              _selectedKind == FfmAssistantDraftKind.receivablePayment)
            _accountField(
              initial: _toAccount,
              onChanged: (value) => setState(() => _toAccount = value),
              label: _selectedKind == FfmAssistantDraftKind.goalUsage
                  ? 'Rekening tujuan dana'
                  : _selectedKind == FfmAssistantDraftKind.receivablePayment
                  ? 'Rekening tujuan terima'
                  : _selectedKind == FfmAssistantDraftKind.income
                  ? 'Rekening tujuan pemasukan'
                  : 'Rekening tujuan',
              hint: 'Pilih rekening yang terdaftar, atau Belum terlacak',
              helperText: _selectedKind == FfmAssistantDraftKind.income
                  ? 'Pemasukan akan menambah saldo rekening ini.'
                  : null,
            ),
          if (_selectedKind == FfmAssistantDraftKind.activity) ...[
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
          if (_selectedKind == FfmAssistantDraftKind.income ||
              _selectedKind == FfmAssistantDraftKind.expense ||
              _selectedKind == FfmAssistantDraftKind.budget ||
              _isActivityDraft) ...[
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(
                labelText: 'Kategori',
                hintText: 'Contoh: Makanan, Transportasi',
              ),
            ),
            if (_categoriesForCurrentKind().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final catName in _categoriesForCurrentKind().take(8))
                      ActionChip(
                        avatar: Icon(
                          _categoryController.text.trim().toLowerCase() ==
                                  catName.toLowerCase()
                              ? Icons.check
                              : Icons.category_outlined,
                          size: 14,
                        ),
                        label: Text(catName),
                        onPressed: () {
                          setState(() => _categoryController.text = catName);
                        },
                      ),
                  ],
                ),
              ),
          ],
          // Kolom transaksi disamakan dengan form resmi + database:
          // merchant, lokasi, tanggal, pihak, biaya admin (transfer).
          if (_selectedKind == FfmAssistantDraftKind.income ||
              _selectedKind == FfmAssistantDraftKind.expense) ...[
            TextField(
              controller: _merchantController,
              decoration: const InputDecoration(
                labelText: 'Toko / tempat (opsional)',
                hintText: 'Contoh: Indomaret, Pasar',
              ),
            ),
            if (_masterMerchants.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final mName in _masterMerchants.take(8))
                      ActionChip(
                        avatar: const Icon(Icons.storefront_outlined, size: 14),
                        label: Text(mName),
                        onPressed: () {
                          setState(() => _merchantController.text = mName);
                        },
                      ),
                  ],
                ),
              ),
          ],
          if (_selectedKind == FfmAssistantDraftKind.income ||
              _selectedKind == FfmAssistantDraftKind.expense) ...[
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Lokasi (opsional)',
                hintText: 'Misalnya pasar, rumah, atau kantor',
              ),
            ),
            if (_meterNumberController.text.isNotEmpty ||
                widget.draft.formValues['meterNumber'] != null ||
                widget.draft.formValues['idpel'] != null ||
                (_categoryController.text.toLowerCase().contains('listrik') ||
                    (widget.draft.categoryName?.toLowerCase().contains('listrik') ?? false))) ...[
              TextField(
                controller: _meterNameController,
                decoration: const InputDecoration(
                  labelText: 'Nama / Label Rumah Meteran PLN (opsional)',
                  hintText: 'Contoh: Rumah Utama, Kontrakan A, Ruko',
                  helperText: 'Label lokasi meteran PLN di Token Listrik',
                ),
              ),
              TextField(
                controller: _meterNumberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nomor Meter / IDPEL PLN (opsional)',
                  hintText: 'Contoh: 14123456789',
                ),
              ),
            ],
          ],
          if (_showsDate)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(
                _isTransaction
                    ? 'Tanggal kejadian'
                    : _isDebtOrReceivable
                    ? 'Tanggal jatuh tempo'
                    : _selectedKind == FfmAssistantDraftKind.goal
                    ? 'Target tanggal tercapai'
                    : _selectedKind == FfmAssistantDraftKind.reminder
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
                        : _selectedKind == FfmAssistantDraftKind.goal
                        ? 'Pilih target tanggal tercapai'
                        : _selectedKind == FfmAssistantDraftKind.reminder
                        ? 'Pilih tanggal pengingat'
                        : _selectedKind == FfmAssistantDraftKind.dailyNote
                        ? 'Pilih tanggal catatan'
                        : 'Pilih tanggal transaksi',
                  );
                  if (picked != null && mounted) {
                    setState(() => _date = picked);
                  }
                },
                child: const Text('Ganti'),
              ),
            ),

          if (_selectedKind == FfmAssistantDraftKind.budget) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _budgetPeriod,
              decoration: const InputDecoration(labelText: 'Periode anggaran'),
              items: const [
                DropdownMenuItem(value: 'monthly', child: Text('Bulanan')),
                DropdownMenuItem(value: 'weekly', child: Text('Mingguan')),
                DropdownMenuItem(
                  value: 'biweekly',
                  child: Text('Per Dua Minggu'),
                ),
                DropdownMenuItem(
                  value: 'nonrecurring',
                  child: Text('Tidak Rutin'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _budgetPeriod = value);
              },
            ),
          ],
          if (_selectedKind == FfmAssistantDraftKind.transfer)
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
          if (_selectedKind == FfmAssistantDraftKind.income) ...[
            TextField(
              controller: _partyController,
              decoration: const InputDecoration(
                labelText: 'Sumber pemasukan (opsional)',
                hintText: 'Contoh: Gaji, Usaha, Klien',
                helperText: 'Nama instansi, klien, atau pemberi dana',
              ),
            ),
            if (_parties.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final p in _parties)
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 14),
                        label: Text(p),
                        onPressed: () {
                          setState(() => _partyController.text = p);
                        },
                      ),
                  ],
                ),
              ),
          ],
          if (_selectedKind == FfmAssistantDraftKind.expense) ...[
            TextField(
              controller: _partyController,
              decoration: const InputDecoration(
                labelText: 'Dipakai oleh (opsional)',
                hintText: 'Contoh: Ayah, Ibu',
                helperText: 'Penanda rincian pemakai keluarga',
              ),
            ),
            if (_parties.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final p in _parties)
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 14),
                        label: Text(p),
                        onPressed: () {
                          setState(() => _partyController.text = p);
                        },
                      ),
                  ],
                ),
              ),
          ],
          if (_selectedKind == FfmAssistantDraftKind.liability)
            TextField(
              controller: _partyController,
              decoration: const InputDecoration(
                labelText: 'Pemberi pinjaman / nama pihak',
                hintText: 'Contoh: Bank Mandiri, Teman, Keluarga',
              ),
            ),
          if (_selectedKind == FfmAssistantDraftKind.receivable)
            TextField(
              controller: _partyController,
              decoration: const InputDecoration(
                labelText: 'Peminjam / nama pihak',
                hintText: 'Contoh: Budi, Saudara, Karyawan',
              ),
            ),
          if (_selectedKind == FfmAssistantDraftKind.liability ||
              _selectedKind == FfmAssistantDraftKind.receivable)
            TextField(
              controller: _monthlyInstallmentController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cicilan per bulan (opsional, Rp)',
                hintText: 'Contoh: 500000',
              ),
            ),
          if (_selectedKind == FfmAssistantDraftKind.income ||
              _selectedKind == FfmAssistantDraftKind.expense) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.label_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedKind == FfmAssistantDraftKind.expense
                        ? 'Tag penanda (wajib)'
                        : 'Tags (opsional)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _selectedKind == FfmAssistantDraftKind.expense
                  ? 'Wajib: Pilih minimal satu penanda dari Data Utama atau tambahkan tag baru.'
                  : 'Opsional. Tag untuk penanda pengelompokan transaksi.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final tagName in _masterTags)
                  FilterChip(
                    label: Text('#$tagName'),
                    selected: _tags.any(
                      (t) => t.toLowerCase() == tagName.toLowerCase(),
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        _addTag(tagName);
                      } else {
                        _removeTag(tagName);
                      }
                    },
                  ),
                for (final customTag in _tags.where(
                  (t) => !_masterTags.any(
                    (m) => m.toLowerCase() == t.toLowerCase(),
                  ),
                ))
                  InputChip(
                    label: Text('#$customTag'),
                    selected: true,
                    onDeleted: () => _removeTag(customTag),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Tag baru'),
                  onPressed: _showAddNewTagDialog,
                ),
              ],
            ),
          ],
          if (_isTransaction) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant
                      .withValues(alpha: 0.5),
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
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
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
          if (_selectedKind != FfmAssistantDraftKind.reminder)
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.35),
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
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                  size: 20,
                ),
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
                  initialValue: item.quantity == 1
                      ? '1'
                      : item.quantity.toString(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Qty',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    final qty =
                        double.tryParse(val.replaceAll(',', '.')) ?? 1.0;
                    onChanged(
                      item.copyWith(quantity: qty, clearLineTotal: true),
                    );
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
                    final p =
                        int.tryParse(val.replaceAll(RegExp(r'[^0-9]'), '')) ??
                        0;
                    onChanged(item.copyWith(price: p, clearLineTotal: true));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Rp${item.calculatedTotal}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
