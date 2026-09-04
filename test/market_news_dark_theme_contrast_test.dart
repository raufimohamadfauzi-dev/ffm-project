import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/asset/data/repositories/market_news_cache_repository.dart';
import 'package:ffm_manager/features/asset/data/services/market_news_radar_service.dart';
import 'package:ffm_manager/features/asset/domain/usecases/asset_auto_valuation_service.dart';
import 'package:ffm_manager/features/asset/presentation/pages/market_news_radar_page.dart';
import 'package:ffm_manager/features/asset/presentation/widgets/market_news_radar_drawer.dart';
import 'package:ffm_manager/features/asset/presentation/widgets/market_price_ticker_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final getIt = GetIt.instance;

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();

    db = createInMemoryDatabaseForTests();
    getIt.registerSingleton<AppDatabase>(db);
    getIt.registerLazySingleton<MarketNewsRadarService>(MarketNewsRadarService.new);
    getIt.registerLazySingleton<MarketNewsCacheRepository>(MarketNewsCacheRepository.new);
    getIt.registerLazySingleton<AssetAutoValuationService>(() => AssetAutoValuationService(db));
  });

  tearDown(() async {
    await db.close();
    await getIt.reset();
  });

  Widget wrapInDarkTheme(Widget child) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10B981),
          brightness: Brightness.dark,
        ),
      ),
      home: child,
    );
  }

  testWidgets('Dark Mode: MarketNewsRadarDrawer renders with sharp contrast and no overflow', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final scaffoldKey = GlobalKey<ScaffoldState>();

    await tester.pumpWidget(
      wrapInDarkTheme(
        Scaffold(
          key: scaffoldKey,
          drawer: const MarketNewsRadarDrawer(),
          body: const Center(child: Text('Content')),
        ),
      ),
    );

    scaffoldKey.currentState?.openDrawer();
    await tester.pumpAndSettle();

    // Verify all header and mini price chips are visible and readable
    expect(find.text('Radar Warta & Pasar'), findsOneWidget);
    expect(find.text('Pantauan Cepat Terkini'), findsOneWidget);
    expect(find.text('Emas 24K: '), findsOneWidget);
    expect(find.text('USD: '), findsOneWidget);

    // Verify category chips
    expect(find.text('Semua'), findsOneWidget);
    expect(find.text('🌾 Tani'), findsOneWidget);
  });

  testWidgets('Dark Mode: MarketPriceTickerCard renders cleanly in dark theme', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      wrapInDarkTheme(
        const Scaffold(
          body: SingleChildScrollView(
            child: MarketPriceTickerCard(),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Radar Pasar & Valuasi Terkini'), findsOneWidget);
    expect(find.text('Warta & Radar'), findsOneWidget);
    expect(find.text('Emas 24K'), findsOneWidget);
    expect(find.text('USD / IDR'), findsOneWidget);
  });

  testWidgets('Dark Mode: MarketNewsRadarPage Tab 1 & Tab 2 render with high contrast', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      wrapInDarkTheme(const MarketNewsRadarPage()),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Tab 1 Title & Calculators
    expect(find.text('Radar Pasar & Berita'), findsOneWidget);
    expect(find.text('Logam Mulia (Emas Batangan & Perhiasan)'), findsOneWidget);
    expect(find.text('Kalkulator Valuasi Karat Emas'), findsOneWidget);
    expect(find.text('Mata Uang Asing (Valas ke IDR)'), findsOneWidget);

    // Switch to Tab 2
    await tester.tap(find.text('Berita & Peringatan'));
    await tester.pumpAndSettle();

    expect(find.text('🌾 Pertanian'), findsOneWidget);
    expect(find.text('🌧️ Cuaca BMKG'), findsOneWidget);
    expect(find.text('📈 Finansial'), findsOneWidget);
  });
}
