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
      expect(
        find.text('Nada: Liec.io classic notification sound'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'menampilkan badge otonom, asal pemicu diagnostik, dan catatan penjelasan',
    (tester) async {
      final reminder = ReminderEntity(
        id: 'reminder-auto',
        householdId: 'local-household',
        title: 'Periksa catatan aplikasi',
        note: 'Terdeteksi antrean data sempat padat. Sistem telah pulih.',
        scheduledAt: DateTime.now().add(const Duration(hours: 4)),
        recurrenceType: ReminderRecurrenceType.once,
        weekdays: const [],
        notificationId: 102,
        origin: ReminderOrigin.autonomous,
        sourceType: ReminderSourceType.diagnostics,
        sourceId: 'diag-1',
        soundName: 'Nada Custom Otonom',
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

      expect(find.text('Dibuat otonom'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
      expect(find.text('Diagnostik Aplikasi'), findsOneWidget);
      expect(find.byIcon(Icons.build_circle_outlined), findsOneWidget);
      expect(
        find.text('Terdeteksi antrean data sempat padat. Sistem telah pulih.'),
        findsOneWidget,
      );
      expect(find.text('Nada: Nada Custom Otonom'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'menandai pengingat yang sudah lewat dengan status waktu sudah lewat dan redup',
    (tester) async {
      final reminder = ReminderEntity(
        id: 'reminder-past-due',
        householdId: 'local-household',
        title: 'Jemput anak sekolah kemarin',
        scheduledAt: DateTime.now().subtract(const Duration(hours: 2)),
        recurrenceType: ReminderRecurrenceType.once,
        weekdays: const [],
        notificationId: 103,
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

      expect(find.text('Waktu sudah lewat'), findsOneWidget);
      expect(find.byIcon(Icons.alarm_off_outlined), findsOneWidget);
      expect(find.text('Nada: Bawaan FFM'), findsOneWidget);

      final opacityFinder = find.byWidgetPredicate(
        (widget) => widget is Opacity && widget.opacity < 1.0,
      );
      expect(opacityFinder, findsOneWidget);
      final Opacity opacityWidget = tester.widget(opacityFinder);
      expect(opacityWidget.opacity, closeTo(0.72, 0.01));
      expect(tester.takeException(), isNull);
    },
  );
}
