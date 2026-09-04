import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/advisor/domain/entities/cash_flow_profile_models.dart';
import 'package:ffm_manager/features/advisor/domain/usecases/flexible_cash_flow_calculator.dart';

void main() {
  group('FlexibleCashFlowCalculator Tests', () {
    const calculator = FlexibleCashFlowCalculator();

    test('calculates safe runway when cash exceeds harvest date', () {
      // Kas 20 juta, Dapur 100rb/hari, Kebun 50rb/hari (Total 150rb/hari) => Runway ~133 hari
      // Sisa hari panen 90 hari => status SAFE
      final result = calculator.calculateRunway(
        effectiveLiquidCash: 20000000,
        dailyLivingBudget: 100000,
        dailyOperationalBudget: 50000,
        daysRemainingToHarvest: 90,
      );

      expect(result.runwayDays, equals(133));
      expect(result.healthStatus, equals(CycleHealthStatus.safe));
      expect(result.deficitDays, equals(0));
      expect(result.safeToSpendDaily, greaterThan(0));
      // Operational 50rb x 90 = 4.5jt. Kas sisa 15.5jt / 90 hari = ~172rb/hari
      expect(result.safeToSpendDaily, equals(172222));
    });

    test('calculates warning status when runway is within 14 days deficit', () {
      // Kas 12 juta, total burn 150rb/hari => Runway 80 hari
      // Sisa hari panen 90 hari => Defisit 10 hari (masuk zona warning 14 hari)
      final result = calculator.calculateRunway(
        effectiveLiquidCash: 12000000,
        dailyLivingBudget: 100000,
        dailyOperationalBudget: 50000,
        daysRemainingToHarvest: 90,
      );

      expect(result.runwayDays, equals(80));
      expect(result.healthStatus, equals(CycleHealthStatus.warning));
      expect(result.deficitDays, equals(10));
      expect(result.message, contains('Waspada'));
    });

    test('calculates critical status when deficit exceeds 14 days', () {
      // Kas 6 juta, total burn 150rb/hari => Runway 40 hari
      // Sisa hari panen 90 hari => Defisit 50 hari
      final result = calculator.calculateRunway(
        effectiveLiquidCash: 6000000,
        dailyLivingBudget: 100000,
        dailyOperationalBudget: 50000,
        daysRemainingToHarvest: 90,
      );

      expect(result.runwayDays, equals(40));
      expect(result.healthStatus, equals(CycleHealthStatus.critical));
      expect(result.deficitDays, equals(50));
      expect(result.message, contains('Kritis'));
    });

    test('handles zero or negative cash gracefully', () {
      final result = calculator.calculateRunway(
        effectiveLiquidCash: 0,
        dailyLivingBudget: 100000,
        dailyOperationalBudget: 50000,
        daysRemainingToHarvest: 30,
      );

      expect(result.runwayDays, equals(0));
      expect(result.healthStatus, equals(CycleHealthStatus.critical));
      expect(result.safeToSpendDaily, equals(0));
    });

    test('handles zero burn rate gracefully', () {
      final result = calculator.calculateRunway(
        effectiveLiquidCash: 10000000,
        dailyLivingBudget: 0,
        dailyOperationalBudget: 0,
        daysRemainingToHarvest: 30,
      );

      expect(result.runwayDays, equals(999));
      expect(result.healthStatus, equals(CycleHealthStatus.safe));
    });

    test('simulates harvest allocation accurately', () {
      // Hasil panen Rp 50.000.000:
      // 45% modal berikutnya = 22.5jt
      // 15% dana darurat = 7.5jt
      // 40% laba bersih keluarga = 20jt
      final alloc = calculator.simulateHarvestAllocation(
        actualHarvestRevenue: 50000000,
      );

      expect(alloc['nextCycleCapital'], equals(22500000));
      expect(alloc['emergencyFund'], equals(7500000));
      expect(alloc['familyProfit'], equals(20000000));
    });
  });
}
