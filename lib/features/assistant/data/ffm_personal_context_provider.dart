import '../../../core/database/app_database.dart';
import '../domain/ffm_personal_context_engine.dart';
import '../domain/ffm_context_relevance.dart';
import '../domain/ffm_assistant_reasoning_context.dart';
import '../domain/ffm_personal_context.dart';
import 'ffm_personal_context_engine_impl.dart';
import 'ffm_assistant_memory_repository.dart';
import 'ffm_assistant_user_model_service.dart';
import 'ffm_personal_memory_service.dart';
import 'ffm_assistant_personalization_repository.dart';
import 'ffm_working_context_manager.dart';
import 'ffm_assistant_chat_history_repository.dart';
import 'ffm_context_adapter.dart';

/// Provider untuk Personal Context Engine.
///
/// Singleton pattern untuk memastikan hanya satu instance yang digunakan
/// di seluruh aplikasi.
class FfmPersonalContextProvider {
  static FfmPersonalContextProvider? _instance;
  
  late final FfmPersonalContextEngine _contextEngine;
  late final FfmWorkingContextManager _workingContextManager;
  late final FfmContextAdapter _contextAdapter;
  late final FfmAssistantChatHistoryRepository _chatHistoryRepository;

  FfmPersonalContextProvider._internal({
    required AppDatabase database,
    FfmAssistantMemoryRepository? memoryRepository,
    FfmAssistantUserModelService? userModelService,
    FfmPersonalMemoryService? personalMemoryService,
    FfmAssistantPersonalizationRepository? personalizationRepository,
    FfmAssistantChatHistoryRepository? chatHistoryRepository,
  }) {
    _chatHistoryRepository = chatHistoryRepository ?? FfmAssistantChatHistoryRepository();
    _workingContextManager = FfmWorkingContextManager(
      chatHistoryRepository: _chatHistoryRepository,
    );
    
    _contextEngine = FfmPersonalContextEngineImpl(
      database: database,
      memoryRepository: memoryRepository,
      userModelService: userModelService,
      personalMemoryService: personalMemoryService,
      personalizationRepository: personalizationRepository,
      workingContextManager: _workingContextManager,
    );
    
    _contextAdapter = const FfmContextAdapter();
  }

  /// Initialize provider dengan database
  static Future<FfmPersonalContextProvider> initialize({
    required AppDatabase database,
    FfmAssistantMemoryRepository? memoryRepository,
    FfmAssistantUserModelService? userModelService,
    FfmPersonalMemoryService? personalMemoryService,
    FfmAssistantPersonalizationRepository? personalizationRepository,
    FfmAssistantChatHistoryRepository? chatHistoryRepository,
  }) async {
    if (_instance != null) return _instance!;
    
    // Rebuild working context dari history saat initialize
    final chatHistoryRepo = chatHistoryRepository ?? FfmAssistantChatHistoryRepository();
    final workingContextManager = FfmWorkingContextManager(
      chatHistoryRepository: chatHistoryRepo,
    );
    await workingContextManager.rebuildFromHistory();

    _instance = FfmPersonalContextProvider._internal(
      database: database,
      memoryRepository: memoryRepository,
      userModelService: userModelService,
      personalMemoryService: personalMemoryService,
      personalizationRepository: personalizationRepository,
      chatHistoryRepository: chatHistoryRepo,
    );

    return _instance!;
  }

  /// Get current instance
  static FfmPersonalContextProvider get instance {
    if (_instance == null) {
      throw StateError('FfmPersonalContextProvider not initialized. Call initialize() first.');
    }
    return _instance!;
  }

  /// Reset instance (untuk testing)
  static void reset() {
    _instance = null;
  }

  /// Get context engine
  FfmPersonalContextEngine get contextEngine => _contextEngine;

  /// Get working context manager
  FfmWorkingContextManager get workingContextManager => _workingContextManager;

  /// Get context adapter
  FfmContextAdapter get contextAdapter => _contextAdapter;

  /// Get chat history repository
  FfmAssistantChatHistoryRepository get chatHistoryRepository => _chatHistoryRepository;

  /// Convenience method untuk build context
  Future<FfmPersonalContext> buildContext({
    required String query,
    FfmAssistantReasoningContext? reasoningContext,
    FfmContextBudget? budget,
  }) async {
    return _contextEngine.buildContext(
      query: query,
      reasoningContext: reasoningContext,
      previousWorkingContext: _workingContextManager.currentContext,
      budget: budget,
    );
  }

  /// Convenience method untuk update reasoning context
  FfmAssistantReasoningContext updateReasoningContext({
    required FfmAssistantReasoningContext originalContext,
    required FfmPersonalContext personalContext,
  }) {
    return _contextAdapter.updateReasoningContext(
      originalContext: originalContext,
      personalContext: personalContext,
    );
  }

  /// Convenience method untuk update working context setelah turn
  void updateAfterTurn({
    required String userQuery,
    required String? assistantResponse,
    Map<String, String>? extractedEntities,
  }) {
    _workingContextManager.updateAfterTurn(
      userQuery: userQuery,
      assistantResponse: assistantResponse,
      extractedEntities: extractedEntities ?? {},
    );
  }

  /// Clear working context
  void clearWorkingContext() {
    _workingContextManager.clear();
  }

  /// Check apakah ada pending clarification
  bool get hasPendingClarification => _workingContextManager.hasPendingClarification;
}
