import 'dart:async';
import 'package:flutter/material.dart';

/// Animasi gelembung berpikir real-time (Live Reasoning / Chain-of-Thought) saat asisten menalar.
class FfmThinkingJourneyBubble extends StatefulWidget {
  const FfmThinkingJourneyBubble({super.key});

  @override
  State<FfmThinkingJourneyBubble> createState() =>
      _FfmThinkingJourneyBubbleState();
}

class _FfmThinkingJourneyBubbleState extends State<FfmThinkingJourneyBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Timer _stepTimer;
  var _currentStepIndex = 0;

  static const _steps = [
    (
      icon: Icons.psychology_alt_outlined,
      title: 'Menelaah Pesan',
      detail: 'Mengekstrak maksud, entitas angka & konteks kalimat...',
    ),
    (
      icon: Icons.hub_outlined,
      title: 'Memanggil 18 Plugin',
      detail: 'Menghubungkan ke Sense, Logic & Actuator lokal...',
    ),
    (
      icon: Icons.storage_outlined,
      title: 'Kueri Data SQLite',
      detail: 'Membaca saldo riil, riwayat transaksi & anggaran...',
    ),
    (
      icon: Icons.draw_outlined,
      title: 'Menyusun Respons',
      detail: 'Merancang draf aman & memverifikasi hasil...',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _stepTimer = Timer.periodic(const Duration(milliseconds: 1100), (_) {
      if (mounted) {
        setState(() {
          _currentStepIndex = (_currentStepIndex + 1) % _steps.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _stepTimer.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final step = _steps[_currentStepIndex];

    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, _) {
          final glowAlpha = 0.25 + (_animController.value * 0.35);
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.45 + (_animController.value * 0.2),
              ),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: glowAlpha),
                width: 1.2,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(
                    alpha: _animController.value * 0.08,
                  ),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    Icon(
                      step.icon,
                      size: 11,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.15),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    key: ValueKey<int>(_currentStepIndex),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            step.title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Langkah ${_currentStepIndex + 1}/${_steps.length}',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        step.detail,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
