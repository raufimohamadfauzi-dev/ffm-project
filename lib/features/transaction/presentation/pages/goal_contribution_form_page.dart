import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../core/ownership/owner_labels.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/date_time_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../../goal/domain/entities/goal_entity.dart';
import '../../../goal/domain/usecases/goal_crud_usecases.dart';
import '../../../goal/presentation/pages/goal_pages.dart';
import '../../../recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';

class GoalContributionFormPage extends StatefulWidget {
  const GoalContributionFormPage({
    super.key,
    this.existingTransaction,
    this.usage = false,
    this.assistantDraft,
  });

  final TransactionWithItems? existingTransaction;
  final bool usage;
  final FfmAssistantDraft? assistantDraft;

  @override
  State<GoalContributionFormPage> createState() =>
      _GoalContributionFormPageState();
}

class _GoalContributionFormPageState extends State<GoalContributionFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  var _goals = <GoalEntity>[];
  var _accounts = <Account>[];
  String? _goalId;
  String? _accountId;
  DateTime _date = DateTime.now();
  int? _accountBalance;
  var _goalsLoading = true;
  var _accountsLoading = true;
  var _balanceLoading = false;
  String? _assistantGoalWarning;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingTransaction;
    if (existing != null) {
      _goalId = existing.transaction.goalId;
      _accountId = existing.transaction.accountId;
      _date = existing.transaction.date;
      _amountController.text = formatRupiahInput(
        existing.transaction.amount.abs().toString(),
      );
      _noteController.text = existing.transaction.note ?? '';
    } else if (widget.assistantDraft != null) {
      final draft = widget.assistantDraft!;
      _date = draft.date ?? _date;
      if (draft.amount != null) {
        _amountController.text = formatRupiahInput(draft.amount.toString());
      }
      _noteController.text = draft.note ?? draft.title ?? '';
    }
    _loadGoals();
    _loadAccounts();
  }

  bool get _isUsage =>
      widget.usage ||
      widget.existingTransaction?.transaction.source == 'goal_usage';

  Future<void> _loadGoals() async {
    final goals = await getIt<GetGoals>()(AppContext.householdId);
    if (!mounted) return;
    setState(() {
      _goals = goals
          .where(
            (goal) => _isUsage
                ? goal.currentAmount > 0 || goal.id == _goalId
                : goal.currentAmount < goal.targetAmount || goal.id == _goalId,
          )
          .toList(growable: false);
      _goalsLoading = false;
    });
    final goalName = widget.assistantDraft?.goalName?.trim().toLowerCase();
    if (goalName != null && goalName.isNotEmpty) {
      final matched = _goals
          .where((goal) => goal.name.trim().toLowerCase() == goalName)
          .firstOrNull;
      if (matched != null && mounted) {
        setState(() => _goalId = matched.id);
      } else if (mounted) {
        setState(() {
          _assistantGoalWarning =
              'Target “${widget.assistantDraft!.goalName}” tidak ditemukan di daftar target aktif. Pilih target yang benar dulu.';
        });
      }
    }
  }

  Future<void> _loadAccounts() async {
    final database = getIt<AppDatabase>();
    final accounts =
        await (database.select(database.accounts)..where(
                (table) =>
                    table.householdId.equals(AppContext.householdId) &
                    table.isArchived.equals(false),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.name)]))
            .get();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _accountsLoading = false;
    });
    final accountName =
        (widget.assistantDraft?.fromAccountName ??
                widget.assistantDraft?.toAccountName)
            ?.trim()
            .toLowerCase();
    if (accountName != null && accountName.isNotEmpty) {
      final matched = _accounts
          .where((account) => account.name.trim().toLowerCase() == accountName)
          .firstOrNull;
      if (matched != null && mounted) setState(() => _accountId = matched.id);
    }
    await _loadBalance(_accountId);
  }

  Future<void> _loadBalance(String? accountId) async {
    if (accountId == null) {
      if (mounted) setState(() => _accountBalance = null);
      return;
    }
    setState(() => _balanceLoading = true);
    var balance = await getIt<GetAccountBookBalance>()(
      AppContext.householdId,
      accountId,
    );
    final existing = widget.existingTransaction;
    if (existing != null && existing.transaction.accountId == accountId) {
      balance -= existing.transaction.amount;
    }
    if (!mounted) return;
    setState(() {
      _accountBalance = balance;
      _balanceLoading = false;
    });
  }

  Future<void> _openGoalForm() async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const GoalFormPage()));
    if (!mounted) return;
    await _loadGoals();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _date,
      helpText: 'Pilih tanggal alokasi',
      cancelText: AppCopy.batal,
      confirmText: AppCopy.selesai,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _date.hour,
        _date.minute,
        _date.second,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      helpText: 'Pilih jam alokasi',
      cancelText: AppCopy.batal,
      confirmText: AppCopy.selesai,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = DateTime(
        _date.year,
        _date.month,
        _date.day,
        picked.hour,
        picked.minute,
        _date.second,
      );
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final amount = parseRupiah(_amountController.text);
    final goal = _goals.where((item) => item.id == _goalId).firstOrNull;
    if (goal == null || _accountId == null || amount <= 0) return;
    if (_isUsage && amount > goal.currentAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nominal pemakaian melebihi dana target yang tersedia.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop([
      TransactionDraft(
        type: TransactionType.expense,
        categoryId: _isUsage ? goal.categoryId : null,
        owner: OwnerLabels.family,
        date: _date,
        amount: -amount,
        note: _noteController.text.trim(),
        source: _isUsage ? 'goal_usage' : 'goal_contribution',
        accountId: _accountId,
        goalId: goal.id,
        items: const [],
      ),
    ]);
  }

  Widget _buildBalancePreview() {
    if (_balanceLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: LinearProgressIndicator(minHeight: 3),
      );
    }
    final balance = _accountBalance;
    if (balance == null) return const SizedBox.shrink();
    final amount = parseRupiah(_amountController.text);
    final after = balance - amount;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Saldo sebelum alokasi'),
                AppMoneyText(balance, compact: true),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_rounded, size: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Saldo setelah alokasi'),
                AppMoneyText(
                  after,
                  compact: true,
                  color: after < 0 ? AppColors.negative : AppColors.positive,
                ),
                if (after < 0)
                  Text(
                    'Saldo jadi minus',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.negative,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedGoal = _goals.where((goal) => goal.id == _goalId).firstOrNull;
    final amount = parseRupiah(_amountController.text);
    final projected = selectedGoal == null
        ? null
        : selectedGoal.currentAmount + (_isUsage ? -amount : amount);
    final progress = selectedGoal == null || selectedGoal.targetAmount <= 0
        ? 0.0
        : (selectedGoal.currentAmount / selectedGoal.targetAmount).clamp(
            0.0,
            1.0,
          );
    final projectedProgress =
        selectedGoal == null || selectedGoal.targetAmount <= 0
        ? 0.0
        : (projected! / selectedGoal.targetAmount).clamp(0.0, 1.0);
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.transactions,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isUsage
                ? (widget.existingTransaction == null
                      ? 'Pakai dana target'
                      : 'Ubah pemakaian target')
                : (widget.existingTransaction == null
                      ? 'Isi target uang terkumpul'
                      : 'Ubah isi target'),
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (widget.assistantDraft != null) ...[
                AppCard(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  padding: const EdgeInsets.all(12),
                  child: const Text(
                    'Diisi dari draft Asisten — periksa target, rekening, dan nominal sebelum simpan.',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              AppCard(
                color: AppColors.primarySoft.withValues(alpha: .55),
                border: BorderSide(color: AppColors.primary, width: 1.5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isUsage
                          ? 'Pakai dana target'
                          : 'Isi target tanpa kategori',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isUsage
                          ? 'Pilih target, tempat uang, dan nominal yang mau dipakai. Saldo rekening berkurang sekali dan saldo target ikut berkurang.'
                          : 'Pilih target, tempat uang, dan nominal alokasi. Ini bukan transaksi belanja, jadi tidak perlu memilih kategori.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppSectionHeader(
                title: '1. Target tujuan',
                helpText: _isUsage
                    ? 'Pilih target yang dananya mau dipakai.'
                    : 'Tentukan target yang ingin kamu tambah progresnya.',
              ),
              const SizedBox(height: 8),
              if (_goalsLoading)
                const LinearProgressIndicator()
              else if (_goals.isEmpty)
                AppCard(
                  color: Theme.of(context).colorScheme.primaryContainer
                      .withValues(alpha: .45),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Belum ada target aktif',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Buat target dulu, misalnya dana darurat, sekolah, atau kebutuhan tertentu.',
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _openGoalForm,
                        icon: const Icon(Icons.add),
                        label: const Text('Buat target sekarang'),
                      ),
                    ],
                  ),
                )
              else ...[
                if (_assistantGoalWarning != null) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange.shade700,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _assistantGoalWarning!,
                            style: TextStyle(
                              color: Colors.orange.shade900,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _goalId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Target uang terkumpul · wajib dipilih',
                    helperText: 'Target tidak mengubah saldo keluarga menjadi saldo kedua.',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                  items: _goals
                      .map(
                        (goal) => DropdownMenuItem<String>(
                          value: goal.id,
                          child: Text(
                            goal.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => setState(() => _goalId = value),
                  validator: (value) =>
                      value == null ? 'Pilih target dulu.' : null,
                ),
                if (selectedGoal != null) ...[
                  const SizedBox(height: 12),
                  AppCard(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Progres ${selectedGoal.name}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: progress),
                        const SizedBox(height: 6),
                        Text(
                          '${formatRupiahInput(selectedGoal.currentAmount.toString())} dari ${formatRupiahInput(selectedGoal.targetAmount.toString())} · ${(progress * 100).round()}%',
                        ),
                        if (amount > 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            '${_isUsage ? 'Setelah dipakai' : 'Setelah disimpan'}: ${formatRupiahInput(projected!.toString())} · ${(projectedProgress * 100).round()}%',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 18),
              AppSectionHeader(
                title: '2. Tempat uang',
                helpText: _isUsage
                    ? 'Pilih rekening atau cash tempat dana target benar-benar dipakai.'
                    : 'Pilih tempat uang yang dipakai untuk alokasi target: tunai, bank, atau dompet digital.',
              ),
              const SizedBox(height: 8),
              if (_accountsLoading)
                const LinearProgressIndicator()
              else if (_accounts.isEmpty)
                const Text('Tambahkan rekening atau tunai di Data Utama dulu.')
              else
                AppCard(
                  color: AppColors.negativeSoft.withValues(alpha: .28),
                  border: const BorderSide(
                    color: AppColors.negative,
                    width: 1.4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tempat uang yang dipakai · wajib dipilih',
                        style: TextStyle(
                          color: AppColors.negative,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SearchableDropdown<Account>(
                        items: _accounts,
                        selectedItem: _accounts
                            .where((account) => account.id == _accountId)
                            .firstOrNull,
                        itemLabel: (account) => account.name,
                        itemId: (account) => account.id,
                        labelText: 'Ambil uang dari',
                        helperText: _isUsage
                            ? 'Saldo tempat uang ini berkurang satu kali; progres target ikut berkurang satu kali.'
                            : 'Saldo tempat uang ini berkurang satu kali; progres target bertambah satu kali.',
                        searchHintText: 'Cari rekening atau dompet',
                        cacheKey: 'target.tempat_uang',
                        onChanged: (account) {
                          setState(() => _accountId = account?.id);
                          _loadBalance(account?.id);
                        },
                        validator: (account) => account == null
                            ? 'Pilih rekening sumber dulu.'
                            : null,
                      ),
                      _buildBalancePreview(),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              AppSectionHeader(
                title: '3. Isi nominal alokasi',
                helpText: _isUsage
                    ? 'Masukkan jumlah dana target yang mau dipakai.'
                    : 'Masukkan jumlah uang yang mau ditambahkan ke target.',
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: const [RupiahInputFormatter()],
                decoration: InputDecoration(
                  labelText: _isUsage
                      ? 'Nominal yang dipakai · wajib diisi'
                      : 'Nominal yang dialokasikan · wajib diisi',
                  prefixText: 'Rp ',
                  hintText: '0',
                  helperText: _isUsage
                      ? 'Nominal ini mengurangi rekening sumber and mengurangi progres target.'
                      : 'Nominal ini mengurangi rekening sumber and menambah progres target.',
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) => parseRupiah(value ?? '') <= 0
                    ? (_isUsage
                          ? 'Isi nominal pemakaian dulu.'
                          : 'Isi nominal alokasi dulu.')
                    : null,
              ),
              const SizedBox(height: 18),
              AppSectionHeader(
                title: '4. Waktu dan catatan',
                helpText:
                    'Tanggal bisa diubah kalau alokasi dicatat belakangan.',
              ),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Tanggal kejadian alokasi'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatTanggalLengkap(_date)),
                    HijriDateLabel(date: _date),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickDate,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('Jam kejadian alokasi'),
                subtitle: Text(formatJam(_date)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickTime,
              ),
              TextFormField(
                controller: _noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Catatan target · opsional',
                  hintText: 'Contoh: sisihan dari pemasukan minggu ini',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _goals.isEmpty || _accounts.isEmpty ? null : _save,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Simpan alokasi target'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
