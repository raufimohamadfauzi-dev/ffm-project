import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/injection.dart';
import '../../data/ffm_assistant_response_feedback_repository.dart';
import '../../data/ffm_assistant_unanswered_question_repository.dart';
import '../../domain/ffm_assistant_models.dart';
import '../widgets/ffm_assistant_page_context.dart';

class FfmAssistantIssueLogPage extends StatefulWidget {
  const FfmAssistantIssueLogPage({super.key});

  @override
  State<FfmAssistantIssueLogPage> createState() =>
      _FfmAssistantIssueLogPageState();
}

enum _IssueExportFormat {
  llmPrompt,
  markdown,
  json,
  shareMarkdown,
}

class _FfmAssistantIssueLogPageState extends State<FfmAssistantIssueLogPage>
    with SingleTickerProviderStateMixin {
  late final FfmAssistantResponseFeedbackRepository _feedbackRepository;
  late final FfmAssistantUnansweredQuestionRepository _unansweredRepository;
  late final TabController _tabController;

  List<FfmAssistantResponseFeedback> _issues = const [];
  List<FfmAssistantUnansweredQuestion> _unanswered = const [];
  var _loading = true;
  String? _error;
  String _searchQuery = '';
  String _selectedOriginFilter = 'all';
  String _selectedStatusFilter = 'all';

  void _retryInChat(String question) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(question);
    } else {
      Clipboard.setData(ClipboardData(text: question));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pertanyaan disalin. Buka chat asisten untuk mencobanya kembali.',
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _feedbackRepository = getIt<FfmAssistantResponseFeedbackRepository>();
    _unansweredRepository = getIt<FfmAssistantUnansweredQuestionRepository>();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final issues = await _feedbackRepository.readAllIssues();
      final unanswered = await _unansweredRepository.readOpen();
      if (!mounted) return;
      setState(() {
        _issues = issues;
        _unanswered = unanswered;
      });
    } on Object {
      if (mounted) setState(() => _error = 'Asisten Log belum dapat dimuat.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<FfmAssistantResponseFeedback> get _filteredIssues {
    return _issues.where((issue) {
      if (_selectedStatusFilter == 'open') {
        if (issue.reviewStatus ==
                FfmAssistantResponseFeedbackReviewStatus.fixed ||
            issue.reviewStatus ==
                FfmAssistantResponseFeedbackReviewStatus.approved ||
            issue.reviewStatus ==
                FfmAssistantResponseFeedbackReviewStatus.rejected) {
          return false;
        }
      } else if (_selectedStatusFilter == 'resolved') {
        if (issue.reviewStatus !=
                FfmAssistantResponseFeedbackReviewStatus.fixed &&
            issue.reviewStatus !=
                FfmAssistantResponseFeedbackReviewStatus.approved &&
            issue.reviewStatus !=
                FfmAssistantResponseFeedbackReviewStatus.rejected) {
          return false;
        }
      }

      if (_selectedOriginFilter != 'all') {
        final origin =
            issue.issueMetadata['responseOrigin']?.toString().toLowerCase() ??
            '';
        if (_selectedOriginFilter == 'gemini' && !origin.contains('gemini')) {
          return false;
        }
        if (_selectedOriginFilter == 'orchestrator' &&
            !origin.contains('orchestrator')) {
          return false;
        }
        if (_selectedOriginFilter == 'rule' && !origin.contains('rule')) {
          return false;
        }
        if (_selectedOriginFilter == 'anomaly' &&
            !origin.contains('anomaly') &&
            !origin.contains('error')) {
          return false;
        }
      }
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      final question = issue.questionText.toLowerCase();
      final answer = issue.responseText.toLowerCase();
      final note = (issue.note ?? '').toLowerCase();
      final plugin =
          (issue.issueMetadata['pluginName'] ?? '').toString().toLowerCase();
      final capability =
          (issue.issueMetadata['usedReadCapability'] ?? '')
              .toString()
              .toLowerCase();
      return question.contains(query) ||
          answer.contains(query) ||
          note.contains(query) ||
          plugin.contains(query) ||
          capability.contains(query);
    }).toList(growable: false);
  }

  List<FfmAssistantUnansweredQuestion> get _filteredUnanswered {
    if (_searchQuery.isEmpty) return _unanswered;
    final query = _searchQuery.toLowerCase();
    return _unanswered
        .where(
          (u) =>
              u.questionText.toLowerCase().contains(query) ||
              (u.pageContext ?? '').toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  String _buildLlmDiagnosticPrompt() {
    final buffer = StringBuffer();
    buffer.writeln(
      '# LAPORAN DIAGNOSTIK ANOMALI ASISTEN FFM UNTUK LLM / AGENT',
    );
    buffer.writeln('');
    buffer.writeln(
      'Halo LLM / AI Coding Assistant, berikut adalah log anomali dan error yang terjadi pada Asisten Keuangan FFM (Family Finance Manager).',
    );
    buffer.writeln(
      'Aplikasi FFM menggunakan arsitektur orkestrator hibrida: logika finansial deterministik di lokal, kemampuan baca terikat (read.summary, read.transactions, dll.), dan Gemini Cloud untuk penalaran.',
    );
    buffer.writeln('');
    buffer.writeln('## LINGKUNGAN SISTEM & ATURAN ARSITEKTUR');
    buffer.writeln('- Target Platform: Android ARM64');
    buffer.writeln('- Arsitektur: Hybrid Orchestrator (Deterministic Local Engine + Gemini Cloud)');
    buffer.writeln('- Bounded Capabilities: read.summary, read.transactions (maks. 8 item terikat)');
    buffer.writeln('- Integritas Finansial: Angka saldo dan transaksi adalah mutlak deterministik dari database lokal. LLM dilarang berhalusinasi.');
    buffer.writeln('- Waktu Ekspor: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
    buffer.writeln('');
    buffer.writeln('TUGAS ANDA:');
    buffer.writeln(
      '1. Analisis mengapa asisten memberikan respon keliru, halusinasi, atau gagal menjawab pertanyaan di bawah ini.',
    );
    buffer.writeln(
      '2. Telusuri apakah akar masalahnya ada di: Prompt / Instruksi, Routing Orkestrator, Read Capability yang dibaca, Format Data lokal, atau UI.',
    );
    buffer.writeln(
      '3. Berikan rekomendasi kode konkret atau perbaikan sistem untuk menyelesaikan masalah ini tanpa memodifikasi data finansial sembarangan.',
    );
    buffer.writeln('');
    buffer.writeln('---');

    if (_issues.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln(
        '## DAFTAR JAWABAN BERMASALAH YANG DILAPORKAN (${_issues.length})',
      );
      for (var i = 0; i < _issues.length; i++) {
        final issue = _issues[i];
        final metadata = issue.issueMetadata;
        buffer.writeln('');
        buffer.writeln('### Masalah #${i + 1}');
        buffer.writeln('- **ID**: `${issue.id}`');
        buffer.writeln(
          '- **Waktu**: `${DateFormat('yyyy-MM-dd HH:mm:ss').format(issue.createdAt)}`',
        );
        buffer.writeln('- **Status Review**: `${issue.reviewStatus.name}`');
        buffer.writeln(
          '- **Origin**: `${metadata['responseOrigin'] ?? 'unknown'}`',
        );
        if (metadata['model'] != null) {
          buffer.writeln('- **Model**: `${metadata['model']}`');
        }
        if (metadata['pluginName'] != null) {
          buffer.writeln('- **Plugin**: `${metadata['pluginName']}`');
        }
        if (metadata['usedReadCapability'] != null) {
          buffer.writeln(
            '- **Read Capability**: `${metadata['usedReadCapability']}`',
          );
        }
        if (issue.pageContext != null) {
          buffer.writeln('- **Halaman**: `${issue.pageContext}`');
        }
        if (issue.note != null && issue.note!.isNotEmpty) {
          buffer.writeln('- **Catatan Pengguna**: ${issue.note}');
        }

        buffer.writeln('');
        buffer.writeln('**Pertanyaan Pengguna**:');
        buffer.writeln('> ${issue.questionText.replaceAll('\n', '\n> ')}');
        buffer.writeln('');
        buffer.writeln('**Jawaban Asisten (Bermasalah)**:');
        buffer.writeln('```text');
        buffer.writeln(issue.responseText);
        buffer.writeln('```');

        final trace = metadata['processTrace'];
        if (trace is Map) {
          buffer.writeln('');
          buffer.writeln('**Execution Trace**:');
          if (trace['elapsedMs'] != null) {
            buffer.writeln('- Total Durasi: `${trace['elapsedMs']}ms`');
          }
          if (trace['fallbackReason'] != null) {
            buffer.writeln('- Fallback Reason: `${trace['fallbackReason']}`');
          }
          if (trace['tokenUsage'] != null) {
            buffer.writeln('- Token Usage: `${trace['tokenUsage']}`');
          }
          final events = trace['events'];
          if (events is List && events.isNotEmpty) {
            buffer.writeln('- Langkah:');
            for (final ev in events) {
              if (ev is Map) {
                final label = ev['label'] ?? '';
                final elapsed = ev['elapsedMs'] ?? 0;
                final detail = ev['detail'];
                buffer.writeln(
                  '  * `[+${elapsed}ms]` $label${detail != null ? ' — _${detail}_' : ''}',
                );
              }
            }
          }
        }
      }
    }

    if (_unanswered.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln(
        '## DAFTAR PERTANYAAN GAGAL DIJAWAB / FALLBACK (${_unanswered.length})',
      );
      for (var i = 0; i < _unanswered.length; i++) {
        final u = _unanswered[i];
        buffer.writeln('');
        buffer.writeln('### Pertanyaan #${i + 1}');
        buffer.writeln('- **Teks Pertanyaan**: "${u.questionText}"');
        buffer.writeln('- **Frekuensi Ditanyakan**: ${u.occurrenceCount} kali');
        if (u.pageContext != null) {
          buffer.writeln('- **Halaman**: `${u.pageContext}`');
        }
        buffer.writeln(
          '- **Waktu Pertama**: `${DateFormat('yyyy-MM-dd HH:mm:ss').format(u.createdAt)}`',
        );
      }
    }

    return buffer.toString();
  }

  Future<void> _handleExportAction(_IssueExportFormat format) async {
    switch (format) {
      case _IssueExportFormat.llmPrompt:
        final prompt = _buildLlmDiagnosticPrompt();
        await Clipboard.setData(ClipboardData(text: prompt));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Prompt diagnostik disalin. Siap ditempel ke ChatGPT, Claude, atau Gemini.',
            ),
          ),
        );
      case _IssueExportFormat.markdown:
        final md = await _feedbackRepository.exportAllIssues();
        await Clipboard.setData(ClipboardData(text: md));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Semua masalah disalin sebagai Markdown.'),
          ),
        );
      case _IssueExportFormat.json:
        final jsonText = await _feedbackRepository.exportAllIssuesJson();
        await Clipboard.setData(ClipboardData(text: jsonText));
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Semua masalah disalin sebagai JSON.')));
      case _IssueExportFormat.shareMarkdown:
        final prompt = _buildLlmDiagnosticPrompt();
        await SharePlus.instance.share(
          ShareParams(
            text: prompt,
            subject: 'FFM Assistant Issue Log Diagnostic Report',
          ),
        );
    }
  }

  Future<void> _copySingleIssuePrompt(FfmAssistantResponseFeedback issue) async {
    final buffer = StringBuffer();
    buffer.writeln('# LAPORAN MASALAH ASISTEN FFM (DIAGNOSTIK LLM)');
    buffer.writeln('');
    buffer.writeln('Tolong analisis masalah asisten keuangan FFM berikut:');
    buffer.writeln('');
    buffer.writeln('## INFORMASI EKSEKUSI');
    buffer.writeln('- ID Masalah: `${issue.id}`');
    buffer.writeln('- Tanggal: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(issue.createdAt)}');
    final metadata = issue.issueMetadata;
    buffer.writeln('- Origin: `${metadata['responseOrigin'] ?? 'unknown'}`');
    if (metadata['model'] != null) buffer.writeln('- Model: `${metadata['model']}`');
    if (metadata['pluginName'] != null) buffer.writeln('- Plugin: `${metadata['pluginName']}`');
    if (metadata['usedReadCapability'] != null) {
      buffer.writeln('- Read Capability: `${metadata['usedReadCapability']}`');
    }
    if (issue.note != null && issue.note!.isNotEmpty) buffer.writeln('- Catatan: ${issue.note}');
    buffer.writeln('');
    buffer.writeln('## PERTANYAAN USER');
    buffer.writeln('> ${issue.questionText.replaceAll('\n', '\n> ')}');
    buffer.writeln('');
    buffer.writeln('## JAWABAN ASISTEN (BERMASALAH)');
    buffer.writeln('```text');
    buffer.writeln(issue.responseText);
    buffer.writeln('```');

    final trace = metadata['processTrace'];
    if (trace is Map) {
      buffer.writeln('');
      buffer.writeln('## PROCESS TRACE');
      if (trace['elapsedMs'] != null) buffer.writeln('- Total Durasi: `${trace['elapsedMs']}ms`');
      if (trace['fallbackReason'] != null) buffer.writeln('- Fallback Reason: `${trace['fallbackReason']}`');
      final events = trace['events'];
      if (events is List && events.isNotEmpty) {
        buffer.writeln('- Timeline:');
        for (final ev in events) {
          if (ev is Map) {
            buffer.writeln('  * `[+${ev['elapsedMs']}ms]` ${ev['label']}${ev['detail'] != null ? ' (${ev['detail']})' : ''}');
          }
        }
      }
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Prompt diagnostik masalah ini telah disalin.')),
    );
  }

  Future<void> _deleteIssue(FfmAssistantResponseFeedback issue) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus masalah ini?'),
        content: const Text(
          'Log ini akan dihapus dari Asisten Log. Jawaban aslinya di chat dapat dilaporkan lagi jika diperlukan.',
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
    await _feedbackRepository.delete(issue.id);
    if (!mounted) return;
    setState(() => _issues = _issues.where((i) => i.id != issue.id).toList());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Masalah dihapus dari Asisten Log.')),
    );
  }

  Future<void> _clearAllLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus semua log asisten?'),
        content: const Text(
          'Semua catatan jawaban bermasalah dan pertanyaan tak terjawab akan dihapus permanen. Data finansial keluarga tetap aman.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus Semua'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _feedbackRepository.deleteAllIssues();
    await _unansweredRepository.deleteAll();
    if (!mounted) return;
    setState(() {
      _issues = const [];
      _unanswered = const [];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Semua log asisten berhasil dibersihkan.')),
    );
  }

  Future<void> _resolveUnanswered(FfmAssistantUnansweredQuestion question) async {
    await _unansweredRepository.markResolved(question.id);
    if (!mounted) return;
    setState(() => _unanswered = _unanswered.where((u) => u.id != question.id).toList());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pertanyaan ditandai selesai.')),
    );
  }

  Future<void> _deleteUnanswered(FfmAssistantUnansweredQuestion question) async {
    await _unansweredRepository.deletePermanently(question.id);
    if (!mounted) return;
    setState(() => _unanswered = _unanswered.where((u) => u.id != question.id).toList());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pertanyaan dihapus.')),
    );
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
          maxLines: 4,
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
    await _feedbackRepository.updateIssueNote(
      issue.id,
      normalized.isEmpty ? null : normalized,
    );
    if (!mounted) return;
    setState(() {
      _issues = _issues.map((i) {
        if (i.id != issue.id) return i;
        return FfmAssistantResponseFeedback(
          id: i.id,
          questionText: i.questionText,
          responseText: i.responseText,
          kind: i.kind,
          reviewStatus: i.reviewStatus,
          isArchived: i.isArchived,
          createdAt: i.createdAt,
          note: normalized.isEmpty ? null : normalized,
          pageContext: i.pageContext,
          updatedAt: DateTime.now(),
          sourceMessageId: i.sourceMessageId,
          issueMetadata: i.issueMetadata,
        );
      }).toList(growable: false);
    });
  }

  Future<void> _changeStatus(
    FfmAssistantResponseFeedback issue,
    FfmAssistantResponseFeedbackReviewStatus status,
  ) async {
    await _feedbackRepository.setReviewStatus(issue.id, status);
    if (!mounted) return;
    setState(() {
      _issues = _issues.map((i) {
        if (i.id != issue.id) return i;
        return FfmAssistantResponseFeedback(
          id: i.id,
          questionText: i.questionText,
          responseText: i.responseText,
          kind: i.kind,
          reviewStatus: status,
          isArchived: i.isArchived,
          createdAt: i.createdAt,
          note: i.note,
          pageContext: i.pageContext,
          updatedAt: DateTime.now(),
          sourceMessageId: i.sourceMessageId,
          issueMetadata: i.issueMetadata,
        );
      }).toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalCount = _issues.length + _unanswered.length;

    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.assistantIssueLog,
      child: Scaffold(
        appBar: AppBar(
        title: const Text('Asisten Log & Anomali'),
        actions: [
          PopupMenuButton<_IssueExportFormat>(
            tooltip: 'Ekspor & Bagikan',
            enabled: totalCount > 0,
            onSelected: _handleExportAction,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _IssueExportFormat.llmPrompt,
                child: Row(
                  children: [
                    Icon(Icons.smart_toy_outlined, color: Colors.purple, size: 20),
                    SizedBox(width: 10),
                    Text('Salin Prompt Diagnostik LLM'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _IssueExportFormat.markdown,
                child: Row(
                  children: [
                    Icon(Icons.description_outlined, color: Colors.blue, size: 20),
                    SizedBox(width: 10),
                    Text('Salin Semua (Markdown .md)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _IssueExportFormat.json,
                child: Row(
                  children: [
                    Icon(Icons.data_object_rounded, color: Colors.teal, size: 20),
                    SizedBox(width: 10),
                    Text('Salin Semua (JSON .json)'),
                  ],
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _IssueExportFormat.shareMarkdown,
                child: Row(
                  children: [
                    Icon(Icons.share_outlined, color: Colors.green, size: 20),
                    SizedBox(width: 10),
                    Text('Bagikan File Log (.md)'),
                  ],
                ),
              ),
            ],
            icon: const Icon(Icons.ios_share_rounded),
          ),
          if (totalCount > 0)
            IconButton(
              tooltip: 'Hapus Semua Log',
              onPressed: _clearAllLogs,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Semua ($totalCount)'),
              Tab(text: 'Jawaban Bermasalah (${_issues.length})'),
              Tab(text: 'Gagal Dijawab (${_unanswered.length})'),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : totalCount == 0
          ? const _EmptyIssueState()
          : Column(
              children: [
                _buildSearchAndFilters(isDark),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 0: Semua
                      _buildCombinedTab(),
                      // Tab 1: Jawaban Bermasalah
                      _buildIssuesTab(),
                      // Tab 2: Gagal Dijawab
                      _buildUnansweredTab(),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildSearchAndFilters(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF9FAFB),
      child: Column(
        children: [
          TextField(
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
            decoration: InputDecoration(
              hintText: 'Cari pertanyaan, jawaban, atau capability...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _searchQuery = ''),
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('all', 'Semua Origin'),
                const SizedBox(width: 6),
                _filterChip('gemini', '✨ Gemini Cloud'),
                const SizedBox(width: 6),
                _filterChip('orchestrator', '🧠 Orkestrator'),
                const SizedBox(width: 6),
                _filterChip('rule', '⚡ Aturan Lokal'),
                const SizedBox(width: 6),
                _filterChip('anomaly', '⚠️ Anomali Cloud'),
                const SizedBox(width: 10),
                Container(
                  height: 18,
                  width: 1,
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
                const SizedBox(width: 10),
                _statusFilterChip('all', 'Semua Status'),
                const SizedBox(width: 6),
                _statusFilterChip('open', '⏳ Perlu Review'),
                const SizedBox(width: 6),
                _statusFilterChip('resolved', '✅ Selesai'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String id, String label) {
    final selected = _selectedOriginFilter == id;
    return FilterChip(
      selected: selected,
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onSelected: (_) => setState(() => _selectedOriginFilter = id),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _statusFilterChip(String id, String label) {
    final selected = _selectedStatusFilter == id;
    return FilterChip(
      selected: selected,
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onSelected: (_) => setState(() => _selectedStatusFilter = id),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildCombinedTab() {
    final issues = _filteredIssues;
    final unanswered = _filteredUnanswered;
    if (issues.isEmpty && unanswered.isEmpty) {
      return const _EmptySearchState();
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          if (issues.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Text(
                'JAWABAN BERMASALAH (${issues.length})',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Colors.grey,
                ),
              ),
            ),
            ...issues.map(
              (issue) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _IssueTile(
                  issue: issue,
                  onCopyPrompt: () => _copySingleIssuePrompt(issue),
                  onRetryInChat: () => _retryInChat(issue.questionText),
                  onDelete: () => _deleteIssue(issue),
                  onEditNote: () => _editNote(issue),
                  onChangeStatus: (s) => _changeStatus(issue, s),
                ),
              ),
            ),
          ],
          if (unanswered.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 16),
              child: Text(
                'PERTANYAAN GAGAL DIJAWAB (${unanswered.length})',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Colors.grey,
                ),
              ),
            ),
            ...unanswered.map(
              (u) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _UnansweredTile(
                  item: u,
                  onRetryInChat: () => _retryInChat(u.questionText),
                  onResolve: () => _resolveUnanswered(u),
                  onDelete: () => _deleteUnanswered(u),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIssuesTab() {
    final issues = _filteredIssues;
    if (issues.isEmpty) return const _EmptySearchState();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        itemCount: issues.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, index) => _IssueTile(
          issue: issues[index],
          onCopyPrompt: () => _copySingleIssuePrompt(issues[index]),
          onRetryInChat: () => _retryInChat(issues[index].questionText),
          onDelete: () => _deleteIssue(issues[index]),
          onEditNote: () => _editNote(issues[index]),
          onChangeStatus: (s) => _changeStatus(issues[index], s),
        ),
      ),
    );
  }

  Widget _buildUnansweredTab() {
    final unanswered = _filteredUnanswered;
    if (unanswered.isEmpty) return const _EmptySearchState();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        itemCount: unanswered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, index) => _UnansweredTile(
          item: unanswered[index],
          onRetryInChat: () => _retryInChat(unanswered[index].questionText),
          onResolve: () => _resolveUnanswered(unanswered[index]),
          onDelete: () => _deleteUnanswered(unanswered[index]),
        ),
      ),
    );
  }
}

class _IssueTile extends StatelessWidget {
  const _IssueTile({
    required this.issue,
    required this.onCopyPrompt,
    required this.onRetryInChat,
    required this.onDelete,
    required this.onEditNote,
    required this.onChangeStatus,
  });

  final FfmAssistantResponseFeedback issue;
  final VoidCallback onCopyPrompt;
  final VoidCallback onRetryInChat;
  final VoidCallback onDelete;
  final VoidCallback onEditNote;
  final ValueChanged<FfmAssistantResponseFeedbackReviewStatus> onChangeStatus;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final metadata = issue.issueMetadata;
    final origin = metadata['responseOrigin']?.toString().toLowerCase() ?? '';
    final problemKind = metadata['problemKind']?.toString() ?? issue.kind.name;
    final model = metadata['model']?.toString();
    final usedReadCapability = metadata['usedReadCapability']?.toString();
    final pluginName = metadata['pluginName']?.toString();
    final statusColor = _statusColor(issue.reviewStatus);

    final originBadge = _originBadgeData(origin);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: originBadge.color.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: .15),
          foregroundColor: statusColor,
          child: Icon(_statusIcon(issue.reviewStatus), size: 22),
        ),
        title: Text(
          issue.questionText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ChipBadge(
                label: originBadge.label,
                color: originBadge.color,
                bgColor: originBadge.bgColor,
              ),
              _ChipBadge(
                label: _statusLabel(issue.reviewStatus),
                color: statusColor,
                bgColor: statusColor.withValues(alpha: 0.12),
              ),
              if (usedReadCapability != null)
                _ChipBadge(
                  label: usedReadCapability,
                  color: Colors.blueGrey,
                  bgColor: Colors.blueGrey.withValues(alpha: 0.12),
                ),
              Text(
                DateFormat('dd MMM HH:mm').format(issue.createdAt),
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Divider(height: 20),
          // Diagnostic info grid
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF242424) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetaRow(label: 'Jenis Masalah', value: problemKind),
                _MetaRow(label: 'Origin Asisten', value: originBadge.label),
                if (model != null) _MetaRow(label: 'Model / AI', value: model),
                if (pluginName != null)
                  _MetaRow(label: 'Plugin Terlibat', value: pluginName),
                if (usedReadCapability != null)
                  _MetaRow(label: 'Data Dibaca', value: usedReadCapability),
                if (issue.pageContext != null)
                  _MetaRow(label: 'Halaman Konteks', value: issue.pageContext!),
                if (issue.note != null && issue.note!.isNotEmpty)
                  _MetaRow(label: 'Catatan User', value: issue.note!),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // User question block
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Pertanyaan Pengguna:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.blue.withValues(alpha: 0.2),
              ),
            ),
            child: SelectableText(
              issue.questionText,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),

          // Assistant answer block
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Jawaban Asisten (Bermasalah):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
            ),
            child: SelectableText(
              issue.responseText,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),

          // Process trace timeline
          if (metadata['processTrace'] is Map) ...[
            const SizedBox(height: 14),
            _ProcessTraceSection(trace: metadata['processTrace'] as Map),
          ],

          const SizedBox(height: 16),
          // Action buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onRetryInChat,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Coba di Chat'),
              ),
              FilledButton.tonalIcon(
                onPressed: onCopyPrompt,
                icon: const Icon(Icons.smart_toy_outlined, size: 18),
                label: const Text('Salin Prompt LLM'),
              ),
              OutlinedButton.icon(
                onPressed: onEditNote,
                icon: const Icon(Icons.edit_note_outlined, size: 18),
                label: const Text('Catatan'),
              ),
              PopupMenuButton<FfmAssistantResponseFeedbackReviewStatus>(
                onSelected: onChangeStatus,
                itemBuilder: (context) =>
                    FfmAssistantResponseFeedbackReviewStatus.values
                        .map(
                          (status) => PopupMenuItem(
                            value: status,
                            child: Row(
                              children: [
                                Icon(_statusIcon(status), color: _statusColor(status), size: 18),
                                const SizedBox(width: 8),
                                Text(_statusLabel(status)),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                child: OutlinedButton.icon(
                  onPressed: null,
                  icon: Icon(Icons.flag_outlined, color: statusColor, size: 18),
                  label: Text(
                    _statusLabel(issue.reviewStatus),
                    style: TextStyle(color: statusColor),
                  ),
                ),
              ),
              IconButton.outlined(
                tooltip: 'Hapus log',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UnansweredTile extends StatelessWidget {
  const _UnansweredTile({
    required this.item,
    required this.onRetryInChat,
    required this.onResolve,
    required this.onDelete,
  });

  final FfmAssistantUnansweredQuestion item;
  final VoidCallback onRetryInChat;
  final VoidCallback onResolve;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.amber.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.help_outline_rounded, size: 14, color: Colors.amber),
                      SizedBox(width: 4),
                      Text(
                        'Gagal Dijawab / Fallback',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white12 : Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${item.occurrenceCount}x ditanyakan',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('dd MMM HH:mm').format(item.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              item.questionText,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            if (item.pageContext != null) ...[
              const SizedBox(height: 6),
              Text(
                'Konteks: ${item.pageContext}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onRetryInChat,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                  label: const Text('Tanyakan ke Asisten'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final text =
                        'Pertanyaan gagal dijawab asisten FFM:\n"${item.questionText}"\n(Konteks: ${item.pageContext ?? '-'})';
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Pertanyaan disalin.')),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('Salin'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onResolve,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Selesai'),
                ),
                IconButton.outlined(
                  tooltip: 'Hapus',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProcessTraceSection extends StatelessWidget {
  const _ProcessTraceSection({required this.trace});

  final Map trace;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final elapsedMs = trace['elapsedMs'];
    final fallbackReason = trace['fallbackReason'];
    final events = trace['events'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline_rounded, size: 16, color: Colors.indigo),
              const SizedBox(width: 6),
              const Text(
                'Trace Eksekusi & Audit',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const Spacer(),
              if (elapsedMs != null)
                Text(
                  'Total: ${elapsedMs}ms',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.indigo,
                  ),
                ),
            ],
          ),
          if (fallbackReason != null) ...[
            const SizedBox(height: 6),
            Text(
              'Alasan Fallback: $fallbackReason',
              style: const TextStyle(fontSize: 11, color: Colors.amber),
            ),
          ],
          if (events is List && events.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...events.map((e) {
              if (e is! Map) return const SizedBox.shrink();
              final label = e['label']?.toString() ?? '';
              final elapsed = e['elapsedMs']?.toString() ?? '0';
              final detail = e['detail']?.toString();
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '[+${elapsed}ms]',
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: const TextStyle(fontSize: 12)),
                          if (detail != null)
                            Text(
                              detail,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipBadge extends StatelessWidget {
  const _ChipBadge({
    required this.label,
    required this.color,
    required this.bgColor,
  });

  final String label;
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _OriginBadgeData {
  const _OriginBadgeData({
    required this.label,
    required this.color,
    required this.bgColor,
  });

  final String label;
  final Color color;
  final Color bgColor;
}

_OriginBadgeData _originBadgeData(String origin) {
  if (origin.contains('geminicloud') || origin.contains('gemini')) {
    return const _OriginBadgeData(
      label: '✨ Gemini Cloud',
      color: Color(0xFF059669),
      bgColor: Color(0xFFD1FAE5),
    );
  }
  if (origin.contains('rule') || origin.contains('offline')) {
    return const _OriginBadgeData(
      label: '⚡ Aturan Lokal',
      color: Color(0xFFD97706),
      bgColor: Color(0xFFFEF3C7),
    );
  }
  if (origin.contains('error') || origin.contains('anomaly')) {
    return const _OriginBadgeData(
      label: '⚠️ Anomali Cloud',
      color: Color(0xFFE11D48),
      bgColor: Color(0xFFFFE4E6),
    );
  }
  return const _OriginBadgeData(
    label: '🧠 Orkestrator Lokal',
    color: Color(0xFF4F46E5),
    bgColor: Color(0xFFEEF2FF),
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
            Icons.check_circle_outline_rounded,
            size: 56,
            color: Colors.green.shade600,
          ),
          const SizedBox(height: 14),
          const Text(
            'Asisten Bekerja Normal',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          const SizedBox(height: 8),
          const Text(
            'Belum ada laporan jawaban keliru atau pertanyaan gagal dijawab.\n\nJika asisten memberikan jawaban ngaco atau salah angka di chat, tekan tombol "Laporkan" pada pesan tersebut.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, height: 1.4),
          ),
        ],
      ),
    ),
  );
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          const Text(
            'Tidak ada log yang cocok',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            'Coba ubah kata kunci pencarian atau filter origin.',
            style: TextStyle(color: Colors.grey),
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
