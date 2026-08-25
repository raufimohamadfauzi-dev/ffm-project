import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../data/routine_repository.dart';
import '../../domain/entities/routine_entity.dart';

/// Section Rutinitas pada Aktivitas & Jurnal. Tidak membuat notifikasi, Jadwal,
/// maupun tindakan otomatis; setiap tanda hanya berlaku untuk hari lokal ini.
class RoutinesSection extends StatefulWidget {
  const RoutinesSection({super.key});

  @override
  State<RoutinesSection> createState() => _RoutinesSectionState();
}

class _RoutinesSectionState extends State<RoutinesSection> {
  final _repository = getIt<RoutineRepository>();
  List<RoutineEntity> _routines = const [];
  Set<String> _completedToday = const {};
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final routines = await _repository.readActive(AppContext.householdId);
    final day = _today();
    final completions = await Future.wait(
      routines.map(
        (routine) => _repository.completionForDay(
          householdId: AppContext.householdId,
          routineId: routine.id,
          day: day,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _routines = routines;
      _completedToday = completions
          .whereType<RoutineCompletionEntity>()
          .map((completion) => completion.routineId)
          .toSet();
      _loading = false;
    });
  }

  Future<void> _edit([RoutineEntity? routine]) async {
    final draft = await showModalBottomSheet<_RoutineDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RoutineForm(routine: routine),
    );
    if (draft == null) return;
    try {
      if (routine == null) {
        await _repository.create(
          householdId: AppContext.householdId,
          title: draft.title,
          note: draft.note,
          weekdays: draft.weekdays,
        );
      } else {
        await _repository.update(
          householdId: AppContext.householdId,
          id: routine.id,
          title: draft.title,
          note: draft.note,
          weekdays: draft.weekdays,
        );
      }
      await _load();
    } on ArgumentError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message?.toString() ?? 'Rutinitas tidak valid.'),
        ),
      );
    }
  }

  Future<void> _toggleToday(RoutineEntity routine) async {
    final day = _today();
    if (_completedToday.contains(routine.id)) {
      await _repository.unmarkCompletedForDay(
        householdId: AppContext.householdId,
        routineId: routine.id,
        day: day,
      );
    } else {
      await _repository.markCompletedForDay(
        householdId: AppContext.householdId,
        routineId: routine.id,
        day: day,
      );
    }
    await _load();
  }

  Future<void> _setActive(RoutineEntity routine, bool value) async {
    await _repository.setActive(
      householdId: AppContext.householdId,
      id: routine.id,
      isActive: value,
    );
    await _load();
  }

  Future<void> _archive(RoutineEntity routine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arsipkan Rutinitas?'),
        content: const Text(
          'Rutinitas tidak dihapus permanen. Riwayat hari lain tetap tersimpan lokal.',
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
      id: routine.id,
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
                  'Rutinitas',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Tambah Rutinitas',
                onPressed: () => _edit(),
                icon: const Icon(Icons.repeat_outlined),
              ),
            ],
          ),
          const Text(
            'Kebiasaan berulang. Tanda selesai hanya berlaku untuk hari ini dan tidak membuat notifikasi.',
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_routines.isEmpty)
            const Text(
              'Belum ada Rutinitas. Tambahkan kebiasaan yang ingin kamu tandai.',
            )
          else
            for (final routine in _routines)
              _RoutineTile(
                routine: routine,
                isCompletedToday: _completedToday.contains(routine.id),
                onToggleToday: routine.isActive
                    ? () => _toggleToday(routine)
                    : null,
                onEdit: () => _edit(routine),
                onActiveChanged: (value) => _setActive(routine, value),
                onArchive: () => _archive(routine),
              ),
        ],
      ),
    ),
  );

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}

class _RoutineTile extends StatelessWidget {
  const _RoutineTile({
    required this.routine,
    required this.isCompletedToday,
    required this.onToggleToday,
    required this.onEdit,
    required this.onActiveChanged,
    required this.onArchive,
  });

  final RoutineEntity routine;
  final bool isCompletedToday;
  final VoidCallback? onToggleToday;
  final VoidCallback onEdit;
  final ValueChanged<bool> onActiveChanged;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: IconButton(
      tooltip: isCompletedToday
          ? 'Batalkan tanda selesai hari ini'
          : 'Tandai selesai hari ini',
      onPressed: onToggleToday,
      icon: Icon(
        isCompletedToday
            ? Icons.check_circle_rounded
            : Icons.radio_button_unchecked_rounded,
      ),
    ),
    title: Text(
      routine.title,
      style: TextStyle(
        decoration: isCompletedToday ? TextDecoration.lineThrough : null,
      ),
    ),
    subtitle: Text(
      [
        _weekdaysLabel(routine.weekdays),
        if (!routine.isActive) 'Tidak aktif',
        if (isCompletedToday) 'Selesai hari ini',
        if (routine.note != null) routine.note!,
      ].join('\n'),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    ),
    isThreeLine: true,
    onTap: onEdit,
    trailing: PopupMenuButton<_RoutineMenuAction>(
      tooltip: 'Aksi Rutinitas',
      onSelected: (action) {
        switch (action) {
          case _RoutineMenuAction.edit:
            onEdit();
          case _RoutineMenuAction.toggleActive:
            onActiveChanged(!routine.isActive);
          case _RoutineMenuAction.archive:
            onArchive();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _RoutineMenuAction.edit,
          child: Text('Ubah'),
        ),
        PopupMenuItem(
          value: _RoutineMenuAction.toggleActive,
          child: Text(routine.isActive ? 'Nonaktifkan' : 'Aktifkan'),
        ),
        const PopupMenuItem(
          value: _RoutineMenuAction.archive,
          child: Text('Arsipkan'),
        ),
      ],
    ),
  );

  static String _weekdaysLabel(List<int> weekdays) {
    if (weekdays.isEmpty) return 'Setiap hari';
    const labels = <int, String>{
      DateTime.monday: 'Sen',
      DateTime.tuesday: 'Sel',
      DateTime.wednesday: 'Rab',
      DateTime.thursday: 'Kam',
      DateTime.friday: 'Jum',
      DateTime.saturday: 'Sab',
      DateTime.sunday: 'Min',
    };
    return weekdays.map((day) => labels[day]).whereType<String>().join(', ');
  }
}

enum _RoutineMenuAction { edit, toggleActive, archive }

class _RoutineDraft {
  const _RoutineDraft({
    required this.title,
    required this.note,
    required this.weekdays,
  });

  final String title;
  final String? note;
  final List<int> weekdays;
}

class _RoutineForm extends StatefulWidget {
  const _RoutineForm({this.routine});

  final RoutineEntity? routine;

  @override
  State<_RoutineForm> createState() => _RoutineFormState();
}

class _RoutineFormState extends State<_RoutineForm> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late Set<int> _weekdays;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.routine?.title ?? '');
    _note = TextEditingController(text: widget.routine?.note ?? '');
    _weekdays = {...?widget.routine?.weekdays};
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
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
          widget.routine == null ? 'Tambah Rutinitas' : 'Ubah Rutinitas',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        TextField(
          controller: _title,
          autofocus: true,
          maxLength: RoutineRepository.maxTitleLength,
          decoration: const InputDecoration(labelText: 'Judul Rutinitas'),
        ),
        TextField(
          controller: _note,
          minLines: 2,
          maxLines: 5,
          maxLength: RoutineRepository.maxNoteLength,
          decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
        ),
        const SizedBox(height: 8),
        const Text('Pola hari (opsional; kosong berarti setiap hari)'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final day in _weekdayOptions)
              FilterChip(
                label: Text(day.label),
                selected: _weekdays.contains(day.value),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _weekdays.add(day.value);
                  } else {
                    _weekdays.remove(day.value);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _RoutineDraft(
                title: _title.text,
                note: _note.text,
                weekdays: _weekdays.toList()..sort(),
              ),
            );
          },
          child: const Text('Simpan Rutinitas'),
        ),
      ],
    ),
  );
}

const _weekdayOptions = <({int value, String label})>[
  (value: DateTime.monday, label: 'Sen'),
  (value: DateTime.tuesday, label: 'Sel'),
  (value: DateTime.wednesday, label: 'Rab'),
  (value: DateTime.thursday, label: 'Kam'),
  (value: DateTime.friday, label: 'Jum'),
  (value: DateTime.saturday, label: 'Sab'),
  (value: DateTime.sunday, label: 'Min'),
];
