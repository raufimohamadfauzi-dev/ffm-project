import 'package:flutter/material.dart';

import '../../../domain/ffm_assistant_action_plan.dart';
import '../../../domain/ffm_assistant_models.dart';
import '../ffm_assistant_markdown_text.dart';
import 'activity_session_chat_card.dart';
import 'ffm_assistant_draft_preview.dart';
import 'ffm_assistant_message_toolbar.dart';
import 'ffm_assistant_process_disclosure.dart';

class FfmAssistantMessageCard extends StatelessWidget {
  const FfmAssistantMessageCard({
    super.key,
    required this.entry,
    this.onSpeak,
    required this.isSpeaking,
    this.onIntent,
    this.primaryActionLabel,
    this.onApproveTeaching,
    required this.teachingSaved,
    this.review,
    this.onEditDraft,
    this.onCancelDraft,
    this.onCopyFeedback,
    this.onCopyText,
    this.onShareFile,
    this.onCorrectMessage,
    this.onConfirmActivity,
    this.onShowTechnical,
    required this.activityConfirmed,
    this.actionPlan,
    this.visibleText,
    this.isStreaming = false,
  });

  final FfmAssistantChatEntry entry;
  final VoidCallback? onSpeak;
  final bool isSpeaking;
  final VoidCallback? onIntent;
  final String? primaryActionLabel;
  final VoidCallback? onApproveTeaching;
  final bool teachingSaved;
  final FfmAssistantDraftReview? review;
  final VoidCallback? onEditDraft;
  final VoidCallback? onCancelDraft;
  final VoidCallback? onCopyFeedback;
  final VoidCallback? onCopyText;
  final VoidCallback? onShareFile;
  final VoidCallback? onCorrectMessage;
  final VoidCallback? onConfirmActivity;
  final VoidCallback? onShowTechnical;
  final bool activityConfirmed;
  final FfmAssistantActionPlan? actionPlan;

  /// Teks yang ditampilkan (progressive reveal saat streaming).
  /// Null berarti gunakan entry.text biasa.
  final String? visibleText;

  /// Apakah teks sedang dalam proses streaming.
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isUser = entry.isUser;
    final intent = entry.intent;
    final isUnknown = !isUser && intent?.type == FfmAssistantIntentType.unknown;

    final userBubbleColor = isDark
        ? const Color(0xFF1E1E1E)
        : const Color(0xFFFFFFFF);
    final textColor = isUser
        ? (isDark ? Colors.white : Colors.black)
        : (isDark ? Colors.white : Colors.black);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isUser && entry.processTrace != null) ...[
          _OriginBadge(trace: entry.processTrace!),
          const SizedBox(height: 6),
          FfmAssistantProcessDisclosure(
            trace: entry.processTrace!,
            actionPlan: actionPlan,
          ),
          const SizedBox(height: 8),
        ],
        if (isUnknown) ...[
          Semantics(
            label: 'Belum ada jawaban tetap. Pertanyaan tersimpan untuk pembaruan.',
            child: Row(
              children: [
                Icon(
                  Icons.school_outlined,
                  size: 17,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Tersimpan di Pengetahuan Asisten • menu Lainnya',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
        ],
        if (entry.filePath != null) ...[
          FfmChatFileCard(
            path: entry.filePath!,
            format: entry.fileFormat,
            onShare: onShareFile,
          ),
          if (entry.text.isNotEmpty) const SizedBox(height: 5),
        ],
        if (entry.text.isNotEmpty) ...[
          FfmAssistantMarkdownText(
            text: visibleText ?? entry.text,
            color: textColor,
          ),
          if (isStreaming && visibleText != null && visibleText!.length < entry.text.length)
            const Padding(
              padding: EdgeInsets.only(left: 2),
              child: SizedBox(
                width: 8,
                height: 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFC27B5F),
                    borderRadius: BorderRadius.all(Radius.circular(1)),
                  ),
                ),
              ),
            ),
        ],
        // Rich Activity Card — shown when assistant response carries live activity metadata
        if (!isUser && intent?.pluginMetadata != null) ...[
          () {
            final meta = intent!.pluginMetadata!;
            final payloadType = meta['activity_payload_type'] as String?;
            if (payloadType == 'live_activity' || payloadType == 'journey_recap') {
              final sessions = (meta['sessions'] ?? meta['recapCards']) as List?;
              if (sessions != null && sessions.isNotEmpty) {
                return Column(
                  children: [
                    const SizedBox(height: 6),
                    ...sessions.map((s) {
                      final sMap = s as Map<String, dynamic>;
                      return ActivitySessionChatCard(
                        title: sMap['title'] as String? ?? '',
                        category: sMap['category'] as String? ?? '',
                        duration: sMap['duration'] as String? ?? '',
                        isActive: meta['hasActive'] as bool? ?? true,
                        checkpoints: (sMap['checkpoints'] as List?)
                                ?.cast<Map<String, dynamic>>() ??
                            const [],
                        childSessions: (sMap['children'] as List?)
                                ?.cast<Map<String, dynamic>>() ??
                            const [],
                        lastCheckpoint: sMap['lastCheckpoint'] as String?,
                      );
                    }),
                  ],
                );
              }
            }
            return const SizedBox.shrink();
          }(),
        ],
        if (intent?.draft != null) ...[
          const SizedBox(height: 7),
          FfmAssistantDraftPreview(draft: intent!.draft!, review: review),
        ],
        if (onCopyText != null ||
            onSpeak != null ||
            onIntent != null ||
            onConfirmActivity != null ||
            onShowTechnical != null) ...[
          const SizedBox(height: 6),
          FfmAssistantMessageToolbar(
            isUser: isUser,
            hasPrimaryAction:
                onIntent != null &&
                intent != null &&
                (intent.destination != null ||
                    intent.draft != null ||
                    intent.type == FfmAssistantIntentType.exportReport ||
                    intent.type == FfmAssistantIntentType.confirm) &&
                (review?.canContinue ?? true),
            primaryActionLabel:
                primaryActionLabel ??
                (intent?.destination != null ? 'Buka' : 'Lanjut'),
            onPrimaryAction: onIntent,
            onConfirmActivity: onConfirmActivity,
            onShowTechnical: onShowTechnical,
            activityConfirmed: activityConfirmed,
            actionPlan: actionPlan,
            onCopyText: onCopyText,
            onSpeak: onSpeak,
            isSpeaking: isSpeaking,
            onCorrectMessage: onCorrectMessage,
            onCopyFeedback: onCopyFeedback,
            onEditDraft: onEditDraft,
            onCancelDraft: onCancelDraft,
            onApproveTeaching: onApproveTeaching,
            teachingSaved: teachingSaved,
            foregroundColor: textColor,
          ),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isUser
                ? constraints.maxWidth * .78
                : constraints.maxWidth * .90,
          ),
          child: isUser
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: userBubbleColor,
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF666666)
                          : const Color(0xFF333333),
                      width: 2.0,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(4),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: content,
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(2, 2, 4, 4),
                  child: content,
                ),
        ),
      ),
    );
  }
}

class FfmChatFileCard extends StatelessWidget {
  const FfmChatFileCard({
    super.key,
    required this.path,
    required this.format,
    this.onShare,
  });

  final String path;
  final String? format;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = path.split('/').last;
    final icon = switch (format?.toLowerCase()) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'json' => Icons.data_object_outlined,
      _ => Icons.description_outlined,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${format ?? 'File'} • tersimpan lokal • belum dibagikan',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          if (onShare != null)
            IconButton(
              tooltip: 'Bagikan file',
              onPressed: onShare,
              icon: const Icon(Icons.share_outlined),
            ),
        ],
      ),
    );
  }
}

class _OriginBadge extends StatelessWidget {
  const _OriginBadge({required this.trace});
  final FfmAssistantProcessTrace trace;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Jika ada pluginName, tampilkan badge plugin eksplisit
    if (trace.pluginName != null && trace.pluginCategory != null) {
      final color = isDark ? const Color(0xFF00BFA5) : const Color(0xFF00796B);
      final icon = switch (trace.pluginCategory) {
        '👁️ Sense' => Icons.visibility_outlined,
        '🧮 Logic' => Icons.calculate_outlined,
        '✋ Actuator' => Icons.edit_outlined,
        _ => Icons.account_tree_outlined,
      };
      final label = '${trace.pluginCategory}: ${_resolvePluginDisplayName(trace.pluginName!)}';
      
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }

    final (icon, label, color) = switch (trace.origin) {
      FfmAssistantResponseOrigin.localSlm => (
        Icons.auto_awesome_outlined,
        'LOKAL AI',
        isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2),
      ),
      FfmAssistantResponseOrigin.localFallback => (
        Icons.info_outline,
        'FALLBACK',
        isDark ? const Color(0xFFFFD54F) : const Color(0xFFF57C00),
      ),
      FfmAssistantResponseOrigin.agentOrchestrator => (
        Icons.account_tree_outlined,
        'AGENT',
        isDark ? const Color(0xFF81C784) : const Color(0xFF388E3C),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  static String _resolvePluginDisplayName(String pluginName) => switch (pluginName) {
    'balance_sense' => 'Saldo & Rekening',
    'transaction_sense' => 'Ringkasan Transaksi',
    'budget_sense' => 'Anggaran',
    'debt_sense' => 'Hutang',
    'asset_sense' => 'Aset',
    'goal_sense' => 'Target Tabungan',
    'user_habits_profile' => 'Profil & Kebiasaan',
    'receivable_sense' => 'Piutang',
    'recurring_transaction_sense' => 'Transaksi Berulang',
    'daily_notes_sense' => 'Catatan Harian',
    'task_sense' => 'Daftar Tugas',
    'schedule_sense' => 'Agenda & Jadwal',
    'routine_sense' => 'Rutinitas Harian',
    'top_merchant_sense' => 'Analisis Merchant',
    'activity_report_sense' => 'Laporan Aktivitas',
    'live_activity_sense' => 'Live Activity (Layar)',
    'quick_note_actuator' => 'Quick Note Cepat',
    'activity_context_logic' => 'Konteks & Durasi Sesi',
    'activity_guard' => 'Pengaman Aktivitas',
    'zakat_logic' => 'Kalkulator Zakat',
    'financial_health_logic' => 'Kesehatan Keuangan',
    'budget_guard_logic' => 'Budget Guard',
    'loan_affordability_logic' => 'Kemampuan Pinjaman',
    'spending_pace_logic' => 'Laju Pengeluaran',
    'holistic_awareness' => 'Potret 360°',
    'emergency_fund_logic' => 'Dana Darurat',
    'debt_snowball_logic' => 'Strategi Bebas Hutang',
    'saving_rate_logic' => 'Rasio Menabung',
    _ => pluginName,
  };
}



