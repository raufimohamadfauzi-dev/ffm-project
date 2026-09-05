import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/liability/domain/services/debt_payoff_strategist_service.dart';
import 'package:ffm_manager/features/liability/presentation/pages/debt_payoff_strategy_page.dart';

void main() {
  group('DebtPayoffStrategyPage Widget Tests', () {
    late AppDatabase db;
    final householdId = AppContext.householdId;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());

      if (getIt.isRegistered<DebtPayoffStrategistService>()) {
        getIt.unregister<DebtPayoffStrategistService>();
      }
      getIt.registerSingleton<DebtPayoffStrategistService>(
        DebtPayoffStrategistService(db),
      );
    });

    tearDown(() async {
      if (getIt.isRegistered<DebtPayoffStrategistService>()) {
        getIt.unregister<DebtPayoffStrategistService>();
      }
      await db.close();
    });

    testWidgets('renders empty state when no debts exist', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DebtPayoffStrategyPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bebas Hutang! 🎉'), findsOneWidget);
      expect(find.textContaining('tidak memiliki catatan hutang aktif'), findsOneWidget);
    });

    testWidgets('renders simulation cards, strategy toggle, and priority list when debts exist', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await db.into(db.liabilities).insert(
        LiabilitiesCompanion.insert(
          id: 'debt-motor',
          householdId: householdId,
          name: 'Cicilan Motor Honda',
          originalAmount: 12000000,
          remainingBalance: 4000000,
          monthlyInstallment: const drift.Value(500000),
          interestRate: const drift.Value(8.0),
          startDate: DateTime(2025, 1, 1),
          dueDate: drift.Value(DateTime(2026, 12, 1)),
          createdAt: DateTime.now(),
        ),
      );
      await db.into(db.liabilities).insert(
        LiabilitiesCompanion.insert(
          id: 'debt-pinjol',
          householdId: householdId,
          name: 'Pinjaman Koperasi',
          originalAmount: 3000000,
          remainingBalance: 1500000,
          monthlyInstallment: const drift.Value(300000),
          interestRate: const drift.Value(14.0),
          startDate: DateTime(2025, 1, 1),
          dueDate: drift.Value(DateTime(2026, 8, 1)),
          createdAt: DateTime.now(),
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: DebtPayoffStrategyPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Simulator Bebas Hutang'), findsOneWidget);
      expect(find.text('Debt Snowball'), findsOneWidget);
      expect(find.text('Debt Avalanche'), findsOneWidget);
      expect(find.text('Estimasi 100% Bebas Hutang'), findsOneWidget);
      expect(find.text('Urutan Prioritas Pelunasan'), findsOneWidget);
      expect(find.text('Cicilan Motor Honda'), findsOneWidget);
      expect(find.text('Pinjaman Koperasi'), findsOneWidget);

      // Tap Avalanche tab
      await tester.tap(find.text('Debt Avalanche'));
      await tester.pumpAndSettle();

      // Tap extra chip +500 rb
      await tester.tap(find.text('+500 rb'));
      await tester.pumpAndSettle();
    });
  });
}
