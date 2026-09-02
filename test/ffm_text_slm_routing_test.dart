import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/network/gemini_service.dart';
import 'package:ffm_manager/core/network/supabase_config.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_local_model_gateway.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeConfig extends SupabaseConfig {
  _FakeConfig({this.verified = true});

  final bool verified;

  @override
  Future<String?> getGeminiKey() async => 'test-key';

  @override
  Future<String?> getGeminiModel() async => 'gemini-2.5-flash';

  @override
  Future<bool> isGeminiVerified() async => verified;
}

class _FakeGemini extends GeminiService {
  _FakeGemini(this.result);

  final GeminiResult result;
  var calls = 0;
  String? lastPrompt;
  String? lastSystemInstruction;

  @override
  Future<GeminiResult> chat({
    required String prompt,
    String? systemInstruction,
    List<Map<String, String>> history = const [],
    String? apiKey,
    String? model,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls++;
    lastPrompt = prompt;
    lastSystemInstruction = systemInstruction;
    return result;
  }
}

class _FakeGateway implements FfmAssistantLocalModelGateway {
  var calls = 0;

  @override
  Future<FfmAssistantModelProposal?> propose({required String input}) async {
    calls++;
    return null;
  }

  @override
  Future<FfmAssistantModelProposal?> proposeWithContext({
    required String input,
    String? pageContext,
    String? conversationHistory,
    List<String> capabilityIds = const <String>[],
    List<String> activeAccountNames = const <String>[],
    List<String> activeCategoryNames = const <String>[],
  }) => propose(input: input);
}

void main() {
  late AppDatabase database;

  setUp(() {
    database = createInMemoryDatabaseForTests();
  });

  tearDown(() => database.close());

  test(
    'pertanyaan bebas diteruskan ke Gemini dengan konteks halaman bounded',
    () async {
      final gemini = _FakeGemini(
        const GeminiResult(
          model: 'gemini-2.5-flash',
          statusCode: 200,
          message: 'Gemini merespons.',
          text: 'Jawaban dari Gemini.',
        ),
      );
      final interpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(),
        geminiService: gemini,
      );

      final intent = await interpreter.interpret(
        'tolong jelaskan dampak inflasi bagi rencana keuangan keluarga',
        currentDestination: FfmAssistantDestination.transactions,
        pageContext: 'Daftar transaksi bulan berjalan',
        capabilityIds: const ['read.transactions', 'draft.expense'],
      );

      expect(gemini.calls, 1);
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
      expect(intent.response, 'Jawaban dari Gemini.');
      expect(intent.pluginMetadata?['model'], 'gemini-2.5-flash');
      expect(gemini.lastPrompt, contains('inflasi'));
      expect(
        gemini.lastSystemInstruction,
        contains('Daftar transaksi bulan berjalan'),
      );
      expect(
        gemini.lastSystemInstruction,
        contains('Halaman aktif: Transaksi'),
      );
      expect(gemini.lastSystemInstruction, contains('read.transactions'));
    },
  );

  test('kegagalan Gemini menjadi cloudError tanpa gateway lokal', () async {
    final gateway = _FakeGateway();
    final gemini = _FakeGemini(
      const GeminiResult(
        model: 'gemini-2.5-flash',
        statusCode: 401,
        message: 'API key Gemini ditolak (HTTP 401).',
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      modelGateway: gateway,
      config: _FakeConfig(),
      geminiService: gemini,
    );

    final intent = await interpreter.interpret(
      'tolong jelaskan dampak inflasi bagi rencana keuangan keluarga',
    );

    expect(gemini.calls, 1);
    expect(gateway.calls, 0);
    expect(intent.responseOrigin, FfmAssistantResponseOrigin.cloudError);
    expect(intent.response, contains('HTTP 401'));
  });

  test('Gemini belum diverifikasi tidak memanggil provider', () async {
    final gemini = _FakeGemini(
      const GeminiResult(
        model: 'gemini-2.5-flash',
        statusCode: 200,
        message: 'tidak boleh dipakai',
        text: 'tidak boleh dipakai',
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      config: _FakeConfig(verified: false),
      geminiService: gemini,
    );

    final intent = await interpreter.interpret(
      'tolong jelaskan dampak inflasi bagi rencana keuangan keluarga',
    );

    expect(gemini.calls, 0);
    expect(intent.responseOrigin, FfmAssistantResponseOrigin.cloudError);
    expect(intent.response, contains('belum siap'));
  });

  test('guard PIN tetap deterministic dan tidak dikirim ke Gemini', () async {
    final gemini = _FakeGemini(
      const GeminiResult(
        model: 'gemini-2.5-flash',
        statusCode: 200,
        message: 'tidak boleh dipakai',
        text: 'tidak boleh dipakai',
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      config: _FakeConfig(),
      geminiService: gemini,
    );

    final intent = await interpreter.interpret('tolong ganti PIN aplikasi');

    expect(gemini.calls, 0);
    expect(intent.type, FfmAssistantIntentType.openPage);
    expect(intent.destination, FfmAssistantDestination.appSecurity);
  });

  test(
    'draft transaksi tetap deterministic dan database belum berubah',
    () async {
      final gemini = _FakeGemini(
        const GeminiResult(
          model: 'gemini-2.5-flash',
          statusCode: 200,
          message: 'tidak boleh dipakai',
          text: 'tidak boleh dipakai',
        ),
      );
      final interpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(),
        geminiService: gemini,
      );

      final intent = await interpreter.interpret('catat makan 25000');

      expect(gemini.calls, 0);
      expect(
        intent.responseOrigin,
        isNot(FfmAssistantResponseOrigin.geminiCloud),
      );
      expect(
        intent.responseOrigin,
        isNot(FfmAssistantResponseOrigin.cloudError),
      );
      expect(await database.select(database.transactions).get(), isEmpty);
    },
  );
}
