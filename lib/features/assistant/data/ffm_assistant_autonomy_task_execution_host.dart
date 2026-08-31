import '../../../core/database/app_database.dart';
import '../domain/ffm_assistant_action_plan.dart';
import '../domain/ffm_assistant_capability_executor.dart';
import '../domain/ffm_assistant_autonomy_policy.dart';
import 'ffm_assistant_autonomy_repository.dart';
import 'ffm_assistant_capability_adapters.dart';

/// Host eksekusi untuk task Agent. Host membuat controller baru per plan agar
/// state plan tidak bocor antar-run atau antar-isolate.
class FfmAssistantAutonomyTaskExecutionHost {
  FfmAssistantAutonomyTaskExecutionHost({
    required this._database,
    required this._repository,
    required this._adapters,
    this._householdId = FfmAssistantAutonomyRepository.householdId,
  });

  final AppDatabase _database;
  final FfmAssistantAutonomyRepository _repository;
  final FfmAssistantCapabilityAdapterRegistry _adapters;
  final String _householdId;

  Future<FfmAssistantActionPlan?> execute(FfmAssistantActionPlan plan) async {
    final policy =
        await _repository.loadPolicy(householdId: _householdId) ??
        const FfmAssistantAutonomyPolicy();
    final controller = FfmAssistantActionPlanController();
    controller.register(plan);
    final executor = FfmAssistantCapabilityExecutor(
      controller: controller,
      handlers: _adapters.handlers,
      readTransaction: <T>(action) => _database.transaction(action),
      onPlanRecorded: _repository.recordPlan,
      onToolExecution: _repository.recordToolExecution,
      autonomyPolicy: policy,
    );
    return executor.execute(plan.id);
  }
}
