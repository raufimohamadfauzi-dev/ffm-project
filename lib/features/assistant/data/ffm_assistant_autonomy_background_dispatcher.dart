import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/injection.dart';
import 'ffm_assistant_autonomy_background_handler.dart';
import 'ffm_assistant_autonomy_background_scheduler.dart';
import 'ffm_assistant_autonomy_worker.dart';

import 'ffm_assistant_proactive_evaluation_task.dart';

@pragma('vm:entry-point')
void ffmAssistantAutonomyCallbackDispatcher() {
  Workmanager().executeTask((taskName, _) async {
    if (taskName != FfmAssistantAutonomyBackgroundScheduler.taskName) {
      return true;
    }
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      await configureDependencies();
      final result = await getIt<FfmAssistantAutonomyWorker>().runOnce(
        getIt<FfmAssistantAutonomyBackgroundEventHandler>().handle,
      );
      if (getIt.isRegistered<FfmAssistantProactiveEvaluationTask>()) {
        await getIt<FfmAssistantProactiveEvaluationTask>().evaluateAndPush();
      }
      return result.failed == 0;
    } on Object {
      return false;
    } finally {
      if (getIt.isRegistered<AppDatabase>()) {
        await getIt<AppDatabase>().close();
      }
    }
  });
}
