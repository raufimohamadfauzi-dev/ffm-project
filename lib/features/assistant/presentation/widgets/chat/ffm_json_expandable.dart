import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/ffm_assistant_models.dart';

/// Viewer JSON proposal di dalam chat — collapsed by default, expand on tap.
/// Gaya ala Claude: header pill + block monospace yang bisa disalin.
class FfmJsonExpandable extends StatefulWidget {
  const FfmJsonExpandable({super.key, required this.intent});

  final FfmAssistantIntent intent;

  @override
  State<FfmJsonExpandable> createState() => _FfmJsonExpandableState();
}

class _FfmJsonExpandableState extends State<FfmJsonExpandable> {
  var _expanded = false;

  Map<String, dynamic> _intentToMap(FfmAssistantIntent intent) {
    Map<String, dynamic>? draftMap;
    final draft = intent.draft;
    if (draft != null) {
      draftMap = <String, dynamic>{
        'kind': draft.kind.name,
        'createdAt': draft.createdAt.toIso8601String(),
        if (draft.amount != null) 'amount': draft.amount,
        if (draft.title != null) 'title': draft.title,
        if (draft.partyName != null) 'partyName': draft.partyName,
        if (draft.fromAccountName != null) 'fromAccountName': draft.fromAccountName,
        if (draft.toAccountName != null) 'toAccountName': draft.toAccountName,
        if (draft.categoryName != null) 'categoryName': draft.categoryName,
        if (draft.adminFee != null) 'adminFee': draft.adminFee,
        if (draft.goalName != null) 'goalName': draft.goalName,
        if (draft.note != null) 'note': draft.note,
        if (draft.date != null) 'date': draft.date!.toIso8601String(),
        if (draft.merchantName != null) 'merchantName': draft.merchantName,
        if (draft.formValues.isNotEmpty) 'formValues': draft.formValues,
        if (draft.slmFieldValues.isNotEmpty) 'slmFieldValues': draft.slmFieldValues,
      };
    }
    return <String, dynamic>{
      'type': intent.type.name,
      if (intent.destination != null) 'destination': intent.destination!.name,
      'confidence': intent.confidence,
      'responseMode': intent.responseMode.name,
      if (intent.clarification != null) 'clarification': intent.clarification,
      if (intent.response != null) 'response': intent.response,
      if (draftMap != null) 'draft': draftMap,
      if (intent.teachingProposal != null)
        'teachingProposal': <String, dynamic>{
          'kind': intent.teachingProposal!.kind,
          'triggerText': intent.teachingProposal!.triggerText,
          'valueText': intent.teachingProposal!.valueText,
        },
      'rawText': intent.rawText,
      'normalizedText': intent.normalizedText,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final jsonString = const JsonEncoder.withIndent('  ').convert(_intentToMap(widget.intent));

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B18) : const Color(0xFFFDFCF9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF3A3530) : const Color(0xFFE8E0D0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.data_object_outlined,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _expanded ? 'Sembunyikan JSON' : 'Lihat JSON proposal',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  if (_expanded)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Salin JSON',
                      icon: const Icon(Icons.copy_outlined, size: 16),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: jsonString));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('JSON disalin.')),
                          );
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: SelectableText(
                  jsonString,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Menlo', 'Consolas', 'monospace'],
                    fontSize: 11,
                    height: 1.4,
                    color: isDark ? const Color(0xFFE8E8E8) : const Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
