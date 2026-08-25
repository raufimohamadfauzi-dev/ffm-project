import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/goal/domain/entities/goal_entity.dart';
import 'package:ffm_manager/features/goal/presentation/pages/goal_pages.dart';
import 'package:ffm_manager/features/hijri/domain/hijri_calendar_service.dart';

void main() {
  late AppDatabase database;
  final goal = GoalEntity(
    id: 'goal-darurat',
    householdId: 'household-test',
    name: 'Dana Darurat',
    targetAmount: 10000000,
    currentAmount: 3500000,
    targetDate: DateTime(2027, 1, 31),
    createdAt: DateTime(2026, 8, 1, 8),
  );

  setUp(() {
    database = createInMemoryDatabaseForTests();
    getIt.registerSingleton<HijriCalendarService>(
      HijriCalendarService(database),
    );
  });

  tearDown(() async {
    await getIt.reset();
    await database.close();
  });

  testWidgets(
    'Detail Target menampilkan progres tanpa mengubah saldo langsung',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: GoalDetailPage(goal: goal)));

      expect(find.text('Detail target'), findsOneWidget);
      expect(find.text('Dana Darurat'), findsOneWidget);
      expect(find.text('Progres berasal dari transaksi'), findsOneWidget);
      expect(find.text('35% tercapai'), findsOneWidget);
      expect(find.text('Target 10.000.000'), findsOneWidget);
      expect(find.text('Sisa 6.500.000'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Arsipkan target'), 200);
      expect(find.text('Ubah target'), findsOneWidget);
      expect(find.text('Arsipkan target'), findsOneWidget);
    },
  );

  testWidgets('Edit Target menolak batas di bawah dana yang sudah terkumpul', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: GoalEditPage(goal: goal)));

    expect(find.text('Saldo target tetap terlindungi'), findsOneWidget);
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));

    await tester.enterText(fields.at(1), '3000000');
    await tester.tap(find.text('Simpan perubahan'));
    await tester.pump();

    expect(
      find.text('Tidak boleh kurang dari dana terkumpul.'),
      findsOneWidget,
    );
  });
}
