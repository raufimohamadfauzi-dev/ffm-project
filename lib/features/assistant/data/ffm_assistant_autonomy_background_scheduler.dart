import 'package:workmanager/workmanager.dart';

class FfmAssistantAutonomyBackgroundScheduler {
  const FfmAssistantAutonomyBackgroundScheduler({this._workmanager});

  static const taskName = 'ffm.autonomy.poll';
  static const uniqueName = 'ffm-autonomy-periodic';
  static const marketNewsTaskName = 'ffm.market-news.refresh';
  static const marketNewsUniqueName = 'ffm-market-news-periodic';
  static const reminderTaskName = 'ffm.reminder.replenish';
  static const reminderUniqueName = 'ffm-reminder-replenish-periodic';
  static const frequency = Duration(minutes: 15);

  final Workmanager? _workmanager;

  Workmanager get _instance => _workmanager ?? Workmanager();

  Future<void> initialize(void Function() dispatcher) =>
      _instance.initialize(dispatcher);

  Future<void> ensureScheduled() async {
    await _instance.registerPeriodicTask(
      uniqueName,
      taskName,
      frequency: frequency,
      initialDelay: frequency,
      tag: 'ffm-autonomy',
    );
    await _instance.registerPeriodicTask(
      marketNewsUniqueName,
      marketNewsTaskName,
      frequency: frequency,
      initialDelay: frequency,
      tag: 'ffm-market-news',
    );
    await _instance.registerPeriodicTask(
      reminderUniqueName,
      reminderTaskName,
      frequency: frequency,
      initialDelay: frequency,
      tag: 'ffm-reminder',
    );
  }

  Future<void> cancel() async {
    await _instance.cancelByUniqueName(uniqueName);
    await _instance.cancelByUniqueName(marketNewsUniqueName);
    await _instance.cancelByUniqueName(reminderUniqueName);
  }
}
