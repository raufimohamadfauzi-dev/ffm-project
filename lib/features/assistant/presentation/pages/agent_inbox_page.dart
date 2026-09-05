import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../data/ffm_assistant_insight_repository.dart';
import '../../domain/autonomous_evaluation_coordinator.dart';
import '../../domain/entities/autonomous_activity_models.dart';
import '../../domain/ffm_assistant_insight.dart';
import '../../domain/ffm_assistant_models.dart';
import '../../domain/ffm_proactive_delivery_policy.dart';
import '../../data/autonomous_activity_repository.dart';
import '../widgets/autonomous_activity_dialogs.dart';
import '../widgets/proactive_settings_dialog.dart';
import '../widgets/ffm_assistant_page_context.dart';

class AgentInboxPage extends StatefulWidget {
  final AutonomousActivityRepository? activityRepository;
  const AgentInboxPage({super.key, this.activityRepository});

  @override
  State<AgentInboxPage> createState() => _AgentInboxPageState();
}

class _AgentInboxPageState extends State<AgentInboxPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  late final FfmAssistantInsightRepository _repository;
  AutonomousActivityRepository? _activityRepository;
  bool _loading = true;
  String? _errorMessage;
  List<FfmAssistantInsight> _activeInsights = const [];
  List<FfmAssistantInsight> _historyInsights = const [];
  List<AutonomousActivityRecord> _activities = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    _repository = FfmAssistantInsightRepository(getIt<AppDatabase>());
    _activityRepository = widget.activityRepository ??
        (getIt.isRegistered<AutonomousActivityRepository>()
            ? getIt<AutonomousActivityRepository>()
            : null);
    _loadInsights();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh data ringan saat user kembali ke aplikasi tanpa evaluasi berat berulang
      _loadInsights(evaluate: false);
    }
  }

  Future<void> _loadInsights({bool evaluate = false}) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
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
      final activities = _activityRepository != null
          ? await _activityRepository!.getRecentActivities(
              AppContext.householdId,
            )
          : <AutonomousActivityRecord>[];

      if (!mounted) return;
      setState(() {
        _activeInsights = active;
        _historyInsights = history;
        _activities = activities;
        _loading = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Gagal memuat insight: $error';
      });
    }
  }

  void _handleNavigate(FfmAssistantDestination? destination) {
    if (destination == null) return;
    Navigator.of(context).pop(destination);
  }

  Future<void> _handleAction(FfmAssistantInsight insight) async {
    // Jika insight memiliki usulan mutasi/payload, tampilkan preview dan konfirmasi eksplisit
    if (insight.actionPayload != null && insight.actionPayload!.isNotEmpty) {
      final payload = insight.actionPayload!;
      final isRebalance = payload['type'] == 'envelope_transfer';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: Text(insight.suggestedAction ?? 'Konfirmasi Tindakan Asisten'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(insight.summary),
              if (isRebalance) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(dialogCtx).colorScheme.primaryContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Theme.of(dialogCtx).colorScheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.swap_horiz_rounded, color: Theme.of(dialogCtx).colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Detail Pergeseran Saldo',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(dialogCtx).colorScheme.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('• Dari: ${payload['fromBudgetName'] ?? 'Pos Sumber'}'),
                      Text('• Ke: ${payload['toBudgetName'] ?? 'Pos Target'}'),
                      Text('• Nominal: Rp ${payload['amount']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(dialogCtx)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Tindakan ini hanya akan dijalankan dengan persetujuan Anda. Tidak ada data yang diubah otomatis di background.',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(isRebalance ? 'Terapkan Sekarang' : 'Lanjutkan'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      if (isRebalance) {
        final db = getIt<AppDatabase>();
        final now = DateTime.now();
        final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
        final transferId = const Uuid().v4();
        await db.into(db.envelopeTransfers).insert(
          EnvelopeTransfersCompanion.insert(
            id: transferId,
            householdId: AppContext.householdId,
            month: Value(monthKey),
            fromEnvelopeId: payload['fromEnvelopeId'].toString(),
            toEnvelopeId: payload['toEnvelopeId'].toString(),
            amount: (payload['amount'] as num).toInt(),
            note: const Value('Penyeimbangan anggaran otonom (Zero-Sum)'),
            createdAt: now,
          ),
        );
        if (_activityRepository != null) {
          await _activityRepository!.recordActivity(
            AutonomousActivityRecord(
              id: const Uuid().v4(),
              householdId: AppContext.householdId,
              title: 'Pergeseran Plafon Anggaran (Rebalance)',
              description:
                  'Menggeser Rp ${payload['amount']} dari ${payload['fromBudgetName']} ke ${payload['toBudgetName']}.',
              activityType: AutonomousActivityType.envelopeRebalance,
              occurredAt: now,
              payload: {
                'transferId': transferId,
                'amount': payload['amount'],
                'fromEnvelopeId': payload['fromEnvelopeId'],
                'toEnvelopeId': payload['toEnvelopeId'],
              },
            ),
          );
        }
        await _markActed(insight.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pergeseran anggaran Rp ${payload['amount']} berhasil diterapkan!',
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await _markActed(insight.id);
    }
    _handleNavigate(insight.destination);
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

    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.agentInbox,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Laporan & Kotak Masuk Asisten'),
          actions: [
            IconButton(
              tooltip: 'Pengaturan Wawasan',
              onPressed: () => ProactiveSettingsDialog.show(
                context,
                getIt<FfmProactiveDeliveryPolicy>(),
              ),
              icon: const Icon(Icons.tune_rounded),
            ),
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
                text: 'Aktivitas Otonom (${_activities.length})',
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
                  _buildAutonomousActivityList(theme),
                  _buildHistoryList(theme),
                ],
              ),
      ),
    );
  }

  Widget _buildActiveList(ThemeData theme) {
    if (_errorMessage != null && _activeInsights.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.orange),
              const SizedBox(height: 12),
              Text(
                'Belum Berhasil Memuat Data',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => _loadInsights(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }

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
            onTapAction: () => _handleAction(insight),
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

  Widget _buildAutonomousActivityList(ThemeData theme) {
    if (_activities.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadInsights(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 60),
            AppEmptyState(
              icon: Icons.smart_toy_outlined,
              title: 'Belum Ada Aktivitas Otonom',
              message:
                  'Aktivitas otomatis seperti pembacaan struk PLN/BBM, penyesuaian jadwal panen, dan pergeseran anggaran akan tercatat di sini.',
            ),
          ],
        ),
      );
    }

    final isDark = theme.brightness == Brightness.dark;
    return RefreshIndicator(
      onRefresh: () => _loadInsights(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        itemCount: _activities.length,
        itemBuilder: (context, index) {
          final activity = _activities[index];
          return _buildActivityCard(activity, theme, isDark);
        },
      ),
    );
  }

  Widget _buildActivityCard(
    AutonomousActivityRecord activity,
    ThemeData theme,
    bool isDark,
  ) {
    final (icon, iconColor, iconBg) = switch (activity.activityType) {
      AutonomousActivityType.utilityMeter => (
        Icons.bolt_rounded,
        Colors.amber.shade800,
        Colors.amber.withValues(alpha: 0.15),
      ),
      AutonomousActivityType.fuelLog => (
        Icons.local_gas_station_rounded,
        Colors.deepOrange,
        Colors.deepOrange.withValues(alpha: 0.15),
      ),
      AutonomousActivityType.envelopeRebalance => (
        Icons.swap_horiz_rounded,
        Colors.purple,
        Colors.purple.withValues(alpha: 0.15),
      ),
      AutonomousActivityType.harvestShift => (
        Icons.agriculture_rounded,
        Colors.green.shade700,
        Colors.green.withValues(alpha: 0.15),
      ),
      AutonomousActivityType.habitDeclaration => (
        Icons.auto_awesome_rounded,
        Colors.teal,
        Colors.teal.withValues(alpha: 0.15),
      ),
    };

    final (statusLabel, statusColor, statusBg) = switch (activity.status) {
      AutonomousActivityStatus.active => (
        'Aktif',
        Colors.green.shade800,
        Colors.green.withValues(alpha: 0.15),
      ),
      AutonomousActivityStatus.corrected => (
        'Telah Dikoreksi',
        Colors.blue.shade800,
        Colors.blue.withValues(alpha: 0.15),
      ),
      AutonomousActivityStatus.reverted => (
        'Dibatalkan',
        Colors.red.shade800,
        Colors.red.withValues(alpha: 0.15),
      ),
    };

    final dateStr =
        '${activity.occurredAt.day.toString().padLeft(2, '0')}/${activity.occurredAt.month.toString().padLeft(2, '0')}/${activity.occurredAt.year} ${activity.occurredAt.hour.toString().padLeft(2, '0')}:${activity.occurredAt.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              activity.description,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[300] : Colors.grey[800],
                decoration: activity.status == AutonomousActivityStatus.reverted
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
            if (activity.status == AutonomousActivityStatus.active) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _handleCorrectActivity(activity),
                    icon: const Icon(Icons.edit_note_rounded, size: 16),
                    label: const Text('Koreksi'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _handleRevertActivity(activity),
                    icon: const Icon(Icons.undo_rounded, size: 16),
                    label: const Text('Batalkan'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _handleRevertActivity(AutonomousActivityRecord activity) async {
    if (_activityRepository == null) return;
    final confirmed = await showRevertActivityDialog(
      context: context,
      activity: activity,
    );
    if (confirmed != true || !mounted) return;
    final ok = await _activityRepository!.revertActivity(
      householdId: AppContext.householdId,
      activityId: activity.id,
    );
    if (!mounted) return;
    if (ok) {
      await _loadInsights();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aksi otonom berhasil dibatalkan.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleCorrectActivity(AutonomousActivityRecord activity) async {
    if (_activityRepository == null) return;
    final result = await showEditActivityDialog(
      context: context,
      activity: activity,
    );
    if (result == null || !mounted) return;
    final ok = await _activityRepository!.correctActivity(
      householdId: AppContext.householdId,
      activityId: activity.id,
      newTitle: result['title'],
      newDescription: result['description'],
    );
    if (!mounted) return;
    if (ok) {
      await _loadInsights();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data otonom berhasil dikoreksi.'),
          backgroundColor: Color(0xFF00A876),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
