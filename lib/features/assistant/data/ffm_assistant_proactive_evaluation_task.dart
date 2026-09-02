import '../../../core/database/app_database.dart';
import '../../advisor/domain/usecases/budget_guard_service.dart';
import '../domain/ffm_assistant_models.dart';
import '../../../core/database/app_context.dart';
import 'ffm_assistant_chat_history_repository.dart';

class FfmAssistantProactiveEvaluationTask {
  const FfmAssistantProactiveEvaluationTask(
    this._database,
    this._chatHistory,
  );

  final AppDatabase _database;
  final FfmAssistantChatHistoryRepository _chatHistory;

  Future<void> evaluateAndPush() async {
    final history = await _chatHistory.load();
    if (history.isNotEmpty) {
      final lastEntry = history.last;
      final now = DateTime.now();
      // Jangan spam jika asisten sudah kirim pesan baru-baru ini
      if (!lastEntry.isUser && lastEntry.createdAt != null) {
        if (now.difference(lastEntry.createdAt!).inHours < 6) return;
      }
    }

    // Evaluasi budget over-limit via BudgetGuardService
    final budgetGuard = BudgetGuardService(_database);
    final overBudgetItems = await budgetGuard.check(AppContext.householdId);

    if (overBudgetItems.isNotEmpty) {
      final worst = overBudgetItems.first;
      final message = 'Halo! Sekadar mengingatkan: ${worst.title}. ${worst.message}';
      
      // Jika pesan sama persis dengan yang terakhir, jangan diduplikat
      if (history.isNotEmpty && history.last.text == message) return;

      history.add(
        FfmAssistantChatEntry(
          isUser: false,
          text: message,
          createdAt: DateTime.now(),
        )
      );

      await _chatHistory.save(history);
    }
  }
}
