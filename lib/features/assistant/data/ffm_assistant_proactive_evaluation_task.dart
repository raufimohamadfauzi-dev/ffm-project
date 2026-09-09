import '../../../core/database/app_database.dart';
import '../../../core/database/app_context.dart';
import '../domain/autonomous_evaluation_coordinator.dart';
import 'ffm_assistant_chat_history_repository.dart';
import 'ffm_assistant_insight_repository.dart';

class FfmAssistantProactiveEvaluationTask {
  const FfmAssistantProactiveEvaluationTask(
    this._database, [
    this._chatHistory,
    this._insightRepository,
    this._coordinatorFactory,
  ]);

  final AppDatabase _database;
  final FfmAssistantChatHistoryRepository? _chatHistory;
  final FfmAssistantInsightRepository? _insightRepository;
  final AutonomousEvaluationCoordinator Function()? _coordinatorFactory;

  Future<void> evaluateAndPush() async {
    if (_chatHistory != null) {
      await _chatHistory.load();
    }
    final repo = _insightRepository ?? FfmAssistantInsightRepository(_database);
    final coordinator =
        _coordinatorFactory?.call() ??
        AutonomousEvaluationCoordinator(
          database: _database,
          insightRepository: repo,
        );

    await coordinator.runEvaluation(householdId: AppContext.householdId);
  }
}
