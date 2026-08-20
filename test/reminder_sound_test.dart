import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/reminder/data/services/reminder_notification_service.dart';
import 'package:ffm_manager/features/reminder/data/services/reminder_sound_picker.dart';
import 'package:ffm_manager/features/reminder/domain/entities/reminder_entity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ffm/reminder_sound');

  ReminderEntity reminder({String? soundUri}) => ReminderEntity(
    id: 'reminder-sound-test',
    householdId: 'local-household',
    title: 'Tes nada',
    scheduledAt: DateTime(2026, 8, 25, 7),
    recurrenceType: ReminderRecurrenceType.once,
    weekdays: const [],
    notificationId: 1001,
    soundUri: soundUri,
    soundName: soundUri == null ? null : 'Nada pilihan',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('picker mengembalikan URI dan nama nada dari native Android', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'pick');
          expect(call.arguments['currentUri'], 'content://old');
          return {
            'uri': 'content://media/external/audio/media/42',
            'name': 'Nada Panen',
          };
        });

    final result = await AndroidReminderSoundPicker(channel: channel)
        .pick(currentUri: 'content://old');

    expect(result?.uri, 'content://media/external/audio/media/42');
    expect(result?.name, 'Nada Panen');
  });

  test('picker yang dibatalkan tidak menghasilkan pilihan baru', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);

    final result = await AndroidReminderSoundPicker(channel: channel).pick();

    expect(result, isNull);
  });

  test('channel stabil untuk suara sama dan berbeda saat suara berubah', () {
    final defaultFirst = reminder();
    final defaultSecond = reminder();
    final custom = reminder(soundUri: 'content://media/audio/42');

    expect(
      reminderNotificationChannelId(defaultFirst),
      reminderNotificationChannelId(defaultSecond),
    );
    expect(
      reminderNotificationChannelId(defaultFirst),
      isNot(reminderNotificationChannelId(custom)),
    );
  });
}
