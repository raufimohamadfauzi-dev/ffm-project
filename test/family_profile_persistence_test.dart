import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/database_seed.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/settings/presentation/pages/family_profile_page.dart';

void main() {
  testWidgets('nama keluarga bertahan setelah simpan, seed, dan buka ulang', (
    tester,
  ) async {
    final database = createInMemoryDatabaseForTests();
    await configureDependencies(database: database);
    addTearDown(() async {
      await database.close();
      await getIt.reset();
    });
    await DatabaseSeed.ensure(database);
    await tester.pumpWidget(const MaterialApp(home: FamilyProfilePage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Keluarga Fauzi');
    final save = find.text('Simpan profil keluarga');
    await tester.scrollUntilVisible(
      save,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
      find.text('Profil keluarga dan data pribadi tersimpan.'),
      findsOneWidget,
    );

    final saved = await (database.select(
      database.households,
    )..where((row) => row.id.equals(AppContext.householdId))).getSingle();
    expect(saved.name, 'Keluarga Fauzi');
    await tester.pumpWidget(const SizedBox.shrink());
    await DatabaseSeed.ensure(database);
    await DatabaseSeed.ensure(database);
    final reseeded = await (database.select(
      database.households,
    )..where((row) => row.id.equals(AppContext.householdId))).getSingle();
    expect(reseeded.name, saved.name);
    expect(reseeded.createdAt, saved.createdAt);
    expect(reseeded.updatedAt, saved.updatedAt);

    await tester.pumpWidget(const MaterialApp(home: FamilyProfilePage()));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'Keluarga Fauzi');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
