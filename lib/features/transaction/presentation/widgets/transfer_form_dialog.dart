import 'package:flutter/material.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../../assistant/domain/ffm_assistant_form_prefill.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';

class TransferDraft {
  const TransferDraft({
    required this.fromAccountId,
    required this.toAccountId,
    required this.amount,
    required this.adminFee,
    required this.date,
    required this.note,
  });

  final String fromAccountId;
  final String toAccountId;
  final int amount;
  final int adminFee;
  final DateTime date;
  final String note;
}

class TransferFormDialog extends StatefulWidget {
  const TransferFormDialog({
    super.key,
    required this.accounts,
    this.assistantDraft,
    this.existingTransfer,
  });

  final List<Account> accounts;
  final FfmAssistantDraft? assistantDraft;
  final Transfer? existingTransfer;

  @override
  State<TransferFormDialog> createState() => _TransferFormDialogState();
}

class _TransferFormDialogState extends State<TransferFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _adminFeeController = TextEditingController();
  final _noteController = TextEditingController();
  late String? _fromAccountId;
  late String? _toAccountId;
  var _date = DateTime.now();
  FfmAssistantFormCheck? _prefillCheck;
  String? _assistantReferenceWarning;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingTransfer;
    if (existing != null) {
      _fromAccountId = existing.fromAccountId;
      _toAccountId = existing.toAccountId;
      _amountController.text = existing.amount.toString();
      if (existing.adminFee > 0) {
        _adminFeeController.text = existing.adminFee.toString();
      }
      _noteController.text = existing.note ?? '';
      _date = existing.date;
      return;
    }

    _fromAccountId = widget.accounts.firstOrNull?.id;
    _toAccountId = widget.accounts.length > 1 ? widget.accounts[1].id : null;
    final draft = widget.assistantDraft;
    if (draft == null) return;

    // Get prefill check for highlighting missing fields
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(draft);
    _prefillCheck = prefill.check;

    final fromAccountId = _accountIdForName(draft.fromAccountName);
    final toAccountId = _accountIdForName(draft.toAccountName);
    _fromAccountId = fromAccountId ?? _fromAccountId;
    _toAccountId = toAccountId ?? _toAccountId;
    final unresolvedAccounts = <String>[
      if (draft.fromAccountName?.trim().isNotEmpty == true &&
          fromAccountId == null)
        'rekening asal “${draft.fromAccountName}”',
      if (draft.toAccountName?.trim().isNotEmpty == true && toAccountId == null)
        'rekening tujuan “${draft.toAccountName}”',
    ];
    if (unresolvedAccounts.isNotEmpty) {
      _assistantReferenceWarning =
          '${unresolvedAccounts.join(' dan ')} belum cocok dengan Data Utama. Pilih rekening yang benar sebelum menyimpan.';
    }
    if (draft.amount != null) _amountController.text = draft.amount.toString();
    if (draft.adminFee != null) {
      _adminFeeController.text = draft.adminFee.toString();
    }
    _noteController.text = draft.note ?? draft.title ?? '';
    _date = draft.date ?? _date;
  }

  String? _accountIdForName(String? name) {
    final normalized = name?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    return widget.accounts
        .where((account) => account.name.trim().toLowerCase() == normalized)
        .firstOrNull
        ?.id;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _adminFeeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _accountLabel(Account account) {
    final type = switch (account.type) {
      'cash' => 'Tunai',
      'bank' => 'Rekening',
      'ewallet' => 'Dompet digital',
      _ => account.type,
    };
    return '${account.name} · $type';
  }

  String _fieldLabel(String field) {
    switch (field) {
      case 'fromAccountName':
        return 'Rekening asal';
      case 'toAccountName':
        return 'Rekening tujuan';
      case 'amount':
        return 'Nominal';
      case 'date':
        return 'Tanggal';
      case 'title':
        return 'Judul';
      case 'categoryName':
        return 'Kategori';
      case 'note':
        return 'Catatan';
      default:
        return field;
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _date,
      helpText: 'Pilih tanggal transfer',
      cancelText: AppCopy.batal,
      confirmText: 'Pakai tanggal ini',
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_fromAccountId == null || _toAccountId == null) return;
    if (_fromAccountId == _toAccountId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rekening asal dan tujuan harus beda.')),
      );
      return;
    }
    final amount = parseRupiah(_amountController.text);
    if (amount <= 0) return;
    Navigator.of(context).pop(
      TransferDraft(
        fromAccountId: _fromAccountId!,
        toAccountId: _toAccountId!,
        amount: amount,
        adminFee: parseRupiah(_adminFeeController.text),
        date: _date,
        note: _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.swap_horiz_rounded),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.existingTransfer != null
                  ? 'Edit transfer saldo'
                  : 'Transfer saldo antar tempat',
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.assistantDraft != null) ...[
                  const Text(
                    'Diisi dari draft Asisten — periksa sebelum simpan.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  if (_prefillCheck != null &&
                      _prefillCheck!.missingFields.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange.shade700,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Field yang belum lengkap:',
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ..._prefillCheck!.missingFields.map(
                            (field) => Padding(
                              padding: const EdgeInsets.only(left: 20, top: 2),
                              child: Text(
                                _fieldLabel(field),
                                style: TextStyle(
                                  color: Colors.orange.shade800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (_prefillCheck != null &&
                      _prefillCheck!.warnings.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.amber.shade700,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Perhatian:',
                                style: TextStyle(
                                  color: Colors.amber.shade900,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ..._prefillCheck!.warnings.map(
                            (warning) => Padding(
                              padding: const EdgeInsets.only(left: 20, top: 2),
                              child: Text(
                                warning,
                                style: TextStyle(
                                  color: Colors.amber.shade800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_assistantReferenceWarning != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Text(
                        _assistantReferenceWarning!,
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                ],
                Text(
                  'Pindahkan saldo dari Rekening, Tunai, atau Dompet digital ke tempat lain. Transfer tidak dihitung sebagai pemasukan atau pengeluaran.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Container(
                  decoration:
                      _prefillCheck?.missingFields.contains(
                            'fromAccountName',
                          ) ==
                          true
                      ? BoxDecoration(
                          border: Border.all(
                            color: Colors.orange.shade400,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        )
                      : null,
                  child: SearchableDropdown(
                    items: widget.accounts,
                    selectedItem: widget.accounts
                        .where((account) => account.id == _fromAccountId)
                        .firstOrNull,
                    itemLabel: _accountLabel,
                    itemId: (account) => account.id,
                    labelText: 'Dari tempat uang',
                    searchHintText: 'Cari rekening, tunai, atau dompet',
                    cacheKey: 'transfer.tempat_asal',
                    onChanged: (account) =>
                        setState(() => _fromAccountId = account?.id),
                    validator: (account) =>
                        account == null ? 'Pilih rekening asal.' : null,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration:
                      _prefillCheck?.missingFields.contains('toAccountName') ==
                          true
                      ? BoxDecoration(
                          border: Border.all(
                            color: Colors.orange.shade400,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        )
                      : null,
                  child: SearchableDropdown(
                    items: widget.accounts,
                    selectedItem: widget.accounts
                        .where((account) => account.id == _toAccountId)
                        .firstOrNull,
                    itemLabel: _accountLabel,
                    itemId: (account) => account.id,
                    labelText: 'Ke tempat uang',
                    searchHintText: 'Cari rekening, tunai, atau dompet',
                    cacheKey: 'transfer.tempat_tujuan',
                    onChanged: (account) =>
                        setState(() => _toAccountId = account?.id),
                    validator: (account) =>
                        account == null ? 'Pilih rekening tujuan.' : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Nominal yang dipindahkan',
                    prefixText: 'Rp ',
                    helperText:
                        'Contoh: 250.000. Ini yang masuk ke rekening tujuan.',
                    border:
                        _prefillCheck?.missingFields.contains('amount') == true
                        ? OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.orange.shade400,
                              width: 2,
                            ),
                          )
                        : null,
                    enabledBorder:
                        _prefillCheck?.missingFields.contains('amount') == true
                        ? OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.orange.shade400,
                              width: 2,
                            ),
                          )
                        : null,
                    focusedBorder:
                        _prefillCheck?.missingFields.contains('amount') == true
                        ? OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.orange.shade400,
                              width: 2,
                            ),
                          )
                        : null,
                  ),
                  validator: (value) => parseRupiah(value ?? '') <= 0
                      ? 'Nominal harus lebih dari nol.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _adminFeeController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Biaya admin (opsional)',
                    prefixText: 'Rp ',
                    helperText:
                        'Dipisahkan sebagai pengeluaran dari rekening asal.',
                  ),
                  validator: (value) => parseRupiah(value ?? '') < 0
                      ? 'Biaya admin tidak boleh negatif.'
                      : null,
                ),
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Tanggal'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                      ),
                      HijriDateLabel(date: _date),
                    ],
                  ),
                  trailing: TextButton(
                    onPressed: _pickDate,
                    child: const Text('Ganti'),
                  ),
                ),
                TextFormField(
                  controller: _noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppCopy.batal),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.swap_horiz_rounded),
          label: Text(
            widget.existingTransfer != null
                ? 'Perbarui transfer'
                : 'Simpan transfer',
          ),
        ),
      ],
    );
  }
}
