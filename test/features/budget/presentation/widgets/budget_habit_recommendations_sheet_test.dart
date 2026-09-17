import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/budget/data/budget_habit_analyzer.dart';
import 'package:ffm_manager/features/budget/presentation/widgets/budget_habit_recommendations_sheet.dart';

void main() {
  Widget host(Future<BudgetHabitAnalysis> Function() loader) => MaterialApp(
    home: Scaffold(body: BudgetHabitRecommendationsSheet(loadAnalysis: loader)),
  );

  testWidgets('shows a read-only deterministic recommendation', (tester) async {
    await tester.pumpWidget(
      host(
        () async => BudgetHabitAnalysis(
          householdId: 'home',
          asOf: DateTime(2026, 6, 15),
          historicalPeriodCount: 3,
          recommendations: [
            BudgetHabitRecommendation(
              categoryId: 'food',
              categoryName: 'Makan',
              historicalPeriodCount: 3,
              sampleCount: 2,
              monthlyTotals: const [100000, 0, 150000],
              medianMonthlySpend: 100000,
              trend: BudgetHabitTrend.increasing,
              recommendedMonthlyAmount: 100000,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Makan'), findsOneWidget);
    expect(find.text('Sampel: 2 dari 3 bulan terakhir'), findsOneWidget);
    expect(find.text('Median pengeluaran'), findsOneWidget);
    expect(find.text('Tren: Meningkat'), findsOneWidget);
    expect(find.text('Rekomendasi bulanan'), findsOneWidget);
    expect(find.text('Rp100.000'), findsNWidgets(2));
    expect(
      find.text(
        'Bersifat baca saja. Tidak ada anggaran atau data yang disimpan dari layar ini.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows insufficient data and supports retry after an error', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      host(() async {
        attempts++;
        if (attempts == 1) throw Exception('offline');
        return BudgetHabitAnalysis(
          householdId: 'home',
          asOf: DateTime(2026, 6, 15),
          historicalPeriodCount: 3,
          recommendations: const [],
        );
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rekomendasi belum dapat dimuat'), findsOneWidget);
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(find.text('Data belum cukup'), findsOneWidget);
    expect(
      find.textContaining('setidaknya 2 bulan dari 3 bulan terakhir'),
      findsOneWidget,
    );
  });
}
