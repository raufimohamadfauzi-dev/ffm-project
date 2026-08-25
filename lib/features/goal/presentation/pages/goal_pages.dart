import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../domain/entities/goal_entity.dart';
import '../../domain/usecases/goal_crud_usecases.dart';

class GoalListPage extends StatefulWidget {
  const GoalListPage({super.key});
  @override
  State<GoalListPage> createState() => _GoalListPageState();
}

class _GoalListPageState extends State<GoalListPage> {
  var _items = <GoalEntity>[];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await getIt<GetGoals>()(AppContext.householdId);
    if (mounted)
      setState(() {
        _items = items;
        _loading = false;
      });
  }

  Future<void> _add() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const GoalFormPage()),
    );
    if (saved == true) _load();
  }

  Future<void> _openDetail(GoalEntity item) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => GoalDetailPage(goal: item)),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) => FfmAssistantPageContext(
    destination: FfmAssistantDestination.goals,
    child: Scaffold(
      appBar: AppBar(title: const Text('Target keuangan')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'goal_add_fab',
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Tambah target'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const AppEmptyState(
              icon: Icons.flag_outlined,
              title: 'Belum ada target',
              message: 'Buat target untuk uang yang ingin dikumpulkan dalam periode tertentu.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: _items.map((item) {
                final progress = item.targetAmount <= 0
                    ? 0.0
                    : (item.currentAmount / item.targetAmount).clamp(0.0, 1.0);
                return AppCard(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openDetail(item),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              AppMoneyText(item.currentAmount, compact: true),
                            ],
                          ),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(value: progress),
                          const SizedBox(height: 6),
                          Text(
                            '${(progress * 100).round()}% dari ${formatRupiahInput(item.targetAmount.toString())} • target ${item.targetDate.day}/${item.targetDate.month}/${item.targetDate.year}',
                          ),
                          HijriDateLabel(date: item.targetDate),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
    ),
  );
}

class GoalDetailPage extends StatelessWidget {
  const GoalDetailPage({super.key, required this.goal});

  final GoalEntity goal;

  Future<void> _edit(BuildContext context) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => GoalEditPage(goal: goal)),
    );
    if (!context.mounted || saved != true) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _archive(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Arsipkan target?'),
        content: Text(
          'Target “${goal.name}” akan disembunyikan dari daftar aktif. Progres dan transaksi yang terkait tetap tersimpan; tidak ada saldo rekening atau transaksi yang diubah.',
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
    if (confirmed != true || !context.mounted) return;
    await getIt<DeleteGoal>()(AppContext.householdId, goal.id);
    if (!context.mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final progress = goal.targetAmount <= 0
        ? 0.0
        : (goal.currentAmount / goal.targetAmount).clamp(0.0, 1.0);
    final remaining = (goal.targetAmount - goal.currentAmount).clamp(
      0,
      goal.targetAmount,
    );
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.goals,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Detail target'),
          actions: [
            IconButton(
              tooltip: 'Ubah target',
              onPressed: () => _edit(context),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const AppHelpBanner(
              title: 'Progres berasal dari transaksi',
              message: 'Setoran dan pemakaian dana target harus dicatat sebagai transaksi resmi. Halaman ini tidak mengubah saldo terkumpul secara langsung.',
              icon: Icons.flag_outlined,
            ),
            const SizedBox(height: 20),
            Center(
              child: CircleAvatar(
                radius: 30,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: Theme.of(context).colorScheme.primary,
                child: const Icon(Icons.flag_outlined, size: 32),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              goal.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Progres dana',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: AppMoneyText(goal.currentAmount, compact: false),
                      ),
                      Text('${(progress * 100).round()}% tercapai'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 10),
                  Text(
                    'Target ${formatRupiahInput(goal.targetAmount.toString())}',
                  ),
                  Text('Sisa ${formatRupiahInput(remaining.toString())}'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const AppSectionHeader(title: 'Informasi target'),
            const SizedBox(height: 8),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('Batas waktu'),
                    subtitle: HijriDateText(
                      date: goal.targetDate,
                      compact: true,
                    ),
                  ),
                  if (goal.createdAt != null) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.event_note_outlined),
                      title: const Text('Tanggal dibuat'),
                      subtitle: HijriDateText(
                        date: goal.createdAt!,
                        compact: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => _edit(context),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Ubah target'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _archive(context),
              icon: const Icon(Icons.archive_outlined),
              label: const Text('Arsipkan target'),
            ),
          ],
        ),
      ),
    );
  }
}

class GoalEditPage extends StatefulWidget {
  const GoalEditPage({super.key, required this.goal});

  final GoalEntity goal;

  @override
  State<GoalEditPage> createState() => _GoalEditPageState();
}

class _GoalEditPageState extends State<GoalEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _target;
  late DateTime _targetDate;
  final _formKey = GlobalKey<FormState>();
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.goal.name);
    _target = TextEditingController(
      text: formatRupiahInput(widget.goal.targetAmount.toString()),
    );
    _targetDate = widget.goal.targetDate;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _pickTargetDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _targetDate,
      helpText: 'Pilih batas waktu target',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (date != null && mounted) setState(() => _targetDate = date);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    final targetAmount = parseRupiah(_target.text);
    if (targetAmount < widget.goal.currentAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nominal target tidak boleh lebih kecil dari dana yang sudah terkumpul (${formatRupiahInput(widget.goal.currentAmount.toString())}).',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    await getIt<SaveGoal>()(
      GoalEntity(
        id: widget.goal.id,
        householdId: widget.goal.householdId,
        name: _name.text.trim(),
        targetAmount: targetAmount,
        currentAmount: widget.goal.currentAmount,
        targetDate: _targetDate,
        categoryId: widget.goal.categoryId,
        isActive: widget.goal.isActive,
        createdAt: widget.goal.createdAt,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => FfmAssistantPageContext(
    destination: FfmAssistantDestination.goals,
    child: Scaffold(
      appBar: AppBar(title: const Text('Ubah target')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            AppHelpBanner(
              title: 'Saldo target tetap terlindungi',
              message:
                  'Perubahan ini hanya memperbarui nama, batas nominal, atau batas waktu. Dana terkumpul ${formatRupiahInput(widget.goal.currentAmount.toString())} tidak dapat diubah dari halaman ini.',
              icon: Icons.lock_outline,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Nama target'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Nama target wajib diisi.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _target,
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Nominal target',
                prefixText: 'Rp ',
              ),
              validator: (value) {
                final amount = parseRupiah(value ?? '');
                if (amount <= 0) return 'Nominal target harus lebih dari nol.';
                if (amount < widget.goal.currentAmount) {
                  return 'Tidak boleh kurang dari dana terkumpul.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Batas waktu'),
              subtitle: HijriDateText(date: _targetDate, compact: true),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: _pickTargetDate,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Menyimpan…' : 'Simpan perubahan'),
            ),
          ],
        ),
      ),
    ),
  );
}

class GoalFormPage extends StatefulWidget {
  const GoalFormPage({
    super.key,
    this.initialName,
    this.initialTargetAmount,
    this.initialTargetDate,
  });

  final String? initialName;
  final int? initialTargetAmount;
  final DateTime? initialTargetDate;
  @override
  State<GoalFormPage> createState() => _GoalFormPageState();
}

class _GoalFormPageState extends State<GoalFormPage> {
  late final TextEditingController _name;
  late final TextEditingController _target;
  late DateTime _targetDate;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName ?? '');
    _target = TextEditingController(
      text: widget.initialTargetAmount == null
          ? ''
          : formatRupiahInput(widget.initialTargetAmount.toString()),
    );
    _targetDate =
        widget.initialTargetDate ??
        DateTime.now().add(const Duration(days: 30));
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseRupiah(_target.text);
    if (_name.text.trim().isEmpty || amount <= 0) return;
    await getIt<SaveGoal>()(
      GoalEntity(
        id: const Uuid().v4(),
        householdId: AppContext.householdId,
        name: _name.text.trim(),
        targetAmount: amount,
        currentAmount: 0,
        targetDate: _targetDate,
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => FfmAssistantPageContext(
    destination: FfmAssistantDestination.goals,
    child: Scaffold(
      appBar: AppBar(title: const Text('Tambah target')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AppHelpBanner(
            title: 'Target itu buat apa?',
            message: 'Target membantu memantau uang yang ingin dikumpulkan. Pengisian saldonya tetap dicatat lewat transaksi.',
            icon: Icons.flag_outlined,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nama target'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _target,
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
            decoration: const InputDecoration(labelText: 'Nominal target'),
          ),
          const SizedBox(height: 12),
          ListTile(
            title: const Text('Batas waktu'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_targetDate.day}/${_targetDate.month}/${_targetDate.year}',
                ),
                HijriDateLabel(date: _targetDate),
              ],
            ),
            trailing: const Icon(Icons.calendar_month_outlined),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                firstDate: DateTime.now(),
                lastDate: DateTime(2100),
                initialDate: _targetDate,
                cancelText: 'Batal',
                confirmText: 'Pilih',
              );
              if (date != null) setState(() => _targetDate = date);
            },
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Simpan target'),
          ),
        ],
      ),
    ),
  );
}
