import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../advisor/presentation/widgets/context_suggestion_card.dart';
import '../../../receivable/presentation/pages/receivable_pages.dart';
import '../../domain/entities/liability_entity.dart';
import '../../domain/usecases/liability_crud_usecases.dart';
import 'liability_detail_page.dart';

enum _LiabilitySort {
  sisaTerbesar,
  sisaTerkecil,
  cicilanTerbesar,
  jatuhTempoTerdekat,
}

class LiabilityReceivablePage extends StatelessWidget {
  const LiabilityReceivablePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Hutang & piutang'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Hutang'),
              Tab(text: 'Piutang'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            LiabilityListPage(embedded: true),
            ReceivableListPage(embedded: true),
          ],
        ),
      ),
    );
  }
}

class LiabilityListPage extends StatefulWidget {
  const LiabilityListPage({this.embedded = false, super.key});

  final bool embedded;

  @override
  State<LiabilityListPage> createState() => _LiabilityListPageState();
}

class _LiabilityListPageState extends State<LiabilityListPage> {
  var _liabilities = <LiabilityEntity>[];
  var _loading = true;
  var _sort = _LiabilitySort.sisaTerbesar;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await getIt<GetLiabilities>()(AppContext.householdId);
    if (!mounted) return;
    setState(() {
      _liabilities = items;
      _loading = false;
    });
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

  Future<void> _openForm() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LiabilityFormPage()),
    );
    if (saved == true) await _load();
  }

  List<LiabilityEntity> _sortLiabilities(List<LiabilityEntity> items) {
    final sorted = List<LiabilityEntity>.of(items);
    sorted.sort((a, b) {
      final comparison = switch (_sort) {
        _LiabilitySort.sisaTerbesar => b.remainingBalance.compareTo(
          a.remainingBalance,
        ),
        _LiabilitySort.sisaTerkecil => a.remainingBalance.compareTo(
          b.remainingBalance,
        ),
        _LiabilitySort.cicilanTerbesar => b.monthlyInstallment.compareTo(
          a.monthlyInstallment,
        ),
        _LiabilitySort.jatuhTempoTerdekat => a.dueDate.compareTo(b.dueDate),
      };
      return comparison == 0 ? a.name.compareTo(b.name) : comparison;
    });
    return sorted;
  }

  bool _isDueSoon(LiabilityEntity item) {
    if (item.remainingBalance <= 0) return false;
    final today = DateTime.now();
    final dueLimit = today.add(const Duration(days: 30));
    return !item.dueDate.isAfter(dueLimit);
  }

  Widget _liabilityList(
    List<LiabilityEntity> items, {
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
              icon: Icons.credit_card_off_outlined,
              title: emptyTitle,
              message: emptyMessage,
              action: FilledButton.icon(
                onPressed: _openForm,
                icon: const Icon(Icons.add),
                label: const Text('Tambah hutang'),
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
                        builder: (_) => LiabilityDetailPage(liability: item),
                      ),
                    );
                    if (mounted) _load();
                  },
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.warningSoft,
                    foregroundColor: AppColors.warning,
                    child: Icon(Icons.credit_card_outlined),
                  ),
                  title: Text(item.name),
                  subtitle: Text(
                    'Cicilan ${_moneyLabel(item.monthlyInstallment)} per bulan\nJatuh tempo ${_dateLabel(item.dueDate)}',
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
    final total = _liabilities.fold<int>(
      0,
      (sum, item) => sum + item.remainingBalance,
    );
    final active = _liabilities
        .where((item) => item.remainingBalance > 0)
        .toList(growable: false);
    final dueSoon = active.where(_isDueSoon).toList(growable: false);
    final paidOff = _liabilities
        .where((item) => item.remainingBalance <= 0)
        .toList(growable: false);

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Hutang keluarga'),
              actions: [
                PopupMenuButton<_LiabilitySort>(
                  tooltip: 'Urutkan hutang',
                  initialValue: _sort,
                  onSelected: (value) => setState(() => _sort = value),
                  icon: const Icon(Icons.sort_rounded),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _LiabilitySort.sisaTerbesar,
                      child: Text('Sisa terbesar'),
                    ),
                    PopupMenuItem(
                      value: _LiabilitySort.sisaTerkecil,
                      child: Text('Sisa terkecil'),
                    ),
                    PopupMenuItem(
                      value: _LiabilitySort.cicilanTerbesar,
                      child: Text('Cicilan terbesar'),
                    ),
                    PopupMenuItem(
                      value: _LiabilitySort.jatuhTempoTerdekat,
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
                          title: 'Cara pakainya',
                          message: 'Catat saldo tersisa, cicilan wajib, dan jatuh tempo. Data ini dipakai untuk membaca beban cicilan dan menyusun strategi pelunasan.',
                          icon: Icons.credit_score_outlined,
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
                                    backgroundColor: AppColors.warningSoft,
                                    foregroundColor: AppColors.warning,
                                    child: Icon(Icons.credit_score_outlined),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Beban yang masih berjalan',
                                    style: AppTextStyles.labelCaps,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Total sisa hutang',
                                style: AppTextStyles.labelCaps,
                              ),
                              const SizedBox(height: 12),
                              AppMoneyText(total),
                              const SizedBox(height: 8),
                              Text(
                                _liabilities.isEmpty
                                    ? 'Belum ada cicilan yang dicatat.'
                                    : '${_liabilities.length} cicilan sedang dicatat.',
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
                          title: _liabilities.isEmpty
                              ? 'Pelan-pelan, yang penting jelas'
                              : 'Biar cicilan nggak bikin kaget',
                          message: _liabilities.isEmpty
                              ? 'Begitu cicilanmu dicatat, kami bantu lihat rasio cicilan dan strategi pelunasan.'
                              : 'Cek sisa hutang dan tanggal jatuh tempo secara berkala supaya rencana tetap aman.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TabBar(
                    isScrollable: true,
                    tabs: [
                      Tab(text: 'Semua (${_liabilities.length})'),
                      Tab(text: 'Aktif (${active.length})'),
                      Tab(text: 'Jatuh tempo (${dueSoon.length})'),
                      Tab(text: 'Lunas (${paidOff.length})'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _liabilityList(
                          _sortLiabilities(_liabilities),
                          emptyTitle: 'Belum ada hutang',
                          emptyMessage: 'Catat cicilan supaya strategi pelunasanmu lebih jelas.',
                        ),
                        _liabilityList(
                          _sortLiabilities(active),
                          emptyTitle: 'Tidak ada hutang aktif',
                          emptyMessage:
                              'Semua hutang sudah lunas atau belum dicatat.',
                        ),
                        _liabilityList(
                          _sortLiabilities(dueSoon),
                          emptyTitle: 'Belum ada jatuh tempo dekat',
                          emptyMessage: 'Hutang dengan jatuh tempo 30 hari ke depan akan muncul di sini.',
                        ),
                        _liabilityList(
                          _sortLiabilities(paidOff),
                          emptyTitle: 'Belum ada hutang lunas',
                          emptyMessage: 'Hutang yang saldonya sudah nol akan muncul di sini.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        icon: const Icon(Icons.add),
        label: const Text('Tambah hutang'),
      ),
    );
  }
}

class LiabilityFormPage extends StatefulWidget {
  const LiabilityFormPage({super.key});

  @override
  State<LiabilityFormPage> createState() => _LiabilityFormPageState();
}

class _LiabilityFormPageState extends State<LiabilityFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _originalController = TextEditingController();
  final _remainingController = TextEditingController();
  final _installmentController = TextEditingController();
  final _interestController = TextEditingController();
  var _dueDate = DateTime.now().add(const Duration(days: 30));

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
    await getIt<SaveLiability>()(
      LiabilityEntity(
        id: const Uuid().v4(),
        householdId: AppContext.householdId,
        name: _nameController.text.trim(),
        originalAmount: _parseMoney(_originalController.text),
        remainingBalance: _parseMoney(_remainingController.text),
        monthlyInstallment: _parseMoney(_installmentController.text),
        interestRate: double.tryParse(
          _interestController.text.replaceAll(',', '.'),
        ),
        startDate: DateTime.now(),
        dueDate: _dueDate,
        updatedAt: DateTime.now(),
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  int _parseMoney(String value) => parseRupiah(value);

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah hutang')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const AppHelpBanner(
              title: 'Catat cicilan dengan lengkap',
              message: 'Isi sisa hutang dan cicilan bulanan. Jatuh tempo membantu kamu melihat kewajiban yang perlu disiapkan.',
              icon: Icons.event_note_outlined,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nama hutang'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Nama hutang belum diisi.'
                  : null,
            ),
            const SizedBox(height: 16),
            _numberField(
              _originalController,
              'Jumlah awal',
              'Rp ',
              required: true,
            ),
            const SizedBox(height: 16),
            _numberField(
              _remainingController,
              'Sisa hutang',
              'Rp ',
              required: true,
            ),
            const SizedBox(height: 16),
            _numberField(
              _installmentController,
              'Cicilan per bulan',
              'Rp ',
              required: true,
            ),
            const SizedBox(height: 16),
            _numberField(_interestController, 'Bunga per tahun', '%'),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Tanggal jatuh tempo'),
              subtitle: Text(_dateLabel(_dueDate)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDueDate,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Simpan hutang'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label,
    String suffix, {
    bool required = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: suffix == 'Rp '
          ? TextInputType.number
          : const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: suffix == 'Rp ' ? const [RupiahInputFormatter()] : null,
      decoration: InputDecoration(
        labelText: label,
        prefixText: suffix == 'Rp ' ? suffix : null,
        suffixText: suffix == '%' ? suffix : null,
      ),
      validator: required
          ? (value) =>
                _parseMoney(value ?? '') <= 0 ? '$label belum valid.' : null
          : null,
    );
  }
}
