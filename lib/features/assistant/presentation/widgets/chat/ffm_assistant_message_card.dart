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
    this.onRetryGemini,
    required this.activityConfirmed,
    this.actionPlan,
    this.visibleText,
    this.isStreaming = false,
    this.onActivityFinish,
    this.onActivityUpdate,
    this.onActivityChat,
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
  final VoidCallback? onRetryGemini;
  final bool activityConfirmed;
  final FfmAssistantActionPlan? actionPlan;

  /// Teks yang ditampilkan (progressive reveal saat streaming).
  /// Null berarti gunakan entry.text biasa.
  final String? visibleText;

  /// Apakah teks sedang dalam proses streaming.
  final bool isStreaming;

  /// Quick-action callbacks untuk activity cards
  final void Function(String sessionId)? onActivityFinish;
  final void Function(String sessionId)? onActivityUpdate;
  final void Function(String sessionId)? onActivityChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isUser = entry.isUser;
    final intent = entry.intent;

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
          FfmAssistantProcessDisclosure(
            trace: entry.processTrace!,
            actionPlan: actionPlan,
          ),
          const SizedBox(height: 8),
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
            onShowTechnical: onShowTechnical,
            onRetryGemini: intent?.responseOrigin ==
                    FfmAssistantResponseOrigin.cloudError
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
