import 'package:workmanager/workmanager.dart';

class FfmAssistantAutonomyBackgroundScheduler {
  const FfmAssistantAutonomyBackgroundScheduler({this._workmanager});

  static const taskName = 'ffm.autonomy.poll';
  static const uniqueName = 'ffm-autonomy-periodic';
  static const frequency = Duration(minutes: 15);

  final Workmanager? _workmanager;

  Workmanager get _instance => _workmanager ?? Workmanager();

  Future<void> initialize(void Function() dispatcher) =>
      _instance.initialize(dispatcher);

  Future<void> ensureScheduled() => _instance.registerPeriodicTask(
    uniqueName,
    taskName,
    frequency: frequency,
    initialDelay: frequency,
    tag: 'ffm-autonomy',
  );

  Future<void> cancel() => _instance.cancelByUniqueName(uniqueName);
}
