import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/asset/domain/entities/asset_entity.dart';
import 'package:ffm_manager/features/asset/presentation/pages/asset_pages.dart';
import 'package:ffm_manager/features/hijri/domain/hijri_calendar_service.dart';

void main() {
  late AppDatabase database;

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
    'Detail Aset menampilkan informasi tanpa mengklaim saldo rekening',
    (tester) async {
      final asset = AssetEntity(
        id: 'asset-motor',
        householdId: 'household-test',
        name: 'Motor Keluarga',
        assetType: 'Kendaraan',
        value: 18000000,
        placement: 'Garasi rumah',
        note: 'Servis rutin setiap tiga bulan.',
        createdAt: DateTime(2026, 8, 1, 8),
        updatedAt: DateTime(2026, 8, 2, 9),
      );

      await tester.pumpWidget(MaterialApp(home: AssetDetailPage(asset: asset)));

      expect(find.text('Detail aset'), findsOneWidget);
      expect(find.text('Motor Keluarga'), findsOneWidget);
      expect(find.text('Kendaraan'), findsOneWidget);
      expect(find.text('Garasi rumah'), findsOneWidget);
      expect(find.text('Aset bukan rekening'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Servis rutin setiap tiga bulan.'),
        200,
      );
      expect(find.text('Servis rutin setiap tiga bulan.'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Arsipkan aset'), 200);
      expect(find.text('Ubah aset'), findsOneWidget);
      expect(find.text('Arsipkan aset'), findsOneWidget);
    },
  );
}
