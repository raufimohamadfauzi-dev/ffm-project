import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../data/task_repository.dart';
import '../../domain/entities/task_entity.dart';

class TasksSection extends StatefulWidget {
  const TasksSection({super.key});

  @override
  State<TasksSection> createState() => _TasksSectionState();
}

class _TasksSectionState extends State<TasksSection> {
  final _repository = getIt<TaskRepository>();
  List<TaskEntity> _tasks = const [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tasks = await _repository.readActive(AppContext.householdId);
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _loading = false;
    });
  }

  Future<void> _edit([TaskEntity? task]) async {
    final draft = await showModalBottomSheet<_TaskDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TaskForm(task: task),
    );
    if (draft == null) return;
    try {
      if (task == null) {
        await _repository.create(
          householdId: AppContext.householdId,
          title: draft.title,
          note: draft.note,
          dueDate: draft.dueDate,
        );
      } else {
        await _repository.update(
          householdId: AppContext.householdId,
          id: task.id,
          title: draft.title,
          note: draft.note,
          dueDate: draft.dueDate,
        );
      }
      await _load();
    } on ArgumentError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message?.toString() ?? 'Tugas tidak valid.'),
        ),
      );
    }
  }

  Future<void> _toggle(TaskEntity task) async {
    if (task.isCompleted) {
      await _repository.reopen(
        householdId: AppContext.householdId,
        id: task.id,
      );
    } else {
      await _repository.complete(
        householdId: AppContext.householdId,
        id: task.id,
      );
    }
    await _load();
  }

  Future<void> _archive(TaskEntity task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arsipkan Tugas?'),
        content: const Text(
          'Tugas tidak dihapus permanen dan masih tersimpan lokal.',
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
    await _repository.archive(householdId: AppContext.householdId, id: task.id);
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
                  'Tugas',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Tambah Tugas',
                onPressed: () => _edit(),
                icon: const Icon(Icons.add_task_outlined),
              ),
            ],
          ),
          const Text(
            'Hal yang perlu dilakukan. Terpisah dari aktivitas bertimer dan Catatan Harian.',
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_tasks.isEmpty)
            const Text(
              'Belum ada Tugas. Tambahkan tindakan yang ingin kamu selesaikan.',
            )
          else
            for (final task in _tasks)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: IconButton(
                  tooltip: task.isCompleted
                      ? 'Buka kembali tugas'
                      : 'Tandai selesai',
                  onPressed: () => _toggle(task),
                  icon: Icon(
                    task.isCompleted
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                  ),
                ),
                title: Text(
                  task.title,
                  style: TextStyle(
                    decoration: task.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                subtitle: Text(
                  [
                    if (task.dueDate != null) 'Target: ${_date(task.dueDate!)}',
                    if (task.note != null) task.note!,
                    if (task.isCompleted) 'Selesai',
                  ].join('\n'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: task.note != null || task.dueDate != null,
                onTap: () => _edit(task),
                trailing: IconButton(
                  tooltip: 'Arsipkan tugas',
                  onPressed: () => _archive(task),
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

class _TaskDraft {
  const _TaskDraft({required this.title, required this.note, this.dueDate});

  final String title;
  final String? note;
  final DateTime? dueDate;
}

class _TaskForm extends StatefulWidget {
  const _TaskForm({this.task});

  final TaskEntity? task;

  @override
  State<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<_TaskForm> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.task?.title ?? '');
    _note = TextEditingController(text: widget.task?.note ?? '');
    _dueDate = widget.task?.dueDate;
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
          widget.task == null ? 'Tambah Tugas' : 'Ubah Tugas',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        TextField(
          controller: _title,
          autofocus: true,
          maxLength: TaskRepository.maxTitleLength,
          decoration: const InputDecoration(labelText: 'Judul tugas'),
        ),
        TextField(
          controller: _note,
          minLines: 2,
          maxLines: 5,
          maxLength: TaskRepository.maxNoteLength,
          decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                  initialDate: _dueDate ?? DateTime.now(),
                );
                if (picked != null) setState(() => _dueDate = picked);
              },
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _dueDate == null
                    ? 'Pilih tanggal target'
                    : 'Target: ${_TasksSectionState._date(_dueDate!)}',
              ),
            ),
            if (_dueDate != null)
              TextButton(
                onPressed: () => setState(() => _dueDate = null),
                child: const Text('Hapus tanggal'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _TaskDraft(
                title: _title.text,
                note: _note.text,
                dueDate: _dueDate,
              ),
            );
          },
          child: const Text('Simpan Tugas'),
        ),
      ],
    ),
  );
}
