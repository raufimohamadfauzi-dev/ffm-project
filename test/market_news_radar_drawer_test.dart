import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/asset/data/repositories/market_news_cache_repository.dart';
import 'package:ffm_manager/features/asset/data/services/market_news_radar_service.dart';
import 'package:ffm_manager/features/asset/presentation/widgets/market_news_radar_drawer.dart';

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
  });

  tearDown(() async {
    await db.close();
    await getIt.reset();
  });

  testWidgets('MarketNewsRadarDrawer opens and renders radar title and mini price chips', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final scaffoldKey = GlobalKey<ScaffoldState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: scaffoldKey,
          drawer: const MarketNewsRadarDrawer(),
          body: const Center(child: Text('Home Screen')),
        ),
      ),
    );

    // Open drawer
    scaffoldKey.currentState?.openDrawer();
    await tester.pumpAndSettle();

    // Verify Drawer Header Title
    expect(find.text('Radar Warta & Pasar'), findsOneWidget);
    expect(find.text('Pantauan Cepat Terkini'), findsOneWidget);

    // Verify Mini Price Bar
    expect(find.text('Emas 24K: '), findsOneWidget);
    expect(find.text('USD: '), findsOneWidget);
    expect(find.text('SGD: '), findsOneWidget);
    expect(find.text('SAR: '), findsOneWidget);
    expect(find.text('BTC: '), findsOneWidget);

    // Verify category chips
    expect(find.text('Semua'), findsOneWidget);
    expect(find.text('🌾 Tani'), findsOneWidget);
    expect(find.text('🌧️ Cuaca'), findsOneWidget);
    expect(find.text('📈 Finansial'), findsOneWidget);
  });
}
