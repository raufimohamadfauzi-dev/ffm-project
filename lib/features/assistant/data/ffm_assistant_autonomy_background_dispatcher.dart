import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/injection.dart';
import '../../asset/data/repositories/market_news_cache_repository.dart';
import '../../asset/data/services/market_news_radar_service.dart';
import '../../reminder/data/services/reminder_schedule_replenisher.dart';
import 'ffm_assistant_autonomy_background_handler.dart';
import 'ffm_assistant_autonomy_background_scheduler.dart';
import 'ffm_assistant_autonomy_worker.dart';
import 'telegram_delivery_processor.dart';

import 'ffm_assistant_proactive_evaluation_task.dart';

@pragma('vm:entry-point')
void ffmAssistantAutonomyCallbackDispatcher() {
  Workmanager().executeTask((taskName, _) async {
    final isAutonomyTask =
        taskName == FfmAssistantAutonomyBackgroundScheduler.taskName;
    final isMarketNewsTask =
        taskName == FfmAssistantAutonomyBackgroundScheduler.marketNewsTaskName;
    final isReminderTask =
        taskName == FfmAssistantAutonomyBackgroundScheduler.reminderTaskName;
    if (!isAutonomyTask && !isMarketNewsTask && !isReminderTask) {
      return true;
    }
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      await configureDependencies();
      if (isReminderTask) {
        await getIt<ReminderScheduleReplenisher>().replenish(
          householdId: 'local-household',
        );
        return true;
      }
      if (isMarketNewsTask) {
        final service = getIt<MarketNewsRadarService>();
        final cache = getIt<MarketNewsCacheRepository>();
        final interval = Duration(
          minutes: await cache.getRefreshIntervalMinutes(),
        );
        final cachedPrice = await cache.getLatestPriceSnapshot();
        if (interval.inMinutes > 0 &&
            DateTime.now().difference(cachedPrice.lastUpdated) >= interval) {
          await cache.savePriceSnapshot(await service.fetchMarketPrices());
        }

        final cachedNews = await cache.getCachedNews();
        final newestNewsAt = cachedNews
            .where((item) => item.isPublishedAtKnown && !item.isFallback)
            .map((item) => item.publishedAt)
            .fold<DateTime?>(
              null,
              (latest, publishedAt) =>
                  latest == null || publishedAt.isAfter(latest)
                  ? publishedAt
                  : latest,
            );
        if (interval.inMinutes > 0 &&
            (newestNewsAt == null ||
                DateTime.now().difference(newestNewsAt) >= interval)) {
          final news = await service.fetchCuratedNews();
          if (!news.every((item) => item.isFallback)) {
            await cache.saveNewsItems(news);
          }
        }
        return true;
      }
      if (getIt.isRegistered<ReminderScheduleReplenisher>()) {
        await getIt<ReminderScheduleReplenisher>().replenish(
          householdId: 'local-household',
        );
      }
      final result = await getIt<FfmAssistantAutonomyWorker>().runOnce(
        getIt<FfmAssistantAutonomyBackgroundEventHandler>().handle,
      );
      if (getIt.isRegistered<TelegramDeliveryProcessor>()) {
        // Proses antrean pengiriman Telegram yang durabel (transaksi, laporan
        // mingguan, dan alarm) pada siklus background.
        await getIt<TelegramDeliveryProcessor>().processPending(
          householdId: 'local-household',
        );
      }
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
