import 'package:flutter/material.dart';

import '../../../domain/ffm_assistant_action_plan.dart';
import '../../../domain/ffm_assistant_budget_habit_proposal.dart';

class FfmBudgetHabitProposalPreview extends StatefulWidget {
  const FfmBudgetHabitProposalPreview({
    super.key,
    required this.proposal,
    required this.actionPlan,
    required this.onConfirm,
    required this.onCancel,
    this.onNextBatch,
    this.batchNumber = 1,
    this.totalBatches = 1,
    this.completedBatchCount = 0,
    this.cancelled = false,
  });

  final FfmAssistantBudgetHabitProposal proposal;
  final FfmAssistantActionPlan? actionPlan;
  final ValueChanged<List<FfmAssistantBudgetHabitProposalItem>>? onConfirm;
  final VoidCallback? onCancel;
  final VoidCallback? onNextBatch;
  final int batchNumber;
  final int totalBatches;
  final int completedBatchCount;
  final bool cancelled;

  @override
  State<FfmBudgetHabitProposalPreview> createState() =>
      _FfmBudgetHabitProposalPreviewState();

  static String _rupiah(Object? value) {
    final amount = value is num ? value.round() : int.tryParse('$value');
    if (amount == null) return '$value';
    return 'Rp${amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (match) => '${match[1]}.')}';
  }

  static String _cadence(FfmAssistantBudgetHabitCadence? cadence) =>
      switch (cadence) {
        FfmAssistantBudgetHabitCadence.weekly => 'Mingguan',
        FfmAssistantBudgetHabitCadence.monthly => 'Bulanan',
        null => 'Periode belum valid',
      };
}

class _FfmBudgetHabitProposalPreviewState
    extends State<FfmBudgetHabitProposalPreview> {
  late Set<String> _selectedItemKeys;
  late Map<String, int> _amounts;

  @override
  void initState() {
    super.initState();
    _selectedItemKeys = _itemsForPlan().map(_itemKey).toSet();
    _amounts = {
      for (final item in _itemsForPlan()) _itemKey(item): item.amount,
    };
  }

  @override
  void didUpdateWidget(covariant FfmBudgetHabitProposalPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actionPlan?.id != widget.actionPlan?.id ||
        oldWidget.proposal != widget.proposal) {
      _selectedItemKeys = _itemsForPlan().map(_itemKey).toSet();
      _amounts = {
        for (final item in _itemsForPlan()) _itemKey(item): item.amount,
      };
    }
  }

  String _itemKey(FfmAssistantBudgetHabitProposalItem item) =>
      '${item.categoryId}|${item.cadence?.periodType}';

  List<FfmAssistantBudgetHabitProposalItem> _itemsForPlan() {
    final plan = widget.actionPlan;
    if (plan == null) return widget.proposal.items;
    final plannedKeys = plan.steps
        .where((step) => step.capabilityId == 'draft.budget')
        .map(
          (step) =>
              '${step.parameters['categoryId']}|${step.parameters['periodType']}',
        )
        .toSet();
    return widget.proposal.items
        .where((item) => plannedKeys.contains(_itemKey(item)))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visibleItems = _itemsForPlan();
    final selectedItems = visibleItems
        .where((item) => _selectedItemKeys.contains(_itemKey(item)))
        .map(
          (item) => FfmAssistantBudgetHabitProposalItem(
            categoryId: item.categoryId,
            categoryName: item.categoryName,
            cadence: item.cadence,
            amount: _amounts[_itemKey(item)] ?? item.amount,
            analysisFacts: item.analysisFacts,
          ),
        )
        .toList(growable: false);
    final executing =
        widget.actionPlan?.status == FfmAssistantActionPlanStatus.executing;
    final terminal = widget.actionPlan?.isTerminal ?? false;
    final completed =
        widget.actionPlan?.status == FfmAssistantActionPlanStatus.completed;
    final failed =
        widget.actionPlan?.status == FfmAssistantActionPlanStatus.failed ||
        widget.actionPlan?.status == FfmAssistantActionPlanStatus.blocked ||
        widget.actionPlan?.status ==
            FfmAssistantActionPlanStatus.blockedByBudget;
    final isCancelled =
        widget.cancelled ||
        widget.actionPlan?.status == FfmAssistantActionPlanStatus.cancelled;
    final isLastBatch = widget.batchNumber >= widget.totalBatches;
    final hasMoreBatches = !isLastBatch && widget.totalBatches > 1;
    final summaryTotal = selectedItems.fold<int>(0, (sum, i) => sum + i.amount);
    final completedItemCount = widget.completedBatchCount * visibleItems.length;
    final pendingItemCount =
        (widget.proposal.items.length -
                visibleItems.length -
                completedItemCount)
            .clamp(0, widget.proposal.items.length);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 7),
              Text(
                'Proposal anggaran kebiasaan',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isCancelled
                ? 'Proposal dibatalkan. Tidak ada anggaran yang disimpan.'
                : failed
                ? 'Proposal belum tersimpan. Proses tidak dapat diselesaikan.'
                : completed
                ? isLastBatch
                      ? 'Semua kategori sudah ditinjau.'
                      : 'Batch $widget.batchNumber dari $widget.totalBatches berhasil disimpan dan diverifikasi.'
                : 'Belum disimpan. Pilih pos yang ingin disimpan lalu konfirmasi.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          if (widget.totalBatches > 1) ...[
            Text(
              'Batch $widget.batchNumber dari $widget.totalBatches${widget.completedBatchCount > 0 ? ' | $widget.completedBatchCount batch selesai' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
          ],
          for (final item in visibleItems) ...[
            _ProposalItem(
              item: item,
              selected: _selectedItemKeys.contains(_itemKey(item)),
              enabled: !terminal && !isCancelled && !executing,
              amount: _amounts[_itemKey(item)] ?? item.amount,
              onAmountChanged: (amount) =>
                  setState(() => _amounts[_itemKey(item)] = amount),
              onChanged: (selected) => setState(() {
                if (selected) {
                  _selectedItemKeys.add(_itemKey(item));
                } else {
                  _selectedItemKeys.remove(_itemKey(item));
                }
              }),
            ),
            if (item != visibleItems.last) const Divider(height: 16),
          ],
          if (pendingItemCount > 0 && !terminal) ...[
            const SizedBox(height: 8),
            Text(
              '$pendingItemCount pos pada batch berikutnya tetap menunggu peninjauan dan belum akan disimpan.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (!terminal && !isCancelled) ...[
            const SizedBox(height: 10),
            if (selectedItems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Total: ${FfmBudgetHabitProposalPreview._rupiah(summaryTotal)} dari ${selectedItems.length} pos dipilih.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (selectedItems.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Pilih minimal satu pos untuk dapat menyimpan.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Semantics(
                  button: true,
                  label: 'Konfirmasi dan simpan proposal anggaran',
                  child: FilledButton.tonalIcon(
                    onPressed:
                        executing ||
                            selectedItems.isEmpty ||
                            widget.onConfirm == null
                        ? null
                        : () => widget.onConfirm?.call(selectedItems),
                    icon: executing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(
                      executing ? 'Menyimpan...' : 'Konfirmasi & simpan',
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Batalkan proposal anggaran',
                  child: TextButton.icon(
                    onPressed: executing || widget.onCancel == null
                        ? null
                        : widget.onCancel,
                    icon: const Icon(Icons.close_outlined, size: 18),
                    label: const Text('Batalkan'),
                  ),
                ),
              ],
            ),
          ],
          if (terminal && !isCancelled && hasMoreBatches) ...[
            const SizedBox(height: 10),
            Semantics(
              button: true,
              label: 'Lihat batch berikutnya',
              child: FilledButton.tonalIcon(
                onPressed: widget.onNextBatch,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('Lihat batch berikutnya'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProposalItem extends StatelessWidget {
  const _ProposalItem({
    required this.item,
    required this.selected,
    required this.enabled,
    required this.amount,
    required this.onAmountChanged,
    required this.onChanged,
  });

  final FfmAssistantBudgetHabitProposalItem item;
  final bool selected;
  final bool enabled;
  final int amount;
  final ValueChanged<int> onAmountChanged;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final facts = item.analysisFacts.values;
    final historical = <String>[
      if (facts['historicalPeriodCount'] != null)
        '${facts['historicalPeriodCount']} periode selesai',
      if (facts['sampleCount'] != null) '${facts['sampleCount']} bulan aktif',
      if (facts['medianMonthlySpend'] != null)
        'median ${FfmBudgetHabitProposalPreview._rupiah(facts['medianMonthlySpend'])}',
      if (facts['trend'] != null) 'tren ${facts['trend']}',
    ];
    final monthlyTotals = facts['monthlyTotals'];
    return Semantics(
      label: 'Pilih pos anggaran ${item.categoryName}',
      child: Material(
        type: MaterialType.transparency,
        child: CheckboxListTile(
          value: selected,
          onChanged: enabled ? (value) => onChanged(value ?? false) : null,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(
            item.categoryName,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(
                '${FfmBudgetHabitProposalPreview._cadence(item.cadence)}  |  ${FfmBudgetHabitProposalPreview._rupiah(amount)}',
              ),
              if (enabled)
                TextButton.icon(
                  onPressed: () => _editAmount(context),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Ubah nominal'),
                ),
              if (historical.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text('Riwayat: ${historical.join(' | ')}'),
              ],
              if (monthlyTotals is Iterable && monthlyTotals.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Total per bulan: ${monthlyTotals.map(FfmBudgetHabitProposalPreview._rupiah).join(', ')}',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editAmount(BuildContext context) async {
    final controller = TextEditingController(text: amount.toString());
    final updated = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nominal ${item.categoryName}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Nominal (Rp)',
            errorText: null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              if (parsed == null || parsed <= 0) return;
              Navigator.pop(context, parsed);
            },
            child: const Text('Gunakan'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updated != null) onAmountChanged(updated);
  }
}
