import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/hijri/domain/hijri_calendar_service.dart';
import 'package:ffm_manager/features/reminder/domain/entities/reminder_entity.dart';
import 'package:ffm_manager/features/reminder/presentation/pages/reminder_page.dart';

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
    'judul dan kontrol pengingat tidak saling berebut lebar di layar kecil',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const title = 'Bayar tagihan internet keluarga bulan September';
      final reminder = ReminderEntity(
        id: 'reminder-layout',
        householdId: 'local-household',
        title: title,
        scheduledAt: DateTime.now().add(const Duration(days: 3, hours: 1)),
        recurrenceType: ReminderRecurrenceType.once,
        weekdays: const [],
        notificationId: 101,
        soundName: 'Liec.io classic notification sound',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderScheduleCard(
              reminder: reminder,
              onTap: () {},
              onActiveChanged: (_) {},
              onEdit: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final titleFinder = find.text(title);
      final countdownFinder = find.text('3 hari lagi');
      expect(titleFinder, findsOneWidget);
      expect(tester.getSize(titleFinder).width, greaterThan(200));
      expect(
        tester.getTopLeft(countdownFinder).dy,
        greaterThan(tester.getBottomLeft(titleFinder).dy),
      );
      expect(find.byType(Switch), findsOneWidget);
      expect(find.text('Dibuat pengguna'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
