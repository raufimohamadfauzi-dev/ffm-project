import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/database/app_database.dart';
import 'core/di/injection.dart';
import 'core/theme/theme_preference.dart';
import 'features/assistant/domain/ffm_assistant_models.dart';
import 'features/assistant/presentation/widgets/ffm_assistant_sheet.dart';
import 'features/asset/presentation/pages/asset_pages.dart';
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
import 'features/advisor/presentation/pages/analysis_page.dart';
import 'features/activity/presentation/pages/activity_page.dart';
import 'features/advisor/presentation/pages/summary_page.dart';
import 'features/budget/presentation/pages/budget_page.dart';
import 'features/settings/presentation/pages/other_menu_page.dart';
import 'features/transaction/presentation/pages/receipt_scan_page.dart';
import 'features/transaction/presentation/pages/transaction_pages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
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
    bool? isDarkMode,
  }) : initialDarkMode = initialDarkMode ?? isDarkMode ?? false;

  final bool initialDarkMode;
  final AppDatabase? database;
  final bool? onboardingComplete;
  final bool? pinEnabled;

  @override
  State<FfmApp> createState() => _FfmAppState();
}

class _FfmAppState extends State<FfmApp> {
  late var _isDark = widget.initialDarkMode;

  @override
  void initState() {
    super.initState();
    if (widget.database != null && !getIt.isRegistered<AppDatabase>()) {
      configureDependencies(database: widget.database);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FFM',
    debugShowCheckedModeBanner: false,
    themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
    theme: _buildTheme(Brightness.light),
    darkTheme: _buildTheme(Brightness.dark),
    home: AppShell(
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

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.isDark,
    required this.onThemeChanged,
  });

  final bool isDark;
  final ValueChanged<bool> onThemeChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _widgetChannel = MethodChannel('ffm/widget');
  var _index = 0;
  var _assistantRequestId = 0;
  FfmAssistantDraft? _assistantTransactionDraft;

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
    switch (action) {
      case 'transaction':
        setState(() => _index = 1);
      case 'budget':
        setState(() => _index = 2);
      case 'activity':
        setState(() => _index = 4);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ActivityPage()));
          }
        });
      case 'scan':
        setState(() => _index = 1);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ReceiptScanPage()));
          }
        });
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
    ),
    const EnvelopeBudgetPage(),
    const AnalysisPage(),
    const OtherMenuPage(),
  ];

  Future<void> _handleAssistantIntent(FfmAssistantIntent intent) async {
    final destination = intent.destination;
    if (destination == null) return;
    switch (destination) {
      case FfmAssistantDestination.summary:
        setState(() => _index = 0);
      case FfmAssistantDestination.transactions:
        if (intent.draft != null) {
          setState(() {
            _index = 1;
            _assistantTransactionDraft = intent.draft;
            _assistantRequestId++;
          });
        } else {
          setState(() => _index = 1);
        }
      case FfmAssistantDestination.budget:
        setState(() => _index = 2);
      case FfmAssistantDestination.analysis:
        setState(() => _index = 3);
      case FfmAssistantDestination.otherMenu:
        setState(() => _index = 4);
      case FfmAssistantDestination.masterData:
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const MasterDataPage()));
      case FfmAssistantDestination.assets:
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const AssetListPage()));
      case FfmAssistantDestination.goals:
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const GoalListPage()));
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
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const ActivityPage()));
      case FfmAssistantDestination.reminders:
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const ReminderPage()));
      case FfmAssistantDestination.backup:
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const BackupPage()));
      case FfmAssistantDestination.monthlyReport:
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const MonthlyReportPage()));
      case FfmAssistantDestination.reconciliation:
        setState(() => _index = 4);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _index, children: _pages),
    floatingActionButton: FloatingActionButton.extended(
      heroTag: 'ffm-assistant',
      tooltip: 'Buka Asisten FFM',
      onPressed: () =>
          showFfmAssistantSheet(context, onIntent: _handleAssistantIntent),
      icon: const Icon(Icons.auto_awesome_outlined),
      label: const Text('Asisten'),
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
          icon: Icon(Icons.track_changes_outlined),
          selectedIcon: Icon(Icons.track_changes),
          label: 'Anggaran',
        ),
        NavigationDestination(
          icon: Icon(Icons.insights_outlined),
          selectedIcon: Icon(Icons.insights),
          label: 'Analisa',
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
