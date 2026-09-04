import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../settings/data/category_repository.dart';
import '../../domain/entities/activity_entity.dart';
import '../bloc/activity_bloc.dart';

/// Halaman Detail Riwayat Aktivitas Full Screen.
///
/// Menggantikan modal bottom sheet sempit. Membedakan secara visual dan fungsional
/// antara sesi ⏱️ Timer (durasi, timeline checkpoint, status berjalan/selesai)
/// dan 📝 Catatan (waktu kejadian, isi catatan, tanpa konsep 'berjalan' atau durasi).
class ActivityDetailPage extends StatelessWidget {
  const ActivityDetailPage({
    super.key,
    required this.sessionId,
  });

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ActivityBloc, ActivityState>(
      builder: (context, state) {
        final session = state.sessions
            .where((s) => s.id == sessionId)
            .firstOrNull;

        if (session == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Detail Aktivitas')),
            body: const Center(
              child: Text('Aktivitas tidak ditemukan atau sudah dihapus.'),
            ),
          );
        }

        final checkpoints = state.checkpoints[session.id] ?? const [];
        final children = state.sessions
            .where((child) => child.parentSessionId == session.id)
            .toList();

        return _ActivityDetailView(
          session: session,
          checkpoints: checkpoints,
          children: children,
        );
      },
    );
  }
}

class _ActivityDetailView extends StatefulWidget {
  const _ActivityDetailView({
    required this.session,
    required this.checkpoints,
    required this.children,
  });

  final ActivitySessionEntity session;
  final List<ActivityCheckpointEntity> checkpoints;
  final List<ActivitySessionEntity> children;

  @override
  State<_ActivityDetailView> createState() => _ActivityDetailViewState();
}

class _ActivityDetailViewState extends State<_ActivityDetailView> {
  final _calculator = const ActivityDurationCalculator();

  String _formatDateTime(DateTime dt) =>
      DateFormat('EEEE, d MMMM yyyy • HH:mm', 'id_ID').format(dt);

  String _formatTime(DateTime dt) => DateFormat('HH:mm', 'id_ID').format(dt);

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final isNote = session.isHistory;
    final isPriority = session.priority > 0;
    final isRunning = !isNote && session.status == ActivitySessionStatus.active;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isNote ? 'Detail Catatan' : 'Detail Aktivitas',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isPriority ? Icons.star_rounded : Icons.star_outline_rounded,
              color: isPriority ? Colors.amber : null,
            ),
            tooltip: isPriority ? 'Lepas prioritas' : 'Jadikan prioritas',
            onPressed: () =>
                context.read<ActivityBloc>().togglePriority(session.id),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit data (koreksi typo)',
            onPressed: () => _openEditSession(context, session),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Hapus aktivitas',
            onPressed: () => _confirmDelete(context, session),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          // Header Card
          AppCard(
            color: isNote
                ? Colors.purple.withValues(alpha: 0.07)
                : (isRunning
                    ? scheme.primaryContainer.withValues(alpha: 0.4)
                    : scheme.surfaceContainerLow),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: isNote
                          ? Colors.purple.withValues(alpha: 0.18)
                          : (isRunning
                              ? scheme.primary
                              : Colors.teal.withValues(alpha: 0.18)),
                      foregroundColor: isNote
                          ? Colors.purple.shade800
                          : (isRunning
                              ? scheme.onPrimary
                              : Colors.teal.shade800),
                      child: Icon(
                        isNote
                            ? Icons.edit_note_rounded
                            : (isRunning
                                ? Icons.play_arrow_rounded
                                : Icons.check_circle_outline_rounded),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.title,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.2,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              // Mode Badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: isNote
                                      ? Colors.purple.withValues(alpha: 0.12)
                                      : Colors.teal.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isNote ? '📝 Catatan' : '⏱️ Timer',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isNote
                                        ? Colors.purple.shade900
                                        : Colors.teal.shade900,
                                  ),
                                ),
                              ),
                              // Category Badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  session.category,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              // Status Badge
                              if (isNote)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '✅ Selesai dicatat',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                )
                              else if (isRunning)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '⏱️ Sedang Berjalan',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '✅ Selesai',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                ),
                              if (isPriority)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '⭐ Prioritas',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Metrik Waktu (Khusus Catatan vs Timer)
          if (isNote) ...[
            AppCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Colors.purple.withValues(alpha: 0.12),
                  foregroundColor: Colors.purple.shade800,
                  child: const Icon(Icons.calendar_today_outlined),
                ),
                title: const Text(
                  'Tanggal & Waktu Kejadian',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  _formatDateTime(session.startedAt),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mulai',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatTime(session.startedAt),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Selesai',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          session.endedAt == null
                              ? 'Berjalan'
                              : _formatTime(session.endedAt!),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: session.endedAt == null
                                ? scheme.primary
                                : scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Durasi',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _calculator.format(session.durationAt()),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),

          // Catatan / Keterangan Teks
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.notes_rounded,
                      size: 20,
                      color: isNote ? Colors.purple.shade800 : scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isNote ? 'Isi Catatan' : 'Keterangan Tambahan',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (session.notes?.trim().isNotEmpty == true)
                  SelectableText(
                    session.notes!,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.5,
                        ),
                  )
                else
                  Text(
                    'Tidak ada catatan tambahan.',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Timeline Update Checkpoints (Khusus Sesi Timer)
          if (!isNote) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Update Aktivitas (Checkpoints)',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                TextButton.icon(
                  onPressed: () => _openAddCheckpoint(context, session),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Tambah'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.checkpoints.isEmpty)
              const AppCard(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Belum ada update aktivitas. Tekan tombol Tambah untuk mencatat momen atau checkpoint.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              for (var i = 0; i < widget.checkpoints.length; i++) ...[
                _CheckpointCard(
                  checkpoint: widget.checkpoints[i],
                  previousTime: i == 0
                      ? session.startedAt
                      : widget.checkpoints[i - 1].occurredAt,
                  calculator: _calculator,
                  onEdit: () =>
                      _openEditCheckpoint(context, widget.checkpoints[i]),
                  onDelete: () =>
                      _confirmDeleteCheckpoint(context, widget.checkpoints[i]),
                ),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 16),
          ],

          // Sub-Aktivitas di dalamnya (Khusus Timer)
          if (!isNote && widget.children.isNotEmpty) ...[
            const Text(
              'Aktivitas di dalamnya (Sub-Aktivitas)',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final child in widget.children)
              AppCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    child.status == ActivitySessionStatus.active
                        ? Icons.play_circle_outline_rounded
                        : Icons.check_circle_outline_rounded,
                    color: child.status == ActivitySessionStatus.active
                        ? scheme.primary
                        : Colors.green,
                  ),
                  title: Text(
                    child.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${_formatDateTime(child.startedAt)} • ${_calculator.format(child.durationAt())}${child.endedAt == null ? ' • berjalan' : ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ActivityDetailPage(sessionId: child.id),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
          ],

          // Tombol aksi selesai jika sesi timer masih berjalan
          if (isRunning) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                await context
                    .read<ActivityBloc>()
                    .finishSession(sessionId: session.id);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Aktivitas berhasil diselesaikan!')),
                );
              },
              icon: const Icon(Icons.done_all_rounded),
              label: const Text(
                'Selesaikan Aktivitas Sekarang',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openEditSession(
    BuildContext context,
    ActivitySessionEntity session,
  ) async {
    final titleController = TextEditingController(text: session.title);
    final notesController = TextEditingController(text: session.notes ?? '');
    DateTime startedAt = session.startedAt;
    String selectedCategory = session.category;
    String? selectedCategoryId = session.categoryId;

    final categories = await getIt<CategoryRepository>().readActive(
      AppContext.householdId,
      type: 'activity',
    );

    if (!context.mounted) return;

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            session.isHistory ? 'Edit Catatan' : 'Edit Aktivitas',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Nama / Judul',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: categories.any((c) => c.name == selectedCategory)
                      ? selectedCategory
                      : (categories.isNotEmpty ? categories.first.name : null),
                  decoration: const InputDecoration(
                    labelText: 'Kategori',
                    border: OutlineInputBorder(),
                  ),
                  items: categories
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.name,
                          child: Text(c.name),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() {
                        selectedCategory = val;
                        selectedCategoryId = categories
                            .firstWhere((c) => c.name == val)
                            .id;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: Text(
                    session.isHistory ? 'Waktu Kejadian' : 'Waktu Mulai',
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    _formatDateTime(startedAt),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                      context: ctx,
                      initialDate: startedAt,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (pickedDate == null || !ctx.mounted) return;
                    final pickedTime = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(startedAt),
                    );
                    if (pickedTime == null || !ctx.mounted) return;
                    setDialogState(() {
                      startedAt = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      );
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Catatan / Keterangan',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.pop(dialogCtx, false);
              },
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.pop(dialogCtx, true);
              },
              child: const Text('Simpan Perubahan'),
            ),
          ],
        ),
      ),
    );

    if (updated == true && context.mounted) {
      await context.read<ActivityBloc>().updateSession(
            sessionId: session.id,
            title: titleController.text.trim(),
            category: selectedCategory,
            categoryId: selectedCategoryId,
            notes: notesController.text.trim().isEmpty
                ? null
                : notesController.text.trim(),
            startedAt: startedAt,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perubahan berhasil disimpan.')),
      );
    }
  }

  Future<void> _openEditCheckpoint(
    BuildContext context,
    ActivityCheckpointEntity cp,
  ) async {
    final labelCtrl = TextEditingController(text: cp.label);
    final placeCtrl = TextEditingController(text: cp.place ?? '');
    final noteCtrl = TextEditingController(text: cp.note ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Edit Update / Checkpoint'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Label Update (misal: Tiba di lokasi)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: placeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Lokasi (opsional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(dialogCtx, false);
            },
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(dialogCtx, true);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (saved == true && context.mounted) {
      await context.read<ActivityBloc>().editCheckpoint(
            checkpointId: cp.id,
            label: labelCtrl.text.trim(),
            place: placeCtrl.text.trim().isEmpty ? null : placeCtrl.text.trim(),
            note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update checkpoint berhasil disimpan.')),
      );
    }
  }

  Future<void> _openAddCheckpoint(
    BuildContext context,
    ActivitySessionEntity session,
  ) async {
    final labelCtrl = TextEditingController();
    final placeCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Tambah Update Aktivitas'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Apa yang sedang terjadi / update?',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: placeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Lokasi (opsional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(dialogCtx, false);
            },
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (labelCtrl.text.trim().isEmpty) return;
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(dialogCtx, true);
            },
            child: const Text('Simpan Update'),
          ),
        ],
      ),
    );

    if (saved == true && context.mounted) {
      await context.read<ActivityBloc>().addCheckpoint(
            sessionId: session.id,
            label: labelCtrl.text.trim(),
            place: placeCtrl.text.trim().isEmpty ? null : placeCtrl.text.trim(),
            note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
          );
    }
  }

  Future<void> _confirmDeleteCheckpoint(
    BuildContext context,
    ActivityCheckpointEntity cp,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus update ini?'),
        content: Text('Update "${cp.label}" akan dihapus permanen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await context.read<ActivityBloc>().deleteCheckpoint(cp.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update checkpoint berhasil dihapus.')),
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ActivitySessionEntity session,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus ${session.isHistory ? 'catatan' : 'aktivitas'}?'),
        content: Text(
          'Semua data ${session.isHistory ? 'catatan' : 'aktivitas'} "${session.title}" akan dihapus permanen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus Permanen'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await context.read<ActivityBloc>().deleteSessionPermanently(session.id);
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Back to activity list
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aktivitas berhasil dihapus.')),
      );
    }
  }
}

class _CheckpointCard extends StatelessWidget {
  const _CheckpointCard({
    required this.checkpoint,
    required this.previousTime,
    required this.calculator,
    required this.onEdit,
    required this.onDelete,
  });

  final ActivityCheckpointEntity checkpoint;
  final DateTime previousTime;
  final ActivityDurationCalculator calculator;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final diff = checkpoint.occurredAt.difference(previousTime);

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: scheme.primary.withValues(alpha: 0.15),
            foregroundColor: scheme.primary,
            child: const Icon(Icons.flag_rounded, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        checkpoint.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      DateFormat('HH:mm').format(checkpoint.occurredAt),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '+ ${calculator.format(diff.isNegative ? Duration.zero : diff)} dari sebelumnya',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
                if (checkpoint.place?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        checkpoint.place!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ],
                if (checkpoint.note?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    checkpoint.note!,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opsi checkpoint',
            iconSize: 18,
            onSelected: (val) {
              if (val == 'edit') onEdit();
              if (val == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Edit update'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18),
                    SizedBox(width: 8),
                    Text('Hapus update'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
