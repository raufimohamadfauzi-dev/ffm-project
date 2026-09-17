import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/advisor/presentation/pages/summary_page.dart';

ReminderHistory _dummyHistory(String id) {
  return ReminderHistory(
    id: id,
    reminderId: 'rem-$id',
    householdId: 'local-household',
    title: 'Pengingat $id',
    occurrenceKey: 'occ-$id',
    scheduledAt: DateTime(2026, 9, 15, 8),
    triggeredAt: DateTime(2026, 9, 15, 8),
    status: 'pending',
    createdAt: DateTime(2026, 9, 15, 7),
    notificationId: 100,
  );
}

void main() {
  testWidgets('badge tidak tampil ketika tidak ada pending history', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: ReminderNotificationButton(
              historyStream: Stream.value(const <ReminderHistory>[]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final badgeFinder = find.byType(Badge);
    expect(badgeFinder, findsOneWidget);
    final badgeWidget = tester.widget<Badge>(badgeFinder);
    expect(badgeWidget.isLabelVisible, isFalse);
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
  });

  testWidgets('tampil angka ketika ada pending triggered history', (
    tester,
  ) async {
    final list = [_dummyHistory('1'), _dummyHistory('2')];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: ReminderNotificationButton(
              historyStream: Stream.value(list),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final badgeFinder = find.byType(Badge);
    expect(badgeFinder, findsOneWidget);
    final badgeWidget = tester.widget<Badge>(badgeFinder);
    expect(badgeWidget.isLabelVisible, isTrue);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('menampilkan 9+ ketika pending triggered history lebih dari 9', (
    tester,
  ) async {
    final list = List.generate(12, (i) => _dummyHistory('$i'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: ReminderNotificationButton(
              historyStream: Stream.value(list),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final badgeFinder = find.byType(Badge);
    expect(badgeFinder, findsOneWidget);
    final badgeWidget = tester.widget<Badge>(badgeFinder);
    expect(badgeWidget.isLabelVisible, isTrue);
    expect(find.text('9+'), findsOneWidget);
  });

  testWidgets(
    'tampil titik merah (badge tanpa label teks) ketika ada pengingat otonom aktif',
    (tester) async {
      final autoReminders = [
        Reminder(
          id: 'rem-auto-1',
          householdId: 'local-household',
          title: 'Pengingat Otonom',
          scheduledAt: DateTime(2026, 9, 15, 9),
          recurrenceType: 'once',
          weekdaysJson: '[]',
          isActive: true,
          defaultSnoozeMinutes: 10,
          notificationId: 101,
          createdAt: DateTime(2026, 9, 15, 7),
          origin: 'autonomous',
          mode: 'notification',
          isSyncedToCalendar: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: ReminderNotificationButton(
                historyStream: Stream.value(const <ReminderHistory>[]),
                autonomousStream: Stream.value(autoReminders),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final badgeFinder = find.byType(Badge);
      expect(badgeFinder, findsOneWidget);
      final badgeWidget = tester.widget<Badge>(badgeFinder);
      expect(badgeWidget.isLabelVisible, isTrue);
      // When label is null, it renders as a pure red dot indicator
      expect(badgeWidget.label, isNull);
    },
  );

  testWidgets('klik membuka ReminderPage atau aksi pengingat', (tester) async {
    var clicked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: ReminderNotificationButton(
              historyStream: Stream.value(const <ReminderHistory>[]),
              onTap: () => clicked = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final buttonFinder = find.byType(IconButton);
    expect(buttonFinder, findsOneWidget);

    await tester.tap(buttonFinder);
    await tester.pump();

    expect(clicked, isTrue);
  });
}
