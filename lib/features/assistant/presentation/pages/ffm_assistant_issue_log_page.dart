import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../data/ffm_assistant_response_feedback_repository.dart';

class FfmAssistantIssueLogPage extends StatefulWidget {
  const FfmAssistantIssueLogPage({super.key});

  @override
  State<FfmAssistantIssueLogPage> createState() =>
      _FfmAssistantIssueLogPageState();
}

enum _IssueExportFormat { markdown, json }

class _FfmAssistantIssueLogPageState extends State<FfmAssistantIssueLogPage> {
  late final FfmAssistantResponseFeedbackRepository _repository;
  List<FfmAssistantResponseFeedback> _issues = const [];
  var _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = getIt<FfmAssistantResponseFeedbackRepository>();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final issues = await _repository.readAllIssues();
      if (!mounted) return;
      setState(() => _issues = issues);
    } on Object {
      if (mounted) setState(() => _error = 'Asisten Log belum dapat dimuat.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyAllAs(_IssueExportFormat format) async {
    await Clipboard.setData(
      ClipboardData(
        text: format == _IssueExportFormat.json
            ? await _repository.exportAllIssuesJson()
            : await _repository.exportAllIssues(),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Semua masalah disalin sebagai ${format == _IssueExportFormat.json ? 'JSON' : 'Markdown'}.',
        ),
      ),
    );
  }

  Future<void> _copyOne(FfmAssistantResponseFeedback issue) async {
    final text = _repository.exportIssue(issue);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Laporan masalah disalin.')));
  }

  Future<void> _delete(FfmAssistantResponseFeedback issue) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus masalah ini?'),
        content: const Text(
          'Data transaksi tidak terpengaruh. Setelah log dihapus, jawaban asalnya dapat ditandai lagi sebagai masalah.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.delete(issue.id);
    if (!mounted) return;
    setState(
      () => _issues = _issues.where((item) => item.id != issue.id).toList(),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Masalah dihapus dari Asisten Log.')),
    );
  }

  Future<void> _changeStatus(
    FfmAssistantResponseFeedback issue,
    FfmAssistantResponseFeedbackReviewStatus status,
  ) async {
    await _repository.setReviewStatus(issue.id, status);
    if (!mounted) return;
    setState(() {
      _issues = _issues
          .map(
            (item) => item.id == issue.id
                ? FfmAssistantResponseFeedback(
                    id: item.id,
                    questionText: item.questionText,
                    responseText: item.responseText,
                    kind: item.kind,
                    reviewStatus: status,
                    isArchived: item.isArchived,
                    createdAt: item.createdAt,
                    note: item.note,
                    pageContext: item.pageContext,
                    updatedAt: DateTime.now(),
                    sourceMessageId: item.sourceMessageId,
                    issueMetadata: item.issueMetadata,
                  )
                : item,
          )
          .toList(growable: false);
    });
  }

  Future<void> _editNote(FfmAssistantResponseFeedback issue) async {
    final controller = TextEditingController(text: issue.note ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit catatan masalah'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: 'Catatan opsional untuk developer atau agent coding.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null) return;
    final normalized = note.trim();
    await _repository.updateIssueNote(
      issue.id,
      normalized.isEmpty ? null : normalized,
    );
    if (!mounted) return;
    setState(() {
      _issues = _issues
          .map(
            (item) => item.id == issue.id
                ? FfmAssistantResponseFeedback(
                    id: item.id,
                    questionText: item.questionText,
                    responseText: item.responseText,
                    kind: item.kind,
                    reviewStatus: item.reviewStatus,
                    isArchived: item.isArchived,
                    createdAt: item.createdAt,
                    note: normalized.isEmpty ? null : normalized,
                    pageContext: item.pageContext,
                    updatedAt: DateTime.now(),
                    sourceMessageId: item.sourceMessageId,
                    issueMetadata: item.issueMetadata,
                  )
                : item,
          )
          .toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asisten Log'),
        actions: [
          PopupMenuButton<_IssueExportFormat>(
            tooltip: 'Salin semua laporan',
            enabled: _issues.isNotEmpty,
            onSelected: _copyAllAs,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _IssueExportFormat.markdown,
                child: Text('Salin semua sebagai Markdown'),
              ),
              PopupMenuItem(
                value: _IssueExportFormat.json,
                child: Text('Salin semua sebagai JSON'),
              ),
            ],
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _issues.isEmpty
          ? const _EmptyIssueState()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: _issues.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) => _IssueTile(
                  issue: _issues[index],
                  onCopy: () => _copyOne(_issues[index]),
                  onDelete: () => _delete(_issues[index]),
                  onEditNote: () => _editNote(_issues[index]),
                  onChangeStatus: (status) =>
                      _changeStatus(_issues[index], status),
                ),
              ),
            ),
    );
  }
}

class _IssueTile extends StatelessWidget {
  const _IssueTile({
    required this.issue,
    required this.onCopy,
    required this.onDelete,
    required this.onEditNote,
    required this.onChangeStatus,
  });

  final FfmAssistantResponseFeedback issue;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final VoidCallback onEditNote;
  final ValueChanged<FfmAssistantResponseFeedbackReviewStatus> onChangeStatus;

  @override
  Widget build(BuildContext context) {
    final metadata = issue.issueMetadata;
    final origin = metadata['responseOrigin']?.toString() ?? 'unknown';
    final problemKind = metadata['problemKind']?.toString() ?? issue.kind.name;
    final source =
        metadata['usedReadCapability']?.toString() ??
        metadata['pluginName']?.toString() ??
        origin;
    final statusColor = _statusColor(issue.reviewStatus);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: .14),
          foregroundColor: statusColor,
          child: Icon(_statusIcon(issue.reviewStatus)),
        ),
        title: Text(
          issue.questionText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '${_statusLabel(issue.reviewStatus)} · $origin · $problemKind\n${DateFormat('dd MMM yyyy, HH:mm').format(issue.createdAt)}',
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          const Divider(),
          _DetailLine(label: 'Jawaban', value: issue.responseText),
          _DetailLine(label: 'Sumber', value: origin),
          _DetailLine(label: 'Pekerjaan/tool', value: source),
          if (issue.pageContext != null)
            _DetailLine(label: 'Halaman', value: issue.pageContext!),
          if (metadata['model'] != null)
            _DetailLine(label: 'Model', value: metadata['model'].toString()),
          if (metadata['groundingBlocked'] != null)
            _DetailLine(
              label: 'Grounding',
              value: metadata['groundingBlocked'] == true
                  ? 'Gagal'
                  : 'Tidak diblokir',
            ),
          if (metadata['verifiedFacts'] != null)
            _DetailLine(
              label: 'Fakta lokal',
              value: metadata['verifiedFacts'].toString(),
            ),
          if (issue.note != null && issue.note!.isNotEmpty)
            _DetailLine(label: 'Catatan', value: issue.note!),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Salin'),
                ),
                OutlinedButton.icon(
                  onPressed: onEditNote,
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text('Catatan'),
                ),
                OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Hapus'),
                ),
                PopupMenuButton<FfmAssistantResponseFeedbackReviewStatus>(
                  onSelected: onChangeStatus,
                  itemBuilder: (context) =>
                      FfmAssistantResponseFeedbackReviewStatus.values
                          .map(
                            (status) => PopupMenuItem(
                              value: status,
                              child: Text(_statusLabel(status)),
                            ),
                          )
                          .toList(),
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.flag_outlined),
                    label: Text(_statusLabel(issue.reviewStatus)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
    ),
  );
}

class _EmptyIssueState extends StatelessWidget {
  const _EmptyIssueState();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 52,
            color: Colors.green.shade700,
          ),
          const SizedBox(height: 12),
          const Text(
            'Belum ada masalah assistant.',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tandai jawaban yang kurang sesuai dari menu titik tiga di chatbot.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

String _statusLabel(FfmAssistantResponseFeedbackReviewStatus status) =>
    switch (status) {
      FfmAssistantResponseFeedbackReviewStatus.pending => 'Baru',
      FfmAssistantResponseFeedbackReviewStatus.investigating => 'Ditinjau',
      FfmAssistantResponseFeedbackReviewStatus.fixed => 'Sudah diperbaiki',
      FfmAssistantResponseFeedbackReviewStatus.approved => 'Disetujui',
      FfmAssistantResponseFeedbackReviewStatus.rejected => 'Diabaikan',
    };

IconData _statusIcon(
  FfmAssistantResponseFeedbackReviewStatus status,
) => switch (status) {
  FfmAssistantResponseFeedbackReviewStatus.pending => Icons.fiber_new_outlined,
  FfmAssistantResponseFeedbackReviewStatus.investigating => Icons.search,
  FfmAssistantResponseFeedbackReviewStatus.fixed => Icons.check_circle_outline,
  FfmAssistantResponseFeedbackReviewStatus.approved => Icons.verified_outlined,
  FfmAssistantResponseFeedbackReviewStatus.rejected => Icons.block_outlined,
};

Color _statusColor(
  FfmAssistantResponseFeedbackReviewStatus status,
) => switch (status) {
  FfmAssistantResponseFeedbackReviewStatus.pending => const Color(0xFFC62828),
  FfmAssistantResponseFeedbackReviewStatus.investigating => const Color(
    0xFFEF6C00,
  ),
  FfmAssistantResponseFeedbackReviewStatus.fixed => const Color(0xFF2E7D32),
  FfmAssistantResponseFeedbackReviewStatus.approved => const Color(0xFF1565C0),
  FfmAssistantResponseFeedbackReviewStatus.rejected => Colors.grey,
};
