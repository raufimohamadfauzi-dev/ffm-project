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

/// Mengubah context layar UI menjadi teks pendek untuk prompt Asisten.
///
/// Context ini bukan tool call dan tidak boleh berisi data mentah halaman.
/// Detail yang tersedia pada snapshot sengaja tidak diteruskan sampai setiap
/// halaman detail memiliki policy field aman yang ditinjau secara eksplisit.
abstract final class FfmAssistantScreenContextPolicy {
  static const maxCharacters = 280;

  static const _nameOnlyDestinations = <FfmAssistantDestination>{
    FfmAssistantDestination.appSecurity,
    FfmAssistantDestination.privacyCenter,
    FfmAssistantDestination.backup,
    FfmAssistantDestination.diagnostics,
    FfmAssistantDestination.databaseStructure,
    FfmAssistantDestination.assistantTraining,
    FfmAssistantDestination.assistantProfile,
    FfmAssistantDestination.masterData,
    FfmAssistantDestination.activityLog,
    FfmAssistantDestination.reconciliation,
    FfmAssistantDestination.recurringTransaction,
    FfmAssistantDestination.intelligenceDashboard,
  };

  static String forPrompt({
    FfmAssistantDestination? destination,
    FfmAssistantPageContextSnapshot? snapshot,
  }) {
    final activeDestination = snapshot?.destination ?? destination;
    if (activeDestination == null) {
      return 'Konteks layar FFM: halaman aktif belum diketahui.';
    }

    final page = FfmAssistantCatalog.findByDestination(activeDestination);
    final pageName = page?.name ?? activeDestination.name;
    final base = 'Konteks layar FFM: Halaman aktif: $pageName.';
    if (_nameOnlyDestinations.contains(activeDestination)) {
      return base;
    }

    final summary = _genericSummary(activeDestination);
    return _clip('$base Ringkasan layar: $summary');
  }

  static bool isNameOnly(FfmAssistantDestination destination) =>
      _nameOnlyDestinations.contains(destination);

  static String _genericSummary(
    FfmAssistantDestination destination,
  ) => switch (destination) {
    FfmAssistantDestination.summary =>
      'Sedang melihat ringkasan periode berjalan.',
    FfmAssistantDestination.transactions =>
      'Sedang melihat daftar transaksi dan tindakan pencatatan.',
    FfmAssistantDestination.budget =>
      'Sedang melihat pengaturan dan pemantauan anggaran.',
    FfmAssistantDestination.analysis =>
      'Sedang melihat analisa dari data yang tersimpan.',
    FfmAssistantDestination.otherMenu =>
      'Sedang melihat daftar fitur pendukung FFM.',
    FfmAssistantDestination.assets => 'Sedang melihat daftar aset keluarga.',
    FfmAssistantDestination.goals => 'Sedang melihat target keuangan.',
    FfmAssistantDestination.liabilities => 'Sedang melihat hutang dan piutang.',
    FfmAssistantDestination.activity =>
      'Sedang melihat aktivitas dan durasinya.',
    FfmAssistantDestination.reminders => 'Sedang melihat pengingat lokal.',
    FfmAssistantDestination.monthlyReport =>
      'Sedang melihat laporan periode bulanan.',
    FfmAssistantDestination.offlineAdvanced =>
      'Sedang melihat alat pemeriksaan offline.',
    FfmAssistantDestination.offlineFeatures =>
      'Sedang melihat panduan fitur tanpa internet.',
    FfmAssistantDestination.localModel =>
      'Pengaturan model lokal tidak tersedia; gunakan Gemini Cloud.',
    FfmAssistantDestination.intelligenceDashboard =>
      'Sedang melihat pengaturan Gemini Cloud dan memori Supabase.',
    _ => 'Sedang melihat halaman fitur FFM.',
  };

  static String _clip(String value) {
    final normalized = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (normalized.length <= maxCharacters) return normalized;
    return '${normalized.substring(0, maxCharacters - 1)}…';
  }
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
