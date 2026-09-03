import '../domain/autonomous_evaluation_coordinator.dart';
import 'ffm_assistant_agent_task_event_handler.dart';
import 'ffm_assistant_autonomy_repository.dart';

class FfmAssistantAutonomyBackgroundEventHandler {
  FfmAssistantAutonomyBackgroundEventHandler(
    this._taskHandler, [
    this._coordinator,
  ]);

  final FfmAssistantAgentTaskEventHandler _taskHandler;
  final AutonomousEvaluationCoordinator? _coordinator;

  Future<void> handle(FfmAssistantAutonomyEvent event) {
    return switch (event.type) {
      'agent.task.due' => _taskHandler.handle(event),
      // Notification action sudah diproses oleh ReminderBloc. Event ini hanya
      // menjadi audit trail dan tidak boleh membuat retry tanpa akhir.
      'reminder.due' => Future<void>.value(),
      'database.changed' => _handleDatabaseChanged(event),
      _ => throw StateError(
        'Tipe event background tidak didukung: ${event.type}',
      ),
    };
  }

  Future<void> _handleDatabaseChanged(FfmAssistantAutonomyEvent event) async {
    if (_coordinator != null) {
      await _coordinator.runEvaluation(householdId: event.householdId);
    }
  }
}
