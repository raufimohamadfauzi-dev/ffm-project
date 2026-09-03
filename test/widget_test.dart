import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/database_factory.dart';
import 'package:ffm_manager/core/database/database_seed.dart';
import 'package:ffm_manager/main.dart';

void main() {
  testWidgets('halaman Ringkasan dapat dirender', (tester) async {
    final database = createInMemoryDatabaseForTests();
    await DatabaseSeed.ensure(database);
    addTearDown(database.close);

    await tester.pumpWidget(
      FfmApp(
        database: database,
        onboardingComplete: true,
        pinEnabled: false,
        isDarkMode: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ringkasan'), findsWidgets);
    expect(find.text('Belum ada angka yang perlu dihitung'), findsOneWidget);
    expect(find.text('Catat transaksi pertama'), findsOneWidget);
    expect(find.text('Saran buat kamu'), findsNothing);
  });
}
