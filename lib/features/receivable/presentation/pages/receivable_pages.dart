import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../../advisor/presentation/widgets/context_suggestion_card.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../domain/entities/receivable_entity.dart';
import '../../domain/usecases/receivable_crud_usecases.dart';

enum _ReceivableSort {
  sisaTerbesar,
  sisaTerkecil,
  cicilanTerbesar,
  jatuhTempoTerdekat,
}

class ReceivableListPage extends StatefulWidget {
  const ReceivableListPage({this.embedded = false, super.key});

  final bool embedded;

  @override
  State<ReceivableListPage> createState() => _ReceivableListPageState();
}

class _ReceivableListPageState extends State<ReceivableListPage> {
  var _receivables = <ReceivableEntity>[];
  var _loading = true;
  var _sort = _ReceivableSort.sisaTerbesar;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await getIt<GetReceivables>()(AppContext.householdId);
    if (!mounted) return;
    setState(() {
      _receivables = items;
      _loading = false;
    });
  }

  Future<void> _openForm() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ReceivableFormPage()),
    );
    if (saved == true) await _load();
  }

  List<ReceivableEntity> _sortItems(List<ReceivableEntity> items) {
    final sorted = List<ReceivableEntity>.of(items);
    sorted.sort((a, b) {
      final comparison = switch (_sort) {
        _ReceivableSort.sisaTerbesar => b.remainingBalance.compareTo(
          a.remainingBalance,
        ),
        _ReceivableSort.sisaTerkecil => a.remainingBalance.compareTo(
          b.remainingBalance,
        ),
        _ReceivableSort.cicilanTerbesar => b.monthlyInstallment.compareTo(
          a.monthlyInstallment,
        ),
        _ReceivableSort.jatuhTempoTerdekat => a.dueDate.compareTo(b.dueDate),
      };
      return comparison == 0 ? a.name.compareTo(b.name) : comparison;
    });
    return sorted;
  }

  bool _isDueSoon(ReceivableEntity item) {
    if (item.remainingBalance <= 0) return false;
    final today = DateTime.now();
    final dueLimit = today.add(const Duration(days: 30));
    return !item.dueDate.isAfter(dueLimit);
  }

  Widget _list(
    List<ReceivableEntity> items, {
    required String emptyTitle,
    required String emptyMessage,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
      children: [
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: AppEmptyState(
              icon: Icons.request_quote_outlined,
              title: emptyTitle,
              message: emptyMessage,
              action: FilledButton.icon(
                onPressed: _openForm,
                icon: const Icon(Icons.add),
                label: const Text('Tambah piutang'),
              ),
            ),
          )
        else
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReceivableDetailPage(receivable: item),
                      ),
                    );
                    if (mounted) _load();
                  },
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.positiveSoft,
                    foregroundColor: AppColors.positive,
                    child: Icon(Icons.request_quote_outlined),
                  ),
                  title: Text(item.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cicilan ${_moneyLabel(item.monthlyInstallment)} per bulan\nJatuh tempo ${_dateLabel(item.dueDate)}',
                      ),
                      HijriDateLabel(date: item.dueDate),
                    ],
                  ),
                  trailing: AppMoneyText(item.remainingBalance, compact: true),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _receivables.fold<int>(
      0,
      (sum, item) => sum + item.remainingBalance,
    );
    final active = _receivables
        .where((item) => item.remainingBalance > 0)
        .toList(growable: false);
    final dueSoon = active.where(_isDueSoon).toList(growable: false);
    final paidOff = _receivables
        .where((item) => item.remainingBalance <= 0)
        .toList(growable: false);

    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.liabilities,
      child: Scaffold(
        appBar: widget.embedded
            ? null
            : AppBar(
                title: const Text('Piutang keluarga'),
                actions: [
                  PopupMenuButton<_ReceivableSort>(
                    tooltip: 'Urutkan piutang',
                    initialValue: _sort,
                    onSelected: (value) => setState(() => _sort = value),
                    icon: const Icon(Icons.sort_rounded),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _ReceivableSort.sisaTerbesar,
                        child: Text('Sisa terbesar'),
                      ),
                      PopupMenuItem(
                        value: _ReceivableSort.sisaTerkecil,
                        child: Text('Sisa terkecil'),
                      ),
                      PopupMenuItem(
                        value: _ReceivableSort.cicilanTerbesar,
                        child: Text('Cicilan terbesar'),
                      ),
                      PopupMenuItem(
                        value: _ReceivableSort.jatuhTempoTerdekat,
                        child: Text('Jatuh tempo terdekat'),
                      ),
                    ],
                  ),
                ],
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : DefaultTabController(
                length: 4,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Column(
                        children: [
                          const AppHelpBanner(
                            title: 'Piutang itu uang yang masih harus diterima',
                            message: 'Catat pinjaman atau tagihan keluarga yang belum dibayar. Piutang dipisahkan dari pemasukan sampai uangnya benar-benar diterima.',
                            icon: Icons.payments_outlined,
                          ),
                          const SizedBox(height: 12),
                          AppCard(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const CircleAvatar(
                                      backgroundColor: AppColors.positiveSoft,
                                      foregroundColor: AppColors.positive,
                                      child: Icon(
                                        Icons.account_balance_wallet_outlined,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Uang yang masih ditunggu',
                                      style: AppTextStyles.labelCaps,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Total sisa piutang',
                                  style: AppTextStyles.labelCaps,
                                ),
                                const SizedBox(height: 12),
                                AppMoneyText(total),
                                const SizedBox(height: 8),
                                Text(
                                  _receivables.isEmpty
                                      ? 'Belum ada piutang yang dicatat.'
                                      : '${_receivables.length} piutang sedang dicatat.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          ContextSuggestionCard(
                            title: _receivables.isEmpty
                                ? 'Catat dulu biar nggak lupa'
                                : 'Pantau uang yang belum balik',
                            message: _receivables.isEmpty
                                ? 'Catat uang yang masih dipinjam orang atau tagihan yang belum dibayar. Saat uang diterima, masukkan sebagai pemasukan biasa.'
                                : 'Cek tanggal jatuh tempo dan sisa piutang secara berkala supaya arus uang keluarga tetap jelas.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TabBar(
                      isScrollable: true,
                      tabs: [
                        Tab(text: 'Semua (${_receivables.length})'),
                        Tab(text: 'Aktif (${active.length})'),
                        Tab(text: 'Jatuh tempo (${dueSoon.length})'),
                        Tab(text: 'Lunas (${paidOff.length})'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _list(
                            _sortItems(_receivables),
                            emptyTitle: 'Belum ada piutang',
                            emptyMessage: 'Catat uang yang masih harus diterima supaya lebih gampang dipantau.',
                          ),
                          _list(
                            _sortItems(active),
                            emptyTitle: 'Tidak ada piutang aktif',
                            emptyMessage:
                                'Semua piutang sudah lunas atau belum dicatat.',
                          ),
                          _list(
                            _sortItems(dueSoon),
                            emptyTitle: 'Belum ada jatuh tempo dekat',
                            emptyMessage: 'Piutang dengan jatuh tempo 30 hari ke depan akan muncul di sini.',
                          ),
                          _list(
                            _sortItems(paidOff),
                            emptyTitle: 'Belum ada piutang lunas',
                            emptyMessage: 'Piutang yang saldonya sudah nol akan muncul di sini.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'receivable_add_fab',
          onPressed: _openForm,
          icon: const Icon(Icons.add),
          label: const Text('Tambah piutang'),
        ),
      ),
    );
  }
}

class ReceivableFormPage extends StatefulWidget {
  const ReceivableFormPage({super.key, this.initialName, this.initialAmount});

  final String? initialName;
  final int? initialAmount;

  @override
  State<ReceivableFormPage> createState() => _ReceivableFormPageState();
}

class _ReceivableFormPageState extends State<ReceivableFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _originalController = TextEditingController();
  final _remainingController = TextEditingController();
  final _installmentController = TextEditingController();
  final _interestController = TextEditingController();
  var _dueDate = DateTime.now().add(const Duration(days: 30));

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName ?? '';
    if (widget.initialAmount != null) {
      final amount = widget.initialAmount.toString();
      _originalController.text = amount;
      _remainingController.text = amount;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _originalController.dispose();
    _remainingController.dispose();
    _installmentController.dispose();
    _interestController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _dueDate,
      helpText: 'Pilih tanggal jatuh tempo',
      cancelText: 'Batal',
      confirmText: 'Selesai',
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final now = DateTime.now();
    await getIt<SaveReceivable>()(
      ReceivableEntity(
        id: const Uuid().v4(),
        householdId: AppContext.householdId,
        name: _nameController.text.trim(),
        originalAmount: parseRupiah(_originalController.text),
        remainingBalance: parseRupiah(_remainingController.text),
        monthlyInstallment: parseRupiah(_installmentController.text),
        interestRate: double.tryParse(
          _interestController.text.replaceAll(',', '.'),
        ),
        startDate: now,
        dueDate: _dueDate,
        updatedAt: now,
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  String? _requiredMoney(String? value) {
    return parseRupiah(value ?? '') <= 0 ? 'Isi nominalnya dulu' : null;
  }

  @override
  Widget build(BuildContext context) {
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.liabilities,
      child: Scaffold(
        appBar: AppBar(title: const Text('Tambah piutang')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const AppHelpBanner(
                title: 'Catat uang yang masih harus diterima',
                message: 'Piutang belum dihitung sebagai pemasukan. Saat uang benar-benar masuk, catat transaksi pemasukan ke rekening atau dompet yang menerima.',
                icon: Icons.info_outline,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nama piutang'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Nama piutang belum diisi'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _originalController,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: const InputDecoration(labelText: 'Nominal awal'),
                validator: _requiredMoney,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _remainingController,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Sisa yang belum diterima',
                ),
                validator: _requiredMoney,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _installmentController,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Perkiraan cicilan per bulan',
                ),
                validator: _requiredMoney,
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
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Jatuh tempo'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_dateLabel(_dueDate)),
                    HijriDateLabel(date: _dueDate),
                  ],
                ),
                trailing: OutlinedButton(
                  onPressed: _pickDueDate,
                  child: const Text('Pilih tanggal'),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Simpan piutang'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReceivableDetailPage extends StatelessWidget {
  const ReceivableDetailPage({required this.receivable, super.key});

  final ReceivableEntity receivable;

  @override
  Widget build(BuildContext context) {
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.liabilities,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Detail piutang'),
          actions: [
            IconButton(
              tooltip: 'Edit piutang',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReceivableEditPage(receivable: receivable),
                  ),
                );
                if (context.mounted) Navigator.pop(context, true);
              },
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const AppHelpBanner(
              title: 'Piutang belum sama dengan uang masuk',
              message: 'Saldo di sini adalah uang yang masih ditunggu. Pemasukan baru dicatat saat uang benar-benar diterima.',
              icon: Icons.account_balance_wallet_outlined,
            ),
            const SizedBox(height: 16),
            AppCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    receivable.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  const Text('Sisa piutang', style: AppTextStyles.labelCaps),
                  const SizedBox(height: 8),
                  AppMoneyText(receivable.remainingBalance),
                  const SizedBox(height: 16),
                  _ReceivableInfoRow(
                    label: 'Nominal awal',
                    value: _moneyLabel(receivable.originalAmount),
                  ),
                  _ReceivableInfoRow(
                    label: 'Cicilan per bulan',
                    value: _moneyLabel(receivable.monthlyInstallment),
                  ),
                  _ReceivableInfoRow(
                    label: 'Jatuh tempo',
                    value: _dateLabel(receivable.dueDate),
                  ),
                  HijriDateLabel(date: receivable.dueDate),
                  _ReceivableInfoRow(
                    label: 'Bunga',
                    value: receivable.interestRate == null
                        ? 'Tanpa bunga'
                        : '${receivable.interestRate}% per tahun',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () async {
                await getIt<DeleteReceivable>()(
                  receivable.householdId,
                  receivable.id,
                );
                if (context.mounted) Navigator.pop(context, true);
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Hapus piutang'),
            ),
          ],
        ),
      ),
    );
  }
}

class ReceivableEditPage extends StatefulWidget {
  const ReceivableEditPage({required this.receivable, super.key});

  final ReceivableEntity receivable;

  @override
  State<ReceivableEditPage> createState() => _ReceivableEditPageState();
}

class _ReceivableEditPageState extends State<ReceivableEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _remainingController;
  late final TextEditingController _installmentController;
  late final TextEditingController _interestController;

  @override
  void initState() {
    super.initState();
    _remainingController = TextEditingController(
      text: formatRupiahInput('${widget.receivable.remainingBalance}'),
    );
    _installmentController = TextEditingController(
      text: formatRupiahInput('${widget.receivable.monthlyInstallment}'),
    );
    _interestController = TextEditingController(
      text: widget.receivable.interestRate?.toString() ?? '',
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
    await getIt<SaveReceivable>()(
      ReceivableEntity(
        id: widget.receivable.id,
        householdId: widget.receivable.householdId,
        name: widget.receivable.name,
        originalAmount: widget.receivable.originalAmount,
        remainingBalance: parseRupiah(_remainingController.text),
        monthlyInstallment: parseRupiah(_installmentController.text),
        interestRate: double.tryParse(
          _interestController.text.replaceAll(',', '.'),
        ),
        startDate: widget.receivable.startDate,
        dueDate: widget.receivable.dueDate,
        updatedAt: DateTime.now(),
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.liabilities,
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit piutang')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              TextFormField(
                controller: _remainingController,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Sisa yang belum diterima',
                ),
                validator: (value) =>
                    parseRupiah(value ?? '') < 0 ? 'Nominal belum valid' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _installmentController,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Perkiraan cicilan per bulan',
                ),
                validator: (value) =>
                    parseRupiah(value ?? '') < 0 ? 'Nominal belum valid' : null,
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

class _ReceivableInfoRow extends StatelessWidget {
  const _ReceivableInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Flexible(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

String _moneyLabel(int value) {
  final digits = value.abs().toString();
  final groups = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    final start = (end - 3).clamp(0, end);
    groups.insert(0, digits.substring(start, end));
  }
  return 'Rp${groups.join('.')}';
}

String _dateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
