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
                );
              }).toList(),
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
