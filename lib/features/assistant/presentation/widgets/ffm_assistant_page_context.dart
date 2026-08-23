import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../domain/ffm_assistant_capabilities.dart';
import '../../domain/ffm_assistant_models.dart';

class FfmAssistantPageContextSnapshot {
  const FfmAssistantPageContextSnapshot({
    required this.destination,
    required this.capabilityIds,
    required this.updatedAt,
    this.dataSummary,
    this.activeFilters = const <String, String>{},
  });

  final FfmAssistantDestination destination;
  final List<String> capabilityIds;
  final DateTime updatedAt;
  final String? dataSummary;
  final Map<String, String> activeFilters;

  FfmAssistantPageContextSnapshot copyWith({
    String? dataSummary,
    Map<String, String>? activeFilters,
  }) => FfmAssistantPageContextSnapshot(
    destination: destination,
    capabilityIds: capabilityIds,
    updatedAt: DateTime.now(),
    dataSummary: dataSummary ?? this.dataSummary,
    activeFilters: activeFilters ?? this.activeFilters,
  );
}

/// Menyimpan konteks route aktif untuk launcher Asisten global.
/// Stack token menjaga konteks halaman induk kembali aktif setelah detail ditutup.
class FfmAssistantPageContextController
    extends ValueNotifier<FfmAssistantDestination?> {
  FfmAssistantPageContextController() : super(null);

  final _entries = <Object, FfmAssistantPageContextSnapshot>{};
  var _isDisposed = false;

  FfmAssistantPageContextSnapshot? get currentSnapshot =>
      _entries.values.isEmpty ? null : _entries.values.last;

  void activate(
    Object token,
    FfmAssistantDestination destination, {
    String? dataSummary,
    Map<String, String> activeFilters = const <String, String>{},
    List<String>? capabilityIds,
  }) {
    if (_isDisposed) return;
    final snapshot = FfmAssistantPageContextSnapshot(
      destination: destination,
      capabilityIds:
          capabilityIds ??
          FfmAssistantCapabilityRegistry.forDestination(destination)
              .map((capability) => capability.id)
              .toList(growable: false),
      updatedAt: DateTime.now(),
      dataSummary: dataSummary,
      activeFilters: Map.unmodifiable(activeFilters),
    );
    _entries
      ..remove(token)
      ..[token] = snapshot;
    value = snapshot.destination;
  }

  void deactivate(Object token) {
    if (_isDisposed) return;
    _entries.remove(token);
    value = currentSnapshot?.destination;
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
    this.dataSummary,
    this.activeFilters = const <String, String>{},
    this.capabilityIds,
  });

  final FfmAssistantDestination destination;
  final Widget child;
  final String? dataSummary;
  final Map<String, String> activeFilters;
  final List<String>? capabilityIds;

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
      controller.activate(
        _token,
        widget.destination,
        dataSummary: widget.dataSummary,
        activeFilters: widget.activeFilters,
        capabilityIds: widget.capabilityIds,
      );
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
    if (oldWidget.destination != widget.destination ||
        oldWidget.dataSummary != widget.dataSummary ||
        !mapEquals(oldWidget.activeFilters, widget.activeFilters) ||
        !listEquals(oldWidget.capabilityIds, widget.capabilityIds)) {
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
