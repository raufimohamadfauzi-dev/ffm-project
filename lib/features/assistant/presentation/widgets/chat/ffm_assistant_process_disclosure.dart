import 'package:flutter/material.dart';

import '../../../domain/ffm_assistant_action_plan.dart';
import '../../../domain/ffm_assistant_models.dart';

class FfmAssistantProcessDisclosure extends StatefulWidget {
  const FfmAssistantProcessDisclosure({
    super.key,
    required this.trace,
    this.actionPlan,
  });

  final FfmAssistantProcessTrace trace;
  final FfmAssistantActionPlan? actionPlan;

  @override
  State<FfmAssistantProcessDisclosure> createState() =>
      _FfmAssistantProcessDisclosureState();
}

class _FfmAssistantProcessDisclosureState
    extends State<FfmAssistantProcessDisclosure> {
  var _expanded = false;

  ({String label, IconData icon, Color color}) get _origin =>
      switch (widget.trace.origin) {
        FfmAssistantResponseOrigin.agentOrchestrator => (
          label: 'Data lokal FFM',
          icon: Icons.account_tree_outlined,
          color: const Color(0xFF00727A),
        ),
        FfmAssistantResponseOrigin.localSlm => (
          label: 'Agent lokal',
          icon: Icons.auto_awesome_outlined,
          color: const Color(0xFF3B6EC4),
        ),
        FfmAssistantResponseOrigin.localFallback => (
          label: 'Agent fallback deterministik',
          icon: Icons.info_outline,
          color: const Color(0xFF9A5B00),
        ),
        FfmAssistantResponseOrigin.geminiCloud => (
          label: 'Gemini Cloud',
          icon: Icons.cloud_done_outlined,
          color: const Color(0xFF2E7D32),
        ),
        FfmAssistantResponseOrigin.cloudError => (
          label: 'Gemini Cloud gagal',
          icon: Icons.cloud_off_outlined,
          color: const Color(0xFFC62828),
        ),
      };

  String get _duration {
    final milliseconds = widget.trace.elapsed.inMilliseconds;
    if (milliseconds < 1000) return '$milliseconds ms';
    return '${(milliseconds / 1000).toStringAsFixed(2)} dtk';
  }

  String _eventTime(Duration elapsed) {
    final milliseconds = elapsed.inMilliseconds;
    return milliseconds < 1000
        ? 'T+$milliseconds ms'
        : 'T+${(milliseconds / 1000).toStringAsFixed(2)} dtk';
  }

  String _capabilityLabel(String capabilityId) => switch (capabilityId) {
    'read.summary' => 'Membaca ringkasan transaksi',
    'read.transactions' => 'Membaca transaksi terbaru',
    'read.budget' => 'Memeriksa anggaran',
    'read.activity' => 'Membaca aktivitas',
    'read.accounts' => 'Memeriksa rekening dan saldo',
    'read.categories' => 'Memeriksa daftar kategori',
    'read.goals' => 'Memeriksa target keuangan',
    'read.model_status' => 'Memeriksa status Assistant',
    'navigate.budget' => 'Membuka halaman Anggaran',
    'navigate.categories' => 'Membuka halaman Kategori',
    'navigate.accounts' => 'Membuka halaman Rekening',
    'navigate.tags' => 'Membuka halaman Tag',
    'navigate.merchants' => 'Membuka halaman Toko',
    'navigate.income_sources' => 'Membuka halaman Sumber Pemasukan',
    'transactions' => 'Mencatat transaksi',
    'expense' => 'Menyiapkan pengeluaran',
    'income' => 'Menyiapkan pemasukan',
    'save draft' || 'save_draft' || 'mutate.save_draft' => 'Menyimpan draf',
    'saved draft' || 'saved_draft' || 'verify.saved_draft' => 'Verifikasi draf tersimpan',
    'draft.expense' => 'Menyusun draf pengeluaran',
    'draft.income' => 'Menyusun draf pemasukan',
    'draft.transfer' => 'Menyusun draf transfer',
    'draft.goal' => 'Menyusun draf target keuangan',
    _ =>
      capabilityId
          .replaceFirst(RegExp(r'^(read|draft|mutate|verify|navigate)\.'), '')
          .replaceAll('_', ' '),
  };

  ({IconData icon, Color color, String label}) _stepStyle(
    FfmAssistantActionStepStatus status,
    ColorScheme scheme,
  ) => switch (status) {
    FfmAssistantActionStepStatus.completed => (
      icon: Icons.check_circle_outline,
      color: const Color(0xFF25854A),
      label: 'Selesai',
    ),
    FfmAssistantActionStepStatus.failed => (
      icon: Icons.cancel_outlined,
      color: scheme.error,
      label: 'Gagal',
    ),
    FfmAssistantActionStepStatus.running => (
      icon: Icons.hourglass_top_rounded,
      color: scheme.primary,
      label: 'Berjalan',
    ),
    FfmAssistantActionStepStatus.skipped => (
      icon: Icons.subdirectory_arrow_right_outlined,
      color: scheme.onSurfaceVariant,
      label: 'Dilewati',
    ),
    FfmAssistantActionStepStatus.pending => (
      icon: Icons.schedule_outlined,
      color: scheme.onSurfaceVariant,
      label: 'Menunggu',
    ),
    FfmAssistantActionStepStatus.blocked => (
      icon: Icons.block_outlined,
      color: scheme.error,
      label: 'Terblokir',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final origin = _origin;
    final plan = widget.actionPlan;
    final isAllPending = plan != null &&
        plan.steps.every((s) => s.status == FfmAssistantActionStepStatus.pending);
    final planSummary = plan == null
        ? '${origin.label} · $_duration'
        : (plan.status == FfmAssistantActionPlanStatus.planned || isAllPending)
        ? 'Menunggu ${plan.steps.length} langkah · perlu konfirmasi'
        : 'Menjalankan ${plan.steps.length} langkah · $_duration';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B2227) : const Color(0xFFEBF1F3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: .08)
              : Colors.black.withValues(alpha: .08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Semantics(
              button: true,
              label:
                  '$planSummary. ${_expanded ? 'Tutup' : 'Buka'} detail proses.',
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(origin.icon, size: 14, color: origin.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        planSummary,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(
              height: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: .08)
                  : Colors.black.withValues(alpha: .08),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final event in widget.trace.events) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _eventTime(event.elapsed),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            event.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (event.detail != null) ...[
                      const SizedBox(height: 2),
                      Text(event.detail!, style: theme.textTheme.bodySmall),
                    ],
                    const SizedBox(height: 8),
                  ],
                  if (plan != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Langkah Action Plan',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final step in plan.steps) ...[
                      Builder(
                        builder: (context) {
                          final style = _stepStyle(
                            step.status,
                            theme.colorScheme,
                          );
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(style.icon, size: 17, color: style.color),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _capabilityLabel(step.capabilityId),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                style.label,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: style.color,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 7),
                    ],
                  ],
                  if (widget.trace.fallbackReason != null)
                    Text(
                      'Alasan fallback: ${widget.trace.fallbackReason}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
