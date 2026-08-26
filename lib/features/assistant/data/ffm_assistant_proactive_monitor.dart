import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../activity/data/repositories/activity_repository.dart';
import '../presentation/widgets/ffm_assistant_global_launcher.dart';

class FfmAssistantProactiveMonitor {
  FfmAssistantProactiveMonitor({
    required this.activityRepository,
    required this.launcherState,
    required this.householdId,
  });

  final ActivityRepository activityRepository;
  final ValueNotifier<FfmAssistantLauncherState> launcherState;
  final String householdId;
  Timer? _timer;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => check());
    // Initial check
    check();
  }

  void stop() {
    _timer?.cancel();
  }

  Future<void> check() async {
    bool notify = false;
    String? reason;
    
    // 1. Check for long running sessions (> 12 hours)
    final active = await activityRepository.getActiveSessions(householdId);
    final now = DateTime.now();
    for (final s in active) {
      if (now.difference(s.startedAt).inHours >= 12) {
        notify = true;
        reason = 'long_running_session:${s.title}';
        break;
      }
    }

    // 2. Check for upcoming habits could be added here
    
    if (launcherState.value.hasNotification != notify || launcherState.value.notificationReason != reason) {
      launcherState.value = FfmAssistantLauncherState(
        isSheetOpen: launcherState.value.isSheetOpen,
        hasNotification: notify,
        notificationReason: reason,
      );
    }
  }
}
