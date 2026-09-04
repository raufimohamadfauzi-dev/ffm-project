import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/injection.dart';
import 'ffm_assistant_autonomy_background_handler.dart';
import 'ffm_assistant_autonomy_worker.dart';
import 'ffm_assistant_proactive_evaluation_task.dart';

/// Top-level callback entry-point untuk Foreground Task Android.
/// Wajib memiliki anotasi `@pragma('vm:entry-point')`.
@pragma('vm:entry-point')
void ffmForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(FfmAssistantForegroundTaskHandler());
}

/// Handler siklus hidup dan event berulang untuk Foreground Service di Status Bar.
class FfmAssistantForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _executeAutonomyCycle(timestamp);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _executeAutonomyCycle(timestamp);
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // Service dihentikan oleh sistem atau user
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'open_app') {
      FlutterForegroundTask.launchApp();
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {}

  Future<void> _executeAutonomyCycle(DateTime timestamp) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      await configureDependencies();

      // 1. Jalankan worker antrean tugas otonom
      if (getIt.isRegistered<FfmAssistantAutonomyWorker>() &&
          getIt.isRegistered<FfmAssistantAutonomyBackgroundEventHandler>()) {
        await getIt<FfmAssistantAutonomyWorker>().runOnce(
          getIt<FfmAssistantAutonomyBackgroundEventHandler>().handle,
        );
      }

      // 2. Jalankan evaluasi radar finansial proaktif
      if (getIt.isRegistered<FfmAssistantProactiveEvaluationTask>()) {
        await getIt<FfmAssistantProactiveEvaluationTask>().evaluateAndPush();
      }

      // 3. Perbarui teks status bar secara dinamis
      final hour = timestamp.hour.toString().padLeft(2, '0');
      final minute = timestamp.minute.toString().padLeft(2, '0');
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Asisten Finansial FFM Aktif',
        notificationText: 'Radar finansial aman • Terakhir diperiksa $hour:$minute',
      );

      // 4. Kirim data pembaruan ke UI jika aplikasi sedang terbuka
      FlutterForegroundTask.sendDataToMain({
        'lastChecked': timestamp.toIso8601String(),
        'status': 'active',
      });
    } catch (_) {
      // Background cycle error tidak boleh membuat service crash
    } finally {
      if (getIt.isRegistered<AppDatabase>()) {
        try {
          await getIt<AppDatabase>().close();
        } catch (_) {}
      }
    }
  }
}

/// Manajer utama layanan Foreground Service di status bar FFM.
class FfmAssistantForegroundServiceManager {
  FfmAssistantForegroundServiceManager({this.preferences});

  final SharedPreferences? preferences;

  static const String preferenceKey = 'ffm_autonomy_foreground_service_enabled';
  static const String channelId = 'ffm_assistant_foreground_channel';
  static const String channelName = 'Radar Finansial FFM (Status Bar)';
  static const int serviceId = 256;
  static const int intervalMillis = 15 * 60 * 1000; // 15 menit

  Future<SharedPreferences> get _prefs async =>
      preferences ?? await SharedPreferences.getInstance();

  Future<bool> isEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(preferenceKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(preferenceKey, enabled);
    if (enabled) {
      await startService();
    } else {
      await stopService();
    }
  }

  Future<bool> isRunning() async {
    if (!Platform.isAndroid) return false;
    return await FlutterForegroundTask.isRunningService;
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
  }

  Future<bool> requestIgnoreBatteryOptimization() async {
    if (!Platform.isAndroid) return true;
    return await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  void initialize() {
    if (!Platform.isAndroid) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: channelId,
        channelName: channelName,
        channelDescription:
            'Menjaga agen otonom dan radar finansial tetap aktif tanpa dimatikan Android.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(intervalMillis),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<bool> startService() async {
    if (!Platform.isAndroid) return false;

    // Pastikan izin notifikasi di Android 13+
    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      final reqResult =
          await FlutterForegroundTask.requestNotificationPermission();
      if (reqResult != NotificationPermission.granted) {
        return false;
      }
    }

    if (await FlutterForegroundTask.isRunningService) {
      final res = await FlutterForegroundTask.restartService();
      return res is ServiceRequestSuccess;
    }

    final res = await FlutterForegroundTask.startService(
      serviceId: serviceId,
      notificationTitle: 'Asisten Finansial FFM Aktif',
      notificationText: 'Radar finansial keluarga memantau • Mode Siaga',
      notificationIcon: null,
      notificationButtons: const [
        NotificationButton(id: 'open_app', text: 'Buka FFM'),
      ],
      callback: ffmForegroundTaskCallback,
    );
    return res is ServiceRequestSuccess;
  }

  Future<bool> stopService() async {
    if (!Platform.isAndroid) return true;
    final res = await FlutterForegroundTask.stopService();
    return res is ServiceRequestSuccess;
  }
}
