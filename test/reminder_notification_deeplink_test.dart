import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ffm_manager/features/reminder/data/services/reminder_notification_service.dart';

void main() {
  const pendingKey = 'ffm_pending_reminder_actions';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test(
    'ketukan biasa dari background menerbitkan target reminder dan history',
    () async {
      final payload = {
        'reminderId': 'reminder-market',
        'historyId': 'reminder-market-2026-08-24T10:00:00',
        'occurrenceKey': '2026-08-24T10:00:00',
        'householdId': 'local-household',
      };
      SharedPreferences.setMockInitialValues({
        pendingKey: [
          jsonEncode({'actionId': 'open', 'payload': jsonEncode(payload)}),
        ],
      });
      final service = ReminderNotificationService();

      final actions = await service.consumePendingActions();

      expect(actions, hasLength(1));
      expect(actions.single.actionId, 'open');
      expect(service.openTarget.value?.reminderId, payload['reminderId']);
      expect(service.openTarget.value?.historyId, payload['historyId']);
      final target = service.takeOpenTarget();
      expect(target?.reminderId, payload['reminderId']);
      expect(service.openTarget.value, isNull);
    },
  );

  test('aksi selesai tidak menerbitkan deep-link ketukan biasa', () async {
    SharedPreferences.setMockInitialValues({
      pendingKey: [
        jsonEncode({
          'actionId': 'complete',
          'payload': jsonEncode({
            'reminderId': 'reminder-market',
            'historyId': 'history-market',
          }),
        }),
      ],
    });
    final service = ReminderNotificationService();

    await service.consumePendingActions();

    expect(service.openTarget.value, isNull);
  });

  test(
    'aksi background baru bertahan sampai acknowledgement berhasil',
    () async {
      const eventId = 'event-1';
      const eventKey = 'ffm_pending_reminder_action_$eventId';
      final payload = {
        'reminderId': 'reminder-market',
        'historyId': 'history-market',
        'occurrenceKey': '20260909-0800',
        'householdId': 'local-household',
      };
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            eventKey: jsonEncode({
              'id': eventId,
              'actionId': 'complete',
              'payload': payload,
            }),
          });
      final service = ReminderNotificationService();

      expect(await service.consumePendingActions(), hasLength(1));
      expect(await service.consumePendingActions(), hasLength(1));

      await service.acknowledgeAction(eventId);

      expect(await service.consumePendingActions(), isEmpty);
    },
  );
}
