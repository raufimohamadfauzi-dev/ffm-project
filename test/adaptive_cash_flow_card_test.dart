import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/advisor/data/cash_flow_profile_repository.dart';
import 'package:ffm_manager/features/advisor/domain/entities/cash_flow_profile_models.dart';
import 'package:ffm_manager/features/advisor/domain/usecases/flexible_cash_flow_calculator.dart';
import 'package:ffm_manager/features/advisor/presentation/widgets/adaptive_cash_flow_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdaptiveCashFlowCard Widget Tests', () {
    late CashFlowProfileRepository repo;
    late FlexibleCashFlowCalculator calculator;
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase(NativeDatabase.memory());

      if (getIt.isRegistered<AppDatabase>()) {
        getIt.unregister<AppDatabase>();
      }
      getIt.registerSingleton<AppDatabase>(db);

      if (getIt.isRegistered<CashFlowProfileRepository>()) {
        getIt.unregister<CashFlowProfileRepository>();
      }
      repo = CashFlowProfileRepository();
      getIt.registerSingleton<CashFlowProfileRepository>(repo);

      if (getIt.isRegistered<FlexibleCashFlowCalculator>()) {
        getIt.unregister<FlexibleCashFlowCalculator>();
      }
      calculator = const FlexibleCashFlowCalculator();
      getIt.registerSingleton<FlexibleCashFlowCalculator>(calculator);
    });

    tearDown(() async {
      await db.close();
      if (getIt.isRegistered<AppDatabase>()) {
        getIt.unregister<AppDatabase>();
      }
      if (getIt.isRegistered<CashFlowProfileRepository>()) {
        getIt.unregister<CashFlowProfileRepository>();
      }
      if (getIt.isRegistered<FlexibleCashFlowCalculator>()) {
        getIt.unregister<FlexibleCashFlowCalculator>();
      }
    });

    testWidgets('renders SizedBox.shrink when there is no active cycle',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveCashFlowCard(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Runway Kas'), findsNothing);
      expect(find.byType(AdaptiveCashFlowCard), findsOneWidget);
    });

    testWidgets('renders active agriculture cycle card with runway and safe-to-spend',
        (tester) async {
      // Seed 1 akun dengan saldo 20 juta
      await db.into(db.accounts).insert(
            AccountsCompanion.insert(
              id: 'acc_bri_1',
              householdId: AppContext.householdId,
              name: 'BRI Simpedes',
              type: 'bank',
              openingBalance: const Value(20000000),
              createdAt: DateTime.now(),
            ),
          );

      // Seed 1 active agricultural profile
      final profile = CashFlowProfile(
        id: 'cycle_padi_1',
        householdId: AppContext.householdId,
        profileType: CashFlowProfileType.agriculture,
        name: 'Kebun Padi Blok Timur MT-1',
        commodityOrBusinessType: 'Padi Ciherang',
        startDate: DateTime.now().subtract(const Duration(days: 30)),
        targetHarvestDate: DateTime.now().add(const Duration(days: 75)),
        initialCapital: 15000000,
        estimatedInflow: 45000000,
        dailyLivingBudget: 90000,
        dailyOperationalBudget: 40000,
        isActive: true,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'ffm_cash_flow_profiles_${AppContext.householdId}',
        jsonEncode([profile.toJson()]),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdaptiveCashFlowCard(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kebun Padi Blok Timur MT-1'), findsOneWidget);
      expect(find.text('Siklus Pertanian / Panen • Padi Ciherang'), findsOneWidget);
      expect(find.text('Runway Kas'), findsOneWidget);
      expect(find.text('Batas Aman Dapur'), findsOneWidget);
    });
  });
}
