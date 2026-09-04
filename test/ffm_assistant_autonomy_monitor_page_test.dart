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
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

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
    expect(find.text('Batas kerja Agent'), findsOneWidget);
    await tester.ensureVisible(find.text('Run monitoring'));
    await tester.pumpAndSettle();
    expect(find.text('Run monitoring'), findsOneWidget);
    expect(find.textContaining('completed'), findsOneWidget);
  });

  testWidgets('monitor menerapkan batas Agent yang dipilih', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = FfmAssistantAutonomyRepository(database);

    await tester.pumpWidget(
      MaterialApp(
        home: FfmAssistantAutonomyMonitorPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Batas tersimpan'), findsOneWidget);
    await tester.ensureVisible(
      find.byType(DropdownButtonFormField<FfmAssistantAutonomyLevel>),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(DropdownButtonFormField<FfmAssistantAutonomyLevel>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Siapkan draft untuk dicek').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Terapkan batas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terapkan batas'));
    await tester.pumpAndSettle();

    expect(find.text('Batas kerja Agent diterapkan.'), findsOneWidget);
    expect(
      (await repository.loadPolicy())?.level,
      FfmAssistantAutonomyLevel.createDraft,
    );
  });
}
