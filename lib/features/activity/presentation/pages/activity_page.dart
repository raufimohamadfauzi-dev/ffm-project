import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
      if (!mounted) return;
      final activityState = context.read<ActivityBloc>().state;
      if (activityState.activeSessions.isNotEmpty) setState(() {});
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

  Future<void> _showSessionDetails(
    ActivitySessionEntity session,
    List<ActivityCheckpointEntity> checkpoints,
    List<ActivitySessionEntity> children,
  ) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                session.title,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${session.category} • ${_dateOnly(session.startedAt)}${session.parentSessionId == null ? '' : ' • aktivitas di dalam sesi lain'}',
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _DetailMetric(
                      label: 'Mulai',
                      value: _time(session.startedAt),
                    ),
                  ),
                  Expanded(
                    child: _DetailMetric(
                      label: 'Selesai',
                      value: session.endedAt == null
                          ? 'Berjalan'
                          : _time(session.endedAt!),
                    ),
                  ),
                  Expanded(
                    child: _DetailMetric(
                      label: 'Durasi',
                      value: _calculator.format(session.durationAt()),
                    ),
                  ),
                ],
              ),
              if (children.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Aktivitas di dalamnya',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                for (final child in children)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      child.status == ActivitySessionStatus.active
                          ? Icons.play_circle_outline
                          : Icons.check_circle_outline,
                    ),
                    title: Text(child.title),
                    subtitle: Text(
                      '${_dateTime(child.startedAt)} • ${_calculator.format(child.durationAt())}${child.endedAt == null ? ' • berjalan' : ''}',
                    ),
                  ),
              ],
              if (session.notes?.isNotEmpty == true) ...[
                const SizedBox(height: 14),
                Text(session.notes!),
              ],
              const SizedBox(height: 18),
              const Text(
                'Update aktivitas',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (checkpoints.isEmpty)
                const Text(
                  'Belum ada update. Tekan Update aktivitas saat ada perubahan.',
                )
              else
                for (var index = 0; index < checkpoints.length; index++)
                  _CheckpointDetailTile(
                    checkpoint: checkpoints[index],
                    previous: index == 0
                        ? session.startedAt
                        : checkpoints[index - 1].occurredAt,
                    calculator: _calculator,
                  ),
            ],
          ),
        ),
      ),
    );
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

  Future<void> _startSession({
    String? parentSessionId,
    String? parentTitle,
  }) async {
    final result = await showModalBottomSheet<_SessionDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SessionForm(parentSessionTitle: parentTitle),
    );
    if (result == null || !mounted) return;
    await context.read<ActivityBloc>().startSession(
      title: result.title,
      category: result.category,
      notes: result.notes,
      startedAt: result.startedAt,
      parentSessionId: parentSessionId,
    );
  }

  Future<void> _addCheckpoint({String? sessionId}) async {
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
      sessionId: sessionId,
    );
  }

  Future<void> _confirmDeleteSession(ActivitySessionEntity session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus aktivitas permanen?'),
        content: Text(
          '“${session.title}” dan seluruh update aktivitasnya akan dihapus dari perangkat. Tindakan ini tidak bisa dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus permanen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<ActivityBloc>().deleteSessionPermanently(session.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Aktivitas dan semua update sudah dihapus.'),
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
          title: const Text('Aktivitas & waktu'),
          actions: [
            IconButton(
              tooltip: 'Cara kerja aktivitas',
              icon: const Icon(Icons.info_outline),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(
                  title: Text('Catat aktivitas harian'),
                  content: Text(
                    'Pakai Mulai sesi untuk melacak perjalanan atau pekerjaan dari awal sampai selesai. Tekan Update aktivitas setiap kali kegiatan berubah, misalnya sampai pasar, bertemu seseorang, atau pindah ke kebun. Ketuk kartu untuk melihat rincian dan durasi tiap update. Semua data disimpan lokal di perangkat.',
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
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'session',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.timer_outlined),
                title: Text('Mulai sesi aktivitas'),
                subtitle: Text(
                  'Timer dan update berjalan dari awal sampai selesai',
                ),
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
                    message: 'Mulai satu aktivitas, lalu tekan Update aktivitas setiap kali ada perubahan. Durasi dihitung otomatis sampai kamu menekan Selesai.',
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
                  Builder(
                    builder: (context) {
                      final visibleActiveSessions = state.activeSessions
                          .where(
                            (session) =>
                                (_typeFilter == 'Semua' ||
                                    session.category == _typeFilter) &&
                                _matchesDay(session.startedAt),
                          )
                          .toList();
                      final visibleSessions = state.sessions
                          .where(
                            (session) =>
                                session.status !=
                                    ActivitySessionStatus.active &&
                                (_typeFilter == 'Semua' ||
                                    session.category == _typeFilter) &&
                                _matchesDay(session.startedAt),
                          )
                          .toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (visibleActiveSessions.isNotEmpty) ...[
                            _SectionTitle(
                              title: 'Sedang berjalan',
                              count: visibleActiveSessions.length,
                            ),
                            for (final session in visibleActiveSessions)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _ActiveSessionCard(
                                  session: session,
                                  checkpoints:
                                      state.checkpoints[session.id] ?? const [],
                                  calculator: _calculator,
                                  onCheckpoint: () =>
                                      _addCheckpoint(sessionId: session.id),
                                  onFinish: () => context
                                      .read<ActivityBloc>()
                                      .finishSession(sessionId: session.id),
                                  onStartChild: () => _startSession(
                                    parentSessionId: session.id,
                                    parentTitle: session.title,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                          ],
                          _SectionTitle(
                            title: 'Aktivitas tersimpan',
                            count: visibleSessions.length,
                          ),
                          if (visibleSessions.isEmpty)
                            const AppEmptyState(
                              icon: Icons.timeline_outlined,
                              title: 'Belum ada aktivitas',
                              message: 'Mulai satu aktivitas, lalu isi update setiap kali berpindah atau melakukan sesuatu.',
                            )
                          else
                            for (final session in visibleSessions)
                              _SessionCard(
                                session: session,
                                checkpoints:
                                    state.checkpoints[session.id] ?? const [],
                                calculator: _calculator,
                                onOpen: () => _showSessionDetails(
                                  session,
                                  state.checkpoints[session.id] ?? const [],
                                  state.sessions
                                      .where(
                                        (child) =>
                                            child.parentSessionId == session.id,
                                      )
                                      .toList(),
                                ),
                                onArchive: () => context
                                    .read<ActivityBloc>()
                                    .archiveSession(session.id),
                                onDelete: () => _confirmDeleteSession(session),
                              ),
                        ],
                      );
                    },
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
    required this.onStartChild,
  });
  final ActivitySessionEntity session;
  final List<ActivityCheckpointEntity> checkpoints;
  final ActivityDurationCalculator calculator;
  final VoidCallback onCheckpoint;
  final VoidCallback onFinish;
  final VoidCallback onStartChild;

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
              OutlinedButton.icon(
                onPressed: onStartChild,
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Tambah di dalam'),
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
    required this.onOpen,
    required this.onArchive,
    required this.onDelete,
  });
  final ActivitySessionEntity session;
  final List<ActivityCheckpointEntity> checkpoints;
  final ActivityDurationCalculator calculator;
  final VoidCallback onOpen;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

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
        onTap: onOpen,
        trailing: PopupMenuButton<String>(
          tooltip: 'Kelola aktivitas',
          onSelected: (value) {
            if (value == 'archive') onArchive();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'archive',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.archive_outlined),
                title: Text('Arsipkan'),
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_forever_outlined),
                title: Text('Hapus permanen'),
              ),
            ),
          ],
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
  const _SessionForm({this.parentSessionTitle});

  final String? parentSessionTitle;
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
        Text(
          widget.parentSessionTitle == null
              ? 'Mulai sesi aktivitas'
              : 'Tambah aktivitas di dalamnya',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        if (widget.parentSessionTitle != null) ...[
          const SizedBox(height: 6),
          Text('Induk: ${widget.parentSessionTitle}'),
        ],
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
          child: Text(
            widget.parentSessionTitle == null
                ? 'Mulai sekarang'
                : 'Mulai aktivitas anak',
          ),
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

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 3),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
    ],
  );
}

class _CheckpointDetailTile extends StatelessWidget {
  const _CheckpointDetailTile({
    required this.checkpoint,
    required this.previous,
    required this.calculator,
  });
  final ActivityCheckpointEntity checkpoint;
  final DateTime previous;
  final ActivityDurationCalculator calculator;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.flag_outlined),
    title: Text(checkpoint.label),
    subtitle: Text(
      [
        _dateTime(checkpoint.occurredAt),
        'selang ${calculator.format(checkpoint.occurredAt.difference(previous))}',
        if (checkpoint.place?.isNotEmpty == true) checkpoint.place!,
        if (checkpoint.note?.isNotEmpty == true) checkpoint.note!,
      ].join(' • '),
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
