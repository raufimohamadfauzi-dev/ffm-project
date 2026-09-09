import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Launcher global FFM yang dapat digeser agar tidak menghalangi FAB atau isi
/// halaman. Posisi tetap selama aplikasi terbuka dan selalu dibatasi layar.
class FfmAssistantLauncherState {
  const FfmAssistantLauncherState({
    required this.isSheetOpen,
    this.isWorking = false,
    this.hasNotification = false,
    this.notificationReason,
  });

  final bool isSheetOpen;
  final bool isWorking;
  final bool hasNotification;
  final String? notificationReason;
}

class FfmAssistantGlobalLauncher extends StatefulWidget {
  const FfmAssistantGlobalLauncher({
    super.key,
    required this.state,
    required this.onOpen,
  });

  final ValueListenable<FfmAssistantLauncherState> state;
  final Future<void> Function() onOpen;

  @override
  State<FfmAssistantGlobalLauncher> createState() =>
      _FfmAssistantGlobalLauncherState();
}

class _FfmAssistantGlobalLauncherState
    extends State<FfmAssistantGlobalLauncher> {
  static const _xKey = 'assistant_launcher_x';
  static const _yKey = 'assistant_launcher_y';

  Offset? _position;
  var _dragDistance = 0.0;

  @override
  void initState() {
    super.initState();
    _restorePosition();
  }

  Future<void> _restorePosition() async {
    final preferences = await SharedPreferences.getInstance();
    final x = preferences.getDouble(_xKey);
    final y = preferences.getDouble(_yKey);
    if (!mounted || x == null || y == null) return;
    setState(() => _position = Offset(x, y));
  }

  Future<void> _savePosition() async {
    final position = _position;
    if (position == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_xKey, position.dx);
    await preferences.setDouble(_yKey, position.dy);
  }

  Offset _clamp(Offset value, Size size) {
    const buttonSize = 56.0;
    const edge = 8.0;
    final maxX = size.width - buttonSize - edge;
    final maxY = size.height - buttonSize - edge;
    if (maxX <= edge || maxY <= edge) {
      return value;
    }
    return Offset(value.dx.clamp(edge, maxX), value.dy.clamp(edge, maxY));
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final initial = Offset(size.width - 64, size.height - 172);
        final position = _clamp(_position ?? initial, size);
        return ValueListenableBuilder<FfmAssistantLauncherState>(
          valueListenable: widget.state,
          builder: (context, value, _) {
            if (value.isSheetOpen) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.topLeft,
              child: Transform.translate(
                offset: position,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => _dragDistance = 0.0,
                  onPanUpdate: (details) {
                    _dragDistance += details.delta.distance;
                    setState(
                      () => _position = _clamp(position + details.delta, size),
                    );
                  },
                  onPanEnd: (_) {
                    _savePosition();
                    if (_dragDistance < 10.0) {
                      widget.onOpen();
                    }
                  },
                  onTap: widget.onOpen,
                  child: Semantics(
                    button: true,
                    label: 'Buka atau geser Asisten FFM',
                    child: Stack(
                      children: [
                        FloatingActionButton.small(
                          heroTag: null,
                          onPressed: widget.onOpen,
                          child: const Icon(Icons.auto_awesome_outlined),
                        ),
                        if (value.hasNotification || value.isWorking)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: value.isWorking && !value.hasNotification
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Container(
                                    width: 12,
                                    height: 12,
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
