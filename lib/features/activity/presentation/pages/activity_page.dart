import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../domain/entities/activity_entity.dart';
import '../bloc/activity_bloc.dart';

class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<ActivityBloc>()..load(),
      child: const _ActivityView(),
    );
  }
}

class _ActivityView extends StatefulWidget {
  const _ActivityView();

  @override
  State<_ActivityView> createState() => _ActivityViewState();
}

class _ActivityViewState extends State<_ActivityView> {
  Timer? _ticker;
  String _typeFilter = 'Semua';
  DateTime? _dayFilter;
  final _calculator = const ActivityDurationCalculator();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool _matchesDay(DateTime value) {
    final day = _dayFilter;
    return day == null ||
        (value.year == day.year &&
            value.month == day.month &&
            value.day == day.day);
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _dayFilter ?? DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _dayFilter = picked);
  }

  Future<void> _startSession() async {
    final result = await showModalBottomSheet<_SessionDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SessionForm(),
    );
    if (result == null || !mounted) return;
    await context.read<ActivityBloc>().startSession(
      title: result.title,
      category: result.category,
      notes: result.notes,
      startedAt: result.startedAt,
    );
  }

  Future<void> _addCheckpoint() async {
    final result = await showModalBottomSheet<_CheckpointDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CheckpointForm(),
    );
    if (result == null || !mounted) return;
    await context.read<ActivityBloc>().addCheckpoint(
      label: result.label,
      place: result.place,
      note: result.note,
      occurredAt: result.occurredAt,
    );
  }

  Future<void> _addJournal() async {
    final result = await showModalBottomSheet<_JournalDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _JournalForm(),
    );
    if (result == null || !mounted) return;
    await context.read<ActivityBloc>().saveEntry(
      ActivityJournalEntryEntity(
        id: const Uuid().v4(),
        householdId: AppContext.householdId,
        activityType: result.activityType,
        title: result.title,
        participants: result.participants,
        topic: result.topic,
        place: result.place,
        startedAt: result.startedAt,
        endedAt: result.endedAt,
        notes: result.notes,
        followUp: result.followUp,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ActivityBloc, ActivityState>(
      listenWhen: (previous, current) => previous.error != current.error,
      listener: (context, state) {
        final error = state.error;
        if (error == null) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Aktivitas & jurnal'),
          actions: [
            IconButton(
              tooltip: 'Cara kerja aktivitas',
              icon: const Icon(Icons.info_outline),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(
                  title: Text('Catat aktivitas harian'),
                  content: Text(
                    'Pakai Mulai sesi untuk melacak perjalanan atau pekerjaan dari awal sampai selesai. Tambahkan checkpoint setiap kali sampai di tempat baru. Untuk pertemuan atau obrolan, pakai Catat jurnal dan tulis ringkasan sendiri. Semua data disimpan lokal di perangkat.',
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: PopupMenuButton<String>(
          tooltip: 'Tambah aktivitas',
          onSelected: (value) {
            if (value == 'session') _startSession();
            if (value == 'journal') _addJournal();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'session',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.timer_outlined),
                title: Text('Mulai sesi perjalanan/kerja'),
              ),
            ),
            PopupMenuItem(
              value: 'journal',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.menu_book_outlined),
                title: Text('Catat jurnal/pertemuan'),
              ),
            ),
          ],
          child: const FloatingActionButton.extended(
            onPressed: null,
            icon: Icon(Icons.add),
            label: Text('Tambah'),
          ),
        ),
        body: BlocBuilder<ActivityBloc, ActivityState>(
          builder: (context, state) {
            if (state.loading &&
                state.sessions.isEmpty &&
                state.entries.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            return RefreshIndicator(
              onRefresh: context.read<ActivityBloc>().load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                children: [
                  const AppHelpBanner(
                    title: 'Waktu kamu bisa dilacak',
                    message: 'Catat dari berangkat, sampai di tempat, ngobrol, bekerja, sampai pulang. Durasi dihitung dari waktu yang kamu masukkan.',
                    icon: Icons.timeline_outlined,
                  ),
                  const SizedBox(height: 16),
                  AppCard(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DropdownButton<String>(
                          value: _typeFilter,
                          underline: const SizedBox.shrink(),
                          items:
                              const [
                                    'Semua',
                                    'Perjalanan',
                                    'Pertemuan/obrolan',
                                    'Belanja',
                                    'Pekerjaan',
                                    'Keluarga',
                                    'Lainnya',
                                  ]
                                  .map(
                                    (item) => DropdownMenuItem(
                                      value: item,
                                      child: Text(item),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) =>
                              setState(() => _typeFilter = value ?? 'Semua'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _pickDay,
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                            _dayFilter == null
                                ? 'Semua tanggal'
                                : _dateOnly(_dayFilter!),
                          ),
                        ),
                        if (_dayFilter != null)
                          IconButton(
                            tooltip: 'Hapus filter tanggal',
                            onPressed: () => setState(() => _dayFilter = null),
                            icon: const Icon(Icons.clear),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (state.activeSession != null)
                    _ActiveSessionCard(
                      session: state.activeSession!,
                      checkpoints:
                          state.checkpoints[state.activeSession!.id] ??
                          const [],
                      calculator: _calculator,
                      onCheckpoint: _addCheckpoint,
                      onFinish: () =>
                          context.read<ActivityBloc>().finishSession(),
                    ),
                  if (state.activeSession != null) const SizedBox(height: 16),
                  _SectionTitle(
                    title: 'Jurnal aktivitas',
                    count: state.entries
                        .where(
                          (entry) =>
                              (_typeFilter == 'Semua' ||
                                  entry.activityType == _typeFilter) &&
                              _matchesDay(entry.startedAt),
                        )
                        .length,
                  ),
                  if (state.entries
                      .where(
                        (entry) =>
                            (_typeFilter == 'Semua' ||
                                entry.activityType == _typeFilter) &&
                            _matchesDay(entry.startedAt),
                      )
                      .isEmpty)
                    const AppEmptyState(
                      icon: Icons.menu_book_outlined,
                      title: 'Belum ada catatan aktivitas',
                      message: 'Catat perjalanan, pekerjaan, pertemuan, atau obrolan keluarga secara manual.',
                    )
                  else
                    for (final entry in state.entries.where(
                      (entry) =>
                          (_typeFilter == 'Semua' ||
                              entry.activityType == _typeFilter) &&
                          _matchesDay(entry.startedAt),
                    ))
                      _JournalCard(
                        entry: entry,
                        calculator: _calculator,
                        onArchive: () =>
                            context.read<ActivityBloc>().archiveEntry(entry.id),
                      ),
                  const SizedBox(height: 18),
                  _SectionTitle(
                    title: 'Sesi perjalanan & kerja',
                    count: state.sessions
                        .where(
                          (session) =>
                              (_typeFilter == 'Semua' ||
                                  session.category == _typeFilter) &&
                              _matchesDay(session.startedAt),
                        )
                        .length,
                  ),
                  if (state.sessions
                      .where(
                        (session) =>
                            (_typeFilter == 'Semua' ||
                                session.category == _typeFilter) &&
                            _matchesDay(session.startedAt),
                      )
                      .isEmpty)
                    const AppEmptyState(
                      icon: Icons.timer_outlined,
                      title: 'Belum ada sesi',
                      message: 'Mulai satu sesi kalau mau melacak perjalanan atau kegiatan dari awal sampai selesai.',
                    )
                  else
                    for (final session in state.sessions.where(
                      (session) =>
                          (_typeFilter == 'Semua' ||
                              session.category == _typeFilter) &&
                          _matchesDay(session.startedAt),
                    ))
                      _SessionCard(
                        session: session,
                        checkpoints: state.checkpoints[session.id] ?? const [],
                        calculator: _calculator,
                        onArchive: () => context
                            .read<ActivityBloc>()
                            .archiveSession(session.id),
                      ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        const SizedBox(width: 8),
        Chip(label: Text('$count')),
      ],
    ),
  );
}

class _ActiveSessionCard extends StatelessWidget {
  const _ActiveSessionCard({
    required this.session,
    required this.checkpoints,
    required this.calculator,
    required this.onCheckpoint,
    required this.onFinish,
  });
  final ActivitySessionEntity session;
  final List<ActivityCheckpointEntity> checkpoints;
  final ActivityDurationCalculator calculator;
  final VoidCallback onCheckpoint;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final duration = session.durationAt();
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      color: scheme.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                child: const Icon(Icons.play_arrow),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  session.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              Text(
                calculator.format(duration),
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Dimulai ${_dateTime(session.startedAt)} • masih berjalan'),
          if (checkpoints.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final checkpoint in checkpoints)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${checkpoint.label}${checkpoint.place == null ? '' : ' — ${checkpoint.place}'} (${_time(checkpoint.occurredAt)})',
                ),
              ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onCheckpoint,
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Update posisi'),
              ),
              FilledButton.icon(
                onPressed: onFinish,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Selesai'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.checkpoints,
    required this.calculator,
    required this.onArchive,
  });
  final ActivitySessionEntity session;
  final List<ActivityCheckpointEntity> checkpoints;
  final ActivityDurationCalculator calculator;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          child: Icon(
            session.status == ActivitySessionStatus.completed
                ? Icons.check
                : Icons.timer_outlined,
          ),
        ),
        title: Text(
          session.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${session.category} • ${_dateTime(session.startedAt)} • ${calculator.format(session.durationAt())}${checkpoints.isEmpty ? '' : ' • ${checkpoints.length} update'}',
        ),
        trailing: IconButton(
          tooltip: 'Arsipkan sesi',
          onPressed: onArchive,
          icon: const Icon(Icons.archive_outlined),
        ),
      ),
    ),
  );
}

class _JournalCard extends StatelessWidget {
  const _JournalCard({
    required this.entry,
    required this.calculator,
    required this.onArchive,
  });
  final ActivityJournalEntryEntity entry;
  final ActivityDurationCalculator calculator;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const CircleAvatar(child: Icon(Icons.menu_book_outlined)),
        title: Text(
          entry.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [
            entry.activityType,
            _dateTime(entry.startedAt),
            if (entry.endedAt != null) calculator.format(entry.durationAt()),
            if (entry.participants?.isNotEmpty == true)
              'dengan ${entry.participants}',
            if (entry.place?.isNotEmpty == true) entry.place!,
            if (entry.topic?.isNotEmpty == true) 'topik: ${entry.topic}',
            if (entry.notes?.isNotEmpty == true) entry.notes!,
            if (entry.followUp?.isNotEmpty == true) 'lanjut: ${entry.followUp}',
          ].join(' • '),
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'Arsipkan catatan',
          onPressed: onArchive,
          icon: const Icon(Icons.archive_outlined),
        ),
      ),
    ),
  );
}

class _SessionDraft {
  const _SessionDraft(this.title, this.category, this.notes, this.startedAt);
  final String title;
  final String category;
  final String? notes;
  final DateTime startedAt;
}

class _SessionForm extends StatefulWidget {
  const _SessionForm();
  @override
  State<_SessionForm> createState() => _SessionFormState();
}

class _SessionFormState extends State<_SessionForm> {
  final _title = TextEditingController();
  final _category = TextEditingController(text: 'Perjalanan');
  final _notes = TextEditingController();
  DateTime _startedAt = DateTime.now();

  @override
  void dispose() {
    _title.dispose();
    _category.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: 16,
      right: 16,
      top: 16,
      bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: ListView(
      shrinkWrap: true,
      children: [
        const Text(
          'Mulai sesi aktivitas',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nama aktivitas',
            hintText: 'Misalnya ke pasar lalu ke kebun',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _category,
          decoration: const InputDecoration(
            labelText: 'Jenis aktivitas',
            hintText: 'Perjalanan, kerja, belanja, atau lainnya',
          ),
        ),
        const SizedBox(height: 10),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mulai pada'),
          subtitle: Text(_dateTime(_startedAt)),
          trailing: const Icon(Icons.schedule),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
              initialDate: _startedAt,
            );
            if (picked == null || !mounted) return;
            setState(
              () => _startedAt = DateTime(
                picked.year,
                picked.month,
                picked.day,
                _startedAt.hour,
                _startedAt.minute,
              ),
            );
          },
        ),
        TextField(
          controller: _notes,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _SessionDraft(
                _title.text.trim(),
                _category.text.trim().isEmpty
                    ? 'Lainnya'
                    : _category.text.trim(),
                _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                _startedAt,
              ),
            );
          },
          child: const Text('Mulai sekarang'),
        ),
      ],
    ),
  );
}

class _CheckpointDraft {
  const _CheckpointDraft(this.label, this.place, this.note, this.occurredAt);
  final String label;
  final String? place;
  final String? note;
  final DateTime occurredAt;
}

class _CheckpointForm extends StatefulWidget {
  const _CheckpointForm();
  @override
  State<_CheckpointForm> createState() => _CheckpointFormState();
}

class _CheckpointFormState extends State<_CheckpointForm> {
  final _label = TextEditingController();
  final _place = TextEditingController();
  final _note = TextEditingController();
  @override
  void dispose() {
    _label.dispose();
    _place.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: 16,
      right: 16,
      top: 16,
      bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: ListView(
      shrinkWrap: true,
      children: [
        const Text(
          'Update aktivitas',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _label,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Sudah sampai/menjalankan apa?',
            hintText: 'Misalnya sampai pasar',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _place,
          decoration: const InputDecoration(labelText: 'Lokasi (opsional)'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _note,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            if (_label.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _CheckpointDraft(
                _label.text.trim(),
                _place.text.trim().isEmpty ? null : _place.text.trim(),
                _note.text.trim().isEmpty ? null : _note.text.trim(),
                DateTime.now(),
              ),
            );
          },
          child: const Text('Simpan update'),
        ),
      ],
    ),
  );
}

class _JournalDraft {
  const _JournalDraft(
    this.activityType,
    this.title,
    this.participants,
    this.topic,
    this.place,
    this.startedAt,
    this.endedAt,
    this.notes,
    this.followUp,
  );
  final String activityType;
  final String title;
  final String? participants;
  final String? topic;
  final String? place;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? notes;
  final String? followUp;
}

class _JournalForm extends StatefulWidget {
  const _JournalForm();
  @override
  State<_JournalForm> createState() => _JournalFormState();
}

class _JournalFormState extends State<_JournalForm> {
  final _title = TextEditingController();
  final _participants = TextEditingController();
  final _topic = TextEditingController();
  final _place = TextEditingController();
  final _notes = TextEditingController();
  final _followUp = TextEditingController();
  String _type = 'Pertemuan/obrolan';
  bool _hasEnded = true;
  DateTime _startedAt = DateTime.now().subtract(const Duration(minutes: 30));
  DateTime _endedAt = DateTime.now();

  @override
  void dispose() {
    _title.dispose();
    _participants.dispose();
    _topic.dispose();
    _place.dispose();
    _notes.dispose();
    _followUp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: 16,
      right: 16,
      top: 16,
      bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: ListView(
      shrinkWrap: true,
      children: [
        const Text(
          'Catat jurnal aktivitas',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Jenis aktivitas'),
          items:
              const [
                    'Pertemuan/obrolan',
                    'Belanja',
                    'Pekerjaan',
                    'Perjalanan',
                    'Keluarga',
                    'Lainnya',
                  ]
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
          onChanged: (value) => setState(() => _type = value ?? _type),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _title,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Judul aktivitas',
            hintText: 'Misalnya ngobrol dengan Pak Budi',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _participants,
          decoration: const InputDecoration(
            labelText: 'Bertemu dengan (opsional)',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _topic,
          decoration: const InputDecoration(labelText: 'Topik (opsional)'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _place,
          decoration: const InputDecoration(labelText: 'Lokasi (opsional)'),
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sudah selesai'),
          value: _hasEnded,
          onChanged: (value) => setState(() => _hasEnded = value),
        ),
        TextField(
          controller: _notes,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Ringkasan/catatan'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _followUp,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Tindak lanjut (opsional)',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _JournalDraft(
                _type,
                _title.text.trim(),
                _participants.text.trim().isEmpty
                    ? null
                    : _participants.text.trim(),
                _topic.text.trim().isEmpty ? null : _topic.text.trim(),
                _place.text.trim().isEmpty ? null : _place.text.trim(),
                _startedAt,
                _hasEnded ? _endedAt : null,
                _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                _followUp.text.trim().isEmpty ? null : _followUp.text.trim(),
              ),
            );
          },
          child: const Text('Simpan catatan'),
        ),
      ],
    ),
  );
}

String _two(int value) => value.toString().padLeft(2, '0');
String _time(DateTime value) =>
    '${_two(value.hour)}:${_two(value.minute)}:${_two(value.second)}';
String _dateOnly(DateTime value) =>
    '${_two(value.day)}/${_two(value.month)}/${value.year}';
String _dateTime(DateTime value) =>
    '${_two(value.day)}/${_two(value.month)}/${value.year} ${_time(value)}';
