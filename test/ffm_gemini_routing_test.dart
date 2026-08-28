import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/network/gemini_service.dart';
import 'package:ffm_manager/core/network/supabase_config.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_local_model_gateway.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

class _FakeConfig extends SupabaseConfig {
  _FakeConfig({
    required this.mode,
    required this.verified,
    this.model = 'gemini-2.5-flash',
  });

  final String mode;
  final bool verified;
  final String model;

  @override
  Future<String?> getGeminiKey() async => 'test-key';

  @override
  Future<String?> getGeminiModel() async => model;

  @override
  Future<bool> isGeminiVerified() async => verified;

  @override
  Future<String> getLlmMode() async => mode;
}

class _FakeGemini extends GeminiService {
  _FakeGemini(this.result);

  final GeminiResult result;
  var calls = 0;
  String? receivedModel;
  String? receivedSystemInstruction;

  @override
  Future<GeminiResult> chat({
    required String prompt,
    String? systemInstruction,
    List<Map<String, String>> history = const [],
    String? apiKey,
    String? model,
  }) async {
    calls++;
    receivedModel = model;
    receivedSystemInstruction = systemInstruction;
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
    'mode AGENT eksplisit tidak memanggil Gemini untuk pertanyaan bebas',
    () async {
      final gemini = _FakeGemini(
        const GeminiResult(
          model: 'gemini-2.5-pro',
          statusCode: 200,
          message: 'tidak boleh dipakai',
          text: 'tidak boleh dipakai',
        ),
      );
      final interpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(mode: 'agent', verified: true),
        geminiService: gemini,
      );

      final intent = await interpreter.interpret(
        'tolong jelaskan dampak inflasi bagi rencana keuangan keluarga',
        routingMode: FfmAssistantRoutingMode.agent,
      );

      expect(gemini.calls, 0);
      expect(
        intent.responseOrigin,
        FfmAssistantResponseOrigin.agentOrchestrator,
      );
    },
  );

  test(
    'mode Gemini eksplisit memanggil Gemini untuk pertanyaan bebas',
    () async {
      final gemini = _FakeGemini(
        const GeminiResult(
          model: 'gemini-2.5-pro',
          statusCode: 200,
          message: 'Gemini merespons.',
          text: 'Jawaban dari Gemini.',
        ),
      );
      final interpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(
          mode: 'agent',
          verified: true,
          model: 'gemini-2.5-pro',
        ),
        geminiService: gemini,
      );

      final intent = await interpreter.interpret(
        'beri rekomendasi bibit pepaya',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 1);
      expect(gemini.receivedModel, 'gemini-2.5-pro');
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
    },
  );

  test('mode Gemini mengirim perintah transaksi natural ke Gemini untuk dibuat draft', () async {
    final gemini = _FakeGemini(
      const GeminiResult(
        model: 'gemini-2.5-pro',
        statusCode: 200,
        message: 'draft transaksi',
        text: '{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"transaction","kind":"expense","amount":25000,"title":"Makan","category":"Makanan","fromAccount":"Tunai","note":"","date":"2026-08-28"}}',
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      config: _FakeConfig(mode: 'agent', verified: true),
      geminiService: gemini,
    );

    final intent = await interpreter.interpret(
      'catat beli makan 25rb',
      routingMode: FfmAssistantRoutingMode.geminiCloud,
    );

    expect(gemini.calls, 1);
    expect(intent.draft, isNotNull);
    expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
  });

  test('mode Gemini sukses diberi origin Gemini Cloud', () async {
    final gateway = _FakeGateway();
    final gemini = _FakeGemini(
      const GeminiResult(
        model: 'gemini-2.5-pro',
        statusCode: 200,
        message: 'Gemini merespons.',
        text: 'Jawaban dari Gemini.',
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      modelGateway: gateway,
      config: _FakeConfig(
        mode: 'gemini',
        verified: true,
        model: 'gemini-2.5-pro',
      ),
      geminiService: gemini,
    );

    final intent = await interpreter.interpret(
      'tolong jelaskan dampak inflasi bagi rencana keuangan keluarga',
      currentDestination: FfmAssistantDestination.masterData,
      pageContext:
          'Konteks layar FFM: Data Utama kategori aktivitas sedang dibuka.',
    );

    expect(gemini.calls, 1);
    expect(gemini.receivedModel, 'gemini-2.5-pro');
    expect(
      gemini.receivedSystemInstruction,
      contains('Data Utama kategori aktivitas sedang dibuka'),
    );
    expect(gateway.calls, 0);
    expect(intent.response, 'Jawaban dari Gemini.');
    expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
    expect(intent.pluginMetadata?['model'], 'gemini-2.5-pro');
  });

  test('mode Gemini gagal tidak diam-diam memakai gateway lokal', () async {
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
      config: _FakeConfig(mode: 'gemini', verified: true),
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

  test('mode Gemini belum diverifikasi tidak memanggil provider', () async {
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
      config: _FakeConfig(mode: 'gemini', verified: false),
      geminiService: gemini,
    );

    final intent = await interpreter.interpret(
      'tolong jelaskan dampak inflasi bagi rencana keuangan keluarga',
    );

    expect(gemini.calls, 0);
    expect(intent.responseOrigin, FfmAssistantResponseOrigin.cloudError);
    expect(intent.response, contains('belum siap'));
  });
}
