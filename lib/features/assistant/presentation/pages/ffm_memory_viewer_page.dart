import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../data/ffm_assistant_memory_repository.dart';
import '../../data/ffm_personal_memory_service.dart';

/// Halaman "Apa yang aku ketahui tentang kamu" — tampilkan dan kelola
/// semua memori pribadi yang telah user setujui.
///
/// Dibuka dari ikon 🧠 di header asisten.
class FfmMemoryViewerPage extends StatefulWidget {
  const FfmMemoryViewerPage({super.key});

  @override
  State<FfmMemoryViewerPage> createState() => _FfmMemoryViewerPageState();
}

class _FfmMemoryViewerPageState extends State<FfmMemoryViewerPage> {
  late final FfmPersonalMemoryService _service;
  List<FfmPersonalMemoryInsight> _all = const [];
  bool _loading = true;

  FfmPersonalMemoryKind? _filterKind;

  @override
  void initState() {
    super.initState();
    _service = FfmPersonalMemoryService(getIt<FfmAssistantMemoryRepository>());
    _load();
  }

  Future<void> _load() async {
    final all = await _service.readAll();
    if (!mounted) return;
    setState(() {
      _all = all;
      _loading = false;
    });
  }

  Future<void> _forget(FfmPersonalMemoryInsight insight) async {
    final id = insight.id;
    if (id == null) return;
    await _service.forget(id);
    setState(() {
      _all = _all.where((i) => i.id != id).toList();
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Memori dihapus'),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {},
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<FfmPersonalMemoryInsight> get _filtered => _filterKind == null
      ? _all
      : _all.where((i) => i.kind == _filterKind).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF10181C) : const Color(0xFFF5F9FA),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF14191C) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00D18F).withValues(alpha: 0.15),
              ),
              child: const Center(
                child: Icon(Icons.psychology_rounded, size: 17, color: Color(0xFF00D18F)),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Memori Pribadi',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  'Apa yang aku ketahui tentang kamu',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _all.isEmpty
              ? _buildEmptyState(isDark, theme)
              : Column(
                  children: [
                    _buildFilterChips(theme, isDark),
                    Expanded(child: _buildList(theme, isDark)),
                  ],
                ),
    );
  }

  Widget _buildEmptyState(bool isDark, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark
                  ? const Color(0xFF1B2428)
                  : const Color(0xFFE6F4EE),
            ),
            child: const Center(
              child: Icon(
                Icons.psychology_outlined,
                size: 36,
                color: Color(0xFF00D18F),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Belum ada memori tersimpan',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Ketika kamu menyebutkan sesuatu tentang dirimu dalam percakapan, asisten akan bertanya apakah boleh mengingatnya.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(ThemeData theme, bool isDark) {
    final chips = [
      (null, 'Semua', Icons.apps_rounded),
      (FfmPersonalMemoryKind.preference, 'Preferensi', Icons.lightbulb_outline_rounded),
      (FfmPersonalMemoryKind.habitChat, 'Dari Chat', Icons.chat_bubble_outline_rounded),
      (FfmPersonalMemoryKind.habitData, 'Dari Data', Icons.bar_chart_rounded),
    ];

    return Container(
      color: isDark ? const Color(0xFF14191C) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: chips.map((chip) {
            final (kind, label, icon) = chip;
            final isSelected = _filterKind == kind;
            final count = kind == null
                ? _all.length
                : _all.where((i) => i.kind == kind).length;
            if (count == 0 && kind != null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: isSelected,
                avatar: Icon(icon, size: 14),
                label: Text('$label ($count)'),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                onSelected: (_) => setState(() => _filterKind = kind),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme, bool isDark) {
    final items = _filtered;
    if (items.isEmpty) {
      return const Center(child: Text('Tidak ada memori di kategori ini'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildMemoryTile(items[index], theme, isDark),
    );
  }

  Widget _buildMemoryTile(
    FfmPersonalMemoryInsight insight,
    ThemeData theme,
    bool isDark,
  ) {
    final sourceLabel = switch (insight.kind) {
      FfmPersonalMemoryKind.preference => 'Dari percakapan',
      FfmPersonalMemoryKind.habitChat => 'Kebiasaan chat',
      FfmPersonalMemoryKind.habitData => 'Dari data transaksi',
    };

    final kindColor = switch (insight.kind) {
      FfmPersonalMemoryKind.preference => const Color(0xFF00C5FF),
      FfmPersonalMemoryKind.habitChat => const Color(0xFF9C7FFF),
      FfmPersonalMemoryKind.habitData => const Color(0xFF00D18F),
    };

    final kindIcon = switch (insight.kind) {
      FfmPersonalMemoryKind.preference => Icons.lightbulb_outline_rounded,
      FfmPersonalMemoryKind.habitChat => Icons.chat_bubble_outline_rounded,
      FfmPersonalMemoryKind.habitData => Icons.bar_chart_rounded,
    };

    final df = DateFormat('d MMM yyyy, HH:mm', 'id_ID');
    final dateStr = insight.savedAt != null ? df.format(insight.savedAt!) : '-';

    return Dismissible(
      key: Key(insight.id ?? insight.key),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.red),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Hapus memori?'),
            content: Text(
              'Asisten akan melupakan: ${insight.humanLabel}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Hapus'),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => _forget(insight),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B2428) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: kindColor.withValues(alpha: 0.25),
            width: 0.8,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kindColor.withValues(alpha: 0.12),
              ),
              child: Center(
                child: Icon(kindIcon, size: 17, color: kindColor),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    insight.humanLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_outlined,
                        size: 11,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: kindColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          sourceLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: kindColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (insight.sourceMessage != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '"${insight.sourceMessage}"',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => _forget(insight),
              icon: Icon(
                Icons.close_rounded,
                size: 17,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
