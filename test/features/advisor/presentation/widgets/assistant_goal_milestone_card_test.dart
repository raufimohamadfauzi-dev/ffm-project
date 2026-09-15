import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/advisor/presentation/pages/summary_page.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_goal_evidence_evaluator.dart';

void main() {
  group('AssistantGoalMilestoneCard Widget Tests', () {
    testWidgets('renders milestone card when goal is ahead of schedule', (
      tester,
    ) async {
      var tapped = false;
      final report = FfmAssistantGoalEvidenceReport(
        goalId: 'goal-1',
        goalName: 'Dana Liburan',
        targetAmount: 10000000,
        currentAmount: 8500000,
        remainingAmount: 1500000,
        progressPercent: 85.0,
        status: FfmAssistantGoalProgressStatus.aheadOfSchedule,
        isAchievableWithCurrentCashflow: true,
        recommendation: 'Target diproyeksikan tercapai 2 bulan lebih cepat berdasarkan surplus Anda.',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssistantGoalMilestoneCard(
              milestones: [report],
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('LEBIH CEPAT DARI TARGET'), findsOneWidget);
      expect(find.text('Dana Liburan'), findsOneWidget);
      expect(find.text('85.0%'), findsOneWidget);
      expect(find.textContaining('8.500.000'), findsOneWidget);
      expect(find.textContaining('10.000.000'), findsOneWidget);
      expect(find.textContaining('lebih cepat'), findsOneWidget);

      await tester.tap(find.text('Buka Target'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('renders target tercapai when status is targetReached', (
      tester,
    ) async {
      final report = FfmAssistantGoalEvidenceReport(
        goalId: 'goal-2',
        goalName: 'Laptop Baru',
        targetAmount: 15000000,
        currentAmount: 15000000,
        remainingAmount: 0,
        progressPercent: 100.0,
        status: FfmAssistantGoalProgressStatus.targetReached,
        isAchievableWithCurrentCashflow: true,
        recommendation: 'Selamat! Target tabungan ini sudah tercapai 100%.',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssistantGoalMilestoneCard(
              milestones: [report],
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('TARGET TERCAPAI!'), findsOneWidget);
      expect(find.text('100.0%'), findsOneWidget);
      expect(find.text('Laptop Baru'), findsOneWidget);
    });
  });
}
