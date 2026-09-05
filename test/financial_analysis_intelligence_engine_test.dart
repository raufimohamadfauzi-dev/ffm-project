import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/advisor/domain/entities/cash_flow_profile_models.dart';
import 'package:ffm_manager/features/advisor/domain/usecases/financial_analysis_intelligence_engine.dart';
import 'package:ffm_manager/features/transaction/domain/entities/transaction_entity.dart';

void main() {
  const engine = FinancialAnalysisIntelligenceEngine();

  TransactionWithItems createTx({
    required int amount,
    required DateTime date,
    String? note,
    String? categoryId = 'cat_1',
  }) {
    return TransactionWithItems(
      transaction: Transaction(
        id: 'tx_${date.millisecondsSinceEpoch}_$amount',
        householdId: 'h1',
        type: amount >= 0 ? 'income' : 'expense',
        amount: amount,
        date: date,
        recordedAt: date,
        note: note,
        categoryId: categoryId,
        isArchived: false,
        isDeleted: false,
        createdAt: date,
      ),
    );
  }

  group('FinancialAnalysisIntelligenceEngine - Burn Rate & Cashflow Projection', () {
    test('menghitung burn rate harian dan proyeksi akhir bulan secara deterministik', () {
      final now = DateTime(2026, 9, 10); // Hari ke-10 bulan September (30 hari total)
      final txs = [
        // Pemasukan 10 juta
        createTx(amount: 10000000, date: DateTime(2026, 9, 1), categoryId: 'gaji'),
        // Pengeluaran 3 juta selama 10 hari (rata-rata 300rb/hari)
        createTx(amount: -1500000, date: DateTime(2026, 9, 3), categoryId: 'makan'),
        createTx(amount: -1500000, date: DateTime(2026, 9, 8), categoryId: 'belanja'),
      ];

      final result = engine.calculateBurnRateAndProjection(
        transactions: txs,
        referenceDate: now,
      );

      expect(result.elapsedDays, 10);
      expect(result.daysLeftInMonth, 20); // 30 - 10 = 20 hari
      expect(result.currentMonthExpense, 3000000);
      expect(result.currentMonthIncome, 10000000);

      // Burn rate: 3jt / 10 hari = 300rb/hari
      expect(result.dailyBurnRate, 300000);

      // Proyeksi sisa pengeluaran: 300rb x 20 hari = 6jt. Total proyeksi = 3jt + 6jt = 9jt
      expect(result.projectedFinalExpense, 9000000);

      // Proyeksi arus kas: 10jt - 9jt = +1jt (Surplus)
      expect(result.projectedNetCashflow, 1000000);
      expect(result.isSurplus, isTrue);

      // Sisa anggaran: 10jt - 3jt = 7jt. Safe daily spend: 7jt / 20 hari = 350rb/hari
      expect(result.safeDailySpend, 350000);
    });

    test('mendeteksi potensi defisit jika pengeluaran harian melampaui pemasukan', () {
      final now = DateTime(2026, 9, 10);
      final txs = [
        createTx(amount: 5000000, date: DateTime(2026, 9, 1), categoryId: 'gaji'),
        // Pengeluaran 4 juta dalam 10 hari (400rb/hari)
        createTx(amount: -4000000, date: DateTime(2026, 9, 5), categoryId: 'belanja'),
      ];

      final result = engine.calculateBurnRateAndProjection(
        transactions: txs,
        referenceDate: now,
      );

      // Burn rate 400rb/hari x 20 hari sisa = 8jt. Total proyeksi = 4jt + 8jt = 12jt
      // Proyeksi net: 5jt - 12jt = -7jt (Defisit)
      expect(result.isSurplus, isFalse);
      expect(result.projectedNetCashflow, lessThan(0));
    });
  });

  group('FinancialAnalysisIntelligenceEngine - Micro-Expense Leak Detector', () {
    test('mendeteksi transaksi mikro berulang (<50rb dan >=3x frekuensi)', () {
      final now = DateTime(2026, 9, 15);
      final txs = [
        createTx(amount: 10000000, date: DateTime(2026, 9, 1)),
        // Kopi 25rb x 4 kali dalam sebulan
        createTx(amount: -25000, date: DateTime(2026, 9, 2), note: 'Kopi Kenangan'),
        createTx(amount: -25000, date: DateTime(2026, 9, 5), note: 'kopi kenangan'),
        createTx(amount: -25000, date: DateTime(2026, 9, 8), note: 'Kopi Kenangan '),
        createTx(amount: -25000, date: DateTime(2026, 9, 12), note: 'Kopi Kenangan'),
        // Transaksi besar 1 kali
        createTx(amount: -1500000, date: DateTime(2026, 9, 4), note: 'Sewa Rumah'),
        // Transaksi mikro 1 kali saja (tidak dianggap kebocoran berulang)
        createTx(amount: -15000, date: DateTime(2026, 9, 6), note: 'Parkir'),
      ];

      final categoryNames = {'cat_1': 'Makanan & Minuman'};

      final leaks = engine.detectMicroExpenseLeaks(
        transactions: txs,
        referenceDate: now,
        categoryNamesById: categoryNames,
        microThreshold: 50000,
        minFrequency: 3,
      );

      expect(leaks.length, 1);
      final leak = leaks.first;
      expect(leak.title.toLowerCase(), contains('kopi kenangan'));
      expect(leak.frequency, 4);
      expect(leak.totalAmount, 100000);
      expect(leak.averageAmount, 25000);
      expect(leak.impactOnSavingsRate, greaterThan(0));
    });
  });

  group('FinancialAnalysisIntelligenceEngine - Top Expense Categories (Pareto)', () {
    test('menghitung distribusi persentase kategori pengeluaran terbesar', () {
      final now = DateTime(2026, 9, 20);
      final txs = [
        createTx(amount: -5000000, date: DateTime(2026, 9, 2), categoryId: 'makanan'),
        createTx(amount: -3000000, date: DateTime(2026, 9, 5), categoryId: 'tani'),
        createTx(amount: -2000000, date: DateTime(2026, 9, 8), categoryId: 'transport'),
      ];

      final categoryNames = {
        'makanan': 'Makanan & Dapur',
        'tani': 'Operasional Kebun',
        'transport': 'Transportasi',
      };

      final shares = engine.calculateTopExpenseCategories(
        transactions: txs,
        referenceDate: now,
        categoryNamesById: categoryNames,
      );

      expect(shares.length, 3);
      // Total belanja: 10jt
      // Makanan: 5jt (50%)
      expect(shares[0].categoryName, 'Makanan & Dapur');
      expect(shares[0].percentage, closeTo(0.50, 0.01));
      // Tani: 3jt (30%)
      expect(shares[1].categoryName, 'Operasional Kebun');
      expect(shares[1].percentage, closeTo(0.30, 0.01));
      // Transport: 2jt (20%)
      expect(shares[2].categoryName, 'Transportasi');
      expect(shares[2].percentage, closeTo(0.20, 0.01));
    });
  });

  group('FinancialAnalysisIntelligenceEngine - AgroTrack Stress Test', () {
    test('menghitung ketahanan kas saat panen tertunda 14 hari', () {
      final profile = CashFlowProfile(
        id: 'cycle_1',
        householdId: 'h1',
        profileType: CashFlowProfileType.agriculture,
        name: 'Siklus Cabai Rawit Merah',
        commodityOrBusinessType: 'Cabai Rawit',
        initialCapital: 10000000,
        estimatedInflow: 35000000,
        dailyLivingBudget: 50000,
        dailyOperationalBudget: 50000,
        startDate: DateTime.now().subtract(const Duration(days: 30)),
        targetHarvestDate: DateTime.now().add(const Duration(days: 30)), // 30 hari lagi
      );

      // Kas likuid 5 juta, burn rate 100rb/hari (50rb dapur + 50rb operasional)
      // Runway: 5jt / 100rb = 50 hari
      // Panen asli: 30 hari. Jika mundur 14 hari => 44 hari (< 50 hari runway => Masih aman)
      final safeResult = engine.simulateCycleStressTest(
        profile: profile,
        currentLiquidCash: 5000000,
        delayedDays: 14,
      );

      expect(safeResult.isStillSafe, isTrue);
      expect(safeResult.delayedDays, 14);
      expect(safeResult.additionalLivingCost, 1400000); // 100rb x 14 = 1.4jt

      // Jika kas likuid hanya 3.5 juta (runway 35 hari < 44 hari => Defisit)
      final deficitResult = engine.simulateCycleStressTest(
        profile: profile,
        currentLiquidCash: 3500000,
        delayedDays: 14,
      );

      expect(deficitResult.isStillSafe, isFalse);
      expect(deficitResult.message, contains('Waspada'));
    });
  });
}
