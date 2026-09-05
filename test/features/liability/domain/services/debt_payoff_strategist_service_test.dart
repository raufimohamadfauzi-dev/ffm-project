import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/liability/domain/services/debt_payoff_strategist_service.dart';

void main() {
  group('DebtPayoffStrategistService', () {
    late AppDatabase db;
    late DebtPayoffStrategistService service;
    const householdId = 'test-household-debt';

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      service = DebtPayoffStrategistService(db);

      await db.into(db.households).insert(
        HouseholdsCompanion.insert(
          id: householdId,
          name: 'Keluarga Mandiri',
          createdAt: DateTime.now(),
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('getAdaptiveLiabilities resolves explicit input when monthlyInstallment > 0', () async {
      await db.into(db.liabilities).insert(
        LiabilitiesCompanion.insert(
          id: 'debt-explicit',
          householdId: householdId,
          name: 'Cicilan Motor',
          originalAmount: 15000000,
          remainingBalance: 10000000,
          monthlyInstallment: const drift.Value(750000),
          interestRate: const drift.Value(6.0),
          startDate: DateTime(2025, 1, 1),
          dueDate: drift.Value(DateTime(2026, 6, 1)),
          createdAt: DateTime.now(),
        ),
      );

      final result = await service.getAdaptiveLiabilities(householdId);
      expect(result.length, 1);
      final debt = result.first;
      expect(debt.id, 'debt-explicit');
      expect(debt.monthlyInstallment, 750000);
      expect(debt.isExplicitInstallment, isTrue);
      expect(debt.installmentOrigin, AdaptiveInstallmentOrigin.explicitInput);
    });

    test('getAdaptiveLiabilities resolves historical payment average when monthlyInstallment == 0', () async {
      await db.into(db.liabilities).insert(
        LiabilitiesCompanion.insert(
          id: 'debt-history',
          householdId: householdId,
          name: 'Pinjaman Kerabat',
          originalAmount: 5000000,
          remainingBalance: 3000000,
          monthlyInstallment: const drift.Value(0),
          startDate: DateTime(2025, 1, 1),
          createdAt: DateTime.now(),
        ),
      );

      // Seed 2 historical payments
      await db.into(db.transactions).insert(
        TransactionsCompanion.insert(
          id: 'tx-pay-1',
          householdId: householdId,
          type: 'expense',
          source: const drift.Value('liability_payment'),
          sourceId: const drift.Value('debt-history'),
          amount: -500000,
          date: DateTime(2025, 2, 1),
          recordedAt: DateTime.now(),
          createdAt: DateTime.now(),
        ),
      );
      await db.into(db.transactions).insert(
        TransactionsCompanion.insert(
          id: 'tx-pay-2',
          householdId: householdId,
          type: 'expense',
          source: const drift.Value('liability_payment'),
          sourceId: const drift.Value('debt-history'),
          amount: -300000,
          date: DateTime(2025, 3, 1),
          recordedAt: DateTime.now(),
          createdAt: DateTime.now(),
        ),
      );

      final result = await service.getAdaptiveLiabilities(householdId);
      expect(result.length, 1);
      final debt = result.first;
      expect(debt.id, 'debt-history');
      // Rata-rata dari 500rb dan 300rb = 400rb
      expect(debt.monthlyInstallment, 400000);
      expect(debt.isExplicitInstallment, isFalse);
      expect(debt.installmentOrigin, AdaptiveInstallmentOrigin.historicalPaymentAverage);
    });

    test('getAdaptiveLiabilities resolves dueDate amortization when no history exists', () async {
      final now = DateTime(2026, 1, 1);
      final due = DateTime(2026, 6, 1); // ~5 bulan ke depan

      await db.into(db.liabilities).insert(
        LiabilitiesCompanion.insert(
          id: 'debt-due',
          householdId: householdId,
          name: 'Hutang Pupuk',
          originalAmount: 2500000,
          remainingBalance: 2500000,
          monthlyInstallment: const drift.Value(0),
          startDate: now,
          dueDate: drift.Value(due),
          createdAt: now,
        ),
      );

      final result = await service.getAdaptiveLiabilities(householdId, now: now);
      expect(result.length, 1);
      final debt = result.first;
      expect(debt.id, 'debt-due');
      expect(debt.isExplicitInstallment, isFalse);
      expect(debt.installmentOrigin, AdaptiveInstallmentOrigin.dueDateAmortization);
      expect(debt.monthlyInstallment, greaterThan(0));
    });

    test('simulate Snowball vs Avalanche prioritizes debts correctly and rolls over payments', () {
      final now = DateTime(2026, 1, 1);
      final debts = [
        AdaptiveLiability(
          id: 'debt-small',
          householdId: householdId,
          name: 'Hutang Warung (Saldo Kecil, Bunga Rendah)',
          originalAmount: 1000000,
          remainingBalance: 800000,
          monthlyInstallment: 50000,
          interestRate: 2.0,
          startDate: now,
          dueDate: now.add(const Duration(days: 360)),
          isExplicitInstallment: true,
          installmentOrigin: AdaptiveInstallmentOrigin.explicitInput,
        ),
        AdaptiveLiability(
          id: 'debt-high-interest',
          householdId: householdId,
          name: 'Pinjaman Online (Saldo Sedang, Bunga Tinggi)',
          originalAmount: 2000000,
          remainingBalance: 1000000,
          monthlyInstallment: 50000,
          interestRate: 24.0,
          startDate: now,
          dueDate: now.add(const Duration(days: 360)),
          isExplicitInstallment: true,
          installmentOrigin: AdaptiveInstallmentOrigin.explicitInput,
        ),
      ];

      // Simulasi Snowball: Hutang kecil harus lunas terlebih dahulu
      final snowballResult = service.simulate(
        liabilities: debts,
        strategy: DebtPayoffStrategy.snowball,
        extraMonthlyPayment: 250000,
        startDate: now,
      );

      expect(snowballResult.milestones.isNotEmpty, isTrue);
      expect(snowballResult.milestones.first.debtId, 'debt-small');

      // Simulasi Avalanche: Hutang berbunga tinggi harus lunas terlebih dahulu
      final avalancheResult = service.simulate(
        liabilities: debts,
        strategy: DebtPayoffStrategy.avalanche,
        extraMonthlyPayment: 250000,
        startDate: now,
      );

      expect(avalancheResult.milestones.isNotEmpty, isTrue);
      expect(avalancheResult.milestones.first.debtId, 'debt-high-interest');

      // Avalanche harus menghemat total bunga dibanding Snowball pada skenario hutang berbunga tinggi
      expect(avalancheResult.totalInterestPaid, lessThan(snowballResult.totalInterestPaid));
    });

    test('compareStrategies computes savings and recommendation text properly', () {
      final now = DateTime(2026, 1, 1);
      final debts = [
        AdaptiveLiability(
          id: 'debt-1',
          householdId: householdId,
          name: 'Kartu Kredit',
          originalAmount: 4000000,
          remainingBalance: 2000000,
          monthlyInstallment: 200000,
          interestRate: 24.0,
          startDate: now,
          dueDate: now.add(const Duration(days: 365)),
          isExplicitInstallment: true,
          installmentOrigin: AdaptiveInstallmentOrigin.explicitInput,
        ),
      ];

      final comp = service.compareStrategies(
        liabilities: debts,
        extraMonthlyPayment: 300000,
        startDate: now,
      );

      expect(comp.monthsSavedAvalanche, greaterThanOrEqualTo(0));
      expect(comp.interestSavedAvalanche, greaterThanOrEqualTo(0));
      expect(comp.recommendationText, contains('Kartu Kredit'));
      expect(comp.recommendationText, contains('Rp 300.000'));
    });
  });
}
