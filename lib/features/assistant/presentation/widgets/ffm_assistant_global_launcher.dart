import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// Launcher global FFM: selalu berada tepat di atas posisi FAB halaman.
/// Sesi chat dan tujuan aktif tetap dikelola oleh AppShell.
class FfmAssistantLauncherState {
  const FfmAssistantLauncherState({required this.isSheetOpen});

  final bool isSheetOpen;
}

class FfmAssistantGlobalLauncher extends StatelessWidget {
  const FfmAssistantGlobalLauncher({
    super.key,
    required this.state,
    required this.onOpen,
  });

  final ValueListenable<FfmAssistantLauncherState> state;
  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<FfmAssistantLauncherState>(
        valueListenable: state,
        builder: (context, value, _) {
          if (value.isSheetOpen) return const SizedBox.shrink();
          return Positioned(
            right: 16,
            bottom: 92,
            child: Semantics(
              button: true,
              label: 'Buka Asisten FFM',
              child: FloatingActionButton.small(
                heroTag: 'ffm-assistant-global-launcher',
                onPressed: onOpen,
                child: const Icon(Icons.auto_awesome_outlined),
              ),
            ),
          );
        },
      );
}
