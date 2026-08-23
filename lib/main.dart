import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/database/app_database.dart';
import 'core/diagnostics/app_diagnostics_service.dart';
import 'core/di/injection.dart';
import 'core/security/app_pin_service.dart';
import 'core/theme/theme_preference.dart';
import 'features/assistant/domain/ffm_assistant_models.dart';
import 'features/assistant/domain/ffm_assistant_widget_protocol.dart';
import 'features/assistant/presentation/widgets/ffm_assistant_global_launcher.dart';
import 'features/assistant/presentation/widgets/ffm_agent_status_indicator.dart';
import 'features/assistant/presentation/widgets/ffm_assistant_page_context.dart';
import 'features/assistant/presentation/widgets/ffm_assistant_sheet.dart';
import 'features/assistant/presentation/pages/assistant_training_page.dart';
import 'features/assistant/presentation/pages/assistant_profile_page.dart';
import 'features/assistant/presentation/pages/local_model_page.dart';
import 'features/asset/presentation/pages/asset_pages.dart';
import 'features/audit/presentation/pages/activity_log_page.dart';
import 'features/backup/presentation/pages/backup_page.dart';
import 'features/backup/presentation/pages/monthly_report_page.dart';
import 'features/goal/presentation/pages/goal_pages.dart';
import 'features/liability/presentation/pages/liability_pages.dart';
import 'features/recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';
import 'features/receivable/presentation/pages/receivable_pages.dart';
import 'features/reminder/data/services/reminder_notification_service.dart';
import 'features/reminder/presentation/bloc/reminder_bloc.dart';
import 'features/reminder/presentation/pages/reminder_page.dart';
import 'features/settings/presentation/pages/master_data_page.dart';
import 'features/activity/presentation/pages/activity_page.dart';
import 'features/advisor/presentation/pages/summary_page.dart';
import 'features/advisor/presentation/pages/analysis_page.dart';
import 'features/budget/presentation/pages/budget_page.dart';
import 'features/settings/presentation/pages/app_diagnostics_page.dart';
import 'features/settings/presentation/pages/database_structure_page.dart';
import 'features/settings/presentation/pages/offline_advanced_page.dart';
import 'features/settings/presentation/pages/offline_features_page.dart';
import 'features/settings/presentation/pages/privacy_center_page.dart';
import 'features/settings/presentation/pages/other_menu_page.dart';
import 'features/settings/presentation/pages/pin_security_page.dart';
import 'features/settings/presentation/widgets/app_pin_entry_panel.dart';
import 'features/settings/presentation/widgets/forgot_pin_dialog.dart';
import 'features/transaction/presentation/pages/receipt_json_import_page.dart';
import 'features/transaction/presentation/pages/transaction_pages.dart';
import 'features/recurring_transaction/presentation/pages/recurring_transaction_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrapDiagnostics = AppDiagnosticsService();
  await bootstrapDiagnostics.recordInterruptedStartupIfNeeded();
  await bootstrapDiagnostics.markStartupStarted(phase: 'bindings_ready');
  await configureDependencies();
  final diagnostics = getIt<AppDiagnosticsService>();
  await diagnostics.markStartupPhase('dependencies_ready');
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      diagnostics.recordException(
        code: 'FLUTTER_UNHANDLED_ERROR',
        feature: 'Tampilan aplikasi',
        error: details.exception,
        stackTrace: details.stack,
        impact: 'Tampilan mungkin perlu dicoba ulang.',
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    unawaited(
      diagnostics.recordException(
        code: 'ASYNC_UNHANDLED_ERROR',
        feature: 'Proses aplikasi',
        error: error,
        stackTrace: stackTrace,
        impact: 'Proses dibatalkan dengan aman.',
      ),
    );
    return true;
  };
  final reminderNotificationService = getIt<ReminderNotificationService>();
  await reminderNotificationService.initialize();
  await getIt<ReminderBloc>().recover();
  await getIt<ProcessRecurringTransactions>()('local-household');
  final isDark = await ThemePreference.isDark();
  runApp(FfmApp(initialDarkMode: isDark));
}

class FfmApp extends StatefulWidget {
  const FfmApp({
    super.key,
    bool? initialDarkMode,
    this.database,
    this.onboardingComplete,
    this.pinEnabled,
    this.pinService,
    this.diagnostics,
    bool? isDarkMode,
  }) : initialDarkMode = initialDarkMode ?? isDarkMode ?? false;

  final bool initialDarkMode;
  final AppDatabase? database;
  final bool? onboardingComplete;
  final bool? pinEnabled;
  final AppPinService? pinService;
  final AppDiagnosticsService? diagnostics;

  @override
  State<FfmApp> createState() => _FfmAppState();
}

class _FfmAppState extends State<FfmApp> with WidgetsBindingObserver {
  static const _lockAfterBackground = Duration(seconds: 10);

  late var _isDark = widget.initialDarkMode;
  late final AppPinService _pinService =
      widget.pinService ?? getIt<AppPinService>();
  late final AppDiagnosticsService _diagnostics =
      widget.diagnostics ?? getIt<AppDiagnosticsService>();
  var _pinGateLoading = true;
  var _isLocked = false;
  var _securityUnavailable = false;
  var _pinLength = AppPinService.defaultPinLength;
  DateTime? _backgroundedAt;
  final _appShellKey = GlobalKey<_AppShellState>();
  final _assistantLauncherState = ValueNotifier(
    const FfmAssistantLauncherState(isSheetOpen: false),
  );
  final _assistantPageContext = FfmAssistantPageContextController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_diagnostics.markStartupComplete());
    });
    if (widget.database != null && !getIt.isRegistered<AppDatabase>()) {
      configureDependencies(database: widget.database);
    }
    _preparePinGate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _assistantLauncherState.dispose();
    _assistantPageContext.dispose();
    super.dispose();
  }

  Future<void> _preparePinGate() async {
    if (widget.pinEnabled == false) {
      if (mounted) setState(() => _pinGateLoading = false);
      return;
    }
    try {
      final configuredLength = await _pinService.configuredPinLength();
      if (!mounted) return;
      setState(() {
        _pinGateLoading = false;
        _securityUnavailable = false;
        _pinLength = configuredLength ?? AppPinService.defaultPinLength;
        _isLocked = configuredLength != null || widget.pinEnabled == true;
      });
    } catch (error, stackTrace) {
      await _diagnostics.recordException(
        code: 'PIN_GATE_READ_FAILED',
        feature: 'Kunci aplikasi',
        error: error,
        stackTrace: stackTrace,
        impact: 'Aplikasi ditahan sampai keamanan bisa dibaca lagi.',
      );
      if (!mounted) return;
      setState(() {
        _pinGateLoading = false;
        _securityUnavailable = true;
        _isLocked = true;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _backgroundedAt ??= DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      if (backgroundedAt != null &&
          DateTime.now().difference(backgroundedAt) >= _lockAfterBackground) {
        _lockAfterBackgroundDelay();
      }
    }
  }

  Future<void> _lockAfterBackgroundDelay() async {
    try {
      final configuredLength = await _pinService.configuredPinLength();
      if (!mounted || configuredLength == null) return;
      setState(() {
        _pinLength = configuredLength;
        _isLocked = true;
      });
    } catch (error, stackTrace) {
      await _diagnostics.recordException(
        code: 'PIN_GATE_RESUME_FAILED',
        feature: 'Kunci aplikasi',
        error: error,
        stackTrace: stackTrace,
        impact: 'Aplikasi ditahan sampai keamanan bisa dibaca lagi.',
      );
      if (mounted) setState(() => _securityUnavailable = true);
    }
  }

  Future<String?> _unlock(String pin) async {
    try {
      final outcome = await _pinService.verifyPin(pin);
      if (!mounted) return null;
      if (outcome == FfmAppPinOperation.success) {
        setState(() => _isLocked = false);
        return null;
      }
      return switch (outcome) {
        FfmAppPinOperation.incorrectPin =>
          'PIN-nya belum cocok. Coba lagi, ya.',
        FfmAppPinOperation.invalidPin => 'PIN harus berisi $_pinLength angka.',
        FfmAppPinOperation.inactive =>
          'PIN belum aktif. Buka Kunci aplikasi dari menu Lainnya.',
        FfmAppPinOperation.success => null,
      };
    } catch (error, stackTrace) {
      await _diagnostics.recordException(
        code: 'PIN_GATE_VERIFY_FAILED',
        feature: 'Kunci aplikasi',
        error: error,
        stackTrace: stackTrace,
        impact: 'Aplikasi tetap terkunci.',
      );
      return 'PIN belum bisa dicek. Coba lagi sebentar, ya.';
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FFM',
    debugShowCheckedModeBanner: false,
    themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
    theme: _buildTheme(Brightness.light),
    darkTheme: _buildTheme(Brightness.dark),
    builder: (context, child) {
      final showAssistant =
          !_pinGateLoading && !_securityUnavailable && !_isLocked;
      if (!showAssistant || child == null) return child ?? const SizedBox();
      return FfmAssistantContextScope(
        controller: _assistantPageContext,
        child: Stack(
          children: [
            child,
            FfmAssistantGlobalLauncher(
              state: _assistantLauncherState,
              onOpen: () async => _appShellKey.currentState?._openAssistant(),
            ),
          ],
        ),
      );
    },
    home: _pinGateLoading
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : _securityUnavailable
        ? _PinSecurityUnavailable(onRetry: _preparePinGate)
        : _isLocked
        ? Scaffold(
            body: AppPinEntryPanel(
              title: 'FFM lagi dikunci',
              message: 'Masukkan PIN untuk lanjut ke data keluarga.',
              onCompleted: _unlock,
              pinLength: _pinLength,
              secondaryLabel: 'Lupa PIN?',
              onSecondaryAction: () => showForgotPinDialog(context),
            ),
          )
        : AppShell(
            key: _appShellKey,
            launcherState: _assistantLauncherState,
            pageContext: _assistantPageContext,
            pageContextController: _assistantPageContext,
            isDark: _isDark,
            onThemeChanged: (value) async {
              setState(() => _isDark = value);
              await ThemePreference.saveDark(value);
            },
          ),
  );

  ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF7FAF9)
          : null,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}

class _PinSecurityUnavailable extends StatelessWidget {
  const _PinSecurityUnavailable({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.security_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                'Keamanan FFM belum bisa dicek',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Biar data keluarga tetap aman, FFM belum dibuka. Coba cek lagi dulu, ya.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.isDark,
    required this.onThemeChanged,
    required this.launcherState,
    required this.pageContext,
    required this.pageContextController,
  });

  final bool isDark;
  final ValueChanged<bool> onThemeChanged;
  final ValueNotifier<FfmAssistantLauncherState> launcherState;
  final ValueListenable<FfmAssistantDestination?> pageContext;
  final FfmAssistantPageContextController pageContextController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _widgetChannel = MethodChannel('ffm/widget');
  var _index = 0;
  var _assistantRequestId = 0;
  var _assistantSheetOpen = false;
  final _agentStatus = getIt<FfmAgentStatusController>();
  FfmAssistantDraft? _assistantTransactionDraft;
  final _assistantSession = FfmAssistantChatSession();

  @override
  void initState() {
    super.initState();
    _widgetChannel.setMethodCallHandler(_handleWidgetCall);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumePendingWidgetAction();
    });
  }

  Future<void> _consumePendingWidgetAction() async {
    final action = await _widgetChannel.invokeMethod<String>(
      'consumePendingAction',
    );
    if (mounted && action != null) {
      _openWidgetAction(action);
    }
  }

  Future<void> _handleWidgetCall(MethodCall call) async {
    if (call.method != 'openAction' || !mounted) return;
    _openWidgetAction(call.arguments?.toString());
  }

  void _openWidgetAction(String? action) {
    if (!mounted) return;
    final parsed = action == null
        ? null
        : FfmAssistantWidgetAction.fromWireName(action);
    switch (parsed) {
      case FfmAssistantWidgetAction.openAssistant:
        _openAssistant();
      case FfmAssistantWidgetAction.readSummary:
        setState(() => _index = 0);
      case FfmAssistantWidgetAction.openModelSetup:
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const LocalModelPage()));
      case FfmAssistantWidgetAction.openTransactions:
        setState(() => _index = 1);
      case FfmAssistantWidgetAction.openBudget:
        setState(() => _index = 3);
      case FfmAssistantWidgetAction.openActivity:
        setState(() => _index = 2);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ActivityPage()));
          }
        });
      case FfmAssistantWidgetAction.openScan:
        setState(() => _index = 1);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReceiptJsonImportPage()),
            );
          }
        });
      case null:
        return;
    }
  }

  @override
  void dispose() {
    _widgetChannel.setMethodCallHandler(null);
    super.dispose();
  }

  List<Widget> get _pages => [
    const SummaryPage(),
    TransactionListPage(
      assistantDraft: _assistantTransactionDraft,
      assistantRequestId: _assistantRequestId,
      onOpenAssistant: _openAssistant,
    ),
    const ActivityPage(), // Menggantikan posisi Anggaran/Analisa sebagai menu harian utama
    const EnvelopeBudgetPage(),
    const OtherMenuPage(),
  ];

  FfmAssistantDestination get _assistantCurrentDestination => switch (_index) {
    0 => FfmAssistantDestination.summary,
    1 => FfmAssistantDestination.transactions,
    2 => FfmAssistantDestination.activity,
    3 => FfmAssistantDestination.budget,
    _ => FfmAssistantDestination.otherMenu,
  };

  int _masterDataTab(FfmAssistantDraft? draft) => switch (draft?.categoryName) {
    'toko' => 1,
    'tag' => 2,
    'rekening' => 3,
    'sumber_pemasukan' => 4,
    _ => 0,
  };

  Future<void> _handleAssistantIntent(FfmAssistantIntent intent) async {
    final destination = intent.destination;
    if (destination == null) return;
    switch (destination) {
      case FfmAssistantDestination.summary:
        setState(() => _index = 0);
      case FfmAssistantDestination.transactions:
        if (intent.draft != null) {
          final draft = intent.draft!;
          if (draft.kind == FfmAssistantDraftKind.income ||
              draft.kind == FfmAssistantDraftKind.expense) {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TransactionFormPage(
                  initialType: draft.kind == FfmAssistantDraftKind.income
                      ? TransactionType.income
                      : TransactionType.expense,
                  initialAmount: draft.amount,
                  initialAccountName: draft.kind == FfmAssistantDraftKind.income
                      ? draft.toAccountName
                      : draft.fromAccountName,
                  initialCategoryName: draft.categoryName,
                  initialNote: draft.note ?? draft.title,
                  initialDate: draft.date,
                ),
              ),
            );
          } else {
            setState(() {
              _index = 1;
              _assistantTransactionDraft = draft;
              _assistantRequestId++;
            });
          }
        } else {
          setState(() => _index = 1);
        }
      case FfmAssistantDestination.budget:
        final draft = intent.draft;
        if (draft?.kind == FfmAssistantDraftKind.budget) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  EnvelopeBudgetPage(assistantAmount: draft?.amount),
            ),
          );
        } else {
          setState(() => _index = 3);
        }
      case FfmAssistantDestination.analysis:
        setState(() => _index = 4);
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const AnalysisPage()));
      case FfmAssistantDestination.otherMenu:
        setState(() => _index = 4);
      case FfmAssistantDestination.masterData:
        final draft = intent.draft;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MasterDataPage(
              assistantTab: draft?.kind == FfmAssistantDraftKind.masterData
                  ? _masterDataTab(draft)
                  : null,
              assistantName: draft?.kind == FfmAssistantDraftKind.masterData
                  ? draft?.title
                  : null,
              assistantFormValues:
                  draft?.kind == FfmAssistantDraftKind.masterData
                  ? draft?.formValues
                  : null,
              assistantProfileName:
                  draft?.kind == FfmAssistantDraftKind.masterData &&
                      draft?.categoryName == 'profil'
                  ? draft?.title
                  : null,
            ),
          ),
        );
      case FfmAssistantDestination.assets:
        final draft = intent.draft;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => draft?.kind == FfmAssistantDraftKind.asset
                ? AssetFormPage(
                    initialName: draft?.title,
                    initialValue: draft?.amount,
                    initialType: draft?.categoryName,
                    initialPlacement: draft?.toAccountName,
                    initialNote: draft?.note,
                  )
                : const AssetListPage(),
          ),
        );
      case FfmAssistantDestination.goals:
        final draft = intent.draft;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => draft?.kind == FfmAssistantDraftKind.goal
                ? GoalFormPage(
                    initialName: draft?.title,
                    initialTargetAmount: draft?.amount,
                    initialTargetDate: draft?.date,
                  )
                : const GoalListPage(),
          ),
        );
      case FfmAssistantDestination.liabilities:
        final draft = intent.draft;
        if (draft?.kind == FfmAssistantDraftKind.liability) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LiabilityFormPage(
                initialName: draft!.partyName,
                initialAmount: draft.amount,
              ),
            ),
          );
        } else if (draft?.kind == FfmAssistantDraftKind.receivable) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ReceivableFormPage(
                initialName: draft!.partyName,
                initialAmount: draft.amount,
              ),
            ),
          );
        } else {
          setState(() => _index = 4);
        }
      case FfmAssistantDestination.activity:
        final draft = intent.draft;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ActivityPage(
              initialTitle: draft?.kind == FfmAssistantDraftKind.activity
                  ? draft?.title
                  : null,
              initialCategory: draft?.kind == FfmAssistantDraftKind.activity
                  ? draft?.categoryName
                  : null,
              initialNotes: draft?.kind == FfmAssistantDraftKind.activity
                  ? draft?.note
                  : null,
            ),
          ),
        );
      case FfmAssistantDestination.reminders:
        final draft = intent.draft;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReminderPage(
              initialTitle: draft?.kind == FfmAssistantDraftKind.reminder
                  ? draft?.title
                  : null,
              initialNote: draft?.kind == FfmAssistantDraftKind.reminder
                  ? draft?.note
                  : null,
            ),
          ),
        );
      case FfmAssistantDestination.backup:
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const BackupPage()));
      case FfmAssistantDestination.monthlyReport:
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const MonthlyReportPage()));
      case FfmAssistantDestination.reconciliation:
        setState(() => _index = 4);
      case FfmAssistantDestination.appSecurity:
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const PinSecurityPage()));
      case FfmAssistantDestination.diagnostics:
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AppDiagnosticsPage()));
      case FfmAssistantDestination.activityLog:
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const ActivityLogPage()));
      case FfmAssistantDestination.assistantTraining:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AssistantTrainingPage()),
        );
      case FfmAssistantDestination.recurringTransaction:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RecurringTransactionPage()),
        );
      case FfmAssistantDestination.offlineAdvanced:
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OfflineAdvancedPage()));
      case FfmAssistantDestination.privacyCenter:
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const PrivacyCenterPage()));
      case FfmAssistantDestination.databaseStructure:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DatabaseStructurePage()),
        );
      case FfmAssistantDestination.offlineFeatures:
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OfflineFeaturesPage()));
      case FfmAssistantDestination.localModel:
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const LocalModelPage()));
      case FfmAssistantDestination.assistantProfile:
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AssistantProfilePage()));
    }
  }

  Future<void> _handleAssistantIntents(List<FfmAssistantIntent> intents) async {
    for (final intent in intents) {
      if (!mounted) return;
      await _handleAssistantIntent(intent);
    }
  }

  Future<void> _openAssistant() async {
    if (_assistantSheetOpen) return;
    setState(() => _assistantSheetOpen = true);
    widget.launcherState.value = const FfmAssistantLauncherState(
      isSheetOpen: true,
    );
    try {
      await showFfmAssistantSheet(
        context,
        onIntent: _handleAssistantIntent,
        onIntents: _handleAssistantIntents,
        session: _assistantSession,
        currentDestination:
            widget.pageContext.value ?? _assistantCurrentDestination,
        currentPageContext: widget.pageContextController.currentSnapshot,
      );
    } finally {
      if (mounted) {
        setState(() => _assistantSheetOpen = false);
        widget.launcherState.value = const FfmAssistantLauncherState(
          isSheetOpen: false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        FfmAgentStatusIndicator(controller: _agentStatus),
        Expanded(
          child: IndexedStack(index: _index, children: _pages),
        ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (value) => setState(() => _index = value),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Beranda',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long),
          label: 'Transaksi',
        ),
        NavigationDestination(
          icon: Icon(Icons.timeline_outlined),
          selectedIcon: Icon(Icons.timeline),
          label: 'Aktivitas',
        ),
        NavigationDestination(
          icon: Icon(Icons.track_changes_outlined),
          selectedIcon: Icon(Icons.track_changes),
          label: 'Anggaran',
        ),
        NavigationDestination(
          icon: Icon(Icons.more_horiz),
          selectedIcon: Icon(Icons.more),
          label: 'Lainnya',
        ),
      ],
    ),
  );
}
