import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/network/gemini_service.dart';
import 'package:ffm_manager/core/network/supabase_config.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_chat_history_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_memory_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_user_model_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_personal_context_engine_impl.dart';
import 'package:ffm_manager/features/assistant/data/ffm_personal_context_provider.dart';
import 'package:ffm_manager/features/assistant/data/ffm_working_context_manager.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeConfig extends SupabaseConfig {
  @override
  Future<String?> getGeminiKey() async => 'test-key';

  @override
  Future<String?> getGeminiModel() async => 'gemini-2.5-flash';

  @override
  Future<bool> isGeminiVerified() async => true;
}

class _CapturingGemini extends GeminiService {
  var calls = 0;
  String? systemInstruction;

  @override
  Future<GeminiResult> chat({
    required String prompt,
    String? systemInstruction,
    List<Map<String, String>> history = const [],
    String? apiKey,
    String? model,
  }) async {
    calls++;
    this.systemInstruction = systemInstruction;
    return const GeminiResult(
      model: 'gemini-2.5-flash',
      statusCode: 200,
      message: 'ok',
      text: 'Jawaban Gemini.',
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

  test(
    'kegagalan resolver context tetap meneruskan Gemini dengan context dasar',
    () async {
      final gemini = _CapturingGemini();
      final interpreter = FfmAssistantInterpreter(
        database,
        geminiService: gemini,
        config: _FakeConfig(),
        personalContextProvider: () => throw StateError('provider gagal'),
      );

      await interpreter.interpret('tolong pahami permintaan baru ini');

      expect(gemini.calls, 1);
      expect(gemini.systemInstruction, contains('Reasoning context FFM'));
    },
  );

  test(
    'Gemini menerima memory approved dan memblokirnya pada halaman sensitif',
    () async {
      final memories = FfmAssistantMemoryRepository(database);
      final userModel = FfmAssistantUserModelService(memories);
      await userModel.saveApproved(
        kind: 'name',
        key: 'panggilan',
        value: 'Budi',
      );
      final provider = await FfmPersonalContextProvider.initialize(
        database: database,
        memoryRepository: memories,
        userModelService: userModel,
      );
      final gemini = _CapturingGemini();
      final interpreter = FfmAssistantInterpreter(
        database,
        geminiService: gemini,
        config: _FakeConfig(),
        taughtMemory: memories,
        personalContextProvider: () => provider,
      );

      await interpreter.interpret('tolong pahami panggilan khusus ini');

      expect(gemini.systemInstruction, contains('panggilan=Budi'));

      await interpreter.interpret(
        'tolong pahami panggilan khusus ini',
        currentDestination: FfmAssistantDestination.appSecurity,
      );

      expect(gemini.systemInstruction, isNot(contains('panggilan=Budi')));
    },
  );
}
