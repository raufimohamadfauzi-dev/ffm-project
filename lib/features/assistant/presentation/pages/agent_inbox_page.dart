import 'package:flutter/material.dart';
import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../data/ffm_assistant_insight_repository.dart';
import '../../domain/autonomous_evaluation_coordinator.dart';
import '../../domain/ffm_assistant_insight.dart';
import '../../domain/ffm_assistant_models.dart';

class AgentInboxPage extends StatefulWidget {
  const AgentInboxPage({super.key});

  @override
  State<AgentInboxPage> createState() => _AgentInboxPageState();
}

class _AgentInboxPageState extends State<AgentInboxPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final FfmAssistantInsightRepository _repository;
  bool _loading = true;
  List<FfmAssistantInsight> _activeInsights = const [];
  List<FfmAssistantInsight> _historyInsights = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _repository = FfmAssistantInsightRepository(getIt<AppDatabase>());
    _loadInsights();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInsights({bool evaluate = false}) async {
    setState(() => _loading = true);
    try {
      if (evaluate) {
        final coordinator = AutonomousEvaluationCoordinator(
          database: getIt<AppDatabase>(),
          insightRepository: _repository,
        );
        await coordinator.runEvaluation(householdId: AppContext.householdId);
      }

      final active = await _repository.getActiveInsights(
        householdId: AppContext.householdId,
      );
      final all = await _repository.getAllInsights(
        householdId: AppContext.householdId,
      );
      final history = all
          .where((i) =>
              i.status == FfmAssistantInsightStatus.acted ||
              i.status == FfmAssistantInsightStatus.dismissed ||
              i.status == FfmAssistantInsightStatus.expired)
          .toList();

      if (!mounted) return;
      setState(() {
        _activeInsights = active;
        _historyInsights = history;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _handleNavigate(FfmAssistantDestination? destination) {
    if (destination == null) return;
    Navigator.of(context).pop(destination);
  }

  Future<void> _dismiss(String id) async {
    await _repository.dismiss(id);
    await _loadInsights();
  }

  Future<void> _snooze(String id) async {
    await _repository.snooze(id, const Duration(days: 1));
    await _loadInsights();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Insight ditunda selama 1 hari.')),
    );
  }

  Future<void> _markActed(String id) async {
    await _repository.markActed(id);
    await _loadInsights();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ditandai sudah ditindaklanjuti.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final newCount =
        _activeInsights.where((i) => i.status == FfmAssistantInsightStatus.newInsight).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan & Kotak Masuk Asisten'),
        actions: [
          IconButton(
            tooltip: 'Evaluasi Sekarang',
            onPressed: () => _loadInsights(evaluate: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Aktif'),
                  if (newCount > 0) ...[
                    const SizedBox(width: 8),
                    Badge.count(
                      count: newCount,
                      backgroundColor: theme.colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              text: 'Riwayat (${_historyInsights.length})',
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildActiveList(theme),
                _buildHistoryList(theme),
              ],
            ),
    );
  }

  Widget _buildActiveList(ThemeData theme) {
    if (_activeInsights.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadInsights(evaluate: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 60),
            AppEmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: 'Kotak Masuk Bersih',
              message:
                  'Semua pos dan indikator keuangan keluarga Anda terpantau aman dan terkendali.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadInsights(evaluate: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: _activeInsights.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final insight = _activeInsights[index];
          return _InsightCard(
            insight: insight,
            onTapAction: () => _handleNavigate(insight.destination),
            onDismiss: () => _dismiss(insight.id),
            onSnooze: () => _snooze(insight.id),
            onMarkActed: () => _markActed(insight.id),
          );
        },
      ),
    );
  }

  Widget _buildHistoryList(ThemeData theme) {
    if (_historyInsights.isEmpty) {
      return const Center(
        child: Text('Belum ada riwayat insight terdahulu.'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      itemCount: _historyInsights.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final insight = _historyInsights[index];
        return _InsightCard(
          insight: insight,
          isHistory: true,
          onTapAction: () => _handleNavigate(insight.destination),
          onDismiss: null,
          onSnooze: null,
          onMarkActed: null,
        );
      },
    );
  }
}

class _InsightCard extends StatefulWidget {
  const _InsightCard({
    required this.insight,
    this.isHistory = false,
    required this.onTapAction,
    this.onDismiss,
    this.onSnooze,
    this.onMarkActed,
  });

  final FfmAssistantInsight insight;
  final bool isHistory;
  final VoidCallback onTapAction;
  final VoidCallback? onDismiss;
  final VoidCallback? onSnooze;
  final VoidCallback? onMarkActed;

  @override
  State<_InsightCard> createState() => _InsightCardState();
}

class _InsightCardState extends State<_InsightCard> {
  bool _expanded = false;

  Color _severityColor(FfmAssistantInsightSeverity severity, ThemeData theme) {
    return switch (severity) {
      FfmAssistantInsightSeverity.critical => theme.colorScheme.error,
      FfmAssistantInsightSeverity.warning => Colors.orange.shade700,
      FfmAssistantInsightSeverity.caution => Colors.amber.shade800,
      FfmAssistantInsightSeverity.info => theme.colorScheme.primary,
    };
  }

  IconData _typeIcon(FfmAssistantInsightType type) {
    return switch (type) {
      FfmAssistantInsightType.runwayRisk => Icons.trending_down_rounded,
      FfmAssistantInsightType.envelopeRebalance => Icons.swap_horiz_rounded,
      FfmAssistantInsightType.anomalySpike => Icons.warning_amber_rounded,
      FfmAssistantInsightType.microExpenseLeak => Icons.receipt_long_rounded,
      FfmAssistantInsightType.debtServiceRatio => Icons.account_balance_rounded,
      FfmAssistantInsightType.goalProgressRisk => Icons.flag_rounded,
      FfmAssistantInsightType.budgetAlert => Icons.pie_chart_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insight = widget.insight;
    final color = _severityColor(insight.severity, theme);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: widget.isHistory ? theme.dividerColor : color.withValues(alpha: 0.5),
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_typeIcon(insight.type), color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        insight.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Prioritas: ${insight.priority}/100 • Keyakinan: ${(insight.confidence * 100).round()}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.isHistory)
                  PopupMenuButton<String>(
                    tooltip: 'Opsi Insight',
                    onSelected: (value) {
                      switch (value) {
                        case 'snooze':
                          widget.onSnooze?.call();
                        case 'dismiss':
                          widget.onDismiss?.call();
                        case 'acted':
                          widget.onMarkActed?.call();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'acted',
                        child: Text('Tandai Selesai'),
                      ),
                      const PopupMenuItem(
                        value: 'snooze',
                        child: Text('Tunda 1 Hari'),
                      ),
                      const PopupMenuItem(
                        value: 'dismiss',
                        child: Text('Abaikan'),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              insight.summary,
              style: theme.textTheme.bodyMedium,
            ),
            if (insight.evidence.isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _expanded ? 'Sembunyikan data pendukung' : 'Lihat data pendukung',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
              if (_expanded)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: insight.evidence.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${entry.key}: ',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                entry.value.toString(),
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
            if (insight.suggestedAction != null) ...[
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: widget.onTapAction,
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: Text(insight.suggestedAction!),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
