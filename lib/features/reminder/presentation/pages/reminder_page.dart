import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../data/services/reminder_sound_picker.dart';
import '../../domain/entities/reminder_entity.dart';
import '../bloc/reminder_bloc.dart';

class ReminderPage extends StatelessWidget {
  const ReminderPage({
    super.key,
    this.initialTitle,
    this.initialNote,
    this.focusReminderId,
    this.focusHistoryId,
  });

  final String? initialTitle;
  final String? initialNote;
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
    this.focusReminderId,
    this.focusHistoryId,
  });

  final String? initialTitle;
  final String? initialNote;
  final String? focusReminderId;
  final String? focusHistoryId;

  @override
  State<_ReminderView> createState() => _ReminderViewState();
}

class _ReminderViewState extends State<_ReminderView> {
  ReminderHistoryStatus? _historyFilter;
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
  }) async {
    final reminder = await showDialog<ReminderEntity>(
      context: context,
      builder: (_) => _ReminderDialog(
        initial: initial,
        initialTitle: initialTitle,
        initialNote: initialNote,
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pengingat')),
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
        if (state.reminders.isEmpty && history.isEmpty) {
          return AppEmptyState(
            icon: Icons.notifications_none_outlined,
            title: 'Belum ada pengingat',
            message: 'Tambahkan jadwal lokal. Pengingat tetap tersimpan di perangkat.',
            action: FilledButton.icon(
              onPressed: () => _openDialog(context),
              icon: const Icon(Icons.add_alert_outlined),
              label: const Text('Tambah pengingat'),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            if (state.reminders.isNotEmpty) ...[
              Text(
                'Jadwal pengingat',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...state.reminders.map(
                (reminder) => AppCard(
                  child: ListTile(
                    onTap: () => _openDialog(context, initial: reminder),
                    leading: Icon(
                      reminder.isActive
                          ? Icons.notifications_active
                          : Icons.notifications_off,
                      color: reminder.isActive
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(reminder.title),
                    subtitle: Text(
                      '${_formatDateTime(reminder.scheduledAt)} · ${reminder.recurrenceType.label}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: reminder.isActive,
                          onChanged: (value) => context
                              .read<ReminderBloc>()
                              .add(ReminderActiveChanged(reminder, value)),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              _openDialog(context, initial: reminder);
                            } else if (value == 'hapus') {
                              context.read<ReminderBloc>().add(
                                ReminderDeleted(reminder),
                              );
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(value: 'hapus', child: Text('Hapus')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (state.history.isNotEmpty) ...[
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
                    hint: const Text('Semua'),
                    underline: const SizedBox.shrink(),
                    items: [
                      const DropdownMenuItem<ReminderHistoryStatus?>(
                        value: null,
                        child: Text('Semua'),
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
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('Belum ada riwayat dengan filter ini.'),
                  ),
                )
              else
                ...history.map((item) {
                  final historyItem = item.history;
                  final isActionable =
                      historyItem.status != ReminderHistoryStatus.completed &&
                      historyItem.status != ReminderHistoryStatus.cancelled;
                  final isHighlighted =
                      historyItem.id == _lastNotifiedPendingHistoryId ||
                      (historyItem.id == widget.focusHistoryId &&
                          historyItem.reminderId == widget.focusReminderId);
                  final colorScheme = Theme.of(context).colorScheme;
                  final subtitle = historyItem.snoozedUntil == null
                      ? '${_formatDateTime(historyItem.scheduledAt)} · ${historyItem.status.label}'
                      : '${_formatDateTime(historyItem.scheduledAt)} · ${historyItem.status.label} sampai ${_formatDateTime(historyItem.snoozedUntil!)}';
                  return AppCard(
                    key: historyItem.id == widget.focusHistoryId
                        ? _focusedHistoryKey
                        : null,
                    color: isHighlighted ? colorScheme.tertiaryContainer : null,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(_statusIcon(historyItem.status)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      historyItem.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
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
                              'Alarm baru masuk. Pilih tindakan di bawah.',
                              style: TextStyle(fontWeight: FontWeight.w700),
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
                                            status:
                                                ReminderHistoryStatus.completed,
                                          ),
                                        ),
                                    icon: const Icon(Icons.check_rounded),
                                    label: const Text('Selesai'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        context.read<ReminderBloc>().add(
                                          ReminderHistoryStatusChanged(
                                            history: historyItem,
                                            status:
                                                ReminderHistoryStatus.snoozed,
                                            snoozedUntil: DateTime.now().add(
                                              const Duration(minutes: 10),
                                            ),
                                          ),
                                        ),
                                    icon: const Icon(Icons.snooze_rounded),
                                    label: const Text('Tunda 10 mnt'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ],
        );
      },
    ),
  );

  static IconData _statusIcon(ReminderHistoryStatus status) => switch (status) {
    ReminderHistoryStatus.completed => Icons.check_circle,
    ReminderHistoryStatus.missed => Icons.warning_amber,
    ReminderHistoryStatus.snoozed => Icons.snooze,
    ReminderHistoryStatus.cancelled => Icons.cancel_outlined,
    ReminderHistoryStatus.pending => Icons.schedule,
  };

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({this.initial, this.initialTitle, this.initialNote});

  final ReminderEntity? initial;
  final String? initialTitle;
  final String? initialNote;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late DateTime _scheduledAt;
  late ReminderRecurrenceType _recurrence;
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
    _scheduledAt =
        initial?.scheduledAt ?? DateTime.now().add(const Duration(hours: 1));
    _recurrence = initial?.recurrenceType ?? ReminderRecurrenceType.once;
    _weekday = [...?initial?.weekdays];
    _soundUri = initial?.soundUri;
    _soundName = initial?.soundName;
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
    Navigator.pop(
      context,
      ReminderEntity(
        id: initial?.id ?? 'reminder-${DateTime.now().microsecondsSinceEpoch}',
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
        notificationId:
            initial?.notificationId ??
            DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        createdAt: initial?.createdAt,
        updatedAt: DateTime.now(),
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
            subtitle: Text(_ReminderViewState._formatDateTime(_scheduledAt)),
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
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.music_note_outlined),
            title: const Text('Nada notifikasi'),
            subtitle: Text(_soundName ?? 'Bawaan FFM'),
            trailing: Wrap(
              spacing: 4,
              children: [
                if (_soundUri != null)
                  IconButton(
                    tooltip: 'Kembalikan ke nada bawaan',
                    onPressed: _clearSound,
                    icon: const Icon(Icons.restart_alt_rounded),
                  ),
                OutlinedButton(
                  onPressed: _pickSound,
                  child: const Text('Pilih nada'),
                ),
              ],
            ),
          ),
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
