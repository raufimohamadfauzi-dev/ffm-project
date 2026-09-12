import 'package:flutter/material.dart';

import '../../../domain/ffm_assistant_action_plan.dart';

enum FfmAssistantMessageMenuAction {
  correct,
  copyFeedback,
  editDraft,
  cancelDraft,
  approveTeaching,
  technicalDetails,
  verifiedFacts,
  markIssue,
  retryGemini,
}

class FfmAssistantMenuLabel extends StatelessWidget {
  const FfmAssistantMenuLabel({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18),
      const SizedBox(width: 10),
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
}

class FfmAssistantMessageToolbar extends StatelessWidget {
  const FfmAssistantMessageToolbar({
    super.key,
    required this.isUser,
    required this.hasPrimaryAction,
    required this.primaryActionLabel,
    this.onPrimaryAction,
    this.onConfirmActivity,
    required this.activityConfirmed,
    this.onCopyText,
    this.onSpeak,
    required this.isSpeaking,
    this.onCorrectMessage,
    this.onCopyFeedback,
    this.onEditDraft,
    this.onCancelDraft,
    this.onApproveTeaching,
    this.onShowTechnical,
    this.onShowVerifiedFacts,
    this.onMarkIssue,
    this.issueLogged = false,
    this.onRetryGemini,
    required this.teachingSaved,
    required this.foregroundColor,
    this.actionPlan,
    this.onShowFollowUpQuestions,
    this.followUpCount = 0,
  });

  final bool isUser;
  final bool hasPrimaryAction;
  final String primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final VoidCallback? onConfirmActivity;
  final bool activityConfirmed;
  final VoidCallback? onCopyText;
  final VoidCallback? onSpeak;
  final bool isSpeaking;
  final VoidCallback? onCorrectMessage;
  final VoidCallback? onCopyFeedback;
  final VoidCallback? onEditDraft;
  final VoidCallback? onCancelDraft;
  final VoidCallback? onApproveTeaching;
  final VoidCallback? onShowTechnical;
  final VoidCallback? onShowVerifiedFacts;
  final VoidCallback? onMarkIssue;
  final bool issueLogged;
  final VoidCallback? onRetryGemini;
  final bool teachingSaved;
  final Color foregroundColor;
  final FfmAssistantActionPlan? actionPlan;
  final VoidCallback? onShowFollowUpQuestions;
  final int followUpCount;

  @override
  Widget build(BuildContext context) {
    final includesNavigation =
        actionPlan?.steps.any(
          (step) => step.capabilityId.startsWith('navigate.'),
        ) ??
        false;
    final hasMoreActions =
        onCorrectMessage != null ||
        onCopyFeedback != null ||
        onEditDraft != null ||
        onCancelDraft != null ||
        onApproveTeaching != null ||
        onShowTechnical != null ||
        onShowVerifiedFacts != null ||
        onMarkIssue != null ||
        onRetryGemini != null;
    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onCopyText != null)
              Tooltip(
                message: 'Salin pesan',
                child: IconButton(
                  onPressed: onCopyText,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  style: IconButton.styleFrom(foregroundColor: foregroundColor),
                  icon: const Icon(Icons.copy_outlined, size: 16),
                ),
              ),
            if (hasMoreActions)
              PopupMenuButton<FfmAssistantMessageMenuAction>(
                iconColor: foregroundColor,
                icon: const Icon(Icons.more_horiz, size: 16),
                tooltip: 'Aksi lainnya',
                padding: EdgeInsets.zero,
                onSelected: (action) {
                  switch (action) {
                    case FfmAssistantMessageMenuAction.correct:
                      onCorrectMessage?.call();
                      return;
                    default:
                      return;
                  }
                },
                itemBuilder: (context) => [
                  if (onCorrectMessage != null)
                    const PopupMenuItem(
                      value: FfmAssistantMessageMenuAction.correct,
                      child: FfmAssistantMenuLabel(
                        icon: Icons.spellcheck_outlined,
                        label: 'Benarkan & kirim ulang',
                      ),
                    ),
                ],
              ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (hasPrimaryAction)
            Tooltip(
              message:
                  actionPlan?.status == FfmAssistantActionPlanStatus.completed &&
                      !includesNavigation
                  ? 'Arahan ini sudah diselesaikan.'
                  : 'Buka arahan ini. Data belum disimpan otomatis.',
              child: FilledButton.tonalIcon(
                onPressed:
                    (actionPlan?.isTerminal ?? false) && !includesNavigation ||
                        actionPlan?.status ==
                            FfmAssistantActionPlanStatus.executing
                    ? null
                    : onPrimaryAction,
                icon: Icon(
                  actionPlan?.status == FfmAssistantActionPlanStatus.completed &&
                          !includesNavigation
                      ? Icons.done_all
                      : Icons.open_in_new,
                  size: 16,
                ),
                label: Text(
                  actionPlan?.status == FfmAssistantActionPlanStatus.completed &&
                          !includesNavigation
                      ? 'Selesai'
                      : primaryActionLabel,
                ),
              ),
            ),
          if (onConfirmActivity != null)
            Tooltip(
              message: activityConfirmed
                  ? 'Aktivitas ini sudah dikonfirmasi.'
                  : 'Simpan aktivitas hanya setelah kamu setuju.',
              child: FilledButton.tonalIcon(
                onPressed: activityConfirmed ? null : onConfirmActivity,
                icon: Icon(
                  activityConfirmed
                      ? Icons.check_circle_outline
                      : Icons.play_circle_outline,
                  size: 16,
                ),
                label: Text(activityConfirmed ? 'Tersimpan' : 'Konfirmasi'),
              ),
            ),
          if (onSpeak != null)
            Tooltip(
              message: isSpeaking
                  ? 'Hentikan bacaan.'
                  : 'Dengarkan jawaban.',
              child: IconButton(
                onPressed: onSpeak,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                style: IconButton.styleFrom(foregroundColor: foregroundColor),
                icon: Icon(
                  isSpeaking
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined,
                  size: 18,
                ),
              ),
            ),
          if (onCopyText != null)
            Tooltip(
              message: 'Salin jawaban',
              child: IconButton(
                onPressed: onCopyText,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                style: IconButton.styleFrom(foregroundColor: foregroundColor),
                icon: const Icon(Icons.copy_outlined, size: 18),
              ),
            ),
          if (onShowFollowUpQuestions != null && followUpCount > 0)
            Tooltip(
              message: 'Saran pertanyaan lanjutan ($followUpCount)',
              child: IconButton(
                onPressed: onShowFollowUpQuestions,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                style: IconButton.styleFrom(
                  foregroundColor: const Color(0xFFEAB308),
                ),
                icon: const Icon(Icons.lightbulb_rounded, size: 18),
              ),
            ),
          if (onMarkIssue != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Tooltip(
                message: issueLogged
                    ? 'Tercatat di Asisten Log'
                    : 'Laporkan jawaban ini',
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: issueLogged ? null : onMarkIssue,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: issueLogged
                          ? (Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF132A1F)
                                : const Color(0xFFE8F8F0))
                          : (Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF2E181D)
                                : const Color(0xFFFFF1F2)),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: issueLogged
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF43F5E).withValues(alpha: 0.6),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          issueLogged
                              ? Icons.check_circle_outline
                              : Icons.report_problem_outlined,
                          size: 13,
                          color: issueLogged
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF43F5E),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          issueLogged ? 'Tercatat' : 'Laporkan',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: issueLogged
                                ? const Color(0xFF10B981)
                                : const Color(0xFFF43F5E),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (hasMoreActions)
            Tooltip(
              message: 'Aksi lainnya',
              child: PopupMenuButton<FfmAssistantMessageMenuAction>(
                iconColor: foregroundColor,
                icon: const Icon(Icons.more_horiz, size: 18),
                tooltip: 'Aksi lainnya',
                padding: const EdgeInsets.all(4),
                onSelected: (action) {
                  switch (action) {
                    case FfmAssistantMessageMenuAction.correct:
                      onCorrectMessage?.call();
                      return;
                    case FfmAssistantMessageMenuAction.copyFeedback:
                      onCopyFeedback?.call();
                      return;
                    case FfmAssistantMessageMenuAction.editDraft:
                      onEditDraft?.call();
                      return;
                    case FfmAssistantMessageMenuAction.cancelDraft:
                      onCancelDraft?.call();
                      return;
                    case FfmAssistantMessageMenuAction.approveTeaching:
                      onApproveTeaching?.call();
                      return;
                    case FfmAssistantMessageMenuAction.technicalDetails:
                      onShowTechnical?.call();
                      return;
                    case FfmAssistantMessageMenuAction.verifiedFacts:
                      onShowVerifiedFacts?.call();
                      return;
                    case FfmAssistantMessageMenuAction.markIssue:
                      onMarkIssue?.call();
                      return;
                    case FfmAssistantMessageMenuAction.retryGemini:
                      onRetryGemini?.call();
                      return;
                  }
                },
                itemBuilder: (context) => [
                  if (onShowTechnical != null)
                    const PopupMenuItem(
                      value: FfmAssistantMessageMenuAction.technicalDetails,
                      child: FfmAssistantMenuLabel(
                        icon: Icons.history_rounded,
                        label: 'Lihat detail teknis',
                      ),
                    ),
                  if (onCorrectMessage != null)
                    const PopupMenuItem(
                      value: FfmAssistantMessageMenuAction.correct,
                      child: FfmAssistantMenuLabel(
                        icon: Icons.spellcheck_outlined,
                        label: 'Benarkan & kirim ulang',
                      ),
                    ),
                  if (onEditDraft != null)
                    const PopupMenuItem(
                      value: FfmAssistantMessageMenuAction.editDraft,
                      child: FfmAssistantMenuLabel(
                        icon: Icons.edit_outlined,
                        label: 'Koreksi draft',
                      ),
                    ),
                  if (onCancelDraft != null)
                    const PopupMenuItem(
                      value: FfmAssistantMessageMenuAction.cancelDraft,
                      child: FfmAssistantMenuLabel(
                        icon: Icons.close_outlined,
                        label: 'Batalkan draft',
                      ),
                    ),
                  if (onApproveTeaching != null)
                    PopupMenuItem(
                      value: FfmAssistantMessageMenuAction.approveTeaching,
                      enabled: !teachingSaved,
                      child: FfmAssistantMenuLabel(
                        icon: teachingSaved
                            ? Icons.bookmark_added_outlined
                            : Icons.bookmark_add_outlined,
                        label: teachingSaved
                            ? 'Ajaran tersimpan'
                            : 'Simpan ajaran',
                      ),
                    ),
                  if (onCopyFeedback != null)
                    const PopupMenuItem(
                      value: FfmAssistantMessageMenuAction.copyFeedback,
                      child: FfmAssistantMenuLabel(
                        icon: Icons.copy_all_outlined,
                        label: 'Salin laporan developer',
                      ),
                    ),
                  if (onShowVerifiedFacts != null)
                    const PopupMenuItem(
                      value: FfmAssistantMessageMenuAction.verifiedFacts,
                      child: FfmAssistantMenuLabel(
                        icon: Icons.fact_check_outlined,
                        label: 'Lihat fakta sumber',
                      ),
                    ),
                  if (onMarkIssue != null)
                    PopupMenuItem(
                      value: FfmAssistantMessageMenuAction.markIssue,
                      enabled: !issueLogged,
                      child: FfmAssistantMenuLabel(
                        icon: issueLogged
                            ? Icons.assignment_turned_in_outlined
                            : Icons.report_problem_outlined,
                        label: issueLogged
                            ? 'Sudah dicatat di Asisten Log'
                            : 'Tandai sebagai masalah',
                      ),
                    ),
                  if (onRetryGemini != null)
                    const PopupMenuItem(
                      value: FfmAssistantMessageMenuAction.retryGemini,
                      child: FfmAssistantMenuLabel(
                        icon: Icons.refresh_outlined,
                        label: 'Coba lagi (Gemini)',
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
