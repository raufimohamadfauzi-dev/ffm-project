import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../data/services/reminder_notification_service.dart';
import '../../data/services/reminder_sound_picker.dart';
import '../../domain/entities/reminder_entity.dart';
import '../bloc/reminder_bloc.dart';

class ReminderPage extends StatelessWidget {
  const ReminderPage({
    super.key,
    this.initialTitle,
    this.initialNote,
    this.initialScheduledAt,
    this.initialRecurrence,
    this.initialMode,
    this.initialSourceType,
    this.initialSourceId,
    this.initialSoundUri,
    this.initialSoundName,
    this.initialWeekdays,
    this.focusReminderId,
    this.focusHistoryId,
  });

  final String? initialTitle;
  final String? initialNote;

  /// Pre-fill the scheduled date/time from an assistant draft (item 29).
  final DateTime? initialScheduledAt;
  final ReminderRecurrenceType? initialRecurrence;
  final ReminderMode? initialMode;
  final ReminderSourceType? initialSourceType;
  final String? initialSourceId;
  final String? initialSoundUri;
  final String? initialSoundName;
  final List<int>? initialWeekdays;
  final String? focusReminderId;
  final String? focusHistoryId;

  @override
  Widget build(BuildContext context) {
    final bloc = getIt<ReminderBloc>()..add(const ReminderLoadRequested());
    return BlocProvider.value(
      value: bloc,
      child: BlocBuilder<ReminderBloc, ReminderState>(
        builder: (context, state) {
          final activeCount = state.reminders.where((r) => r.isActive).length;
          final summary =
              'Ada ${state.reminders.length} pengingat terdaftar, $activeCount aktif.';

          return FfmAssistantPageContext(
            destination: FfmAssistantDestination.reminders,
            dataSummary: summary,
            child: _ReminderView(
              initialTitle: initialTitle,
              initialNote: initialNote,
              initialScheduledAt: initialScheduledAt,
              initialRecurrence: initialRecurrence,
              initialMode: initialMode,
              initialSourceType: initialSourceType,
              initialSourceId: initialSourceId,
              initialSoundUri: initialSoundUri,
              initialSoundName: initialSoundName,
              initialWeekdays: initialWeekdays,
              focusReminderId: focusReminderId,
              focusHistoryId: focusHistoryId,
            ),
          );
        },
      ),
    );
  }
}

class _ReminderView extends StatefulWidget {
  const _ReminderView({
    this.initialTitle,
    this.initialNote,
    this.initialScheduledAt,
    this.initialRecurrence,
    this.initialMode,
    this.initialSourceType,
    this.initialSourceId,
    this.initialSoundUri,
    this.initialSoundName,
    this.initialWeekdays,
    this.focusReminderId,
    this.focusHistoryId,
  });

  final String? initialTitle;
  final String? initialNote;
  final DateTime? initialScheduledAt;
  final ReminderRecurrenceType? initialRecurrence;
  final ReminderMode? initialMode;
  final ReminderSourceType? initialSourceType;
  final String? initialSourceId;
  final String? initialSoundUri;
  final String? initialSoundName;
  final List<int>? initialWeekdays;
  final String? focusReminderId;
  final String? focusHistoryId;

  @override
  State<_ReminderView> createState() => _ReminderViewState();
}

class _ReminderViewState extends State<_ReminderView> {
  ReminderHistoryStatus? _historyFilter;
  ReminderOrigin? _originFilter;
  String? _lastNotifiedPendingHistoryId;
  final _focusedHistoryKey = GlobalKey();
  var _focusAttempted = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialTitle?.trim().isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openDialog(
            context,
            initialTitle: widget.initialTitle,
            initialNote: widget.initialNote,
            initialScheduledAt: widget.initialScheduledAt,
            initialRecurrence: widget.initialRecurrence,
            initialMode: widget.initialMode,
            initialSourceType: widget.initialSourceType,
            initialSourceId: widget.initialSourceId,
            initialSoundUri: widget.initialSoundUri,
            initialSoundName: widget.initialSoundName,
            initialWeekdays: widget.initialWeekdays,
          );
        }
      });
    }
  }

  Future<void> _openDialog(
    BuildContext context, {
    ReminderEntity? initial,
    String? initialTitle,
    String? initialNote,
    DateTime? initialScheduledAt,
    ReminderRecurrenceType? initialRecurrence,
    ReminderMode? initialMode,
    ReminderSourceType? initialSourceType,
    String? initialSourceId,
    String? initialSoundUri,
    String? initialSoundName,
    List<int>? initialWeekdays,
  }) async {
    final reminder = await showDialog<ReminderEntity>(
      context: context,
      builder: (_) => _ReminderDialog(
        initial: initial,
        initialTitle: initialTitle,
        initialNote: initialNote,
        initialScheduledAt: initialScheduledAt,
        initialRecurrence: initialRecurrence,
        initialMode: initialMode ?? widget.initialMode,
        initialSourceType: initialSourceType,
        initialSourceId: initialSourceId,
        initialSoundUri: initialSoundUri,
        initialSoundName: initialSoundName,
        initialWeekdays: initialWeekdays,
      ),
    );
    if (reminder != null && context.mounted) {
      context.read<ReminderBloc>().add(ReminderSaved(reminder));
    }
  }

  void _notifyPendingHistory(ReminderState state) {
    final pending = state.history
        .where(
          (item) =>
              item.history.status == ReminderHistoryStatus.pending &&
              item.history.triggeredAt != null,
        )
        .firstOrNull;
    if (pending == null ||
        pending.history.id == _lastNotifiedPendingHistoryId) {
      return;
    }
    _lastNotifiedPendingHistoryId = pending.history.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Alarm masuk ke riwayat. Pilih Selesai atau Tunda 10 menit.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  void _revealNotificationTarget(ReminderState state) {
    final historyId = widget.focusHistoryId;
    if (historyId == null || _focusAttempted) return;
    final exists = state.history.any(
      (item) =>
          item.history.id == historyId &&
          item.history.reminderId == widget.focusReminderId,
    );
    if (!exists) return;
    _focusAttempted = true;
    _lastNotifiedPendingHistoryId = historyId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = _focusedHistoryKey.currentContext;
      if (mounted && targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: .32,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Pengingat'),
        bottom: const TabBar(
          tabs: [
            Tab(
              icon: Icon(Icons.notifications_active_outlined),
              text: 'Jadwal Aktif',
            ),
            Tab(icon: Icon(Icons.history_rounded), text: 'Riwayat Pengingat'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'reminder_add_fab',
        onPressed: () => _openDialog(context),
        icon: const Icon(Icons.add_alert_outlined),
        label: const Text('Tambah'),
      ),
      body: BlocConsumer<ReminderBloc, ReminderState>(
        listener: (context, state) {
          _notifyPendingHistory(state);
          _revealNotificationTarget(state);
          final message = state.errorMessage;
          if (message != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(message)));
          }
        },
        builder: (context, state) {
          if (state.isLoading && state.reminders.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final history = _historyFilter == null
              ? state.history
              : state.history
                    .where((item) => item.history.status == _historyFilter)
                    .toList(growable: false);

          final rawReminders = _originFilter == null
              ? state.reminders
              : state.reminders
                    .where((item) => item.origin == _originFilter)
                    .toList(growable: false);

          final now = DateTime.now();
          final reminders = List<ReminderEntity>.from(rawReminders)
            ..sort((a, b) {
              final aIsPastDue =
                  a.recurrenceType == ReminderRecurrenceType.once &&
                  a.scheduledAt.isBefore(now);
              final bIsPastDue =
                  b.recurrenceType == ReminderRecurrenceType.once &&
                  b.scheduledAt.isBefore(now);
              final aIsUpcoming = a.isActive && !aIsPastDue;
              final bIsUpcoming = b.isActive && !bIsPastDue;

              if (aIsUpcoming && !bIsUpcoming) return -1;
              if (!aIsUpcoming && bIsUpcoming) return 1;

              if (aIsUpcoming && bIsUpcoming) {
                return a.scheduledAt.compareTo(b.scheduledAt);
              } else {
                return b.scheduledAt.compareTo(a.scheduledAt);
              }
            });

          return TabBarView(
            children: [
              // Tab 1: Jadwal Aktif
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  if (state.permissionState != null &&
                      !state.permissionState!.canSchedule)
                    _PermissionBanner(
                      notificationsEnabled:
                          state.permissionState!.notificationsEnabled,
                      exactAlarmEnabled:
                          state.permissionState!.exactAlarmEnabled,
                    ),
                  Text(
                    'Jadwal pengingat',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      FilterChip(
                        label: const Text('Semua'),
                        selected: _originFilter == null,
                        onSelected: (_) => setState(() => _originFilter = null),
                      ),
                      FilterChip(
                        label: const Text('Otonom'),
                        selected: _originFilter == ReminderOrigin.autonomous,
                        onSelected: (_) => setState(
                          () => _originFilter = ReminderOrigin.autonomous,
                        ),
                      ),
                      FilterChip(
                        label: const Text('Saya'),
                        selected: _originFilter == ReminderOrigin.user,
                        onSelected: (_) =>
                            setState(() => _originFilter = ReminderOrigin.user),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (reminders.isEmpty)
                    AppEmptyState(
                      icon: Icons.notifications_none_outlined,
                      title: 'Belum ada jadwal pengingat',
                      message: 'Tambahkan jadwal pengingat untuk mengelola keuangan dan tugas Anda.',
                      action: FilledButton.icon(
                        onPressed: () => _openDialog(context),
                        icon: const Icon(Icons.add_alert_outlined),
                        label: const Text('Tambah pengingat'),
                      ),
                    )
                  else
                    ...reminders.map(
                      (reminder) => ReminderScheduleCard(
                        reminder: reminder,
                        onTap: () => _openDialog(context, initial: reminder),
                        onActiveChanged: (value) => context
                            .read<ReminderBloc>()
                            .add(ReminderActiveChanged(reminder, value)),
                        onEdit: () => _openDialog(context, initial: reminder),
                        onDelete: () => context.read<ReminderBloc>().add(
                          ReminderDeleted(reminder),
                        ),
                      ),
                    ),
                ],
              ),

              // Tab 2: Riwayat Pengingat
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Riwayat pengingat',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      DropdownButton<ReminderHistoryStatus?>(
                        value: _historyFilter,
                        hint: const Text('Semua Status'),
                        underline: const SizedBox.shrink(),
                        items: [
                          const DropdownMenuItem<ReminderHistoryStatus?>(
                            value: null,
                            child: Text('Semua Status'),
                          ),
                          ...ReminderHistoryStatus.values.map(
                            (status) => DropdownMenuItem(
                              value: status,
                              child: Text(status.label),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _historyFilter = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (history.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: AppEmptyState(
                        icon: Icons.history_toggle_off_rounded,
                        title: 'Riwayat kosong',
                        message: _historyFilter == null
                            ? 'Belum ada riwayat pengingat yang tercatat.'
                            : 'Belum ada riwayat dengan filter status ${_historyFilter!.label}.',
                      ),
                    )
                  else
                    ...history.map((item) {
                      final historyItem = item.history;
                      final reminderMode =
                          item.reminder?.mode ?? ReminderMode.notification;
                      final isActionable =
                          historyItem.status !=
                              ReminderHistoryStatus.completed &&
                          historyItem.status != ReminderHistoryStatus.cancelled;
                      final isMissed =
                          historyItem.status == ReminderHistoryStatus.missed;
                      final isCompleted =
                          historyItem.status == ReminderHistoryStatus.completed;
                      final isHighlighted =
                          historyItem.id == _lastNotifiedPendingHistoryId ||
                          (historyItem.id == widget.focusHistoryId &&
                              historyItem.reminderId == widget.focusReminderId);
                      final colorScheme = Theme.of(context).colorScheme;

                      final subtitle = historyItem.snoozedUntil == null
                          ? '${_formatReminderDateTime(historyItem.scheduledAt)} · ${historyItem.status.label}'
                          : '${_formatReminderDateTime(historyItem.scheduledAt)} · ${historyItem.status.label} sampai ${_formatReminderDateTime(historyItem.snoozedUntil!)}';

                      final cardColor = isMissed
                          ? colorScheme.errorContainer.withAlpha(120)
                          : isCompleted
                          ? colorScheme.surfaceContainerHighest.withAlpha(120)
                          : isHighlighted
                          ? colorScheme.tertiaryContainer
                          : null;

                      return AppCard(
                        key: historyItem.id == widget.focusHistoryId
                            ? _focusedHistoryKey
                            : null,
                        color: cardColor,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _statusIcon(historyItem.status),
                                    color: isMissed
                                        ? colorScheme.error
                                        : isCompleted
                                        ? colorScheme.primary
                                        : null,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                historyItem.title,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: isMissed
                                                      ? colorScheme
                                                            .onErrorContainer
                                                      : null,
                                                ),
                                              ),
                                            ),
                                            if (isMissed) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: colorScheme.error,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  'Terlewat',
                                                  style: TextStyle(
                                                    color: colorScheme.onError,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        Text(subtitle),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    tooltip: 'Aksi riwayat',
                                    onSelected: (value) {
                                      if (value == 'hapus') {
                                        context.read<ReminderBloc>().add(
                                          ReminderHistoryDeleted(historyItem),
                                        );
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'hapus',
                                        child: Text('Hapus dari riwayat'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (isHighlighted) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Pengingat baru masuk. Pilih tindakan di bawah.',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              if (isActionable) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () =>
                                            context.read<ReminderBloc>().add(
                                              ReminderHistoryStatusChanged(
                                                history: historyItem,
                                                status: ReminderHistoryStatus
                                                    .completed,
                                              ),
                                            ),
                                        icon: const Icon(Icons.check_rounded),
                                        label: const Text('Selesai'),
                                      ),
                                    ),
                                    if (reminderMode == ReminderMode.alarm) ...[
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () =>
                                              context.read<ReminderBloc>().add(
                                                ReminderHistoryStatusChanged(
                                                  history: historyItem,
                                                  status: ReminderHistoryStatus
                                                      .snoozed,
                                                  snoozedUntil: DateTime.now()
                                                      .add(
                                                        const Duration(
                                                          minutes: 10,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                          icon: const Icon(
                                            Icons.snooze_rounded,
                                          ),
                                          label: const Text('Tunda 10 mnt'),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );

  static IconData _statusIcon(ReminderHistoryStatus status) => switch (status) {
    ReminderHistoryStatus.completed => Icons.check_circle,
    ReminderHistoryStatus.missed => Icons.warning_amber,
    ReminderHistoryStatus.snoozed => Icons.snooze,
    ReminderHistoryStatus.cancelled => Icons.cancel_outlined,
    ReminderHistoryStatus.pending => Icons.schedule,
  };
}

enum _CountdownStatus { upcoming, pastDue, recurringWait, inactive }

/// Badge penanda asal entitas/pemicu dibuatnya pengingat (Trigger Provenance).
class _ReminderSourceTypeBadge extends StatelessWidget {
  const _ReminderSourceTypeBadge({required this.sourceType});

  final ReminderSourceType sourceType;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (sourceType) {
      ReminderSourceType.diagnostics => (
        Icons.build_circle_outlined,
        'Diagnostik Aplikasi',
        Colors.amber.shade800,
      ),
      ReminderSourceType.liability => (
        Icons.credit_card_outlined,
        'Hutang / Cicilan',
        Colors.red.shade700,
      ),
      ReminderSourceType.receivable => (
        Icons.account_balance_wallet_outlined,
        'Tagihan Piutang',
        Colors.teal.shade700,
      ),
      ReminderSourceType.recurringTransaction => (
        Icons.sync_rounded,
        'Transaksi Rutin',
        Colors.blue.shade700,
      ),
      ReminderSourceType.goal || ReminderSourceType.goalSetup => (
        Icons.flag_outlined,
        'Target Keuangan',
        Colors.green.shade700,
      ),
      ReminderSourceType.activity => (
        Icons.timer_outlined,
        'Aktivitas',
        Colors.indigo.shade700,
      ),
      ReminderSourceType.task => (
        Icons.check_circle_outline,
        'Tugas',
        Colors.orange.shade800,
      ),
      ReminderSourceType.budgetSetup => (
        Icons.pie_chart_outline,
        'Anggaran',
        Colors.cyan.shade800,
      ),
      ReminderSourceType.accountSetup => (
        Icons.account_balance_outlined,
        'Rekening',
        Colors.blueGrey.shade700,
      ),
      ReminderSourceType.cashFlowProfile => (
        Icons.trending_up,
        'Siklus Kas',
        Colors.lightGreen.shade800,
      ),
      ReminderSourceType.telegram => (
        Icons.send_rounded,
        'Telegram',
        Colors.lightBlue.shade700,
      ),
      ReminderSourceType.familyProfile => (
        Icons.family_restroom,
        'Profil Keluarga',
        Colors.purple.shade700,
      ),
      _ => (Icons.info_outline, sourceType.label, colorScheme.primary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(160),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(90), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3.5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 10.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact reminder summary that keeps the title independent from its controls.
class ReminderScheduleCard extends StatelessWidget {
  const ReminderScheduleCard({
    required this.reminder,
    required this.onTap,
    required this.onActiveChanged,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final ReminderEntity reminder;
  final VoidCallback onTap;
  final ValueChanged<bool> onActiveChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isPastDue =
        reminder.recurrenceType == ReminderRecurrenceType.once &&
        reminder.scheduledAt.isBefore(now);
    final isUpcoming =
        reminder.isActive && !isPastDue && !reminder.scheduledAt.isBefore(now);
    final countdownText = _buildReminderCountdownText(
      reminder.scheduledAt,
      reminder.isActive,
      recurrenceType: reminder.recurrenceType,
    );
    final countdownStatus = !reminder.isActive
        ? _CountdownStatus.inactive
        : (isPastDue
              ? _CountdownStatus.pastDue
              : (isUpcoming
                    ? _CountdownStatus.upcoming
                    : _CountdownStatus.recurringWait));

    final cardContent = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  reminder.isActive
                      ? (isPastDue
                            ? Icons.alarm_off_outlined
                            : Icons.notifications_active_outlined)
                      : Icons.notifications_off_outlined,
                  color: reminder.isActive
                      ? (isPastDue ? colorScheme.error : colorScheme.primary)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: isPastDue
                            ? colorScheme.onSurface.withAlpha(190)
                            : colorScheme.onSurface,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Origin Badge with high visual contrast
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  reminder.origin == ReminderOrigin.autonomous
                                  ? (colorScheme.brightness == Brightness.dark
                                        ? Colors.deepPurple.shade900.withAlpha(
                                            190,
                                          )
                                        : Colors.deepPurple.shade50)
                                  : colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color:
                                    reminder.origin == ReminderOrigin.autonomous
                                    ? (colorScheme.brightness == Brightness.dark
                                          ? Colors.purple.shade300.withAlpha(
                                              140,
                                            )
                                          : Colors.deepPurple.shade400)
                                    : colorScheme.outlineVariant,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  reminder.origin == ReminderOrigin.autonomous
                                      ? Icons.auto_awesome
                                      : Icons.person_outline,
                                  size: 12,
                                  color:
                                      reminder.origin ==
                                          ReminderOrigin.autonomous
                                      ? (colorScheme.brightness ==
                                                Brightness.dark
                                            ? Colors.purple.shade200
                                            : Colors.deepPurple.shade800)
                                      : colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  reminder.origin.label,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color:
                                            reminder.origin ==
                                                ReminderOrigin.autonomous
                                            ? (colorScheme.brightness ==
                                                      Brightness.dark
                                                  ? Colors.purple.shade100
                                                  : Colors.deepPurple.shade900)
                                            : colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          // Provenance / Trigger Badge
                          if (reminder.sourceType != null)
                            _ReminderSourceTypeBadge(
                              sourceType: reminder.sourceType!,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatReminderDateTime(reminder.scheduledAt)} · ${reminder.recurrenceType.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    HijriDateLabel(date: reminder.scheduledAt),
                    // Sound indicator
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          Icon(
                            reminder.soundName != null &&
                                    reminder.soundName!.isNotEmpty
                                ? Icons.music_note_rounded
                                : Icons.notifications_none_rounded,
                            size: 13,
                            color:
                                reminder.soundName != null &&
                                    reminder.soundName!.isNotEmpty
                                ? colorScheme.primary
                                : colorScheme.outline,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              reminder.soundName != null &&
                                      reminder.soundName!.isNotEmpty
                                  ? 'Nada: ${reminder.soundName}'
                                  : (reminder.origin ==
                                            ReminderOrigin.autonomous
                                        ? 'Nada: Nada otonom FFM'
                                        : 'Nada: Bawaan FFM'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontSize: 11,
                                    color:
                                        reminder.soundName != null &&
                                            reminder.soundName!.isNotEmpty
                                        ? colorScheme.primary
                                        : colorScheme.outline,
                                    fontWeight:
                                        reminder.soundName != null &&
                                            reminder.soundName!.isNotEmpty
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Explanatory note if present
                    if (reminder.note != null &&
                        reminder.note!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withAlpha(100),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.notes_rounded,
                                size: 13,
                                color: colorScheme.outline,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  reminder.note!.trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 11,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Aksi pengingat',
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit();
                  } else if (value == 'hapus') {
                    onDelete();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'hapus', child: Text('Hapus')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _ReminderCountdownChip(
                    text: countdownText,
                    status: countdownStatus,
                  ),
                ),
              ),
              Semantics(
                label: reminder.isActive
                    ? 'Pengingat aktif'
                    : 'Pengingat nonaktif',
                child: Switch(
                  value: reminder.isActive,
                  onChanged: onActiveChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: isPastDue
          ? Opacity(opacity: 0.72, child: cardContent)
          : cardContent,
    );
  }
}

class _ReminderCountdownChip extends StatelessWidget {
  const _ReminderCountdownChip({required this.text, this.status});

  final String text;
  final _CountdownStatus? status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveStatus = status ?? _CountdownStatus.inactive;

    final (bg, fg, border) = switch (effectiveStatus) {
      _CountdownStatus.pastDue => (
        colorScheme.errorContainer.withAlpha(190),
        colorScheme.onErrorContainer,
        Border.all(color: colorScheme.error.withAlpha(110), width: 0.8),
      ),
      _CountdownStatus.upcoming => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
        null,
      ),
      _CountdownStatus.recurringWait => (
        colorScheme.tertiaryContainer.withAlpha(150),
        colorScheme.onTertiaryContainer,
        null,
      ),
      _CountdownStatus.inactive => (
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
        null,
      ),
    };

    final icon = switch (effectiveStatus) {
      _CountdownStatus.pastDue => Icons.history_rounded,
      _CountdownStatus.upcoming => Icons.hourglass_top_rounded,
      _CountdownStatus.recurringWait => Icons.update_rounded,
      _CountdownStatus.inactive => Icons.pause_circle_outline_rounded,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: border,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}

String _formatReminderDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}

String _buildReminderCountdownText(
  DateTime scheduledAt,
  bool isActive, {
  ReminderRecurrenceType recurrenceType = ReminderRecurrenceType.once,
}) {
  if (!isActive) return 'Nonaktif';
  final now = DateTime.now();
  final diff = scheduledAt.difference(now);
  if (diff.isNegative) {
    if (recurrenceType == ReminderRecurrenceType.once) {
      return 'Waktu sudah lewat';
    }
    return 'Menunggu jadwal berikutnya';
  }
  if (diff.inDays >= 1) {
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    return hours > 0 ? '$days hr $hours jam lagi' : '$days hari lagi';
  }
  if (diff.inHours >= 1) {
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    return minutes > 0 ? '$hours jam $minutes mnt lagi' : '$hours jam lagi';
  }
  if (diff.inMinutes >= 1) return '${diff.inMinutes} mnt lagi';
  return '< 1 mnt lagi';
}

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({
    this.initial,
    this.initialTitle,
    this.initialNote,
    this.initialScheduledAt,
    this.initialRecurrence,
    this.initialMode,
    this.initialSourceType,
    this.initialSourceId,
    this.initialSoundUri,
    this.initialSoundName,
    this.initialWeekdays,
  });

  final ReminderEntity? initial;
  final String? initialTitle;
  final String? initialNote;

  /// Pre-filled schedule coming from an assistant draft (item 29).
  final DateTime? initialScheduledAt;
  final ReminderRecurrenceType? initialRecurrence;
  final ReminderMode? initialMode;
  final ReminderSourceType? initialSourceType;
  final String? initialSourceId;
  final String? initialSoundUri;
  final String? initialSoundName;
  final List<int>? initialWeekdays;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late DateTime _scheduledAt;
  late ReminderRecurrenceType _recurrence;
  late ReminderMode _mode;
  late List<int> _weekday;
  String? _soundUri;
  String? _soundName;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _titleController = TextEditingController(
      text: initial?.title ?? widget.initialTitle ?? '',
    );
    _noteController = TextEditingController(
      text: initial?.note ?? widget.initialNote ?? '',
    );
    // Priority: existing entity scheduledAt > pre-fill from draft > now+1h
    final initialDate = initial?.scheduledAt ?? widget.initialScheduledAt;
    if (initialDate != null) {
      if (initialDate.isBefore(DateTime.now()) && initial == null) {
        final now = DateTime.now();
        var rollover = DateTime(
          now.year,
          now.month,
          now.day,
          initialDate.hour,
          initialDate.minute,
        );
        if (rollover.isBefore(now)) {
          rollover = rollover.add(const Duration(days: 1));
        }
        _scheduledAt = rollover;
      } else {
        _scheduledAt = initialDate;
      }
    } else {
      _scheduledAt = DateTime.now().add(const Duration(hours: 1));
    }
    _recurrence =
        initial?.recurrenceType ??
        widget.initialRecurrence ??
        ReminderRecurrenceType.once;
    _mode = initial?.mode ?? widget.initialMode ?? ReminderMode.notification;
    _weekday = [...?initial?.weekdays, ...?widget.initialWeekdays];
    if (_recurrence == ReminderRecurrenceType.weekly && _weekday.isEmpty) {
      _weekday = [_scheduledAt.weekday];
    }
    _soundUri = initial?.soundUri ?? widget.initialSoundUri;
    _soundName = initial?.soundName ?? widget.initialSoundName;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDate: _scheduledAt.isBefore(DateTime.now())
          ? DateTime.now()
          : _scheduledAt,
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (!mounted || time == null) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _pickSound() async {
    try {
      final selection = await getIt<ReminderSoundPicker>().pick(
        currentUri: _soundUri,
      );
      if (!mounted || selection == null) return;
      setState(() {
        _soundUri = selection.uri;
        _soundName = selection.name;
      });
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nada dering belum bisa dipilih: $error')),
      );
    }
  }

  void _clearSound() {
    setState(() {
      _soundUri = null;
      _soundName = null;
    });
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty || _scheduledAt.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Isi judul dan pilih waktu yang masih akan datang.'),
        ),
      );
      return;
    }
    if (_recurrence == ReminderRecurrenceType.weekly && _weekday.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih minimal satu hari untuk pengulangan mingguan.'),
        ),
      );
      return;
    }
    final initial = widget.initial;
    final id = initial?.id ?? const Uuid().v4();
    // Derive a stable notification id from the reminder UUID so two reminders
    // created in rapid succession never collide (unlike millisecondsSinceEpoch).
    int stableIdFor(String reminderId) {
      var hash = 2166136261;
      for (final codeUnit in reminderId.codeUnits) {
        hash = (hash ^ codeUnit) * 16777619;
        hash &= 0x7fffffff;
      }
      return hash == 0 ? 1 : hash;
    }

    Navigator.pop(
      context,
      ReminderEntity(
        id: id,
        householdId: initial?.householdId ?? 'local-household',
        title: title,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        scheduledAt: _scheduledAt,
        recurrenceType: _recurrence,
        weekdays: _weekday,
        isActive: initial?.isActive ?? true,
        soundUri: _soundUri,
        soundName: _soundName,
        defaultSnoozeMinutes: initial?.defaultSnoozeMinutes ?? 10,
        notificationId: initial?.notificationId ?? stableIdFor(id),
        createdAt: initial?.createdAt,
        updatedAt: DateTime.now(),
        sourceType: initial?.sourceType ?? widget.initialSourceType,
        sourceId: initial?.sourceId ?? widget.initialSourceId,
        origin: initial?.origin ?? ReminderOrigin.user,
        mode: _mode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'Tambah pengingat' : 'Edit pengingat'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            autofocus: widget.initial == null,
            decoration: const InputDecoration(labelText: 'Judul pengingat'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Catatan tambahan (opsional)',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Waktu mulai'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatReminderDateTime(_scheduledAt)),
                HijriDateLabel(date: _scheduledAt),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit_calendar),
              onPressed: _pickDateTime,
            ),
          ),
          DropdownButtonFormField<ReminderRecurrenceType>(
            initialValue: _recurrence,
            decoration: const InputDecoration(labelText: 'Pengulangan'),
            items: ReminderRecurrenceType.values
                .map(
                  (item) =>
                      DropdownMenuItem(value: item, child: Text(item.label)),
                )
                .toList(),
            onChanged: (value) => setState(
              () => _recurrence = value ?? ReminderRecurrenceType.once,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ReminderMode>(
            initialValue: _mode,
            decoration: const InputDecoration(labelText: 'Tipe pengingat'),
            items: ReminderMode.values
                .map(
                  (item) => DropdownMenuItem(
                    value: item,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item == ReminderMode.alarm
                              ? Icons.alarm_rounded
                              : Icons.notifications_none_rounded,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(item.label),
                      ],
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) =>
                setState(() => _mode = value ?? ReminderMode.notification),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.music_note_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Nada notifikasi',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _soundName ?? 'Bawaan FFM',
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickSound,
                        icon: const Icon(Icons.folder_open_outlined, size: 18),
                        label: const Text('Pilih nada'),
                      ),
                    ),
                    if (_soundUri != null) ...[
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'Kembalikan ke nada bawaan',
                        onPressed: _clearSound,
                        icon: const Icon(Icons.restart_alt_rounded),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_recurrence == ReminderRecurrenceType.weekly)
            Wrap(
              spacing: 4,
              children: List.generate(7, (index) {
                final day = index + 1;
                return FilterChip(
                  label: Text('$day'),
                  selected: _weekday.contains(day),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _weekday = [..._weekday, day]..sort();
                    } else {
                      _weekday = _weekday.where((item) => item != day).toList();
                    }
                  }),
                );
              }),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(onPressed: _save, child: const Text('Simpan')),
    ],
  );
}

// ---------------------------------------------------------------------------
// Permission banner — shown at the top of the list when the device has not
// granted the exact alarm or notification permission that reminders need.
// ---------------------------------------------------------------------------

class _PermissionBanner extends StatefulWidget {
  const _PermissionBanner({
    required this.notificationsEnabled,
    required this.exactAlarmEnabled,
  });

  final bool notificationsEnabled;
  final bool exactAlarmEnabled;

  @override
  State<_PermissionBanner> createState() => _PermissionBannerState();
}

class _PermissionBannerState extends State<_PermissionBanner> {
  bool _requesting = false;

  Future<void> _requestOrOpen() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      final service = getIt<ReminderNotificationService>();
      if (!widget.notificationsEnabled) {
        // Ask for POST_NOTIFICATIONS at runtime (Android 13+).
        await service.requestPermissions();
      } else {
        // Exact alarm requires the user to navigate to system settings.
        await service.openNotificationSettings();
      }
      // Refresh the bloc so the banner can disappear if permissions are now OK.
      if (mounted) {
        context.read<ReminderBloc>().add(const ReminderLoadRequested());
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final message = !widget.notificationsEnabled
        ? 'Izin notifikasi belum diberikan. Pengingat tidak akan berbunyi.'
        : !widget.exactAlarmEnabled
        ? 'Izin “Alarm & Pengingat” perlu diaktifkan di Pengaturan '
              'agar alarm tepat waktu.'
        : '';
    final buttonLabel = !widget.notificationsEnabled
        ? 'Izinkan notifikasi'
        : 'Buka pengaturan';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: colorScheme.onErrorContainer,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: TextStyle(
                        color: colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 32,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.error,
                          foregroundColor: colorScheme.onError,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                        onPressed: _requesting ? null : _requestOrOpen,
                        child: _requesting
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onError,
                                ),
                              )
                            : Text(buttonLabel),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
