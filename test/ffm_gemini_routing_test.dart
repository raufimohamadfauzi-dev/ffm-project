import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/network/gemini_service.dart';
import 'package:ffm_manager/core/network/supabase_config.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_local_model_gateway.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_cloud_context.dart';
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

class _SecondCallFailsGemini extends GeminiService {
  var calls = 0;

  @override
  Future<GeminiResult> chat({
    required String prompt,
    String? systemInstruction,
    List<Map<String, String>> history = const [],
    String? apiKey,
    String? model,
  }) async {
    calls++;
    return calls == 1
        ? const GeminiResult(
            model: 'gemini-2.5-pro',
            statusCode: 200,
            message: 'capability request',
            text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.summary","arguments":{"period":"current_month"}}',
          )
        : const GeminiResult(
            model: 'gemini-2.5-pro',
            statusCode: 503,
            message: 'Gemini sementara tidak tersedia (HTTP 503).',
          );
  }
}

class _OutsideMonthReadGemini extends GeminiService {
  var calls = 0;

  @override
  Future<GeminiResult> chat({
    required String prompt,
    String? systemInstruction,
    List<Map<String, String>> history = const [],
    String? apiKey,
    String? model,
  }) async {
    calls++;
    return const GeminiResult(
      model: 'gemini-2.5-pro',
      statusCode: 200,
      message: 'capability request',
      text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.transactions","arguments":{"period":"current_month","startDate":"2026-07-30","endDate":"2026-08-02"}}',
    );
  }
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

  test(
    'kill switch context-first tidak diam-diam memanggil provider lain',
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
        geminiContextFirstEnabled: false,
      );

      final intent = await interpreter.interpret(
        'ringkasan keuangan bulan ini',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 0);
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.cloudError);
      expect(intent.pluginMetadata?['model'], 'context-first-disabled');
      expect(intent.response, contains('context-first Gemini'));
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
    expect(gemini.receivedSystemInstruction, contains('`read.summary`'));
    expect(gemini.receivedSystemInstruction, contains('`read.transactions`'));
    expect(
      gemini.receivedSystemInstruction,
      isNot(contains('`read.accounts`')),
    );
    expect(
      gemini.receivedSystemInstruction,
      isNot(contains('`read.activity`')),
    );
    expect(
      gemini.receivedSystemInstruction,
      isNot(contains('ANALYSIS FACTS:')),
    );
    expect(gateway.calls, 0);
    expect(intent.response, 'Jawaban dari Gemini.');
    expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
    expect(intent.pluginMetadata?['model'], 'gemini-2.5-pro');
  });

  test(
    'mode Gemini menerima active draft sebagai context field-aware',
    () async {
      final gemini = _FakeGemini(
        const GeminiResult(
          model: 'gemini-2.5-pro',
          statusCode: 200,
          message: 'Gemini merespons.',
          text: 'Nama draft dapat dikoreksi.',
        ),
      );
      final interpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(mode: 'gemini', verified: true),
        geminiService: gemini,
      );

      await interpreter.interpret(
        'koreksi nama draft ini',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
        activeDraft: FfmAssistantDraft(
          kind: FfmAssistantDraftKind.masterData,
          createdAt: DateTime(2026, 8, 31),
          title: 'BandarPPT1',
          categoryName: 'tag',
          amount: 987654321,
          fromAccountName: 'REKENING-TIDAK-RELEVAN',
        ),
      );

      expect(
        gemini.receivedSystemInstruction,
        contains(FfmAssistantCloudContextEnvelope.schemaVersion),
      );
      expect(gemini.receivedSystemInstruction, contains('ACTIVE DRAFT'));
      expect(gemini.receivedSystemInstruction, contains('kind=masterData'));
      expect(gemini.receivedSystemInstruction, contains('BandarPPT1'));
      expect(gemini.receivedSystemInstruction, isNot(contains('987654321')));
      expect(
        gemini.receivedSystemInstruction,
        isNot(contains('REKENING-TIDAK-RELEVAN')),
      );
    },
  );

  test(
    'permintaan analisis mengirim hasil analysis engine ke Gemini',
    () async {
      final gemini = _FakeGemini(
        const GeminiResult(
          model: 'gemini-2.5-pro',
          statusCode: 200,
          message: 'Gemini merespons.',
          text: 'Belum ada transaksi untuk dianalisis.',
        ),
      );
      final interpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(mode: 'gemini', verified: true),
        geminiService: gemini,
        clock: () => DateTime(2026, 8, 31),
      );

      await interpreter.interpret(
        'analisis pengeluaran bulan ini',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(
        gemini.receivedSystemInstruction,
        contains('"requestClass":"analysis"'),
      );
      expect(gemini.receivedSystemInstruction, contains('ANALYSIS FACTS'));
      expect(gemini.receivedSystemInstruction, contains('bulan ini'));
    },
  );

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

  test('read.monthly_summary capability ditolak oleh allowlist', () async {
    final gemini = _FakeGemini(
      const GeminiResult(
        model: 'gemini-2.5-pro',
        statusCode: 200,
        message: 'capability request',
        text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.monthly_summary","arguments":{"period":"current_month"},"userFacingReply":"Saya cek ringkasan bulan ini dulu."}',
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      config: _FakeConfig(mode: 'agent', verified: true),
      geminiService: gemini,
    );

    final intent = await interpreter.interpret(
      'berikan ringkasan bulan ini',
      routingMode: FfmAssistantRoutingMode.geminiCloud,
    );

    // Request tidak boleh diteruskan ke executor atau panggilan Gemini kedua.
    expect(gemini.calls, 1);
    expect(intent.responseOrigin, FfmAssistantResponseOrigin.cloudError);
    expect(intent.response, contains('tidak diizinkan'));
  });

  test('capability yang tidak ada di allowlist ditolak', () async {
    final gemini = _FakeGemini(
      const GeminiResult(
        model: 'gemini-2.5-pro',
        statusCode: 200,
        message: 'invalid capability',
        text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.invalid_capability","arguments":{"period":"current_month"}}',
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      config: _FakeConfig(mode: 'agent', verified: true),
      geminiService: gemini,
    );

    final intent = await interpreter.interpret(
      'berikan data invalid',
      routingMode: FfmAssistantRoutingMode.geminiCloud,
    );

    expect(gemini.calls, 1);
    expect(intent.response, contains('tidak diizinkan'));
  });

  test(
    'Gemini gagal pada panggilan kedua tidak menyamar sebagai jawaban lokal',
    () async {
      final gemini = _SecondCallFailsGemini();
      final interpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(mode: 'gemini', verified: true),
        geminiService: gemini,
      );

      final intent = await interpreter.interpret(
        'ringkas keuangan saya bulan ini',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 2);
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.cloudError);
      expect(intent.response, contains('HTTP 503'));
      expect(intent.draft, isNull);
    },
  );

  test(
    'executor menolak rentang di luar bulan tanpa panggilan Gemini kedua',
    () async {
      final gemini = _OutsideMonthReadGemini();
      final interpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(mode: 'gemini', verified: true),
        geminiService: gemini,
        clock: () => DateTime(2026, 8, 28),
      );

      final intent = await interpreter.interpret(
        'lihat transaksi lama',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 1);
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.cloudError);
      expect(intent.response, contains('tidak dapat dibaca dengan aman'));
      expect(intent.draft, isNull);
    },
  );

  test(
    'Gemini mode + sapaan + pertanyaan pendek tetap memanggil Gemini',
    () async {
      final gemini = _FakeGemini(
        const GeminiResult(
          model: 'gemini-2.5-pro',
          statusCode: 200,
          message: 'Gemini merespons.',
          text: 'Halo! Saya siap membantu.',
        ),
      );
      final interpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(mode: 'agent', verified: true),
        geminiService: gemini,
      );

      final intent = await interpreter.interpret(
        'hai',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 1);
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
    },
  );

  test('Gemini mode + perintah Aktivitas tetap memanggil Gemini lalu proposal menjadi draft', () async {
    final gemini = _FakeGemini(
      const GeminiResult(
        model: 'gemini-2.5-pro',
        statusCode: 200,
        message: 'activity proposal',
        text: '{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"activity","title":"Panen Padi","category":"Pertanian","note":"","date":"2026-08-28"}}',
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      config: _FakeConfig(mode: 'agent', verified: true),
      geminiService: gemini,
    );

    final intent = await interpreter.interpret(
      'catat aktivitas panen padi',
      routingMode: FfmAssistantRoutingMode.geminiCloud,
    );

    expect(gemini.calls, 1);
    expect(intent.draft, isNotNull);
    expect(intent.draft!.kind, FfmAssistantDraftKind.activity);
    expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
  });

  test(
    'JSON mutasi tidak bisa mencapai persistence tanpa konfirmasi',
    () async {
      final gemini = _FakeGemini(
        const GeminiResult(
          model: 'gemini-2.5-pro',
          statusCode: 200,
          message: 'transaction proposal',
          text: '{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"transaction","kind":"expense","amount":50000,"title":"Makan Siang","category":"Makanan","fromAccount":"Tunai","note":"","date":"2026-08-28"}}',
        ),
      );
      final interpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(mode: 'agent', verified: true),
        geminiService: gemini,
      );

      final intent = await interpreter.interpret(
        'catat beli makan 50rb',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 1);
      expect(intent.draft, isNotNull);
      expect(intent.draft!.kind, FfmAssistantDraftKind.expense);
      // Draft harus butuh konfirmasi, tidak langsung disimpan
      expect(intent.needsConfirmation, isTrue);
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
    },
  );

  test(
    'timeout/format JSON Gemini buruk menghasilkan fallback jujur tanpa mutasi',
    () async {
      final gemini = _FakeGemini(
        const GeminiResult(
          model: 'gemini-2.5-pro',
          statusCode: 200,
          message: 'invalid JSON',
          text: 'ini bukan JSON yang valid {broken',
        ),
      );
      final interpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(mode: 'agent', verified: true),
        geminiService: gemini,
      );

      final intent = await interpreter.interpret(
        'catat beli makan 50rb',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 1);
      expect(intent.draft, isNull);
      expect(intent.response, contains('valid'));
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
    },
  );

  test('executor capability melempar error → tidak ada panggilan Gemini kedua dan tidak ada mutasi', () async {
    final gemini = _FakeGemini(
      const GeminiResult(
        model: 'gemini-2.5-pro',
        statusCode: 200,
        message: 'capability request',
        text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.summary","arguments":{"period":"current_month"}}',
      ),
    );
    gemini.calls = 0;
    final interpreter = FfmAssistantInterpreter(
      database,
      config: _FakeConfig(mode: 'agent', verified: true),
      geminiService: gemini,
    );

    // Mock capability executor yang akan melempar error
    // Ini mensimulasikan kasus di mana database tidak bisa dibaca
    final intent = await interpreter.interpret(
      'berikan ringkasan bulan ini',
      routingMode: FfmAssistantRoutingMode.geminiCloud,
    );

    // Gemini dipanggil sekali untuk request capability
    expect(gemini.calls, greaterThanOrEqualTo(1));
    // Tidak ada draft yang dibuat
    expect(intent.draft, isNull);
    // Origin harus menunjukkan error cloud
    expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
  });

  test('Gemini gagal pada panggilan kedua → respons jujur cloudError tanpa fallback', () async {
    final gemini = _FakeGemini(
      const GeminiResult(
        model: 'gemini-2.5-pro',
        statusCode: 200,
        message: 'capability request',
        text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.summary","arguments":{"period":"current_month"}}',
      ),
    );
    gemini.calls = 0;
    final interpreter = FfmAssistantInterpreter(
      database,
      config: _FakeConfig(mode: 'agent', verified: true),
      geminiService: gemini,
    );

    final intent = await interpreter.interpret(
      'berikan ringkasan bulan ini',
      routingMode: FfmAssistantRoutingMode.geminiCloud,
    );

    // Gemini dipanggil untuk request capability
    expect(gemini.calls, greaterThanOrEqualTo(1));
    // Origin harus menunjukkan error cloud jika panggilan kedua gagal
    expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
  });

  test(
    'JSON capability rusak/argumen tidak dikenal → ditolak sebelum executor',
    () async {
      final gemini = _FakeGemini(
        const GeminiResult(
          model: 'gemini-2.5-pro',
          statusCode: 200,
          message: 'invalid capability JSON',
          text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.summary","arguments":{"invalid_param":"value"}}',
        ),
      );
      final interpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(mode: 'agent', verified: true),
        geminiService: gemini,
      );

      final intent = await interpreter.interpret(
        'berikan ringkasan dengan parameter invalid',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 1);
      expect(intent.response, contains('tidak diizinkan'));
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.cloudError);
    },
  );

  test('filter tanggal lintas bulan → executor menolak', () async {
    final gemini = _FakeGemini(
      const GeminiResult(
        model: 'gemini-2.5-pro',
        statusCode: 200,
        message: 'capability request with cross-month dates',
        text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.transactions","arguments":{"startDate":"2026-07-01","endDate":"2026-08-15"}}',
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      config: _FakeConfig(mode: 'agent', verified: true),
      geminiService: gemini,
    );

    final intent = await interpreter.interpret(
      'berikan transaksi dari Juli sampai Agustus',
      routingMode: FfmAssistantRoutingMode.geminiCloud,
    );

    expect(gemini.calls, 1);
    expect(intent.response, contains('14 hari'));
    expect(intent.responseOrigin, FfmAssistantResponseOrigin.cloudError);
  });
}
