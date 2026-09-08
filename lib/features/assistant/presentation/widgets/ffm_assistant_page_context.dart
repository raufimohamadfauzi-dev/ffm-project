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
  static const maxCharacters = 600;

  static const _nameOnlyDestinations = <FfmAssistantDestination>{
    FfmAssistantDestination.appSecurity,
    FfmAssistantDestination.privacyCenter,
    FfmAssistantDestination.backup,
    FfmAssistantDestination.diagnostics,
    FfmAssistantDestination.databaseStructure,

    FfmAssistantDestination.assistantProfile,
    FfmAssistantDestination.masterData,
    FfmAssistantDestination.familyProfile,
    FfmAssistantDestination.activityLog,
    FfmAssistantDestination.reconciliation,
    FfmAssistantDestination.recurringTransaction,
    FfmAssistantDestination.intelligenceDashboard,
    FfmAssistantDestination.utilityMeter,
  };

  /// Halaman yang menampilkan data keuangan mentah \u2014 gunakan ringkasan generik
  /// agar nama merchant, nominal individual, dll. tidak bocor ke prompt model.
  /// Halaman laporan/agregat (monthlyReport, budget, dsb.) aman meneruskan
  /// dataSummary karena hanya berisi nilai agregat anonim.
  static const _rawDataDestinations = <FfmAssistantDestination>{
    FfmAssistantDestination.transactions,
    FfmAssistantDestination.summary,
    FfmAssistantDestination.liabilities,
    FfmAssistantDestination.assets,
    FfmAssistantDestination.goals,
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
    if (isNameOnly(activeDestination)) {
      return base;
    }
    final useGeneric = _rawDataDestinations.contains(activeDestination);
    final dataSummary = snapshot?.dataSummary;
    final summary =
        useGeneric || dataSummary == null || dataSummary.trim().isEmpty
            ? _genericSummary(activeDestination)
            : dataSummary.trim();
    final filters =
        snapshot?.activeFilters.entries
            .where(
              (entry) =>
                  entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty,
            )
            .map((entry) => '${entry.key}=${entry.value}')
            .join(', ') ??
        '';
    final filterText = filters.isEmpty ? '' : ' Filter aktif: $filters.';
    return _clip('$base Ringkasan layar: $summary.$filterText');
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

    FfmAssistantDestination.intelligenceDashboard =>
      'Sedang melihat pengaturan Gemini Cloud dan memori Supabase.',
    FfmAssistantDestination.familyProfile =>
      'Sedang melihat profil keluarga.',
    FfmAssistantDestination.utilityMeter =>
      'Sedang melihat Buku Saku Meteran & Token Listrik PLN.',
    _ => 'Sedang melihat halaman fitur FFM.',
  };

  static String _clip(String value) {
    final normalized = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (normalized.length <= maxCharacters) return normalized;
    return '${normalized.substring(0, maxCharacters - 1)}…';
  }
}

/// Menyimpan konteks route aktif untuk launcher Asisten global.
/// Stack token menjaga konteks halaman induk kembali aktif setelah detail ditutup,
/// sedangkan shell tab (beranda, transaksi, aktivitas, anggaran, lainnya) diisolasi
/// agar pembaruan data di tab latar belakang tidak membajak halaman aktif saat ini.
class FfmAssistantPageContextController
    extends ValueNotifier<FfmAssistantDestination?> {
  FfmAssistantPageContextController({
    FfmAssistantDestination? defaultDestination,
  })  : _currentShellTab = defaultDestination,
        super(defaultDestination);

  final _entries = <Object, FfmAssistantPageContextSnapshot>{};
  final _tabSnapshots =
      <FfmAssistantDestination, FfmAssistantPageContextSnapshot>{};
  FfmAssistantDestination? _currentShellTab;
  var _isDisposed = false;

  FfmAssistantDestination? get currentDestination =>
      _entries.values.isNotEmpty
          ? _entries.values.last.destination
          : _currentShellTab;

  FfmAssistantPageContextSnapshot? get currentSnapshot {
    if (_entries.values.isNotEmpty) {
      return _entries.values.last;
    }
    final shellTab = _currentShellTab;
    if (shellTab == null) return null;
    return _tabSnapshots[shellTab] ??
        FfmAssistantPageContextSnapshot(
          destination: shellTab,
          capabilityIds:
              FfmAssistantCapabilityRegistry.forDestination(shellTab)
                  .map((capability) => capability.id)
                  .toList(growable: false),
          updatedAt: DateTime.now(),
        );
  }

  void setShellTab(FfmAssistantDestination? destination) {
    if (_isDisposed) return;
    _currentShellTab = destination;
    if (_entries.isEmpty) {
      value = destination;
    }
  }

  void activate(
    Object token,
    FfmAssistantDestination destination, {
    String? dataSummary,
    Map<String, String> activeFilters = const <String, String>{},
    List<String>? capabilityIds,
    bool isTab = false,
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

    if (isTab) {
      _tabSnapshots[destination] = snapshot;
      if (_entries.isEmpty && _currentShellTab == destination) {
        value = destination;
      }
      return;
    }

    _entries
      ..remove(token)
      ..[token] = snapshot;
    value = snapshot.destination;
  }

  void deactivate(Object token) {
    if (_isDisposed) return;
    _entries.remove(token);
    value = currentDestination;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _entries.clear();
    _tabSnapshots.clear();
    super.dispose();
  }
}

class FfmAssistantContextScope
    extends InheritedNotifier<FfmAssistantPageContextController> {
  const FfmAssistantContextScope({
    super.key,
    required FfmAssistantPageContextController controller,
    this.onOpenAssistant,
    required super.child,
  }) : super(notifier: controller);

  final Future<void> Function({String? initialPrompt})? onOpenAssistant;

  /// Lookup tanpa mendaftarkan dependency. Pembungkus halaman hanya perlu
  /// menemukan controller sekali; launcher global yang mendengarkan nilainya.
  static FfmAssistantPageContextController? maybeOf(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<FfmAssistantContextScope>();
    return (element?.widget as FfmAssistantContextScope?)?.notifier;
  }

  /// Membuka asisten global jika didukung oleh shell aplikasi induk.
  static Future<void> Function({String? initialPrompt})? openAssistantOf(
    BuildContext context,
  ) {
    final element = context
        .getElementForInheritedWidgetOfExactType<FfmAssistantContextScope>();
    return (element?.widget as FfmAssistantContextScope?)?.onOpenAssistant;
  }
}

class FfmAssistantPageContext extends StatefulWidget {
  const FfmAssistantPageContext({
    super.key,
    required this.destination,
    required this.child,
    this.isTab = false,
    this.dataSummary,
    this.activeFilters = const <String, String>{},
    this.capabilityIds,
  });

  final FfmAssistantDestination destination;
  final Widget child;
  final bool isTab;
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
        isTab: widget.isTab,
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
        oldWidget.isTab != widget.isTab ||
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
