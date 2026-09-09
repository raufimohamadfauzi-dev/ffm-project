import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../activity/data/repositories/activity_repository.dart';
import 'ffm_assistant_insight_repository.dart';
import '../domain/ffm_assistant_insight.dart';
import '../presentation/widgets/ffm_assistant_global_launcher.dart';

class FfmAssistantProactiveMonitor {
  FfmAssistantProactiveMonitor({
    required this.activityRepository,
    required this.launcherState,
    required this.householdId,
    required this.insightRepository,
  });

  final ActivityRepository activityRepository;
  final ValueNotifier<FfmAssistantLauncherState> launcherState;
  final String householdId;
  final FfmAssistantInsightRepository insightRepository;
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
    _setState(isWorking: true);
    bool notify = false;
    String? reason;

    try {
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

      // 2. Unread financial insights must also be visible on the global launcher.
      final insights = await insightRepository.getActiveInsights(
        householdId: householdId,
      );
      if (insights.any(
        (insight) => insight.status == FfmAssistantInsightStatus.newInsight,
      )) {
        notify = true;
        reason ??= 'new_financial_insight';
      }
    } finally {
      _setState(
        isWorking: false,
        hasNotification: notify,
        reason: reason,
        clearReason: true,
      );
    }
  }

  void _setState({
    bool? isWorking,
    bool? hasNotification,
    String? reason,
    bool clearReason = false,
  }) {
    final current = launcherState.value;
    launcherState.value = FfmAssistantLauncherState(
      isSheetOpen: current.isSheetOpen,
      isWorking: isWorking ?? current.isWorking,
      hasNotification: hasNotification ?? current.hasNotification,
      notificationReason: clearReason
          ? reason
          : reason ?? current.notificationReason,
    );
  }
}
