import 'package:flutter/material.dart';

import '../../domain/ffm_assistant_models.dart';

/// Avatar Claude-style: lingkaran solid warm terracotta, tanpa animasi gradient.
/// Nama class dipertahankan sebagai GeminiAvatar untuk kompatibilitas import.
class GeminiAvatar extends StatelessWidget {
  const GeminiAvatar({super.key, this.size = 42});

  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? const Color(0xFF8B5A3C) : const Color(0xFFC27B5F),
        border: Border.all(
          color: isDark ? const Color(0xFF3A2A20) : const Color(0xFFE8DCC8),
          width: 1.5,
        ),
      ),
      child: const Center(
        child: Icon(Icons.auto_awesome, size: 20, color: Colors.white),
      ),
    );
  }
}

/// Header asisten gaya Claude: warm paper, minimal, status chip di bawah judul.
/// Nama class dipertahankan sebagai GeminiHeader agar pemanggil tidak perlu diubah.
class GeminiHeader extends StatelessWidget {
  const GeminiHeader({
    super.key,
    required this.currentPage,
    required this.isFullScreen,
    required this.onToggleFullScreen,
    this.showFullscreenToggle = true,
    required this.onOpenVoicePicker,
    required this.onResetChat,
    required this.onClose,
    required this.cloudChecking,
    required this.cloudReady,
    required this.cloudStatusError,
    required this.onRefreshCloudStatus,
    this.onSetupGemini,
    this.cloudModel,
    this.onOpenMemory,
    this.memoryCount = 0,
    this.onOpenInbox,
    this.inboxCount = 0,
  });

  final FfmAssistantPage? currentPage;
  final bool isFullScreen;
  final VoidCallback onToggleFullScreen;
  final bool showFullscreenToggle;
  final VoidCallback onOpenVoicePicker;
  final VoidCallback onResetChat;
  final VoidCallback onClose;
  final bool cloudChecking;
  final bool cloudReady;
  final String? cloudStatusError;
  final VoidCallback onRefreshCloudStatus;
  final VoidCallback? onSetupGemini;
  final String? cloudModel;
  final VoidCallback? onOpenMemory;
  final int memoryCount;
  final VoidCallback? onOpenInbox;
  final int inboxCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color statusColor;
    final IconData statusIcon;
    final String statusLabel;
    final bool showSetupAction;

    if (cloudChecking) {
      statusColor = isDark ? const Color(0xFF8B8B8B) : const Color(0xFF8A7E6B);
      statusIcon = Icons.hourglass_top_rounded;
      statusLabel = 'Memeriksa AI';
      showSetupAction = false;
    } else if (cloudReady) {
      statusColor = isDark ? const Color(0xFF7BA37B) : const Color(0xFF6B7F5B);
      statusIcon = Icons.verified_outlined;
      statusLabel = cloudModel == null || cloudModel!.trim().isEmpty
          ? 'Gemini Cloud siap'
          : 'Gemini Cloud siap · ${cloudModel!.trim()}';
      showSetupAction = false;
    } else {
      statusColor = isDark ? const Color(0xFFC49A6B) : const Color(0xFFB07A4A);
      statusIcon = Icons.edit_note_outlined;
      statusLabel = cloudStatusError ?? 'Gemini Cloud belum aktif (Perlu Key)';
      showSetupAction = onSetupGemini != null;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B18) : const Color(0xFFFDFCF9),
        borderRadius: isFullScreen
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF2E2A26) : const Color(0xFFE8E0D0),
            width: 0.8,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const GeminiAvatar(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Asisten FFM',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: isDark
                            ? const Color(0xFFEDE8E0)
                            : const Color(0xFF2B2117),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currentPage == null
                          ? 'Konteks umum • data chat lokal'
                          : 'Halaman: ${currentPage!.name}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? const Color(0xFF9A9590)
                            : const Color(0xFF8A7E6B),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (showFullscreenToggle)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: isFullScreen ? 'Tampilan normal' : 'Layar penuh',
                  onPressed: onToggleFullScreen,
                  icon: Icon(
                    isFullScreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    size: 22,
                    color: isDark
                        ? const Color(0xFF9A9590)
                        : const Color(0xFF6B5E4F),
                  ),
                ),
              if (onOpenMemory != null)
                Stack(
                  alignment: Alignment.topRight,
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Memori Pribadi ($memoryCount tersimpan)',
                      onPressed: onOpenMemory,
                      icon: Icon(
                        Icons.psychology_outlined,
                        size: 21,
                        color: isDark
                            ? const Color(0xFF9A9590)
                            : const Color(0xFF6B5E4F),
                      ),
                    ),
                    if (memoryCount > 0)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark
                                ? const Color(0xFF7BA37B)
                                : const Color(0xFFC27B5F),
                          ),
                          child: Center(
                            child: Text(
                              memoryCount > 9 ? '9+' : '$memoryCount',
                              style: const TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              if (onOpenInbox != null)
                Stack(
                  alignment: Alignment.topRight,
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Kotak Masuk Asisten ($inboxCount catatan)',
                      onPressed: onOpenInbox,
                      icon: Icon(
                        inboxCount > 0
                            ? Icons.inbox_rounded
                            : Icons.inbox_outlined,
                        size: 21,
                        color: inboxCount > 0
                            ? (isDark
                                ? const Color(0xFFC49A6B)
                                : const Color(0xFFB07A4A))
                            : (isDark
                                ? const Color(0xFF9A9590)
                                : const Color(0xFF6B5E4F)),
                      ),
                    ),
                    if (inboxCount > 0)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark
                                ? const Color(0xFFC49A6B)
                                : const Color(0xFFB07A4A),
                          ),
                          child: Center(
                            child: Text(
                              inboxCount > 9 ? '9+' : '$inboxCount',
                              style: const TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              PopupMenuButton<String>(
                tooltip: 'Menu Asisten',
                onSelected: (value) {
                  switch (value) {
                    case 'inbox':
                      onOpenInbox?.call();
                    case 'voice':
                      onOpenVoicePicker();
                    case 'reset':
                      onResetChat();
                  }
                },
                itemBuilder: (_) => [
                  if (onOpenInbox != null)
                    const PopupMenuItem(
                      value: 'inbox',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.inbox_outlined),
                        title: Text('Kotak Masuk Asisten'),
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'voice',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.record_voice_over_outlined),
                      title: Text('Pilih suara bacaan'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'reset',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.refresh),
                      title: Text('Reset chat'),
                    ),
                  ),
                ],
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Tutup asisten',
                onPressed: onClose,
                icon: Icon(
                  Icons.close,
                  size: 22,
                  color: isDark
                      ? const Color(0xFF9A9590)
                      : const Color(0xFF6B5E4F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              InkWell(
                onTap: onRefreshCloudStatus,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.32),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 13, color: statusColor),
                      const SizedBox(width: 5),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Text(
                          statusLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (showSetupAction) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onSetupGemini,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 24),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: statusColor.withValues(alpha: 0.15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(
                    'Setup Sekarang',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );

  }
}
