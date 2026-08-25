import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../data/schedule_repository.dart';
import '../../domain/entities/schedule_entry_entity.dart';

/// Section agenda lokal pada Aktivitas & Jurnal. Jadwal tidak membuat alarm,
/// notifikasi, Aktivitas, transaksi, maupun tindakan otomatis.
class ScheduleSection extends StatefulWidget {
  const ScheduleSection({super.key});

  @override
  State<ScheduleSection> createState() => _ScheduleSectionState();
}

class _ScheduleSectionState extends State<ScheduleSection> {
  final _repository = getIt<ScheduleRepository>();
  List<ScheduleEntryEntity> _entries = const [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _repository.readActive(AppContext.householdId);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _edit([ScheduleEntryEntity? entry]) async {
    final draft = await showModalBottomSheet<_ScheduleDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ScheduleForm(entry: entry),
    );
    if (draft == null) return;
    try {
      if (entry == null) {
        await _repository.create(
          householdId: AppContext.householdId,
          title: draft.title,
          note: draft.note,
          scheduledDate: draft.scheduledDate,
          isAllDay: draft.isAllDay,
          startMinutes: draft.startMinutes,
          endMinutes: draft.endMinutes,
        );
      } else {
        await _repository.update(
          householdId: AppContext.householdId,
          id: entry.id,
          title: draft.title,
          note: draft.note,
          scheduledDate: draft.scheduledDate,
          isAllDay: draft.isAllDay,
          startMinutes: draft.startMinutes,
          endMinutes: draft.endMinutes,
        );
      }
      await _load();
    } on ArgumentError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message?.toString() ?? 'Jadwal tidak valid.'),
        ),
      );
    }
  }

  Future<void> _archive(ScheduleEntryEntity entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arsipkan Jadwal?'),
        content: const Text(
          'Jadwal tidak dihapus permanen. Ini juga tidak mengubah Pengingat atau Aktivitas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Arsipkan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.archive(
      householdId: AppContext.householdId,
      id: entry.id,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Jadwal',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Tambah Jadwal',
                onPressed: () => _edit(),
                icon: const Icon(Icons.event_outlined),
              ),
            ],
          ),
          const Text(
            'Agenda lokal bertanggal. Tidak membuat alarm, notifikasi, Aktivitas, atau tindakan otomatis.',
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_entries.isEmpty)
            const Text(
              'Belum ada Jadwal. Tambahkan agenda yang ingin kamu ingat secara manual.',
            )
          else
            for (final entry in _entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  entry.isAllDay
                      ? Icons.today_outlined
                      : Icons.schedule_outlined,
                ),
                title: Text(entry.title),
                subtitle: Text(
                  [
                    _date(entry.scheduledDate),
                    entry.isAllDay
                        ? 'Sepanjang hari'
                        : entry.timeRangeLabel ?? 'Waktu belum lengkap',
                    if (entry.note != null) entry.note!,
                  ].join('\n'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                onTap: () => _edit(entry),
                trailing: IconButton(
                  tooltip: 'Arsipkan Jadwal',
                  onPressed: () => _archive(entry),
                  icon: const Icon(Icons.archive_outlined),
                ),
              ),
        ],
      ),
    ),
  );

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}

class _ScheduleDraft {
  const _ScheduleDraft({
    required this.title,
    required this.note,
    required this.scheduledDate,
    required this.isAllDay,
    this.startMinutes,
    this.endMinutes,
  });

  final String title;
  final String? note;
  final DateTime scheduledDate;
  final bool isAllDay;
  final int? startMinutes;
  final int? endMinutes;
}

class _ScheduleForm extends StatefulWidget {
  const _ScheduleForm({this.entry});

  final ScheduleEntryEntity? entry;

  @override
  State<_ScheduleForm> createState() => _ScheduleFormState();
}

class _ScheduleFormState extends State<_ScheduleForm> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late DateTime _scheduledDate;
  late bool _isAllDay;
  int? _startMinutes;
  int? _endMinutes;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.entry?.title ?? '');
    _note = TextEditingController(text: widget.entry?.note ?? '');
    _scheduledDate = widget.entry?.scheduledDate ?? _today();
    _isAllDay = widget.entry?.isAllDay ?? true;
    _startMinutes = widget.entry?.startMinutes;
    _endMinutes = widget.entry?.endMinutes;
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool end}) async {
    final current = end ? _endMinutes : _startMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOfDay(current ?? (end ? 9 * 60 : 8 * 60)),
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    setState(() {
      if (end) {
        _endMinutes = minutes;
      } else {
        _startMinutes = minutes;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      8,
      16,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: ListView(
      shrinkWrap: true,
      children: [
        Text(
          widget.entry == null ? 'Tambah Jadwal' : 'Ubah Jadwal',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        TextField(
          controller: _title,
          autofocus: true,
          maxLength: ScheduleRepository.maxTitleLength,
          decoration: const InputDecoration(labelText: 'Judul Jadwal'),
        ),
        TextField(
          controller: _note,
          minLines: 2,
          maxLines: 5,
          maxLength: ScheduleRepository.maxNoteLength,
          decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
        ),
        TextButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
              initialDate: _scheduledDate,
            );
            if (picked != null) setState(() => _scheduledDate = picked);
          },
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(
            'Tanggal: ${_ScheduleSectionState._date(_scheduledDate)}',
          ),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sepanjang hari'),
          subtitle: const Text(
            'Matikan untuk menentukan jam mulai dan selesai.',
          ),
          value: _isAllDay,
          onChanged: (value) => setState(() {
            _isAllDay = value;
            if (value) {
              _startMinutes = null;
              _endMinutes = null;
            }
          }),
        ),
        if (!_isAllDay) ...[
          TextButton.icon(
            onPressed: () => _pickTime(end: false),
            icon: const Icon(Icons.schedule_outlined),
            label: Text(
              _startMinutes == null
                  ? 'Pilih waktu mulai'
                  : 'Mulai: ${_time(_startMinutes!)}',
            ),
          ),
          TextButton.icon(
            onPressed: () => _pickTime(end: true),
            icon: const Icon(Icons.schedule_outlined),
            label: Text(
              _endMinutes == null
                  ? 'Pilih waktu selesai (opsional)'
                  : 'Selesai: ${_time(_endMinutes!)}',
            ),
          ),
          if (_endMinutes != null)
            TextButton(
              onPressed: () => setState(() => _endMinutes = null),
              child: const Text('Hapus waktu selesai'),
            ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _ScheduleDraft(
                title: _title.text,
                note: _note.text,
                scheduledDate: _scheduledDate,
                isAllDay: _isAllDay,
                startMinutes: _startMinutes,
                endMinutes: _endMinutes,
              ),
            );
          },
          child: const Text('Simpan Jadwal'),
        ),
      ],
    ),
  );

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static TimeOfDay _timeOfDay(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  static String _time(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
}
