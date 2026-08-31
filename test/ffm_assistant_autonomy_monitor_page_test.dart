import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_repository.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_autonomy_policy.dart';
import 'package:ffm_manager/features/assistant/presentation/pages/ffm_assistant_autonomy_monitor_page.dart';

void main() {
  testWidgets('monitor menampilkan run terbaru secara read-only', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = FfmAssistantAutonomyRepository(database);
    await repository.recordPlan(
      FfmAssistantActionPlan(
        id: 'monitor-run',
        summary: 'Run monitoring',
        createdAt: DateTime(2026, 9, 1),
        status: FfmAssistantActionPlanStatus.completed,
        steps: const [],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FfmAssistantAutonomyMonitorPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Monitoring Agent'), findsOneWidget);
    expect(find.text('Kebijakan Autonomy'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pump();
    expect(find.text('Run monitoring'), findsOneWidget);
    expect(find.textContaining('completed'), findsOneWidget);
  });

  testWidgets('monitor dapat menyimpan policy autonomy default yang aman', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = FfmAssistantAutonomyRepository(database);

    await tester.pumpWidget(
      MaterialApp(
        home: FfmAssistantAutonomyMonitorPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan kebijakan'));
    await tester.pumpAndSettle();

    expect(find.text('Kebijakan autonomy tersimpan.'), findsOneWidget);
    expect(
      (await repository.loadPolicy())?.level,
      FfmAssistantAutonomyLevel.explicitApproval,
    );
  });
}
