import 'dart:io';

import 'package:flutter/material.dart';

import '../../../domain/ffm_assistant_action_plan.dart';
import '../../../domain/ffm_assistant_models.dart';
import '../ffm_assistant_markdown_text.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isUser = entry.isUser;
    final intent = entry.intent;
    final isUnknown = !isUser && intent?.type == FfmAssistantIntentType.unknown;

    // Claude palette: warm paper, flat, no shadow
    final bubbleColor = isUser
        ? (isDark ? const Color(0xFF2E2E2C) : const Color(0xFFF0EBE0))
        : isUnknown
        ? (isDark ? const Color(0xFF2E2520) : const Color(0xFFFFF3E0))
        : (isDark ? const Color(0xFF1E1E1C) : Colors.white);

    final onBubbleColor = isUser
        ? (isDark ? const Color(0xFFEDE8E0) : const Color(0xFF2B2117))
        : isUnknown
        ? (isDark ? const Color(0xFFFFD180) : const Color(0xFF8A4B00))
        : (isDark ? const Color(0xFFEDE8E0) : const Color(0xFF2B2117));

    final bubbleBorder = Border.all(
      color: isUnknown
          ? const Color(0xFFFFA726).withValues(alpha: 0.6)
          : isDark
          ? const Color(0xFF3A3530)
          : const Color(0xFFE8E0D0),
      width: 0.8,
    );

    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isUser
                ? constraints.maxWidth * .80
                : constraints.maxWidth * .90,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bubbleColor,
              border: bubbleBorder,
              borderRadius: isUser
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(4),
                    )
                  : const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                      bottomLeft: Radius.circular(4),
                      bottomRight: Radius.circular(12),
                    ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isUser && entry.processTrace != null) ...[
                    FfmAssistantProcessDisclosure(trace: entry.processTrace!),
                    const SizedBox(height: 6),
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
                    const SizedBox(height: 8),
                  ],
                  if (entry.imagePath != null) ...[
                    FfmChatImagePreview(path: entry.imagePath!),
                    if (entry.text.isNotEmpty) const SizedBox(height: 8),
                  ],
                  if (entry.filePath != null) ...[
                    FfmChatFileCard(
                      path: entry.filePath!,
                      format: entry.fileFormat,
                      onShare: onShareFile,
                    ),
                    if (entry.text.isNotEmpty) const SizedBox(height: 8),
                  ],
                  if (entry.text.isNotEmpty)
                    FfmAssistantMarkdownText(
                      text: entry.text,
                      color: onBubbleColor,
                    ),
                  if (intent?.draft != null) ...[
                    const SizedBox(height: 10),
                    FfmAssistantDraftPreview(
                      draft: intent!.draft!,
                      review: review,
                    ),
                  ],
                  if (onCopyText != null ||
                      onSpeak != null ||
                      onIntent != null ||
                      onConfirmActivity != null ||
                      onShowTechnical != null) ...[
                    const SizedBox(height: 8),
                    FfmAssistantMessageToolbar(
                      isUser: isUser,
                      hasPrimaryAction:
                          onIntent != null &&
                          intent != null &&
                          (intent.destination != null ||
                              intent.draft != null ||
                              intent.type ==
                                  FfmAssistantIntentType.exportReport ||
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
                      foregroundColor: onBubbleColor,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FfmChatImagePreview extends StatelessWidget {
  const FfmChatImagePreview({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Pratinjau gambar. Ketuk untuk memperbesar.',
      child: GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: InteractiveViewer(
              minScale: .8,
              maxScale: 4,
              child: Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Gambar tidak lagi tersedia di perangkat.'),
                ),
              ),
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(
            File(path),
            height: 150,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: 80,
              alignment: Alignment.center,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Text('Gambar tidak tersedia'),
            ),
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
