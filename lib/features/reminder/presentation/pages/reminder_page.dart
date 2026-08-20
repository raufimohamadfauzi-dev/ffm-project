import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../domain/entities/reminder_entity.dart';
import '../bloc/reminder_bloc.dart';

class ReminderPage extends StatelessWidget {
  const ReminderPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => getIt<ReminderBloc>()..add(const ReminderLoadRequested()),
    child: const _ReminderView(),
  );
}

class _ReminderView extends StatefulWidget {
  const _ReminderView();

  @override
  State<_ReminderView> createState() => _ReminderViewState();
}

class _ReminderViewState extends State<_ReminderView> {
  ReminderHistoryStatus? _historyFilter;

  Future<void> _openDialog(
    BuildContext context, {
    ReminderEntity? initial,
  }) async {
    final reminder = await showDialog<ReminderEntity>(
      context: context,
      builder: (_) => _ReminderDialog(initial: initial),
    );
    if (reminder != null && context.mounted) {
      context.read<ReminderBloc>().add(ReminderSaved(reminder));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pengingat')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _openDialog(context),
      icon: const Icon(Icons.add_alert_outlined),
      label: const Text('Tambah'),
    ),
    body: BlocConsumer<ReminderBloc, ReminderState>(
      listener: (context, state) {
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
                ...history.map(
                  (item) => AppCard(
                    child: ListTile(
                      leading: Icon(_statusIcon(item.history.status)),
                      title: Text(item.history.title),
                      subtitle: Text(
                        '${_formatDateTime(item.history.scheduledAt)} · ${item.history.status.label}',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'selesai') {
                            context.read<ReminderBloc>().add(
                              ReminderHistoryStatusChanged(
                                history: item.history,
                                status: ReminderHistoryStatus.completed,
                              ),
                            );
                          } else if (value == 'tunda') {
                            context.read<ReminderBloc>().add(
                              ReminderHistoryStatusChanged(
                                history: item.history,
                                status: ReminderHistoryStatus.snoozed,
                                snoozedUntil: DateTime.now().add(
                                  const Duration(minutes: 10),
                                ),
                              ),
                            );
                          } else if (value == 'hapus') {
                            context.read<ReminderBloc>().add(
                              ReminderHistoryDeleted(item.history),
                            );
                          }
                        },
                        itemBuilder: (_) => [
                          if (item.history.status !=
                              ReminderHistoryStatus.completed)
                            const PopupMenuItem(
                              value: 'selesai',
                              child: Text('Tandai selesai'),
                            ),
                          if (item.history.status !=
                              ReminderHistoryStatus.completed)
                            const PopupMenuItem(
                              value: 'tunda',
                              child: Text('Tunda 10 menit'),
                            ),
                          const PopupMenuItem(
                            value: 'hapus',
                            child: Text('Hapus dari riwayat'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
    final two = (int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({this.initial});

  final ReminderEntity? initial;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late DateTime _scheduledAt;
  late ReminderRecurrenceType _recurrence;
  late List<int> _weekday;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _titleController = TextEditingController(text: initial?.title ?? '');
    _noteController = TextEditingController(text: initial?.note ?? '');
    _scheduledAt =
        initial?.scheduledAt ?? DateTime.now().add(const Duration(hours: 1));
    _recurrence = initial?.recurrenceType ?? ReminderRecurrenceType.once;
    _weekday = [...?initial?.weekdays];
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
        soundUri: initial?.soundUri,
        soundName: initial?.soundName,
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
