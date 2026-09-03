import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../domain/debt_receivable_validation.dart';
import '../../domain/usecases/process_debt_payment.dart';

class DebtPaymentDialog extends StatefulWidget {
  const DebtPaymentDialog({
    super.key,
    required this.targetId,
    required this.targetName,
    required this.remainingBalance,
    required this.isLiability,
  });

  final String targetId;
  final String targetName;
  final int remainingBalance;
  final bool isLiability;

  static Future<bool?> show(
    BuildContext context, {
    required String targetId,
    required String targetName,
    required int remainingBalance,
    required bool isLiability,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => DebtPaymentDialog(
        targetId: targetId,
        targetName: targetName,
        remainingBalance: remainingBalance,
        isLiability: isLiability,
      ),
    );
  }

  @override
  State<DebtPaymentDialog> createState() => _DebtPaymentDialogState();
}

class _DebtPaymentDialogState extends State<DebtPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;

  var _paymentDate = DateTime.now();
  var _isFullPayoff = false;
  var _recordCashTx = true;
  var _submitting = false;

  String? _selectedAccountId;
  List<Account> _accounts = [];
  bool _loadingAccounts = true;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _noteController = TextEditingController(
      text: widget.isLiability
          ? 'Pembayaran hutang: ${widget.targetName}'
          : 'Penerimaan piutang: ${widget.targetName}',
    );
    _loadAccounts();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    try {
      final db = getIt<AppDatabase>();
      final rows = await (db.select(db.accounts)
            ..where(
              (tbl) =>
                  tbl.householdId.equals(AppContext.householdId) &
                  tbl.isActive.equals(true) &
                  tbl.isArchived.equals(false),
            )
            ..orderBy([(tbl) => OrderingTerm.asc(tbl.name)]))
          .get();

      if (!mounted) return;
      setState(() {
        _accounts = rows;
        _loadingAccounts = false;
        if (rows.isNotEmpty) {
          _selectedAccountId = rows.first.id;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingAccounts = false);
    }
  }

  int _parseAmount(String text) {
    return parseRupiah(text);
  }

  void _onToggleMode(bool isFull) {
    setState(() {
      _isFullPayoff = isFull;
      if (isFull) {
        _amountController.text = formatRupiahInput('${widget.remainingBalance}');
      } else {
        _amountController.clear();
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Pilih tanggal pembayaran',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (picked != null) {
      setState(() => _paymentDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = _parseAmount(_amountController.text);
    final error = validateDebtPaymentAmount(
      paymentAmount: amount,
      remainingBalance: widget.remainingBalance,
    );
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.negative),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final processPayment = getIt<ProcessDebtPayment>();
      await processPayment(
        householdId: AppContext.householdId,
        targetId: widget.targetId,
        targetName: widget.targetName,
        isLiability: widget.isLiability,
        amount: amount,
        date: _paymentDate,
        accountId: _selectedAccountId,
        note: _noteController.text.trim(),
        recordCashTransaction: _recordCashTx,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isLiability
                ? 'Pembayaran hutang Rp${formatRupiahInput('$amount')} berhasil dicatat.'
                : 'Penerimaan piutang Rp${formatRupiahInput('$amount')} berhasil dicatat.',
          ),
          backgroundColor: AppColors.positive,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mencatat pembayaran: $e'),
          backgroundColor: AppColors.negative,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isLiability
        ? 'Catat Pembayaran Hutang'
        : 'Terima Pembayaran Piutang';
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            widget.isLiability
                ? Icons.payment_outlined
                : Icons.account_balance_wallet_outlined,
            color: widget.isLiability ? AppColors.warning : AppColors.positive,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sisa Saldo: Rp${formatRupiahInput('${widget.remainingBalance}')}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: 12),
              // Segmented Choice: Sebagian vs Lunasi Penuh
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Sebagian')),
                      selected: !_isFullPayoff,
                      onSelected: (val) => _onToggleMode(false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Lunasi Penuh')),
                      selected: _isFullPayoff,
                      onSelected: (val) => _onToggleMode(true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Nominal Input
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nominal Pembayaran',
                  prefixText: 'Rp ',
                ),
                onChanged: (val) {
                  final formatted = formatRupiahInput(val);
                  if (formatted != val) {
                    _amountController.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(
                        offset: formatted.length,
                      ),
                    );
                  }
                },
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Nominal wajib diisi';
                  }
                  final amount = _parseAmount(val);
                  return validateDebtPaymentAmount(
                    paymentAmount: amount,
                    remainingBalance: widget.remainingBalance,
                  );
                },
              ),
              const SizedBox(height: 12),
              // Rekening Pembayaran
              if (_loadingAccounts)
                const LinearProgressIndicator()
              else if (_accounts.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _selectedAccountId,
                  decoration: const InputDecoration(
                    labelText: 'Rekening Kas',
                    prefixIcon: Icon(Icons.account_balance_outlined),
                  ),
                  items: _accounts.map((acc) {
                    return DropdownMenuItem<String>(
                      value: acc.id,
                      child: Text(acc.name),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedAccountId = val),
                ),
              const SizedBox(height: 12),
              // Tanggal Pembayaran
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Tanggal Pembayaran',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(
                    '${_paymentDate.day.toString().padLeft(2, '0')}/${_paymentDate.month.toString().padLeft(2, '0')}/${_paymentDate.year}',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Catatan
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Catatan (Opsional)',
                  prefixIcon: Icon(Icons.note_alt_outlined),
                ),
              ),
              const SizedBox(height: 8),
              // Checkbox catat kas
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Catat transaksi ke kas rekening'),
                value: _recordCashTx,
                onChanged: (val) => setState(() => _recordCashTx = val ?? true),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Simpan Pembayaran'),
        ),
      ],
    );
  }
}
