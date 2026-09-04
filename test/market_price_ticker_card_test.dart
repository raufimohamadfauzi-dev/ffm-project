import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/asset/data/repositories/market_news_cache_repository.dart';
import 'package:ffm_manager/features/asset/data/services/market_news_radar_service.dart';
import 'package:ffm_manager/features/asset/domain/usecases/asset_auto_valuation_service.dart';
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

  testWidgets('MarketPriceTickerCard renders header and price chips', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarketPriceTickerCard(),
          ),
        ),
      ),
    );

    // Initial pump
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Title
    expect(find.text('Radar Pasar & Valuasi Terkini'), findsOneWidget);

    // Verify presence of buttons / chips
    expect(find.text('Warta & Radar'), findsOneWidget);
    expect(find.byIcon(Icons.radar_outlined), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });
}
