import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/database/app_database.dart';
import 'core/database/app_context.dart';
import 'core/database/database_seed.dart';
import 'core/diagnostics/app_diagnostics_service.dart';
import 'core/di/injection.dart';
import 'core/security/app_pin_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_controller.dart';
import 'core/theme/theme_preference.dart';
import 'features/assistant/domain/assistant_onboarding_orchestrator.dart';
import 'features/assistant/domain/ffm_assistant_models.dart';
import 'features/assistant/data/ffm_assistant_chat_history_repository.dart';
import 'features/assistant/data/ffm_assistant_memory_repository.dart';
import 'features/assistant/data/ffm_assistant_personalization_repository.dart';
import 'features/assistant/data/ffm_assistant_user_model_service.dart';
import 'features/assistant/data/ffm_personal_context_provider.dart';
import 'features/assistant/data/ffm_personal_memory_service.dart';
import 'features/assistant/domain/ffm_assistant_widget_protocol.dart';
import 'features/assistant/presentation/widgets/ffm_assistant_global_launcher.dart';
import 'features/assistant/presentation/widgets/ffm_assistant_page_context.dart';
import 'features/assistant/presentation/widgets/ffm_assistant_sheet.dart';
import 'features/assistant/presentation/widgets/nfc_scan_dialog.dart';
import 'features/assistant/data/nfc_bridge.dart';

import 'features/assistant/presentation/pages/assistant_profile_page.dart';
import 'features/assistant/presentation/pages/agent_inbox_page.dart';
import 'features/asset/presentation/pages/asset_pages.dart';
import 'features/audit/presentation/pages/activity_log_page.dart';
import 'features/backup/presentation/pages/backup_page.dart';
import 'features/backup/presentation/pages/monthly_report_page.dart';
import 'features/asset/presentation/widgets/market_news_radar_drawer.dart';
import 'features/goal/presentation/pages/goal_pages.dart';
import 'features/goal/domain/entities/goal_entity.dart';
import 'features/goal/domain/usecases/goal_crud_usecases.dart';
import 'features/liability/presentation/pages/liability_pages.dart';
import 'features/recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';
import 'features/receivable/presentation/pages/receivable_pages.dart';
import 'features/reminder/data/services/reminder_notification_service.dart';
import 'features/reminder/presentation/bloc/reminder_bloc.dart';
import 'features/reminder/presentation/pages/reminder_page.dart';
import 'features/settings/presentation/pages/master_data_page.dart';
import 'features/settings/presentation/pages/family_profile_page.dart';
import 'features/activity/presentation/pages/activity_page.dart';
import 'features/advisor/presentation/pages/summary_page.dart';
import 'features/advisor/presentation/pages/analysis_page.dart';
import 'features/budget/presentation/pages/budget_page.dart';
import 'features/settings/presentation/pages/app_diagnostics_page.dart';
import 'features/settings/presentation/pages/database_structure_page.dart';

import 'features/settings/presentation/pages/privacy_center_page.dart';
import 'features/settings/presentation/pages/other_menu_page.dart';
import 'features/settings/presentation/pages/pin_security_page.dart';
import 'features/settings/presentation/pages/supabase_setup_page.dart';
import 'features/settings/presentation/widgets/app_pin_entry_panel.dart';
import 'features/settings/presentation/widgets/forgot_pin_dialog.dart';
import 'features/assistant/data/ffm_memory_maintenance_service.dart';
import 'features/assistant/data/ffm_assistant_proactive_monitor.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'features/assistant/data/ffm_assistant_autonomy_background_dispatcher.dart';
import 'features/assistant/data/ffm_assistant_autonomy_background_scheduler.dart';
import 'features/assistant/data/ffm_assistant_foreground_service.dart';
import 'features/assistant/domain/autonomous_evaluation_coordinator.dart';
import 'features/activity/data/repositories/activity_repository.dart';
import 'features/assistant/data/notification_listener_bridge.dart';
import 'features/assistant/presentation/pages/payment_detector_settings_page.dart';
import 'features/assistant/presentation/pages/telegram_setup_page.dart';
import 'features/assistant/presentation/pages/ffm_assistant_autonomy_monitor_page.dart';
import 'features/hijri/presentation/pages/hijri_settings_page.dart';
import 'features/settings/presentation/pages/calendar_settings_page.dart';
import 'features/asset/presentation/pages/market_news_radar_page.dart';
import 'features/settings/presentation/pages/utility_meter_page.dart';
import 'features/transaction/presentation/pages/transaction_pages.dart';
import 'features/recurring_transaction/presentation/pages/recurring_transaction_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  // Muat data simbol locale agar DateFormat(..., 'id_ID') tidak memicu
  // LocaleDataException saat UI memformat tanggal.
  await initializeDateFormatting('id_ID', null);
  final bootstrapDiagnostics = AppDiagnosticsService();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      bootstrapDiagnostics.recordException(
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
      bootstrapDiagnostics.recordException(
        code: 'ASYNC_UNHANDLED_ERROR',
        feature: 'Proses aplikasi',
        error: error,
        stackTrace: stackTrace,
        impact: 'Proses dibatalkan dengan aman.',
      ),
    );
    return true;
  };
  await bootstrapDiagnostics.recordInterruptedStartupIfNeeded();
  await bootstrapDiagnostics.markStartupStarted(phase: 'bindings_ready');
  await configureDependencies();
  final diagnostics = getIt<AppDiagnosticsService>();
  try {
    await DatabaseSeed.ensure(getIt<AppDatabase>());
  } catch (error, stackTrace) {
    await diagnostics.recordException(
      code: 'DATABASE_SEED_FAILED',
      feature: 'Database Seed',
      error: error,
      stackTrace: stackTrace,
      impact: 'Seed data dasar akan dicoba lagi pada siklus berikutnya.',
    );
  }
  await diagnostics.markStartupPhase('dependencies_ready');
  await _scheduleAutonomyBackgroundWork(diagnostics);
  unawaited(_initializePersonalContext(diagnostics));
  // Pemeliharaan memori: decay berkala tanpa memblok startup.
  if (getIt.isRegistered<FfmMemoryMaintenanceService>()) {
    getIt<FfmMemoryMaintenanceService>().start();
  }
  try {
    final reminderNotificationService = getIt<ReminderNotificationService>();
    await reminderNotificationService.initialize();
    await getIt<ReminderBloc>().recover();
  } catch (error, stackTrace) {
    await diagnostics.recordException(
      code: 'REMINDER_BOOTSTRAP_FAILED',
      feature: 'Pengingat',
      error: error,
      stackTrace: stackTrace,
      impact: 'Pengingat akan dipulihkan saat dibuka.',
    );
  }
  try {
    await getIt<ProcessRecurringTransactions>()('local-household');
  } catch (error, stackTrace) {
    await diagnostics.recordException(
      code: 'RECURRING_TRANSACTION_BOOTSTRAP_FAILED',
      feature: 'Transaksi Berulang',
      error: error,
      stackTrace: stackTrace,
      impact: 'Transaksi berulang akan diproses pada siklus berikutnya.',
    );
  }
  bool isDark = false;
  try {
    isDark = await ThemePreference.isDark();
  } catch (_) {}

  // Inisialisasi pendengar notifikasi perbankan & e-wallet lokal
  try {
    if (getIt.isRegistered<NotificationListenerBridge>()) {
      getIt<NotificationListenerBridge>().startListening();
    }
  } catch (_) {}

  runApp(FfmApp(initialDarkMode: isDark));
}

Future<void> _scheduleAutonomyBackgroundWork(
  AppDiagnosticsService diagnostics,
) async {
  try {
    final scheduler = getIt<FfmAssistantAutonomyBackgroundScheduler>();
    await scheduler.initialize(ffmAssistantAutonomyCallbackDispatcher);
    await scheduler.ensureScheduled();
  } catch (error, stackTrace) {
    await diagnostics.recordException(
      code: 'AUTONOMY_BACKGROUND_SCHEDULER_INIT_FAILED',
      feature: 'Background Agent',
      error: error,
      stackTrace: stackTrace,
      impact: 'Agent tetap berjalan saat aplikasi dibuka; scheduler akan dicoba lagi pada startup berikutnya.',
    );
  }

  // Inisialisasi dan pulihkan Foreground Service jika diaktifkan pengguna
  try {
    if (getIt.isRegistered<FfmAssistantForegroundServiceManager>()) {
      final fgManager = getIt<FfmAssistantForegroundServiceManager>();
      fgManager.initialize();
      final isEnabled = await fgManager.isEnabled();
      if (isEnabled) {
        await fgManager.startService();
      }
    }
  } catch (error, stackTrace) {
    await diagnostics.recordException(
      code: 'AUTONOMY_FOREGROUND_SERVICE_INIT_FAILED',
      feature: 'Foreground Agent',
      error: error,
      stackTrace: stackTrace,
      impact: 'Layanan status bar akan dicoba lagi pada siklus berikutnya.',
    );
  }
}

Future<void> _initializePersonalContext(
  AppDiagnosticsService diagnostics,
) async {
  try {
    await FfmPersonalContextProvider.initialize(
      database: getIt<AppDatabase>(),
      memoryRepository: getIt<FfmAssistantMemoryRepository>(),
      userModelService: getIt<FfmAssistantUserModelService>(),
      personalMemoryService: getIt<FfmPersonalMemoryService>(),
      personalizationRepository: getIt<FfmAssistantPersonalizationRepository>(),
      chatHistoryRepository: getIt<FfmAssistantChatHistoryRepository>(),
    );
  } catch (error, stackTrace) {
    await diagnostics.recordException(
      code: 'PERSONAL_CONTEXT_INIT_FAILED',
      feature: 'Konteks personal Asisten',
      error: error,
      stackTrace: stackTrace,
      impact:
          'Asisten memakai konteks dasar sampai konteks personal siap lagi.',
    );
  }
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
  AppThemeController? _themeController;
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

  void _onThemeStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (getIt.isRegistered<AppThemeController>()) {
      _themeController = getIt<AppThemeController>();
      _themeController?.addListener(_onThemeStateChanged);
      unawaited(_themeController?.loadSavedTheme());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_diagnostics.markStartupComplete());
        _triggerCatchUpEvaluation();
      }
    });
    if (widget.database != null && !getIt.isRegistered<AppDatabase>()) {
      configureDependencies(database: widget.database);
    }
    _preparePinGate();
  }

  void _triggerCatchUpEvaluation() {
    unawaited(() async {
      try {
        if (getIt.isRegistered<AutonomousEvaluationCoordinator>()) {
          await getIt<AutonomousEvaluationCoordinator>().runEvaluation(
            householdId: AppContext.householdId,
          );
        }
      } catch (_) {}
    }());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _themeController?.removeListener(_onThemeStateChanged);
    _assistantLauncherState.dispose();
    _assistantPageContext.dispose();
    super.dispose();
  }

  void _checkAutoOpenOnboarding() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        if (getIt.isRegistered<AssistantOnboardingOrchestrator>()) {
          final needs = await getIt<AssistantOnboardingOrchestrator>()
              .checkNeedsOnboarding();
          if (needs && mounted) {
            await _appShellKey.currentState?._openAssistant();
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _preparePinGate() async {
    if (widget.pinEnabled == false) {
      if (mounted) {
        setState(() => _pinGateLoading = false);
        _checkAutoOpenOnboarding();
      }
      return;
    }
    try {
      final configuredLength = await _pinService.configuredPinLength().timeout(
        const Duration(seconds: 4),
      );
      if (!mounted) return;
      final isLocked = configuredLength != null || widget.pinEnabled == true;
      setState(() {
        _pinGateLoading = false;
        _securityUnavailable = false;
        _pinLength = configuredLength ?? AppPinService.defaultPinLength;
        _isLocked = isLocked;
      });
      if (!isLocked) {
        _checkAutoOpenOnboarding();
      }
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
      _triggerCatchUpEvaluation();
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
        _checkAutoOpenOnboarding();
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
    themeMode: _themeController?.themeMode ??
        (_isDark ? ThemeMode.dark : ThemeMode.light),
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    builder: (context, child) {
      final showAssistant =
          !_pinGateLoading && !_securityUnavailable && !_isLocked;
      if (!showAssistant || child == null) return child ?? const SizedBox();
      return FfmAssistantContextScope(
        controller: _assistantPageContext,
        onOpenAssistant: ({String? initialPrompt}) async =>
            _appShellKey.currentState?._openAssistant(),
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
        ? Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/branding/Logo_FFM.png',
                    width: 96,
                    height: 96,
                  ),
                  const SizedBox(height: 20),
                  const CircularProgressIndicator(),
                ],
              ),
            ),
          )
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
            isDark: _themeController?.isDark ?? _isDark,
            onThemeChanged: (value) async {
              if (_themeController != null) {
                await _themeController!.setThemeMode(
                  value ? ThemeMode.dark : ThemeMode.light,
                );
              } else {
                setState(() => _isDark = value);
                await ThemePreference.saveDark(value);
              }
            },
          ),
  );
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
              Image.asset(
                'assets/branding/Logo_FFM.png',
                width: 80,
                height: 80,
              ),
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
  late final ReminderNotificationService _reminderNotifications =
      getIt<ReminderNotificationService>();
  FfmAssistantProactiveMonitor? _proactiveMonitor;
  FfmAssistantDraft? _assistantTransactionDraft;
  final _assistantSession = FfmAssistantChatSession();

  final _nfcBridge = NfcBridge();

  @override
  void initState() {
    super.initState();
    _widgetChannel.setMethodCallHandler(_handleWidgetCall);
    _nfcBridge.setTagTriggerListener(_handleNfcSmartTagTrigger);
    _reminderNotifications.openTarget.addListener(
      _openReminderFromNotification,
    );
    _reminderNotifications.inboxOpenTarget.addListener(
      _openInboxFromNotification,
    );
    _proactiveMonitor = FfmAssistantProactiveMonitor(
      activityRepository: getIt<ActivityRepository>(),
      launcherState: widget.launcherState,
      householdId: 'local-household',
    )..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumePendingWidgetAction();
      _consumePendingNfcTagTrigger();
      _openReminderFromNotification();
      _openInboxFromNotification();
    });
  }

  void _openReminderFromNotification() {
    if (!mounted) return;
    final target = _reminderNotifications.takeOpenTarget();
    if (target == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReminderPage(
          focusReminderId: target.reminderId,
          focusHistoryId: target.historyId,
        ),
      ),
    );
  }

  void _openInboxFromNotification() {
    if (!mounted) return;
    final target = _reminderNotifications.takeInboxOpenTarget();
    if (target == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AgentInboxPage(),
      ),
    );
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
      case FfmAssistantWidgetAction.openAssistant ||
          FfmAssistantWidgetAction.quickNote:
        _openAssistant();
      case FfmAssistantWidgetAction.scanNfc:
        NfcScanDialog.show(context);
      case FfmAssistantWidgetAction.readSummary:
        setState(() => _index = 0);
      case FfmAssistantWidgetAction.openModelSetup:
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const SupabaseSetupPage()));
      case FfmAssistantWidgetAction.openTransactions:
        setState(() => _index = 1);
      case FfmAssistantWidgetAction.openBudget:
        setState(() => _index = 3);
      case FfmAssistantWidgetAction.openActivity:
        setState(() => _index = 2);
      case FfmAssistantWidgetAction.openScan:
        setState(() => _index = 1);
      case null:
        return;
    }
  }

  Future<void> _consumePendingNfcTagTrigger() async {
    final uriStr = await _nfcBridge.consumePendingTagTrigger();
    if (mounted && uriStr != null) {
      _handleNfcSmartTagTrigger(uriStr);
    }
  }

  void _handleNfcSmartTagTrigger(String uriString) {
    if (!mounted) return;
    final uri = Uri.tryParse(uriString);
    if (uri == null || uri.scheme != 'ffm') return;

    final type = uri.queryParameters['type'];
    switch (type) {
      case 'voice_assistant':
        _openAssistant();
      case 'timer_activity':
        setState(() => _index = 2);
      case 'fuel' || 'groceries' || 'custom':
        setState(() => _index = 1);
        _openAssistant();
      default:
        _openAssistant();
    }
  }

  @override
  void dispose() {
    _proactiveMonitor?.stop();
    _reminderNotifications.openTarget.removeListener(
      _openReminderFromNotification,
    );
    _reminderNotifications.inboxOpenTarget.removeListener(
      _openInboxFromNotification,
    );
    _widgetChannel.setMethodCallHandler(null);
    _nfcBridge.setTagTriggerListener(null);
    super.dispose();
  }

  List<Widget> get _pages => [
    const SummaryPage(),
    TransactionListPage(
      assistantDraft: _assistantTransactionDraft,
      assistantRequestId: _assistantRequestId,
      onOpenAssistant: _openAssistant,
      onAssistantDraftSaved: _markActiveAssistantDraftCompleted,
      onAssistantDraftReturnedWithoutSave: _markActiveAssistantDraftReady,
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

  Future<void> _markActiveAssistantDraftCompleted() async {
    final id = _assistantSession.activeDraftQueueId;
    if (id == null || !mounted) return;
    final index = _assistantSession.draftQueue.indexWhere(
      (item) => item.id == id,
    );
    if (index < 0) return;
    setState(() {
      _assistantSession.draftQueue[index] = _assistantSession.draftQueue[index]
          .copyWith(status: FfmAssistantDraftQueueStatus.completed);
      _assistantSession
        ..activeDraftReview = null
        ..activeDraftIntent = null
        ..activeDraftQueueId = null;
      _assistantTransactionDraft = null;
    });
  }

  Future<void> _markActiveAssistantDraftReady() async {
    final id = _assistantSession.activeDraftQueueId;
    if (id == null || !mounted) return;
    final index = _assistantSession.draftQueue.indexWhere(
      (item) => item.id == id,
    );
    if (index < 0) return;
    setState(() {
      _assistantSession.draftQueue[index] = _assistantSession.draftQueue[index]
          .copyWith(status: FfmAssistantDraftQueueStatus.ready);
      _assistantTransactionDraft = null;
    });
  }

  Future<void> _syncAssistantDraftAfterForm(Object? result) => result == true
      ? _markActiveAssistantDraftCompleted()
      : _markActiveAssistantDraftReady();

  Future<bool> _saveGoalDraft(FfmAssistantDraft draft) async {
    final name = draft.title?.trim();
    final amount = draft.amount;
    final targetDate = draft.date;
    if (name == null ||
        name.isEmpty ||
        amount == null ||
        amount <= 0 ||
        targetDate == null) {
      return false;
    }
    await getIt<SaveGoal>()(
      GoalEntity(
        id:
            draft.formValues['targetId'] ??
            draft.createdAt.microsecondsSinceEpoch.toString(),
        householdId: AppContext.householdId,
        name: name,
        targetAmount: amount,
        currentAmount: 0,
        targetDate: targetDate,
      ),
    );
    return true;
  }

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
            // Form resmi dibuka oleh TransactionListPage agar hasil simpan
            // dapat diverifikasi sebelum status antrean draft diubah.
            setState(() {
              _index = 1;
              _assistantTransactionDraft = draft;
              _assistantRequestId++;
            });
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
              builder: (_) => EnvelopeBudgetPage(
                assistantAmount: draft?.amount,
                assistantCategoryName: draft?.categoryName,
                assistantPeriodType: draft?.formValues['periodType']
                    ?.toString(),
                onAssistantDraftResult: (saved) =>
                    _syncAssistantDraftAfterForm(saved),
              ),
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
        final isProfileTarget =
            draft?.kind == FfmAssistantDraftKind.masterData &&
            draft?.categoryName == 'profil';
        final createdId = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => isProfileTarget
                ? FamilyProfilePage(initialHouseholdName: draft?.title)
                : MasterDataPage(
                    assistantTab: draft?.kind == FfmAssistantDraftKind.masterData
                        ? _masterDataTab(draft)
                        : null,
                    assistantName:
                        draft?.kind == FfmAssistantDraftKind.masterData
                        ? draft?.title
                        : null,
                    assistantFormValues:
                        draft?.kind == FfmAssistantDraftKind.masterData
                        ? draft?.formValues
                        : null,
                    returnOnCreate:
                        draft?.kind == FfmAssistantDraftKind.masterData,
                  ),
          ),
        );
        if (!isProfileTarget &&
            draft?.kind == FfmAssistantDraftKind.masterData) {
          await _syncAssistantDraftAfterForm(createdId != null);
        }
      case FfmAssistantDestination.familyProfile:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FamilyProfilePage(
              initialIdentityName:
                  intent.draft?.kind == FfmAssistantDraftKind.profile
                  ? intent.draft?.title
                  : null,
            ),
          ),
        );
      case FfmAssistantDestination.assets:
        final draft = intent.draft;
        final saved = await Navigator.of(context).push<bool>(
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
        if (draft?.kind == FfmAssistantDraftKind.asset) {
          await _syncAssistantDraftAfterForm(saved);
        }
      case FfmAssistantDestination.goals:
        final draft = intent.draft;
        if (draft?.kind == FfmAssistantDraftKind.goal &&
            draft?.title != null &&
            draft!.amount != null &&
            draft.amount! > 0 &&
            draft.date != null) {
          final saved = await _saveGoalDraft(draft);
          await _syncAssistantDraftAfterForm(saved);
        } else {
          final saved = await Navigator.of(context).push<bool>(
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
          if (draft?.kind == FfmAssistantDraftKind.goal) {
            await _syncAssistantDraftAfterForm(saved);
          }
        }
      case FfmAssistantDestination.liabilities:
        final draft = intent.draft;
        if (draft?.kind == FfmAssistantDraftKind.liability) {
          final saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => LiabilityFormPage(
                initialName: draft!.partyName,
                initialAmount: draft.amount,
              ),
            ),
          );
          await _syncAssistantDraftAfterForm(saved);
        } else if (draft?.kind == FfmAssistantDraftKind.receivable) {
          final saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => ReceivableFormPage(
                initialName: draft!.partyName,
                initialAmount: draft.amount,
              ),
            ),
          );
          await _syncAssistantDraftAfterForm(saved);
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

      case FfmAssistantDestination.recurringTransaction:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RecurringTransactionPage()),
        );

      case FfmAssistantDestination.privacyCenter:
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const PrivacyCenterPage()));
      case FfmAssistantDestination.databaseStructure:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DatabaseStructurePage()),
        );

      case FfmAssistantDestination.assistantProfile:
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AssistantProfilePage()));
      case FfmAssistantDestination.intelligenceDashboard:
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const SupabaseSetupPage()));
      case FfmAssistantDestination.paymentDetector:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const PaymentDetectorSettingsPage(),
          ),
        );
      case FfmAssistantDestination.telegramSetup:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const TelegramSetupPage(),
          ),
        );
      case FfmAssistantDestination.agentInbox:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AgentInboxPage(),
          ),
        );
      case FfmAssistantDestination.autonomyMonitor:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const FfmAssistantAutonomyMonitorPage(),
          ),
        );
      case FfmAssistantDestination.hijriSettings:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const HijriSettingsPage(),
          ),
        );
      case FfmAssistantDestination.calendarSettings:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CalendarSettingsPage(),
          ),
        );
      case FfmAssistantDestination.marketNewsRadar:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const MarketNewsRadarPage(),
          ),
        );
      case FfmAssistantDestination.utilityMeter:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const UtilityMeterPage(),
          ),
        );
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
        launcherState: widget.launcherState,
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
    drawer: const MarketNewsRadarDrawer(),
    body: SafeArea(
      bottom: false,
      child: IndexedStack(index: _index, children: _pages),
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
