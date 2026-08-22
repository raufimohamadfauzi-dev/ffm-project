import 'package:flutter/material.dart';

import '../../domain/ffm_assistant_models.dart';

/// Menyimpan konteks route aktif untuk launcher Asisten global.
/// Stack token menjaga konteks halaman induk kembali aktif setelah detail ditutup.
class FfmAssistantPageContextController
    extends ValueNotifier<FfmAssistantDestination?> {
  FfmAssistantPageContextController() : super(null);

  final _entries = <Object, FfmAssistantDestination>{};
  var _isDisposed = false;

  void activate(Object token, FfmAssistantDestination destination) {
    if (_isDisposed) return;
    _entries
      ..remove(token)
      ..[token] = destination;
    value = _entries.values.isEmpty ? null : _entries.values.last;
  }

  void deactivate(Object token) {
    if (_isDisposed) return;
    _entries.remove(token);
    value = _entries.values.isEmpty ? null : _entries.values.last;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _entries.clear();
    super.dispose();
  }
}

class FfmAssistantContextScope
    extends InheritedNotifier<FfmAssistantPageContextController> {
  const FfmAssistantContextScope({
    super.key,
    required FfmAssistantPageContextController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Lookup tanpa mendaftarkan dependency. Pembungkus halaman hanya perlu
  /// menemukan controller sekali; launcher global yang mendengarkan nilainya.
  static FfmAssistantPageContextController? maybeOf(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<FfmAssistantContextScope>();
    return (element?.widget as FfmAssistantContextScope?)?.notifier;
  }
}

class FfmAssistantPageContext extends StatefulWidget {
  const FfmAssistantPageContext({
    super.key,
    required this.destination,
    required this.child,
  });

  final FfmAssistantDestination destination;
  final Widget child;

  @override
  State<FfmAssistantPageContext> createState() =>
      _FfmAssistantPageContextState();
}

class _FfmAssistantPageContextState extends State<FfmAssistantPageContext> {
  final _token = Object();
  FfmAssistantPageContextController? _controller;
  var _isDisposed = false;

  void _scheduleActivation() {
    final controller = _controller;
    if (controller == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposed || controller != _controller) return;
      controller.activate(_token, widget.destination);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = FfmAssistantContextScope.maybeOf(context);
    _scheduleActivation();
  }

  @override
  void didUpdateWidget(covariant FfmAssistantPageContext oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destination != widget.destination) {
      _scheduleActivation();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    final controller = _controller;
    if (controller != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => controller.deactivate(_token),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
