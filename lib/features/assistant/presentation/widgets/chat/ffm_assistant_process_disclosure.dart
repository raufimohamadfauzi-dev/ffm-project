import 'package:flutter/material.dart';

import '../../../domain/ffm_assistant_models.dart';

class FfmAssistantProcessDisclosure extends StatefulWidget {
  const FfmAssistantProcessDisclosure({super.key, required this.trace});

  final FfmAssistantProcessTrace trace;

  @override
  State<FfmAssistantProcessDisclosure> createState() =>
      _FfmAssistantProcessDisclosureState();
}

class _FfmAssistantProcessDisclosureState
    extends State<FfmAssistantProcessDisclosure> {
  var _expanded = false;

  ({String label, IconData icon, Color color}) get _origin =>
      switch (widget.trace.origin) {
        FfmAssistantResponseOrigin.agentOrchestrator => (
          label: 'Agent Orkestrator',
          icon: Icons.account_tree_outlined,
          color: const Color(0xFF00727A),
        ),
        FfmAssistantResponseOrigin.localSlm => (
          label: 'Dibantu SLM lokal',
          icon: Icons.auto_awesome_outlined,
          color: const Color(0xFF3B6EC4),
        ),
        FfmAssistantResponseOrigin.localFallback => (
          label: 'Fallback lokal setelah SLM',
          icon: Icons.info_outline,
          color: const Color(0xFF9A5B00),
        ),
      };

  String get _duration {
    final milliseconds = widget.trace.elapsed.inMilliseconds;
    if (milliseconds < 1000) return '${milliseconds} ms';
    return '${(milliseconds / 1000).toStringAsFixed(2)} dtk';
  }

  String _eventTime(Duration elapsed) {
    final milliseconds = elapsed.inMilliseconds;
    return milliseconds < 1000
        ? 'T+$milliseconds ms'
        : 'T+${(milliseconds / 1000).toStringAsFixed(2)} dtk';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final origin = _origin;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B2227) : const Color(0xFFEBF1F3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: .08)
              : Colors.black.withValues(alpha: .08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Semantics(
              button: true,
              label:
                  '${origin.label}, $_duration. ${_expanded ? 'Tutup' : 'Buka'} detail proses.',
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(origin.icon, size: 16, color: origin.color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${origin.label} · $_duration',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(
              height: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: .08)
                  : Colors.black.withValues(alpha: .08),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final event in widget.trace.events) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _eventTime(event.elapsed),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            event.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (event.detail != null) ...[
                      const SizedBox(height: 2),
                      Text(event.detail!, style: theme.textTheme.bodySmall),
                    ],
                    const SizedBox(height: 8),
                  ],
                  if (widget.trace.fallbackReason != null)
                    Text(
                      'Alasan fallback: ${widget.trace.fallbackReason}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
