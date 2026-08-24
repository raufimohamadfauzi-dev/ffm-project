import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../data/daily_note_repository.dart';
import '../../domain/entities/daily_note_entity.dart';

class DailyNotesSection extends StatefulWidget {
  const DailyNotesSection({super.key});

  @override
  State<DailyNotesSection> createState() => _DailyNotesSectionState();
}

class _DailyNotesSectionState extends State<DailyNotesSection> {
  final _repository = getIt<DailyNoteRepository>();
  List<DailyNoteEntity> _notes = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final notes = await _repository.readActive(AppContext.householdId);
    if (mounted)
      setState(() {
        _notes = notes;
        _loading = false;
      });
  }

  Future<void> _edit([DailyNoteEntity? note]) async {
    final draft = await showModalBottomSheet<_DailyNoteDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DailyNoteForm(note: note),
    );
    if (draft == null) return;
    try {
      if (note == null) {
        await _repository.create(
          householdId: AppContext.householdId,
          noteDate: draft.noteDate,
          title: draft.title,
          body: draft.body,
        );
      } else {
        await _repository.update(
          householdId: AppContext.householdId,
          id: note.id,
          noteDate: draft.noteDate,
          title: draft.title,
          body: draft.body,
        );
      }
      await _load();
    } on ArgumentError catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message?.toString() ?? 'Catatan tidak valid.'),
          ),
        );
    }
  }

  Future<void> _archive(DailyNoteEntity note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arsipkan Catatan Harian?'),
        content: const Text(
          'Catatan tidak dihapus permanen dan masih tersimpan lokal.',
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
    await _repository.archive(householdId: AppContext.householdId, id: note.id);
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
                  'Catatan Harian',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Tambah Catatan Harian',
                onPressed: () => _edit(),
                icon: const Icon(Icons.note_add_outlined),
              ),
            ],
          ),
          const Text(
            'Refleksi atau ringkasan hari ini. Terpisah dari sesi aktivitas bertimer.',
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_notes.isEmpty)
            const Text(
              'Belum ada Catatan Harian. Tambahkan saat ingin menyimpan ringkasan hari ini.',
            )
          else
            for (final note in _notes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sticky_note_2_outlined),
                title: Text(note.title ?? 'Catatan ${_date(note.noteDate)}'),
                subtitle: Text(
                  '${_date(note.noteDate)}\n${note.body}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                onTap: () => _edit(note),
                trailing: IconButton(
                  tooltip: 'Arsipkan catatan',
                  onPressed: () => _archive(note),
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

class _DailyNoteDraft {
  const _DailyNoteDraft({
    required this.noteDate,
    required this.title,
    required this.body,
  });
  final DateTime noteDate;
  final String? title;
  final String body;
}

class _DailyNoteForm extends StatefulWidget {
  const _DailyNoteForm({this.note});
  final DailyNoteEntity? note;
  @override
  State<_DailyNoteForm> createState() => _DailyNoteFormState();
}

class _DailyNoteFormState extends State<_DailyNoteForm> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late DateTime _date;
  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note?.title ?? '');
    _body = TextEditingController(text: widget.note?.body ?? '');
    _date = widget.note?.noteDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
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
          widget.note == null ? 'Tambah Catatan Harian' : 'Ubah Catatan Harian',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        TextButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
              initialDate: _date,
            );
            if (picked != null) setState(() => _date = picked);
          },
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text('Tanggal: ${_DailyNotesSectionState._date(_date)}'),
        ),
        TextField(
          controller: _title,
          maxLength: DailyNoteRepository.maxTitleLength,
          decoration: const InputDecoration(labelText: 'Judul (opsional)'),
        ),
        TextField(
          controller: _body,
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          maxLength: DailyNoteRepository.maxBodyLength,
          decoration: const InputDecoration(
            labelText: 'Isi catatan',
            hintText: 'Tulis refleksi atau ringkasan hari ini',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            if (_body.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _DailyNoteDraft(
                noteDate: _date,
                title: _title.text,
                body: _body.text,
              ),
            );
          },
          child: const Text('Simpan Catatan'),
        ),
      ],
    ),
  );
}
