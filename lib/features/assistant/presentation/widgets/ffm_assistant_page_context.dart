import 'package:flutter/material.dart';

import '../../domain/ffm_assistant_models.dart';

/// Menyimpan konteks route aktif untuk launcher Asisten global.
/// Stack token menjaga konteks halaman induk kembali aktif setelah detail ditutup.
class FfmAssistantPageContextController
    extends ValueNotifier<FfmAssistantDestination?> {
  FfmAssistantPageContextController() : super(null);

  final _entries = <Object, FfmAssistantDestination>{};

  void activate(Object token, FfmAssistantDestination destination) {
    _entries
      ..remove(token)
      ..[token] = destination;
    value = _entries.values.isEmpty ? null : _entries.values.last;
  }

  void deactivate(Object token) {
    _entries.remove(token);
    value = _entries.values.isEmpty ? null : _entries.values.last;
  }
}

class FfmAssistantContextScope
    extends InheritedNotifier<FfmAssistantPageContextController> {
  const FfmAssistantContextScope({
    super.key,
    required FfmAssistantPageContextController controller,
    required super.child,
  }) : super(notifier: controller);

  static FfmAssistantPageContextController? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<FfmAssistantContextScope>()
          ?.notifier;
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = FfmAssistantContextScope.maybeOf(context);
    _controller?.activate(_token, widget.destination);
  }

  @override
  void didUpdateWidget(covariant FfmAssistantPageContext oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destination != widget.destination) {
      _controller?.activate(_token, widget.destination);
    }
  }

  @override
  void dispose() {
    _controller?.deactivate(_token);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
