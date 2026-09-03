import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../domain/debt_receivable_validation.dart';
import '../../domain/entities/liability_entity.dart';
import '../../domain/usecases/liability_crud_usecases.dart';
import '../widgets/debt_payment_dialog.dart';

class LiabilityDetailPage extends StatefulWidget {
  const LiabilityDetailPage({super.key, required this.liability});

  final LiabilityEntity liability;

  @override
  State<LiabilityDetailPage> createState() => _LiabilityDetailPageState();
}

class _LiabilityDetailPageState extends State<LiabilityDetailPage> {
  late LiabilityEntity _liability;
  List<Transaction> _paymentHistory = [];
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _liability = widget.liability;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final db = getIt<AppDatabase>();
      final txs = await (db.select(db.transactions)
            ..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.source.equals('liability_payment') &
                  row.sourceId.equals(_liability.id),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.date)]))
          .get();

      if (!mounted) return;
      setState(() {
        _paymentHistory = txs;
        _loadingHistory = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _refreshData() async {
    final db = getIt<AppDatabase>();
    final row = await (db.select(db.liabilities)
          ..where(
            (r) =>
                r.householdId.equals(AppContext.householdId) &
                r.id.equals(_liability.id),
          ))
        .getSingleOrNull();

    if (row != null && mounted) {
      setState(() {
        _liability = LiabilityEntity(
          id: row.id,
          householdId: row.householdId,
          name: row.name,
          originalAmount: row.originalAmount,
          remainingBalance: row.remainingBalance,
          monthlyInstallment: row.monthlyInstallment,
          interestRate: row.interestRate,
          startDate: row.startDate,
          dueDate: row.dueDate ?? row.startDate,
          updatedAt: row.createdAt,
          note: row.note,
        );
      });
      await _loadHistory();
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _liability.originalAmount <= 0
        ? 0.0
        : (1 - _liability.remainingBalance / _liability.originalAmount).clamp(
            0.0,
            1.0,
          );
    final status = classifyDebtReceivableDue(
      remainingBalance: _liability.remainingBalance,
      dueDate: _liability.dueDate,
      today: DateTime.now(),
    );

    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.liabilities,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Detail hutang'),
          actions: [
            IconButton(
              tooltip: 'Edit hutang',
              onPressed: () async {
                final updated = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LiabilityEditPage(liability: _liability),
                  ),
                );
                if (updated == true) {
                  await _refreshData();
                }
              },
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refreshData,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              // Kartu Status Utama & Progress
              AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _liability.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Sisa hutang',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      AppMoneyText(_liability.remainingBalance, compact: false),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _liability.remainingBalance <= 0
                              ? AppColors.positiveSoft
                              : status == DebtReceivableDueStatus.overdue
                              ? AppColors.negativeSoft
                              : AppColors.warningSoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          debtReceivableDueStatusLabel(status),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _liability.remainingBalance <= 0
                                ? AppColors.positive
                                : status == DebtReceivableDueStatus.overdue
                                ? AppColors.negative
                                : AppColors.warning,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      LinearProgressIndicator(value: progress),
                      const SizedBox(height: 8),
                      Text(
                        '${(progress * 100).round()}% sudah terbayar dari ${formatRupiahInput(_liability.originalAmount.toString())}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Tombol Utama: Catat Pembayaran Hutang
              if (_liability.remainingBalance > 0)
                FilledButton.icon(
                  onPressed: () async {
                    final paid = await DebtPaymentDialog.show(
                      context,
                      targetId: _liability.id,
                      targetName: _liability.name,
                      remainingBalance: _liability.remainingBalance,
                      isLiability: true,
                    );
                    if (paid == true) {
                      await _refreshData();
                    }
                  },
                  icon: const Icon(Icons.payment_outlined),
                  label: const Text('Catat Pembayaran Hutang'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),

              const SizedBox(height: 16),

              // Informasi Rincian
              AppCard(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Nominal awal'),
                      trailing: AppMoneyText(_liability.originalAmount, compact: true),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('Tanggal mulai'),
                      trailing: Text(_formatDate(_liability.startDate)),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('Cicilan per bulan'),
                      trailing: AppMoneyText(
                        _liability.monthlyInstallment,
                        compact: true,
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('Jatuh tempo'),
                      subtitle: HijriDateLabel(date: _liability.dueDate),
                      trailing: Text(_formatDate(_liability.dueDate)),
                    ),
                    if (_liability.interestRate != null) ...[
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('Bunga per tahun'),
                        trailing: Text(
                          '${_liability.interestRate!.toStringAsFixed(2)}%',
                        ),
                      ),
                    ],
                    if (_liability.note?.trim().isNotEmpty == true) ...[
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('Catatan'),
                        subtitle: Text(_liability.note!),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Riwayat Pembayaran Kas
              Text(
                'Riwayat Pembayaran Kas',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              if (_loadingHistory)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_paymentHistory.isEmpty)
                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'Belum ada riwayat pembayaran yang tercatat.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                )
              else
                AppCard(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _paymentHistory.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final tx = _paymentHistory[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppColors.positiveSoft,
                          foregroundColor: AppColors.positive,
                          child: Icon(Icons.check_circle_outline, size: 20),
                        ),
                        title: Text(tx.note ?? 'Pembayaran hutang'),
                        subtitle: Text(_formatDate(tx.date)),
                        trailing: AppMoneyText(tx.amount.abs(), compact: true),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 24),

              // Tombol Arsipkan
              OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Arsipkan hutang?'),
                      content: const Text(
                        'Hutang akan disembunyikan dari daftar aktif, tetapi datanya tetap tersimpan.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Batal'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Arsipkan'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  await getIt<DeleteLiability>()(
                    _liability.householdId,
                    _liability.id,
                  );
                  if (context.mounted) Navigator.pop(context, true);
                },
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Arsipkan hutang'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LiabilityEditPage extends StatefulWidget {
  const LiabilityEditPage({required this.liability, super.key});

  final LiabilityEntity liability;

  @override
  State<LiabilityEditPage> createState() => _LiabilityEditPageState();
}

class _LiabilityEditPageState extends State<LiabilityEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _remainingController;
  late final TextEditingController _installmentController;
  late final TextEditingController _interestController;

  @override
  void initState() {
    super.initState();
    _remainingController = TextEditingController(
      text: formatRupiahInput('${widget.liability.remainingBalance}'),
    );
    _installmentController = TextEditingController(
      text: formatRupiahInput('${widget.liability.monthlyInstallment}'),
    );
    _interestController = TextEditingController(
      text: widget.liability.interestRate?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _remainingController.dispose();
    _installmentController.dispose();
    _interestController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final interestText = _interestController.text.trim();
    final interestRate = interestText.isEmpty
        ? null
        : double.tryParse(interestText.replaceAll(',', '.'));
    final validationError = interestText.isNotEmpty && interestRate == null
        ? 'Bunga belum valid.'
        : validateDebtReceivableAmounts(
            originalAmount: widget.liability.originalAmount,
            remainingBalance: parseRupiah(_remainingController.text),
            monthlyInstallment: parseRupiah(_installmentController.text),
            interestRate: interestRate,
          );
    if (validationError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(validationError)));
      return;
    }
    await getIt<SaveLiability>()(
      LiabilityEntity(
        id: widget.liability.id,
        householdId: AppContext.householdId,
        name: widget.liability.name,
        originalAmount: widget.liability.originalAmount,
        remainingBalance: parseRupiah(_remainingController.text),
        monthlyInstallment: parseRupiah(_installmentController.text),
        interestRate: interestRate,
        startDate: widget.liability.startDate,
        dueDate: widget.liability.dueDate,
        updatedAt: DateTime.now(),
        note: widget.liability.note,
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.liabilities,
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit hutang')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                'Hutang: ${widget.liability.name}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _remainingController,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: const InputDecoration(labelText: 'Sisa hutang'),
                validator: (value) => parseRupiah(value ?? '') < 0
                    ? 'Sisa hutang belum valid.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _installmentController,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Cicilan per bulan',
                ),
                validator: (value) => parseRupiah(value ?? '') < 0
                    ? 'Cicilan belum valid.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _interestController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Bunga per tahun (opsional)',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Simpan perubahan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
