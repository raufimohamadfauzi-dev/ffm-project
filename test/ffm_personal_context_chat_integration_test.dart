import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_chat_history_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_local_model_gateway.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_memory_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_user_model_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_personal_context_engine_impl.dart';
import 'package:ffm_manager/features/assistant/data/ffm_personal_context_provider.dart';
import 'package:ffm_manager/features/assistant/data/ffm_working_context_manager.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CapturingGateway implements FfmAssistantLocalModelGateway {
  String? pageContext;

  @override
  Future<FfmAssistantModelProposal?> propose({
    required String input,
    String? imagePath,
  }) async => const FfmAssistantModelProposal(
    intent: FfmAssistantIntentType.help,
    confidence: .95,
  );

  @override
  Future<FfmAssistantModelProposal?> proposeWithContext({
    required String input,
    String? imagePath,
    String? pageContext,
    String? conversationHistory,
    List<String> capabilityIds = const <String>[],
    List<String> activeAccountNames = const <String>[],
    List<String> activeCategoryNames = const <String>[],
  }) async {
    this.pageContext = pageContext;
    return const FfmAssistantModelProposal(
      intent: FfmAssistantIntentType.help,
      confidence: .95,
    );
  }
}

void main() {
  late AppDatabase database;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FfmPersonalContextProvider.reset();
    database = createInMemoryDatabaseForTests();
  });

  tearDown(() async {
    FfmPersonalContextProvider.reset();
    await database.close();
  });

  test(
    'provider mempertahankan working context hasil restore dari history',
    () async {
      final history = FfmAssistantChatHistoryRepository();
      await history.save([
        const FfmAssistantChatEntry(
          isUser: true,
          text: 'pengeluaran bulan ini bagaimana?',
        ),
      ]);

      final provider = await FfmPersonalContextProvider.initialize(
        database: database,
        chatHistoryRepository: history,
      );

      expect(
        provider.workingContextManager.currentContext.currentTopic,
        'spending',
      );
      expect(
        provider.workingContextManager.currentContext.currentPeriod,
        'current_month',
      );
    },
  );

  test(
    'build context tidak mengubah working context sebelum respons tersedia',
    () async {
      final history = FfmAssistantChatHistoryRepository();
      final manager = FfmWorkingContextManager(chatHistoryRepository: history);
      final engine = FfmPersonalContextEngineImpl(
        database: database,
        workingContextManager: manager,
      );

      await engine.buildContext(query: 'pengeluaran bulan ini bagaimana?');

      expect(manager.currentContext.currentTopic, isNull);
      expect(manager.currentContext.currentPeriod, isNull);
    },
  );

  test('working context tidak menyimpan isi respons mentah', () {
    final manager = FfmWorkingContextManager(
      chatHistoryRepository: FfmAssistantChatHistoryRepository(),
    );

    manager.updateAfterTurn(
      userQuery: 'pengeluaran bulan ini bagaimana?',
      assistantResponse:
          'Catatan pribadi dan nominal mentah tidak boleh disimpan.',
      extractedEntities: const {},
    );

    expect(manager.currentContext.currentTopic, 'spending');
    expect(manager.currentContext.currentPeriod, 'current_month');
    expect(manager.currentContext.lastActionResult, 'assistant_response_ready');
  });

  test('clear working context tidak menghapus memory approved', () async {
    final memories = FfmAssistantMemoryRepository(database);
    final userModel = FfmAssistantUserModelService(memories);
    await userModel.saveApproved(kind: 'name', key: 'panggilan', value: 'Budi');
    final provider = await FfmPersonalContextProvider.initialize(
      database: database,
      memoryRepository: memories,
      userModelService: userModel,
    );
    provider.updateAfterTurn(
      userQuery: 'pengeluaran bulan ini bagaimana?',
      assistantResponse: 'queryData',
    );

    provider.clearWorkingContext();

    expect(provider.workingContextManager.currentContext.currentTopic, isNull);
    expect(await userModel.readApproved(), hasLength(1));
  });

  test(
    'follow-up memakai topik working context tanpa menyimpan respons mentah',
    () async {
      final manager = FfmWorkingContextManager(
        chatHistoryRepository: FfmAssistantChatHistoryRepository(),
      );
      manager.updateAfterTurn(
        userQuery: 'pengeluaran bulan ini bagaimana?',
        assistantResponse: 'queryData',
        extractedEntities: const {},
      );
      final engine = FfmPersonalContextEngineImpl(
        database: database,
        workingContextManager: manager,
      );

      final context = await engine.buildContext(query: 'bagaimana sekarang?');

      expect(context.detectedEntities['topic'], 'spending');
      expect(context.detectedEntities['period'], 'current_month');
      expect(
        manager.currentContext.lastActionResult,
        'assistant_response_ready',
      );
    },
  );

  test('kegagalan resolver context tetap meneruskan model-first dengan context dasar', () async {
    final gateway = _CapturingGateway();
    final interpreter = FfmAssistantInterpreter(
      database,
      modelGateway: gateway,
      personalContextProvider: () => throw StateError('provider gagal'),
    );

    await interpreter.interpret('tolong pahami permintaan baru ini');

    expect(gateway.pageContext, contains('Reasoning context FFM'));
  });

  test('model-first menerima memory approved dan memblokirnya pada halaman sensitif', () async {
    final memories = FfmAssistantMemoryRepository(database);
    final userModel = FfmAssistantUserModelService(memories);
    await userModel.saveApproved(kind: 'name', key: 'panggilan', value: 'Budi');
    final provider = await FfmPersonalContextProvider.initialize(
      database: database,
      memoryRepository: memories,
      userModelService: userModel,
    );
    final gateway = _CapturingGateway();
    final interpreter = FfmAssistantInterpreter(
      database,
      modelGateway: gateway,
      taughtMemory: memories,
      personalContextProvider: () => provider,
    );

    await interpreter.interpret('tolong pahami panggilan khusus ini');

    expect(gateway.pageContext, contains('panggilan=Budi'));

    await interpreter.interpret(
      'tolong pahami panggilan khusus ini',
      currentDestination: FfmAssistantDestination.appSecurity,
    );

    expect(gateway.pageContext, isNot(contains('panggilan=Budi')));
  });
}
