import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../data/ffm_assistant_knowledge_pack_service.dart';
import '../../data/ffm_assistant_memory_repository.dart';
import 'assistant_training_import_dialog.dart';

/// Gaya v54: ajaran pengguna selalu eksplisit, lokal, dapat ditinjau, dan
/// tidak pernah memberi Asisten izin menyimpan data finansial secara otomatis.
class AssistantTrainingPage extends StatefulWidget {
  const AssistantTrainingPage({super.key});

  @override
  State<AssistantTrainingPage> createState() => _AssistantTrainingPageState();
}

class _AssistantTrainingPageState extends State<AssistantTrainingPage> {
  final _repository = getIt<FfmAssistantMemoryRepository>();
  final _knowledgePack = getIt<FfmAssistantKnowledgePackService>();
  late Future<List<FfmAssistantMemoryRecord>> _memories;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _memories = _repository.readAll();
  }

  Future<void> _teach() async {
    final draft = await showDialog<_MemoryDraft>(
      context: context,
      builder: (_) => const _TeachAssistantDialog(),
    );
    if (draft == null) return;
    await _repository.save(
      kind: draft.kind,
      triggerText: draft.trigger,
      valueText: draft.value,
      source: 'user',
    );
    if (!mounted) return;
    setState(_reload);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ajaran disimpan lokal di perangkat ini.')),
    );
  }

  Future<void> _archive(FfmAssistantMemoryRecord memory) async {
    final shouldArchive = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arsipkan ajaran?'),
        content: Text(
          '“${memory.triggerText}” tidak akan dipakai Asisten lagi. Data tetap ada di riwayat memori dan dapat ikut backup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Arsipkan'),
          ),
        ],
      ),
    );
    if (shouldArchive != true) return;
    await _repository.archive(memory.id);
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _edit(FfmAssistantMemoryRecord memory) async {
    final draft = await showDialog<_MemoryDraft>(
      context: context,
      builder: (_) => _TeachAssistantDialog(existing: memory),
    );
    if (draft == null) return;
    await _repository.update(
      memory: memory,
      kind: draft.kind,
      triggerText: draft.trigger,
      valueText: draft.value,
    );
    if (!mounted) return;
    setState(_reload);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Ajaran diperbarui.')));
  }

  Future<void> _copyLlmPrompt() async {
    await Clipboard.setData(
      ClipboardData(text: _knowledgePack.buildLlmPrompt()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Prompt LLM disalin. Tambahkan ajaran tanpa data pribadi.',
        ),
      ),
    );
  }

  Future<void> _copyKnowledgePack() async {
    final content = await _knowledgePack.exportJson();
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Knowledge pack JSON disalin. Riwayat chat tidak ikut.'),
      ),
    );
  }

  Future<void> _importKnowledgePack() async {
    final content = await showDialog<String>(
      context: context,
      builder: (_) => const AssistantTrainingImportDialog(),
    );
    if (content == null) return;

    try {
      final preview = _knowledgePack.previewJson(content);
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Tinjau knowledge pack'),
          content: Text(
            'Ditemukan ${preview.total} ajaran. Ajaran akan disimpan lokal, tidak memberi izin simpan data otomatis, dan dapat diubah/diarsipkan nanti. Lanjut impor?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Impor ajaran'),
            ),
          ],
        ),
      );
      if (approved != true) return;
      final count = await _knowledgePack.importJson(content);
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count ajaran diimpor ke memori lokal.')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Knowledge pack tidak bisa diimpor: ${error.message}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pusat Latihan Asisten'),
        actions: [
          IconButton(
            tooltip: 'Info latihan Asisten',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAppInfoDialog(
              context,
              title: 'Cara kerja latihan',
              message: 'Ajaran disimpan lokal sebagai aturan yang kamu setujui. Asisten memakainya untuk memahami istilah dan menjawab pertanyaan, tetapi tetap hanya membuat draft—bukan menyimpan data otomatis.',
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _teach,
        icon: const Icon(Icons.school_outlined),
        label: const Text('Ajarkan Asisten'),
      ),
      body: FutureBuilder<List<FfmAssistantMemoryRecord>>(
        future: _memories,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final memories = snapshot.data ?? const [];
          final active = memories.where((item) => !item.isArchived).toList();
          final archived = memories.where((item) => item.isArchived).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              AppCard(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.psychology_alt_outlined),
                  title: Text(
                    'Ajar dengan contoh yang jelas',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    'Contoh: “tabungan” artinya SeaBank Pribadi. Kamu selalu bisa mengarsipkan ajaran yang sudah tidak berlaku.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Knowledge pack & LLM',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Salin prompt ke LLM pilihanmu, lalu tempel JSON hasilnya di sini untuk ditinjau. FFM tidak mengirim data ke internet sendiri.',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _copyLlmPrompt,
                          icon: const Icon(Icons.content_copy_outlined),
                          label: const Text('Salin prompt LLM'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _copyKnowledgePack,
                          icon: const Icon(Icons.ios_share_outlined),
                          label: const Text('Salin JSON'),
                        ),
                        FilledButton.icon(
                          onPressed: _importKnowledgePack,
                          icon: const Icon(Icons.file_download_outlined),
                          label: const Text('Impor JSON'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              AppSectionHeader(title: 'Memori aktif (${active.length})'),
              const SizedBox(height: 8),
              if (active.isEmpty)
                const AppEmptyState(
                  icon: Icons.school_outlined,
                  title: 'Belum ada ajaran',
                  message: 'Tekan Ajarkan Asisten untuk menyimpan alias, jawaban fitur, kebiasaan, atau alur FFM versi kamu.',
                )
              else
                ...active.map(
                  (memory) => _MemoryCard(
                    memory: memory,
                    onEdit: () => _edit(memory),
                    onArchive: () => _archive(memory),
                  ),
                ),
              if (archived.isNotEmpty) ...[
                const SizedBox(height: 20),
                AppSectionHeader(title: 'Diarsipkan (${archived.length})'),
                const SizedBox(height: 8),
                ...archived.map(
                  (memory) => _MemoryCard(memory: memory, archived: true),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    required this.memory,
    this.archived = false,
    this.onEdit,
    this.onArchive,
  });

  final FfmAssistantMemoryRecord memory;
  final bool archived;
  final VoidCallback? onEdit;
  final VoidCallback? onArchive;

  String get _kindLabel => switch (memory.kind) {
    'alias' => 'Alias',
    'answer' => 'Jawaban fitur',
    'habit' => 'Kebiasaan draft',
    'flow' => 'Alur aplikasi',
    _ => 'Ajaran',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            archived ? Icons.inventory_2_outlined : Icons.lightbulb_outline,
          ),
          title: Text(
            memory.triggerText,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text('$_kindLabel · ${memory.valueText}'),
          onTap: archived ? null : onEdit,
          trailing: archived
              ? const Tooltip(
                  message: 'Sudah diarsipkan',
                  child: Icon(Icons.archive_outlined),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Ubah ajaran',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: onEdit,
                    ),
                    IconButton(
                      tooltip: 'Arsipkan ajaran',
                      icon: const Icon(Icons.archive_outlined),
                      onPressed: onArchive,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _MemoryDraft {
  const _MemoryDraft({
    required this.kind,
    required this.trigger,
    required this.value,
  });

  final String kind;
  final String trigger;
  final String value;
}

class _TeachAssistantDialog extends StatefulWidget {
  const _TeachAssistantDialog({this.existing});

  final FfmAssistantMemoryRecord? existing;

  @override
  State<_TeachAssistantDialog> createState() => _TeachAssistantDialogState();
}

class _TeachAssistantDialogState extends State<_TeachAssistantDialog> {
  late final TextEditingController _triggerController;
  late final TextEditingController _valueController;
  late String _kind;

  @override
  void initState() {
    super.initState();
    _triggerController = TextEditingController(
      text: widget.existing?.triggerText ?? '',
    );
    _valueController = TextEditingController(
      text: widget.existing?.valueText ?? '',
    );
    _kind = widget.existing?.kind ?? 'alias';
  }

  @override
  void dispose() {
    _triggerController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  void _submit() {
    final trigger = _triggerController.text.trim();
    final value = _valueController.text.trim();
    if (trigger.isEmpty || value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pemicu dan isi ajaran wajib diisi.')),
      );
      return;
    }
    Navigator.pop(
      context,
      _MemoryDraft(kind: _kind, trigger: trigger, value: value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Ajarkan Asisten' : 'Ubah ajaran'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Jenis ajaran'),
              items: const [
                DropdownMenuItem(value: 'alias', child: Text('Alias data')),
                DropdownMenuItem(value: 'answer', child: Text('Jawaban fitur')),
                DropdownMenuItem(
                  value: 'habit',
                  child: Text('Kebiasaan draft'),
                ),
                DropdownMenuItem(value: 'flow', child: Text('Alur aplikasi')),
              ],
              onChanged: (value) => setState(() => _kind = value ?? 'alias'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _triggerController,
              decoration: const InputDecoration(
                labelText: 'Saat kamu bilang atau tanya',
                hintText: 'Contoh: tabungan',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _valueController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Artinya atau jawaban yang benar',
                hintText: 'Contoh: SeaBank Pribadi',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            const Text(
              'Ajaran ini tersimpan lokal. Jangan masukkan PIN, kata sandi, atau data rahasia.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(
            widget.existing == null ? 'Simpan ajaran' : 'Simpan perubahan',
          ),
        ),
      ],
    );
  }
}
