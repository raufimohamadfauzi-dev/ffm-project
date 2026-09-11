import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../domain/ffm_assistant_action_plan.dart';
import '../../../domain/ffm_assistant_models.dart';
import '../ffm_assistant_markdown_text.dart';
import 'activity_session_chat_card.dart';
import 'ffm_assistant_draft_preview.dart';
import 'ffm_assistant_message_toolbar.dart';
import 'ffm_assistant_feedback_toolbar.dart';
import 'ffm_json_expandable.dart';

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
    this.showTechnicalDetails = false,
    this.onToggleTechnicalDetails,
    this.onShowVerifiedFacts,
    this.onMarkIssue,
    this.issueLogged = false,
    this.onRetryGemini,
    required this.activityConfirmed,
    this.actionPlan,
    this.visibleText,
    this.isStreaming = false,
    this.onActivityFinish,
    this.onActivityUpdate,
    this.onActivityChat,
    this.showVerifiedFacts = false,
    this.onToggleVerifiedFacts,
    this.showAnalysisResults = false,
    this.onToggleAnalysisResults,
    this.onFeedbackThumbsUp,
    this.onFeedbackThumbsDown,
    this.onFeedbackMarkIncorrect,
    this.onFeedbackReportIssue,
    this.onFeedbackProvideCorrection,
    this.onShowFollowUpQuestions,
    this.statusMessage,
  });

  final FfmAssistantChatEntry entry;
  final String? statusMessage;
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
  final bool showTechnicalDetails;
  final VoidCallback? onToggleTechnicalDetails;
  final VoidCallback? onShowVerifiedFacts;
  final VoidCallback? onMarkIssue;
  final bool issueLogged;
  final VoidCallback? onRetryGemini;
  final bool activityConfirmed;
  final FfmAssistantActionPlan? actionPlan;
  final void Function(List<String> questions)? onShowFollowUpQuestions;

  /// Teks yang ditampilkan (progressive reveal saat streaming).
  /// Null berarti gunakan entry.text biasa.
  final String? visibleText;

  /// Apakah teks sedang dalam proses streaming.
  final bool isStreaming;

  /// Quick-action callbacks untuk activity cards
  final void Function(String sessionId)? onActivityFinish;
  final void Function(String sessionId)? onActivityUpdate;
  final void Function(String sessionId)? onActivityChat;

  /// Show verified facts card
  final bool showVerifiedFacts;
  final VoidCallback? onToggleVerifiedFacts;

  /// Show analysis results card
  final bool showAnalysisResults;
  final VoidCallback? onToggleAnalysisResults;

  /// Feedback callbacks
  final VoidCallback? onFeedbackThumbsUp;
  final VoidCallback? onFeedbackThumbsDown;
  final VoidCallback? onFeedbackMarkIncorrect;
  final VoidCallback? onFeedbackReportIssue;
  final VoidCallback? onFeedbackProvideCorrection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isUser = entry.isUser;
    final intent = entry.intent;
    final origin = intent?.responseOrigin;
    final groundingBlocked =
        intent?.pluginMetadata?['groundingBlocked'] == true;

    final userBubbleColor = isDark
        ? const Color(0xFF1E1E1E)
        : const Color(0xFFFFFFFF);
    final (
      Color assistantBorderColor,
      Color assistantBgColor,
      IconData assistantOriginIcon,
      String assistantOriginLabel
    ) = groundingBlocked
        ? (
            isDark ? const Color(0xFFFB7185) : const Color(0xFFE11D48),
            isDark ? const Color(0xFF2E151A) : const Color(0xFFFFF1F2),
            Icons.warning_amber_rounded,
            '⚠️ Diblokir Validator',
          )
        : switch (origin) {
            FfmAssistantResponseOrigin.agentOrchestrator => (
                isDark ? const Color(0xFFA5B4FC) : const Color(0xFF6366F1),
                isDark ? const Color(0xFF1E1B2E) : const Color(0xFFF5F3FF),
                Icons.psychology_rounded,
                '🧠 Orkestrator Lokal',
              ),
            FfmAssistantResponseOrigin.localFallback => (
                isDark ? const Color(0xFFFCD34D) : const Color(0xFFD97706),
                isDark ? const Color(0xFF261D12) : const Color(0xFFFFFBEB),
                Icons.bolt_rounded,
                '⚡ Aturan Lokal / Offline',
              ),
            FfmAssistantResponseOrigin.cloudError => (
                isDark ? const Color(0xFFFB7185) : const Color(0xFFE11D48),
                isDark ? const Color(0xFF2E151A) : const Color(0xFFFFF1F2),
                Icons.error_outline_rounded,
                '⚠️ Anomali / Error Cloud',
              ),
            FfmAssistantResponseOrigin.geminiCloud || null => (
                isDark ? const Color(0xFF6EE7B7) : const Color(0xFF059669),
                isDark ? const Color(0xFF12241C) : const Color(0xFFECFDF5),
                Icons.auto_awesome,
                '✨ Gemini Cloud',
              ),
          };
    final textColor = isUser
        ? (isDark ? Colors.white : Colors.black)
        : (isDark ? Colors.white : Colors.black);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isUser) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: assistantBorderColor.withValues(
                alpha: isDark ? 0.18 : 0.12,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: assistantBorderColor.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  assistantOriginIcon,
                  size: 12,
                  color: assistantBorderColor,
                ),
                const SizedBox(width: 4),
                Text(
                  assistantOriginLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: assistantBorderColor,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ],

        if (statusMessage != null && statusMessage!.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    statusMessage!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (entry.text.isNotEmpty) ...[
          FfmAssistantMarkdownText(
            text: visibleText ?? entry.text,
            color: textColor,
          ),
          if (isStreaming &&
              visibleText != null &&
              visibleText!.length < entry.text.length)
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
        if (entry.absorbedMemory != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF132A1F) : const Color(0xFFE8F8F0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF00A876).withValues(alpha: 0.4),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 13,
                  color: Color(0xFF00A876),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '✨ Memori Terserap: ${entry.absorbedMemory}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFF56E3A6)
                          : const Color(0xFF007552),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (entry.isCorrected) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2013) : const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFD97706).withValues(alpha: 0.4),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.edit_note_rounded,
                  size: 14,
                  color: Color(0xFFD97706),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    entry.correctionText != null && entry.correctionText!.isNotEmpty
                        ? '✏️ Dikoreksi: "${entry.correctionText}"'
                        : '✏️ Jawaban telah dikoreksi pengguna',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        // Rich Activity Card — shown when assistant response carries live activity metadata
        if (!isUser && intent?.pluginMetadata != null) ...[
          () {
            final meta = intent!.pluginMetadata!;
            final payloadType = meta['activity_payload_type'] as String?;
            if (payloadType == 'live_activity' ||
                payloadType == 'journey_recap') {
              final sessions =
                  (meta['sessions'] ?? meta['recapCards']) as List?;
              if (sessions != null && sessions.isNotEmpty) {
                return Column(
                  children: [
                    const SizedBox(height: 6),
                    ...sessions.map((s) {
                      final sMap = s as Map<String, dynamic>;
                      final sessionId = sMap['id'] as String? ?? '';
                      final isActive = meta['hasActive'] as bool? ?? true;
                      return ActivitySessionChatCard(
                        title: sMap['title'] as String? ?? '',
                        category: sMap['category'] as String? ?? '',
                        duration: sMap['duration'] as String? ?? '',
                        sessionId: sessionId,
                        isActive: isActive,
                        checkpoints:
                            (sMap['checkpoints'] as List?)
                                ?.cast<Map<String, dynamic>>() ??
                            const [],
                        childSessions:
                            (sMap['children'] as List?)
                                ?.cast<Map<String, dynamic>>() ??
                            const [],
                        lastCheckpoint: sMap['lastCheckpoint'] as String?,
                        onFinish: isActive && onActivityFinish != null
                            ? () => onActivityFinish!(sessionId)
                            : null,
                        onUpdate: isActive && onActivityUpdate != null
                            ? () => onActivityUpdate!(sessionId)
                            : null,
                        onChat: isActive && onActivityChat != null
                            ? () => onActivityChat!(sessionId)
                            : null,
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
          FfmAssistantDraftPreview(
            draft: intent!.draft!,
            review: review,
            onEdit: onEditDraft,
          ),
        ],
        if (!isUser && entry.feedbackType != null) ...[
          const SizedBox(height: 8),
          _buildFeedbackIndicator(
            context,
            entry.feedbackType!,
            entry.feedbackCategory,
          ),
        ],
        if (!isUser &&
            (onFeedbackThumbsUp != null ||
                onFeedbackThumbsDown != null ||
                onFeedbackMarkIncorrect != null ||
                onFeedbackReportIssue != null ||
                onFeedbackProvideCorrection != null)) ...[
          const SizedBox(height: 8),
          FfmAssistantFeedbackToolbar(
            onThumbsUp: onFeedbackThumbsUp ?? () {},
            onThumbsDown: onFeedbackThumbsDown ?? () {},
            onMarkIncorrect: onFeedbackMarkIncorrect,
            onReportIssue: onFeedbackReportIssue,
            onProvideCorrection: onFeedbackProvideCorrection,
          ),
        ],
        if (onCopyText != null ||
            onSpeak != null ||
            onIntent != null ||
            onConfirmActivity != null ||
            onToggleTechnicalDetails != null) ...[
          const SizedBox(height: 6),
          FfmAssistantMessageToolbar(
            isUser: isUser,
            hasPrimaryAction:
                onIntent != null &&
                intent != null &&
                (intent.needsTeachingApproval ||
                    intent.responseOrigin ==
                        FfmAssistantResponseOrigin.cloudError ||
                    intent.destination != null ||
                    intent.draft != null ||
                    intent.type == FfmAssistantIntentType.exportReport ||
                    intent.type == FfmAssistantIntentType.confirm) &&
                (review?.canContinue ?? true),
            primaryActionLabel:
                primaryActionLabel ??
                (intent?.destination != null ? 'Buka' : 'Lanjut'),
            onPrimaryAction: onIntent,
            onConfirmActivity: onConfirmActivity,
            onShowTechnical: onToggleTechnicalDetails,
            onShowVerifiedFacts: onShowVerifiedFacts,
            onMarkIssue: onMarkIssue,
            issueLogged: issueLogged,
            onRetryGemini:
                intent?.responseOrigin == FfmAssistantResponseOrigin.cloudError
                ? onRetryGemini
                : null,
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
            onShowFollowUpQuestions:
                onShowFollowUpQuestions != null &&
                    entry.suggestedQuestions.isNotEmpty
                ? () => onShowFollowUpQuestions!(entry.suggestedQuestions)
                : null,
            followUpCount: entry.suggestedQuestions.length,
          ),
        ],
        if (showTechnicalDetails && intent != null) ...[
          const SizedBox(height: 8),
          _AssistantExecutionMethodologyCard(
            entry: entry,
            intent: intent,
            isDark: isDark,
          ),
          const SizedBox(height: 6),
          FfmJsonExpandable(intent: intent, initiallyExpanded: true),
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
          child: _BubbleTapReveal(
            isUser: isUser,
            sentAt: entry.sentAt ?? entry.createdAt,
            receivedAt: entry.receivedAt,
            modelUsed: entry.modelUsed,
            textColor: textColor,
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
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: assistantBgColor,
                      border: Border.all(
                        color: assistantBorderColor,
                        width: 1.5,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                        bottomLeft: Radius.circular(4),
                        bottomRight: Radius.circular(20),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: assistantBorderColor.withValues(
                            alpha: isDark ? 0.08 : 0.04,
                          ),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: content,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeedbackIndicator(
    BuildContext context,
    String feedbackType,
    String? feedbackCategory,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color color;
    IconData icon;
    String label;

    switch (feedbackType.toLowerCase()) {
      case 'thumbsup':
        color = isDark ? const Color(0xFF4CAF50) : const Color(0xFF2E7D32);
        icon = Icons.thumb_up;
        label = 'Berguna';
        break;
      case 'thumbsdown':
        color = isDark ? const Color(0xFFF44336) : const Color(0xFFC62828);
        icon = Icons.thumb_down;
        label = 'Tidak Berguna';
        break;
      case 'incorrect':
        color = isDark ? const Color(0xFFFF9800) : const Color(0xFFEF6C00);
        icon = Icons.error_outline;
        label = 'Salah';
        break;
      case 'issue':
        color = isDark ? const Color(0xFF2196F3) : const Color(0xFF1565C0);
        icon = Icons.flag;
        label = 'Dilaporkan';
        break;
      case 'correction':
        color = isDark ? const Color(0xFF9C27B0) : const Color(0xFF6A1B9A);
        icon = Icons.edit;
        label = 'Dikoreksi';
        break;
      default:
        color = Colors.grey;
        icon = Icons.feedback;
        label = 'Feedback';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (feedbackCategory != null) ...[
            const SizedBox(width: 6),
            Container(
              width: 1,
              height: 12,
              color: color.withValues(alpha: 0.3),
            ),
            const SizedBox(width: 6),
            Text(
              feedbackCategory,
              style: TextStyle(
                fontSize: 11,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
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
    final fileName = path.split(RegExp(r'[/\\]')).last;
    final isImage =
        format?.toLowerCase() == 'image' ||
        path.toLowerCase().endsWith('.jpg') ||
        path.toLowerCase().endsWith('.jpeg') ||
        path.toLowerCase().endsWith('.png') ||
        path.toLowerCase().endsWith('.webp');

    if (isImage) {
      final file = File(path);
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () {
              showDialog<void>(
                context: context,
                builder: (ctx) => Dialog(
                  backgroundColor: Colors.black87,
                  insetPadding: const EdgeInsets.all(12),
                  child: Stack(
                    alignment: Alignment.topRight,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Center(
                          child: InteractiveViewer(
                            child: Image.file(
                              file,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Center(
                                child: Text(
                                  'Gambar struk tidak dapat ditampilkan.',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          tooltip: 'Tutup pratinjau',
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(11),
                    bottomLeft: Radius.circular(11),
                  ),
                  child: Image.file(
                    file,
                    width: 54,
                    height: 54,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 54,
                      height: 54,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.receipt_long_outlined, size: 24),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      Text(
                        'Foto struk • Ketuk untuk lihat',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onShare != null)
                  IconButton(
                    tooltip: 'Bagikan file',
                    onPressed: onShare,
                    icon: const Icon(Icons.share_outlined, size: 20),
                  ),
              ],
            ),
          ),
        ),
      );
    }

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

/// Layout metadata yang tersembunyi dan muncul saat bubble pesan ditekan.
/// Memberi transparansi eksekusi tanpa mencemari tampilan percakapan.
class _BubbleTapReveal extends StatefulWidget {
  const _BubbleTapReveal({
    required this.isUser,
    required this.sentAt,
    required this.receivedAt,
    required this.modelUsed,
    required this.textColor,
    required this.child,
  });

  final bool isUser;
  final DateTime? sentAt;
  final DateTime? receivedAt;
  final String? modelUsed;
  final Color textColor;
  final Widget child;

  @override
  State<_BubbleTapReveal> createState() => _BubbleTapRevealState();
}

class _BubbleTapRevealState extends State<_BubbleTapReveal> {
  bool _visible = false;
  Timer? _hideTimer;
  DateTime? _downAt;
  Offset? _downPosition;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    _hideTimer?.cancel();
    final next = !_visible;
    setState(() => _visible = next);
    if (next) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _visible = false);
      });
    }
  }

  void _down(PointerDownEvent event) {
    _downAt = DateTime.now();
    _downPosition = event.position;
  }

  void _up(PointerUpEvent event) {
    final downAt = _downAt;
    final downPosition = _downPosition;
    _downAt = null;
    _downPosition = null;
    if (downAt == null || downPosition == null) return;
    final elapsed = DateTime.now().difference(downAt);
    final distance = (event.position - downPosition).distance;
    if (elapsed < const Duration(milliseconds: 400) && distance < 20) {
      _handleTap();
    }
  }

  void _cancel(PointerEvent event) {
    _downAt = null;
    _downPosition = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: widget.isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          widget.child,
          if (_visible) ...[const SizedBox(height: 4), _metadataLine(context)],
        ],
      ),
    );
  }

  Widget _metadataLine(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[];
    final sent = widget.sentAt;
    if (sent != null) parts.add('Kirim ${_formatTime(sent)}');
    final received = widget.receivedAt;
    if (widget.receivedAt != null &&
        (sent == null || received!.isAfter(sent))) {
      parts.add('Terima ${_formatTime(received!)}');
    }
    final model = widget.modelUsed;
    if (model != null && model.isNotEmpty) parts.add(model);
    if (parts.isEmpty) parts.add('Pesan');
    return Text(
      parts.join(' • '),
      style: theme.textTheme.labelSmall?.copyWith(
        color: widget.textColor.withValues(alpha: 0.55),
        fontStyle: FontStyle.italic,
      ),
      textAlign: widget.isUser ? TextAlign.end : TextAlign.start,
    );
  }

  String _formatTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}

class _AssistantExecutionMethodologyCard extends StatelessWidget {
  const _AssistantExecutionMethodologyCard({
    required this.entry,
    required this.intent,
    required this.isDark,
  });

  final FfmAssistantChatEntry entry;
  final FfmAssistantIntent intent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final trace = entry.processTrace;
    final events = trace?.events ?? const [];

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_tree_outlined,
                size: 16,
                color: Color(0xFF0284C7),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '🔍 Langkah Eksekusi & Sumber Data AI',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (trace != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '⚡ ${trace.elapsed.inMilliseconds}ms',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0284C7),
                    ),
                  ),
                ),
            ],
          ),
          if (events.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...events.map((e) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.check_circle_outline,
                        size: 13,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '+${e.elapsed.inMilliseconds}ms',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.lightbulb_outline,
                size: 15,
                color: Color(0xFFD97706),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '💡 Cara Meniru Analisis Ini Sendiri:',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD97706),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getReproductionGuide(intent),
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getReproductionGuide(FfmAssistantIntent intent) {
    final destination = intent.destination;
    final usedReadCapability = intent.pluginMetadata?['usedReadCapability'] as String?;

    if (usedReadCapability == 'read.transactions' || destination == FfmAssistantDestination.transactions) {
      return '1. Buka menu Transaksi di beranda.\n2. Buka filter transaksi lalu sesuaikan rentang tanggal atau kategori terkait.\n3. Jumlahkan total transaksi yang muncul untuk mencocokkan hasil perhitungan deterministik.';
    }
    if (usedReadCapability == 'read.summary') {
      return '1. Buka Ringkasan Kas di beranda utama.\n2. Cek akumulasi Pemasukan dan Pengeluaran bulan berjalan.\n3. Transfer antar rekening tidak dihitung sebagai arus kas pengeluaran.';
    }
    if (usedReadCapability == 'read.budget' || destination == FfmAssistantDestination.budget) {
      return '1. Buka menu Anggaran.\n2. Periksa sisa alokasi pos anggaran per kategori untuk mengevaluasi batas belanja bulanan.';
    }
    if (usedReadCapability == 'read.reminders' || destination == FfmAssistantDestination.reminders) {
      return '1. Buka menu Pengingat / Jadwal.\n2. Periksa daftar alarm aktif dan waktu jatuh tempo pengingat yang terdaftar.';
    }
    return '1. Buka menu data terkait di aplikasi FFM.\n2. Bandingkan data yang dibaca dengan ringkasan di atas untuk memverifikasi kebenaran finansial secara independen.';
  }
}

