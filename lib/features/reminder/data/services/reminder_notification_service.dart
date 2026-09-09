import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../../domain/entities/reminder_entity.dart';

const _pendingReminderActionsKey = 'ffm_pending_reminder_actions';
const _pendingReminderActionPrefix = 'ffm_pending_reminder_action_';
const _assistantMorningReminderEnabledKey =
    'ffm_assistant_morning_reminder_enabled';
const _assistantMorningReminderNotificationId = 61006;
const _assistantMorningReminderChannelId = 'ffm_assistant_morning';

@pragma('vm:entry-point')
Future<void> reminderNotificationBackgroundResponse(
  NotificationResponse response,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final rawPayload = response.payload;
  if (rawPayload == null || rawPayload.isEmpty) return;
  final actionId = response.actionId ?? 'open';
  if (!const {'open', 'complete', 'snooze_10'}.contains(actionId)) return;
  final receivedAt = DateTime.now();
  Map<String, dynamic>? payload;
  try {
    final decoded = jsonDecode(rawPayload);
    if (decoded is Map<String, dynamic>) {
      payload = _normalizeReminderActionPayload(decoded, receivedAt);
    }
  } catch (_) {}
  if (payload == null) return;

  if (actionId == 'snooze_10') {
    final minutes = _boundedSnoozeMinutes(payload['defaultSnoozeMinutes']);
    final snoozedUntil = receivedAt.add(Duration(minutes: minutes));
    payload['snoozedUntil'] = snoozedUntil.toIso8601String();
    payload['snoozeScheduled'] = false;
    try {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
      final plugin = FlutterLocalNotificationsPlugin();
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await plugin.initialize(
        settings: const InitializationSettings(android: android),
      );
      await _scheduleBackgroundSnooze(plugin, payload, snoozedUntil);
      payload['snoozeScheduled'] = true;
    } catch (_) {}
  }

  final eventId = const Uuid().v4();
  final preferences = SharedPreferencesAsync();
  await preferences.setString(
    '$_pendingReminderActionPrefix$eventId',
    jsonEncode({
      'id': eventId,
      'actionId': actionId,
      'payload': payload,
      'receivedAt': receivedAt.toIso8601String(),
    }),
  );
}

String _backgroundOccurrenceKey(DateTime value) {
  final v = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${v.year}${two(v.month)}${two(v.day)}-${two(v.hour)}${two(v.minute)}';
}

int _boundedSnoozeMinutes(Object? raw) {
  final parsed = int.tryParse('$raw') ?? 10;
  return parsed.clamp(1, 1440);
}

Map<String, dynamic> _normalizeReminderActionPayload(
  Map<String, dynamic> payload,
  DateTime receivedAt,
) {
  final normalized = Map<String, dynamic>.from(payload);
  if (payload['isNativeSeries'] != true || payload['isSnooze'] == true) {
    return normalized;
  }
  final reminderId = '${payload['reminderId'] ?? ''}'.trim();
  final base = DateTime.tryParse('${payload['seriesScheduledAt'] ?? ''}')
      ?.toLocal();
  if (reminderId.isEmpty || base == null) return normalized;

  DateTime occurrence;
  final slotWeekday = int.tryParse('${payload['seriesWeekday'] ?? ''}');
  if (slotWeekday != null && slotWeekday >= 1 && slotWeekday <= 7) {
    final daysBack = (receivedAt.weekday - slotWeekday) % 7;
    final day = DateTime(
      receivedAt.year,
      receivedAt.month,
      receivedAt.day - daysBack,
    );
    occurrence = DateTime(
      day.year,
      day.month,
      day.day,
      base.hour,
      base.minute,
      base.second,
    );
    if (occurrence.isAfter(receivedAt)) {
      occurrence = DateTime(
        day.year,
        day.month,
        day.day - 7,
        base.hour,
        base.minute,
        base.second,
      );
    }
  } else {
    occurrence = DateTime(
      receivedAt.year,
      receivedAt.month,
      receivedAt.day,
      base.hour,
      base.minute,
      base.second,
    );
    if (occurrence.isAfter(receivedAt)) {
      occurrence = DateTime(
        receivedAt.year,
        receivedAt.month,
        receivedAt.day - 1,
        base.hour,
        base.minute,
        base.second,
      );
    }
  }
  if (occurrence.isBefore(base)) occurrence = base;
  final occurrenceKey = _backgroundOccurrenceKey(occurrence);
  normalized
    ..['rootOccurrenceKey'] = occurrenceKey
    ..['occurrenceKey'] = occurrenceKey
    ..['historyId'] = '$reminderId-$occurrenceKey'
    ..['scheduledAt'] = occurrence.toIso8601String();
  return normalized;
}

Future<void> _scheduleBackgroundSnooze(
  FlutterLocalNotificationsPlugin plugin,
  Map<String, dynamic> payload,
  DateTime snoozedUntil,
) async {
  final reminderId = '${payload['reminderId'] ?? ''}';
  final occurrenceKey =
      '${payload['rootOccurrenceKey'] ?? payload['occurrenceKey'] ?? ''}';
  if (reminderId.isEmpty || occurrenceKey.isEmpty) return;

  final snoozeNotifId = stableSnoozeNotificationId(reminderId, occurrenceKey);
  final channelId = '${payload['channelId'] ?? ''}'.trim().isNotEmpty
      ? '${payload['channelId']}'.trim()
      : 'reminder_snooze';
  final channelName = '${payload['title'] ?? 'Pengingat FFM'}'.trim();
  final soundUri = '${payload['soundUri'] ?? ''}'.trim();
  final androidSound = soundUri.isNotEmpty
      ? UriAndroidNotificationSound(soundUri)
      : null;

  await plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(
        AndroidNotificationChannel(
          channelId,
          channelName,
          description: 'Notifikasi pengingat yang ditunda',
          importance: Importance.max,
          playSound: true,
          sound: androidSound,
        ),
      );
  await plugin.zonedSchedule(
    id: snoozeNotifId,
    title: 'Pengingat Ditunda',
    body: '${payload['title'] ?? 'Pengingat FFM'}',
    scheduledDate: tz.TZDateTime.from(snoozedUntil, tz.local),
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Notifikasi pengingat yang ditunda',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        sound: androidSound,
        actions: const [
          AndroidNotificationAction('complete', 'Selesai'),
          AndroidNotificationAction('snooze_10', 'Tunda 10 menit'),
        ],
      ),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    payload: jsonEncode({
      ...payload,
      'isSnooze': true,
      'rootOccurrenceKey': occurrenceKey,
      'notificationId': snoozeNotifId,
      'snoozedUntil': snoozedUntil.toIso8601String(),
      'snoozeScheduled': true,
    }),
  );
}

class ReminderNotificationAction {
  const ReminderNotificationAction({
    required this.id,
    required this.actionId,
    required this.payload,
  });

  final String id;
  final String actionId;
  final Map<String, dynamic> payload;
}

class ReminderNotificationOpenTarget {
  const ReminderNotificationOpenTarget({
    required this.reminderId,
    required this.historyId,
  });

  final String reminderId;
  final String historyId;
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

abstract interface class ReminderNotificationLifecycleGateway {
  Future<void> acknowledgeAction(String id);

  Future<void> scheduleSnooze({
    required ReminderEntity reminder,
    required ReminderHistoryEntity history,
    required DateTime scheduledAt,
  });

  Future<void> cancelReminder(String reminderId);

  Future<void> cancelHistory(String historyId);
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

class ReminderNotificationService
    implements
        ReminderNotificationGateway,
        ReminderNotificationLifecycleGateway {
  ReminderNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  @override
  Future<void> Function(String action, Map<String, dynamic> payload)? onAction;
  final ValueNotifier<ReminderNotificationOpenTarget?> _openTarget =
      ValueNotifier(null);
  final ValueNotifier<String?> _inboxOpenTarget = ValueNotifier(null);
  final Map<String, String> _legacyPendingActions = {};
  bool _initialized = false;

  ValueListenable<ReminderNotificationOpenTarget?> get openTarget =>
      _openTarget;

  ValueListenable<String?> get inboxOpenTarget => _inboxOpenTarget;

  ReminderNotificationOpenTarget? takeOpenTarget() {
    final target = _openTarget.value;
    _openTarget.value = null;
    return target;
  }

  String? takeInboxOpenTarget() {
    final target = _inboxOpenTarget.value;
    _inboxOpenTarget.value = null;
    return target;
  }

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
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchResponse != null) {
      await _dispatch(launchResponse.actionId, launchResponse.payload);
    }
  }

  /// Pengingat ringan yang tidak membuat atau mengubah data apa pun.
  /// Android yang memicu notifikasi setiap pagi; FFM tidak perlu tetap terbuka.
  Future<bool> isAssistantMorningReminderEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_assistantMorningReminderEnabledKey) ?? false;
  }

  Future<void> setAssistantMorningReminderEnabled(bool enabled) async {
    await initialize();
    final preferences = await SharedPreferences.getInstance();
    if (!enabled) {
      await _plugin.cancel(id: _assistantMorningReminderNotificationId);
      await preferences.setBool(_assistantMorningReminderEnabledKey, false);
      return;
    }

    final permission = await requestPermissions();
    if (!permission.canSchedule) {
      throw StateError(
        'Izin notifikasi dan alarm presisi perlu diaktifkan agar pengingat pagi bisa berbunyi.',
      );
    }
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _assistantMorningReminderChannelId,
            'Pengingat pagi Asisten',
            description: 'Saran pagi dari Asisten FFM',
            importance: Importance.defaultImportance,
          ),
        );

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, 6);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id: _assistantMorningReminderNotificationId,
      title: 'Asisten FFM',
      body: 'Pagi! Kalau ada rencana atau kegiatan hari ini, yuk catat aktivitasnya biar rapi.',
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _assistantMorningReminderChannelId,
          'Pengingat pagi Asisten',
          channelDescription: 'Saran pagi dari Asisten FFM',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: jsonEncode({'type': 'assistant_morning_nudge'}),
    );
    await preferences.setBool(_assistantMorningReminderEnabledKey, true);
  }

  @override
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

  @override
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

  @override
  Future<List<ReminderNotificationAction>> consumePendingActions() async {
    final actions = <ReminderNotificationAction>[];
    final asyncPreferences = SharedPreferencesAsync();
    final keys =
        (await asyncPreferences.getKeys())
            .where((key) => key.startsWith(_pendingReminderActionPrefix))
            .toList()
          ..sort();
    for (final key in keys) {
      final raw = await asyncPreferences.getString(key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final rawPayload = decoded['payload'];
        final payload = rawPayload is Map
            ? rawPayload.cast<String, dynamic>()
            : jsonDecode('$rawPayload');
        if (payload is Map<String, dynamic>) {
          final action = ReminderNotificationAction(
            id: '${decoded['id'] ?? key.substring(_pendingReminderActionPrefix.length)}',
            actionId: '${decoded['actionId'] ?? 'open'}',
            payload: payload,
          );
          actions.add(action);
          _publishOpenTarget(action.actionId, action.payload);
        }
      } on Object {
        // Aksi yang rusak diabaikan agar startup tetap aman.
      }
    }

    // Migrasi antrean list versi lama. Item baru tidak lagi memakai pola
    // read-modify-write yang dapat kehilangan aksi lintas isolate.
    final legacyPreferences = await SharedPreferences.getInstance();
    await legacyPreferences.reload();
    final legacyItems =
        legacyPreferences.getStringList(_pendingReminderActionsKey) ?? const [];
    for (var index = 0; index < legacyItems.length; index++) {
      final raw = legacyItems[index];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final payload = jsonDecode('${decoded['payload']}');
        if (payload is! Map<String, dynamic>) continue;
        final id =
            'legacy:${stableReminderNotificationId('action', '$raw:$index')}';
        _legacyPendingActions[id] = raw;
        final action = ReminderNotificationAction(
          id: id,
          actionId: '${decoded['actionId'] ?? 'open'}',
          payload: payload,
        );
        actions.add(action);
        _publishOpenTarget(action.actionId, action.payload);
      } on Object {
        // Item rusak tetap dibiarkan agar tidak menghapus data lain tanpa ack.
      }
    }
    return actions;
  }

  @override
  Future<void> acknowledgeAction(String id) async {
    if (id.startsWith('legacy:')) {
      final raw = _legacyPendingActions.remove(id);
      if (raw == null) return;
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      final pending =
          preferences.getStringList(_pendingReminderActionsKey) ?? const [];
      final remaining = List<String>.of(pending)..remove(raw);
      if (remaining.isEmpty) {
        await preferences.remove(_pendingReminderActionsKey);
      } else {
        await preferences.setStringList(_pendingReminderActionsKey, remaining);
      }
      return;
    }
    await SharedPreferencesAsync().remove('$_pendingReminderActionPrefix$id');
  }

  @override
  Future<void> schedule({
    required ReminderEntity reminder,
    required ReminderOccurrence occurrence,
    String? historyId,
  }) async {
    await initialize();
    final now = DateTime.now();
    if (!occurrence.scheduledAt.isAfter(now)) return;
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
        'payloadVersion': 2,
        'reminderId': reminder.id,
        'historyId': historyId ?? '${reminder.id}-${occurrence.key}',
        'rootOccurrenceKey': occurrence.key,
        'occurrenceKey': occurrence.key,
        'householdId': reminder.householdId,
        'title': reminder.title,
        'note': reminder.note ?? '',
        'channelId': channelId,
        'soundUri': reminder.soundUri ?? '',
        'recurrence': reminder.recurrenceType.storageValue,
        'weekdays': reminder.weekdays,
        'seriesScheduledAt': reminder.scheduledAt.toIso8601String(),
        'isNativeSeries': false,
        'defaultSnoozeMinutes': reminder.defaultSnoozeMinutes,
        'scheduledAt': occurrence.scheduledAt.toIso8601String(),
        'notificationId': occurrence.notificationId,
      }),
    );
  }

  @override
  Future<void> scheduleSnooze({
    required ReminderEntity reminder,
    required ReminderHistoryEntity history,
    required DateTime scheduledAt,
  }) async {
    await initialize();
    if (!scheduledAt.isAfter(DateTime.now())) return;
    final permission = await permissionState();
    if (!permission.canSchedule) {
      throw StateError(
        'Izin notifikasi atau alarm presisi belum aktif. Buka pengaturan izin lalu coba lagi.',
      );
    }
    final channelId = reminderNotificationChannelId(reminder);
    final soundUri = reminder.soundUri?.trim() ?? '';
    final androidSound = soundUri.isEmpty
        ? null
        : UriAndroidNotificationSound(soundUri);
    final id = stableSnoozeNotificationId(reminder.id, history.occurrenceKey);
    await _plugin.zonedSchedule(
      id: id,
      title: 'Pengingat Ditunda',
      body: reminder.title,
      scheduledDate: tz.TZDateTime.from(scheduledAt, tz.local),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          reminder.soundName ?? 'Pengingat FFM',
          channelDescription: 'Notifikasi pengingat yang ditunda',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          sound: androidSound,
          actions: const [
            AndroidNotificationAction('complete', 'Selesai'),
            AndroidNotificationAction('snooze_10', 'Tunda 10 menit'),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: jsonEncode({
        'payloadVersion': 2,
        'reminderId': reminder.id,
        'historyId': history.id,
        'rootOccurrenceKey': history.occurrenceKey,
        'occurrenceKey': history.occurrenceKey,
        'householdId': reminder.householdId,
        'title': reminder.title,
        'note': reminder.note ?? '',
        'channelId': channelId,
        'soundUri': reminder.soundUri ?? '',
        'recurrence': reminder.recurrenceType.storageValue,
        'weekdays': reminder.weekdays,
        'seriesScheduledAt': reminder.scheduledAt.toIso8601String(),
        'isNativeSeries': false,
        'isSnooze': true,
        'defaultSnoozeMinutes': reminder.defaultSnoozeMinutes,
        'scheduledAt': history.scheduledAt.toIso8601String(),
        'snoozedUntil': scheduledAt.toIso8601String(),
        'snoozeScheduled': true,
        'notificationId': id,
      }),
    );
  }

  @override
  Future<void> cancelReminder(String reminderId) async {
    await initialize();
    final requests = await _plugin.pendingNotificationRequests();
    for (final request in requests) {
      final payload = _decodePayload(request.payload);
      if ('${payload?['reminderId'] ?? ''}' == reminderId) {
        await _plugin.cancel(id: request.id);
      }
    }
  }

  @override
  Future<void> cancelHistory(String historyId) async {
    await initialize();
    final requests = await _plugin.pendingNotificationRequests();
    for (final request in requests) {
      final payload = _decodePayload(request.payload);
      if (payload?['isNativeSeries'] != true &&
          '${payload?['historyId'] ?? ''}' == historyId) {
        await _plugin.cancel(id: request.id);
      }
    }
  }

  Map<String, dynamic>? _decodePayload(String? rawPayload) {
    if (rawPayload == null || rawPayload.isEmpty) return null;
    try {
      final payload = jsonDecode(rawPayload);
      return payload is Map<String, dynamic> ? payload : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> cancel(int notificationId) async {
    await initialize();
    await _plugin.cancel(id: notificationId);
  }

  @override
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

  static const _assistantInsightNotificationIdBase = 62000;
  static const _assistantInsightChannelId = 'ffm_assistant_insights';

  Future<void> showAssistantInsightNotification({
    required String insightId,
    required String title,
    required String summary,
  }) async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _assistantInsightChannelId,
        'Kotak Masuk Asisten',
        description: 'Pemberitahuan wawasan dan rekomendasi penting Asisten AI',
        importance: Importance.high,
      ),
    );

    final notificationId =
        _assistantInsightNotificationIdBase + (insightId.hashCode.abs() % 1000);
    final payload = jsonEncode({
      'type': 'assistant_insight',
      'insightId': insightId,
    });

    await _plugin.show(
      id: notificationId,
      title: 'Wawasan Asisten AI',
      body: 'Ada catatan keuangan baru untuk ditinjau: $title',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _assistantInsightChannelId,
          'Kotak Masuk Asisten',
          channelDescription:
              'Pemberitahuan wawasan dan rekomendasi penting Asisten AI',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
          styleInformation: BigTextStyleInformation(
            summary,
            contentTitle: title,
            summaryText: 'Asisten AI',
          ),
        ),
      ),
      payload: payload,
    );
  }

  Future<void> _dispatch(String? actionId, String? rawPayload) async {
    if (rawPayload == null || rawPayload.isEmpty) return;
    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is Map<String, dynamic>) {
        final action = actionId ?? 'open';
        if (!const {'open', 'complete', 'snooze_10'}.contains(action) &&
            '${decoded['type'] ?? ''}' != 'assistant_insight') {
          return;
        }
        final payload = _normalizeReminderActionPayload(
          decoded,
          DateTime.now(),
        );
        if (onAction != null) {
          await onAction!(action, payload);
        }
        _publishOpenTarget(action, payload);
      }
    } on Object {
      // Payload invalid tidak boleh membuat callback notifikasi crash.
    }
  }

  void _publishOpenTarget(String actionId, Map<String, dynamic> payload) {
    if (actionId != 'open') return;
    final type = '${payload['type'] ?? ''}'.trim();
    if (type == 'assistant_insight') {
      final insightId = '${payload['insightId'] ?? ''}'.trim();
      _inboxOpenTarget.value = insightId.isNotEmpty ? insightId : 'open';
      return;
    }
    final reminderId = '${payload['reminderId'] ?? ''}'.trim();
    final historyId = '${payload['historyId'] ?? ''}'.trim();
    if (reminderId.isEmpty || historyId.isEmpty) return;
    _openTarget.value = ReminderNotificationOpenTarget(
      reminderId: reminderId,
      historyId: historyId,
    );
  }
}
