import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/services/transaction_pattern_miner.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/ffm_habit_suggestion_card.dart';

void main() {
  const pattern = MinedTransactionPattern(
    id: 'pat_test_1',
    title: 'Kopi Kenangan',
    merchant: 'Kopi Kenangan',
    amount: 25000,
    dayOfWeek: DateTime.saturday,
    occurrenceCount: 4,
    confidence: 0.9,
    isDueToday: true,
  );

  Widget createWidget({
    VoidCallback? onAccept,
    VoidCallback? onSnooze,
    VoidCallback? onDismiss,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: FfmHabitSuggestionCard(
          pattern: pattern,
          onAccept: onAccept ?? () {},
          onSnooze: onSnooze ?? () {},
          onDismiss: onDismiss ?? () {},
        ),
      ),
    );
  }

  group('FfmHabitSuggestionCard', () {
    testWidgets('renders title, prompt message, and buttons properly', (tester) async {
      await tester.pumpWidget(createWidget());

      expect(find.text('Saran Rutin Hari Ini'), findsOneWidget);
      expect(find.text('Terdeteksi dari kebiasaan Anda'), findsOneWidget);
      expect(find.textContaining('Kopi Kenangan'), findsWidgets);
      expect(find.textContaining('Rp 25.000'), findsOneWidget);

      expect(find.text('Catat Sekarang'), findsOneWidget);
      expect(find.text('Lewati Minggu Ini'), findsOneWidget);
      expect(find.text('Matikan Saran'), findsOneWidget);
    });

    testWidgets('triggers onAccept when Catat Sekarang tapped', (tester) async {
      var accepted = false;
      await tester.pumpWidget(createWidget(onAccept: () => accepted = true));

      await tester.tap(find.text('Catat Sekarang'));
      await tester.pump();

      expect(accepted, isTrue);
    });

    testWidgets('triggers onSnooze when Lewati Minggu Ini tapped', (tester) async {
      var snoozed = false;
      await tester.pumpWidget(createWidget(onSnooze: () => snoozed = true));

      await tester.tap(find.text('Lewati Minggu Ini'));
      await tester.pump();

      expect(snoozed, isTrue);
    });

    testWidgets('triggers onDismiss when Matikan Saran confirmed', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(createWidget(onDismiss: () => dismissed = true));

      await tester.tap(find.text('Matikan Saran'));
      await tester.pumpAndSettle();

      expect(find.text('Matikan Saran Rutin Ini?'), findsOneWidget);
      await tester.tap(find.text('Matikan'));
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
    });
  });
}
