import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../data/ffm_assistant_memory_repository.dart';
import '../../data/ffm_personal_memory_control_service.dart';

/// Pusat kontrol untuk memori tahan lama yang telah disetujui dan eligible
/// untuk context engine. Riwayat chat mentah dan draft tidak pernah tampil.
class FfmMemoryViewerPage extends StatefulWidget {
  const FfmMemoryViewerPage({super.key});

  @override
  State<FfmMemoryViewerPage> createState() => _FfmMemoryViewerPageState();
}

class _FfmMemoryViewerPageState extends State<FfmMemoryViewerPage> {
  late final FfmPersonalMemoryControlService _service;
  List<FfmPersonalMemoryControlItem> _items = const [];
  List<FfmPendingMemoryItem> _pendingItems = const [];
  FfmPersonalMemoryControlScope? _filter;
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _service = FfmPersonalMemoryControlService(
      getIt<FfmAssistantMemoryRepository>(),
    );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.readVisible(),
        _service.readPendingLearning(),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<FfmPersonalMemoryControlItem>;
        _pendingItems = results[1] as List<FfmPendingMemoryItem>;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Memori belum dapat dimuat. Coba muat ulang.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approvePending(FfmPendingMemoryItem item) async {
    final ok = await _service.approvePending(item.id);
    if (!mounted) return;
    if (ok) {
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('“${item.kindLabel}” disetujui dan mulai dipakai Asisten.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Memori belum dapat disetujui. Coba lagi.')),
      );
    }
  }

  Future<void> _rejectPending(FfmPendingMemoryItem item) async {
    try {
      await _service.rejectPending(item.id);
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usulan memori dibuang tanpa dipakai.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Memori belum dapat dibuang. Coba lagi.')),
      );
    }
  }

  Future<void> _forget(FfmPersonalMemoryControlItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lupakan memori ini?'),
        content: Text(
          'Asisten tidak akan memakai “${item.label}” pada percakapan berikutnya. Tindakan ini tidak menghapus riwayat chat dan tidak mengubah data keuangan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Lupakan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.forget(item.id);
      if (!mounted) return;
      setState(
        () => _items = _items.where((entry) => entry.id != item.id).toList(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Memori dilupakan secara lokal.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Memori belum dapat dilupakan. Coba lagi.'),
        ),
      );
    }
  }

  List<FfmPersonalMemoryControlItem> get _visibleItems => _filter == null
      ? _items
      : _items.where((item) => item.scope == _filter).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pusat Kontrol Memori'),
        actions: [
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
          ? _ErrorState(message: _error!, onRetry: _load)
          : _buildContent(theme),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final items = _visibleItems;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Card(
          color: theme.colorScheme.secondaryContainer,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.privacy_tip_outlined),
                    SizedBox(width: 8),
                    Text(
                      'Memori yang dapat dipakai Asisten',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'Hanya item lokal yang telah disetujui dan lolos filter privasi tampil di sini. Riwayat chat, draft, PIN, data finansial mentah, dan metadata teknis tidak disimpan sebagai daftar memori.',
                ),
                SizedBox(height: 8),
                Text(
                  'Reset chat hanya menghapus konteks sementara. Gunakan “Lupakan” untuk menghentikan pemakaian item ini pada percakapan berikutnya.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_pendingItems.isNotEmpty) ...[
          _PendingSection(
            items: _pendingItems,
            onApprove: _approvePending,
            onReject: _rejectPending,
          ),
          const SizedBox(height: 16),
        ],
        _buildFilters(),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _EmptyState(hasItems: _items.isNotEmpty)
        else
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MemoryItemCard(item: item, onForget: () => _forget(item)),
            ),
          ),
      ],
    );
  }

  Widget _buildFilters() {
    final entries = <(FfmPersonalMemoryControlScope?, String, IconData)>[
      (null, 'Semua', Icons.apps_outlined),
      (FfmPersonalMemoryControlScope.userModel, 'Profil', Icons.person_outline),
      (
        FfmPersonalMemoryControlScope.personalMemory,
        'Memori',
        Icons.psychology_outlined,
      ),
      (
        FfmPersonalMemoryControlScope.aliasCorrection,
        'Koreksi',
        Icons.spellcheck_outlined,
      ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: entries.map((entry) {
        final (scope, label, icon) = entry;
        final count = scope == null
            ? _items.length
            : _items.where((item) => item.scope == scope).length;
        return FilterChip(
          selected: _filter == scope,
          avatar: Icon(icon, size: 16),
          label: Text('$label ($count)'),
          onSelected: (_) => setState(() => _filter = scope),
        );
      }).toList(),
    );
  }
}

class _PendingSection extends StatelessWidget {
  const _PendingSection({
    required this.items,
    required this.onApprove,
    required this.onReject,
  });

  final List<FfmPendingMemoryItem> items;
  final Future<void> Function(FfmPendingMemoryItem) onApprove;
  final Future<void> Function(FfmPendingMemoryItem) onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pending_actions_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Menunggu Persetujuan (${items.length})',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Tersimpulan otomatis dari percakapanmu. Setujui agar Asisten boleh memakainya, atau buang bila kurang tepat.',
            ),
            const SizedBox(height: 10),
            ...items.map(
              (item) => _PendingItemCard(
                item: item,
                onApprove: () => onApprove(item),
                onReject: () => onReject(item),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingItemCard extends StatelessWidget {
  const _PendingItemCard({
    required this.item,
    required this.onApprove,
    required this.onReject,
  });

  final FfmPendingMemoryItem item;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.kindLabel.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: .3,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(item.value, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onReject,
                child: const Text('Buang'),
              ),
              const SizedBox(width: 4),
              FilledButton.tonalIcon(
                onPressed: onApprove,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Setujui'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemoryItemCard extends StatelessWidget {  const _MemoryItemCard({required this.item, required this.onForget});

  final FfmPersonalMemoryControlItem item;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (item.scope) {
      FfmPersonalMemoryControlScope.userModel => theme.colorScheme.primary,
      FfmPersonalMemoryControlScope.personalMemory =>
        theme.colorScheme.tertiary,
      FfmPersonalMemoryControlScope.aliasCorrection =>
        theme.colorScheme.secondary,
    };
    final icon = switch (item.scope) {
      FfmPersonalMemoryControlScope.userModel => Icons.person_outline,
      FfmPersonalMemoryControlScope.personalMemory => Icons.psychology_outlined,
      FfmPersonalMemoryControlScope.aliasCorrection =>
        Icons.spellcheck_outlined,
    };
    final date = DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(item.savedAt);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .12),
          foregroundColor: color,
          child: Icon(icon),
        ),
        title: Text(
          item.label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            Text(item.value),
            const SizedBox(height: 6),
            Text('${item.sourceLabel} • $date'),
          ],
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'Lupakan memori',
          onPressed: onForget,
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasItems});

  final bool hasItems;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
    child: Column(
      children: [
        const Icon(Icons.visibility_off_outlined, size: 42),
        const SizedBox(height: 12),
        Text(
          hasItems
              ? 'Tidak ada memori pada kategori ini'
              : 'Belum ada memori tersimpan',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        const Text(
          'Memori hanya muncul setelah persetujuan eksplisit. Asisten tetap dapat membantu tanpa menyimpan fakta baru secara otomatis.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 42),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Muat ulang'),
          ),
        ],
      ),
    ),
  );
}
