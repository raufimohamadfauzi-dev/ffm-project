import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/entities/reminder_entity.dart';

const _pendingReminderActionsKey = 'ffm_pending_reminder_actions';

@pragma('vm:entry-point')
Future<void> reminderNotificationBackgroundResponse(
  NotificationResponse response,
) async {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;
  final preferences = await SharedPreferences.getInstance();
  final pending = preferences.getStringList(_pendingReminderActionsKey) ?? [];
  pending.add(
    jsonEncode({
      'actionId': response.actionId ?? 'open',
      'payload': payload,
      'receivedAt': DateTime.now().toIso8601String(),
    }),
  );
  await preferences.setStringList(_pendingReminderActionsKey, pending);
}

class ReminderNotificationAction {
  const ReminderNotificationAction({
    required this.actionId,
    required this.payload,
  });

  final String actionId;
  final Map<String, dynamic> payload;
}

class ReminderPermissionState {
  const ReminderPermissionState({
    required this.notificationsEnabled,
    required this.exactAlarmEnabled,
  });

  final bool notificationsEnabled;
  final bool exactAlarmEnabled;

  bool get canSchedule => notificationsEnabled && exactAlarmEnabled;
}

abstract interface class ReminderNotificationGateway {
  Future<ReminderPermissionState> permissionState();

  Future<ReminderPermissionState> requestPermissions();

  Future<List<ReminderNotificationAction>> consumePendingActions();

  Future<void> schedule({
    required ReminderEntity reminder,
    required ReminderOccurrence occurrence,
    String? historyId,
  });

  Future<void> cancel(int notificationId);

  Future<void> cancelAll();

  Future<void> Function(String action, Map<String, dynamic> payload)? onAction;
}

String reminderNotificationChannelId(ReminderEntity reminder) {
  final soundKey = reminder.soundUri?.trim().isNotEmpty == true
      ? reminder.soundUri!
      : 'default';
  var hash = 2166136261;
  for (final codeUnit in soundKey.codeUnits) {
    hash = (hash ^ codeUnit) * 16777619;
    hash &= 0x7fffffff;
  }
  return 'reminder_${reminder.id}_${hash == 0 ? 1 : hash}';
}

class ReminderNotificationService implements ReminderNotificationGateway {
  ReminderNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void> Function(String action, Map<String, dynamic> payload)? onAction;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: (response) async {
        await _dispatch(response.actionId, response.payload);
      },
      onDidReceiveBackgroundNotificationResponse:
          reminderNotificationBackgroundResponse,
    );
    _initialized = true;
  }

  Future<ReminderPermissionState> permissionState() async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final notifications = await android?.areNotificationsEnabled() ?? true;
    final exactAlarm = await android?.canScheduleExactNotifications() ?? true;
    return ReminderPermissionState(
      notificationsEnabled: notifications,
      exactAlarmEnabled: exactAlarm,
    );
  }

  Future<ReminderPermissionState> requestPermissions() async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (await android?.areNotificationsEnabled() == false) {
      await android?.requestNotificationsPermission();
    }
    if (await android?.canScheduleExactNotifications() == false) {
      await android?.requestExactAlarmsPermission();
    }
    return permissionState();
  }

  Future<bool?> openNotificationSettings() async {
    await initialize();
    return _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.openAppNotificationSettings();
  }

  Future<List<ReminderNotificationAction>> consumePendingActions() async {
    final preferences = await SharedPreferences.getInstance();
    final rawItems =
        preferences.getStringList(_pendingReminderActionsKey) ?? [];
    if (rawItems.isEmpty) return const [];
    await preferences.remove(_pendingReminderActionsKey);
    final actions = <ReminderNotificationAction>[];
    for (final raw in rawItems) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final payload = jsonDecode('${decoded['payload']}');
        if (payload is Map<String, dynamic>) {
          actions.add(
            ReminderNotificationAction(
              actionId: '${decoded['actionId'] ?? 'open'}',
              payload: payload,
            ),
          );
        }
      } on Object {
        // Aksi yang rusak diabaikan agar startup tetap aman.
      }
    }
    return actions;
  }

  Future<void> schedule({
    required ReminderEntity reminder,
    required ReminderOccurrence occurrence,
    String? historyId,
  }) async {
    await initialize();
    if (occurrence.scheduledAt.isBefore(DateTime.now())) return;
    final permission = await permissionState();
    if (!permission.canSchedule) {
      throw StateError(
        'Izin notifikasi atau alarm presisi belum aktif. Buka pengaturan izin lalu coba lagi.',
      );
    }
    final channelId = reminderNotificationChannelId(reminder);
    final androidSound = reminder.soundUri?.trim().isNotEmpty == true
        ? UriAndroidNotificationSound(reminder.soundUri!)
        : null;
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            channelId,
            reminder.soundName ?? 'Pengingat FFM',
            description: 'Notifikasi pengingat FFM',
            importance: Importance.max,
            playSound: true,
            sound: androidSound,
          ),
        );
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        reminder.soundName ?? 'Pengingat FFM',
        channelDescription: 'Notifikasi pengingat FFM',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        sound: androidSound,
        actions: const [
          AndroidNotificationAction('complete', 'Selesai'),
          AndroidNotificationAction('snooze_10', 'Tunda 10 menit'),
        ],
      ),
    );
    await _plugin.zonedSchedule(
      id: occurrence.notificationId,
      title: reminder.title,
      body: reminder.note?.trim().isNotEmpty == true
          ? reminder.note
          : 'Waktunya menjalankan pengingat.',
      scheduledDate: tz.TZDateTime.from(occurrence.scheduledAt, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: jsonEncode({
        'reminderId': reminder.id,
        'historyId': historyId ?? '${reminder.id}-${occurrence.key}',
        'occurrenceKey': occurrence.key,
        'householdId': reminder.householdId,
      }),
    );
  }

  Future<void> cancel(int notificationId) async {
    await initialize();
    await _plugin.cancel(id: notificationId);
  }

  Future<void> cancelAll() async {
    await initialize();
    await _plugin.cancelAll();
  }

  static int stableId(String reminderId, String occurrenceKey) {
    var hash = 2166136261;
    for (final codeUnit in '$reminderId:$occurrenceKey'.codeUnits) {
      hash = (hash ^ codeUnit) * 16777619;
      hash &= 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  Future<void> _dispatch(String? actionId, String? rawPayload) async {
    if (rawPayload == null || rawPayload.isEmpty) return;
    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is Map<String, dynamic> && onAction != null) {
        await onAction!(actionId ?? 'open', decoded);
      }
    } on Object {
      // Payload invalid tidak boleh membuat callback notifikasi crash.
    }
  }
}
