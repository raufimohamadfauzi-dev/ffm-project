import 'package:flutter/material.dart';

import '../../../domain/ffm_assistant_action_plan.dart';

enum FfmAssistantMessageMenuAction {
  correct,
  copyFeedback,
  editDraft,
  cancelDraft,
  approveTeaching,
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
    children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
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
    required this.teachingSaved,
    required this.foregroundColor,
    this.actionPlan,
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
  final bool teachingSaved;
  final Color foregroundColor;
  final FfmAssistantActionPlan? actionPlan;

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
        onApproveTeaching != null;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
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
                size: 17,
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
                size: 17,
              ),
              label: Text(activityConfirmed ? 'Tersimpan' : 'Konfirmasi'),
            ),
          ),
        if (!isUser && onSpeak != null)
          Tooltip(
            message: isSpeaking
                ? 'Hentikan bacaan. Ketuk Dengarkan lagi untuk melanjutkan.'
                : 'Dengarkan jawaban. Ketuk lagi untuk berhenti.',
            child: IconButton(
              onPressed: onSpeak,
              style: IconButton.styleFrom(foregroundColor: foregroundColor),
              icon: Icon(
                isSpeaking ? Icons.volume_off_outlined : Icons.volume_up_outlined,
              ),
            ),
          ),
        if (onCopyText != null)
          Tooltip(
            message: isUser ? 'Salin pesan' : 'Salin jawaban',
            child: IconButton(
              onPressed: onCopyText,
              style: IconButton.styleFrom(foregroundColor: foregroundColor),
              icon: const Icon(Icons.copy_outlined),
            ),
          ),
        if (hasMoreActions)
          Tooltip(
            message: 'Aksi lainnya',
            child: PopupMenuButton<FfmAssistantMessageMenuAction>(
              iconColor: foregroundColor,
              icon: const Icon(Icons.more_horiz),
              tooltip: 'Aksi lainnya',
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
                      label: 'Salin bahan perbaikan',
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
