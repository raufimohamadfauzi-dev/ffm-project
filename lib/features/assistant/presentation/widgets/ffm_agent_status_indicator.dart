import 'package:flutter/material.dart';

class FfmAgentStatusSnapshot {
  const FfmAgentStatusSnapshot({
    required this.message,
    required this.isActive,
    this.isError = false,
  });

  const FfmAgentStatusSnapshot.idle()
    : message = 'Asisten lokal siap — menunggu aktivitas.',
      isActive = false,
      isError = false;

  final String message;
  final bool isActive;
  final bool isError;
}

class FfmAgentStatusController extends ValueNotifier<FfmAgentStatusSnapshot> {
  FfmAgentStatusController() : super(const FfmAgentStatusSnapshot.idle());

  void working(String message) {
    value = FfmAgentStatusSnapshot(message: message, isActive: true);
  }

  void done(String message) {
    value = FfmAgentStatusSnapshot(message: message, isActive: false);
  }

  void failed(String message) {
    value = FfmAgentStatusSnapshot(
      message: message,
      isActive: false,
      isError: true,
    );
  }

  void idle() => value = const FfmAgentStatusSnapshot.idle();
}

class FfmAgentStatusIndicator extends StatelessWidget {
  const FfmAgentStatusIndicator({super.key, required this.controller});

  final FfmAgentStatusController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FfmAgentStatusSnapshot>(
      valueListenable: controller,
      builder: (context, snapshot, _) {
        final scheme = Theme.of(context).colorScheme;
        final color = snapshot.isError
            ? scheme.error
            : snapshot.isActive
            ? scheme.primary
            : scheme.tertiary;
        return Semantics(
          label: snapshot.message,
          liveRegion: snapshot.isActive,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: color.withValues(alpha: 0.10),
            child: Row(
              children: [
                SizedBox(
                  width: 9,
                  height: 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    snapshot.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (snapshot.isActive)
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: color,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
