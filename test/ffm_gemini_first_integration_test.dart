// ignore_for_file: unused_element_parameter
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/network/gemini_service.dart';
import 'package:ffm_manager/core/network/supabase_config.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

class _FakeConfig extends SupabaseConfig {
  _FakeConfig({this.verified = true});

  final bool verified;

  @override
  Future<String?> getGeminiKey() async => 'test-key';

  @override
  Future<String?> getGeminiModel() async => 'gemini-2.5-flash';

  @override
  Future<bool> isGeminiVerified() async => verified;

  @override
  Future<String> getLlmMode() async => 'gemini';
}

class _TwoCallFakeGemini extends GeminiService {
  _TwoCallFakeGemini(this.first, this.second);

  final GeminiResult first;
  final GeminiResult second;
  var calls = 0;
  String? finalInstruction;

  @override
  Future<GeminiResult> chat({
    required String prompt,
    String? systemInstruction,
    List<Map<String, String>> history = const [],
    String? apiKey,
    String? model,
    List<Map<String, dynamic>>? tools,
    GeminiImageInput? image,
    int? maxOutputTokens,
  }) async {
    calls++;
    if (calls == 2) finalInstruction = systemInstruction;
    return calls == 1 ? first : second;
  }
}

class _SingleFakeGemini extends GeminiService {
  _SingleFakeGemini(this.result);

  final GeminiResult result;
  var calls = 0;

  @override
  Future<GeminiResult> chat({
    required String prompt,
    String? systemInstruction,
    List<Map<String, String>> history = const [],
    String? apiKey,
    String? model,
    List<Map<String, dynamic>>? tools,
    GeminiImageInput? image,
    int? maxOutputTokens,
  }) async {
    calls++;
    return result;
  }
}

class _ThrowingFakeGemini extends GeminiService {
  var calls = 0;

  @override
  Future<GeminiResult> chat({
    required String prompt,
    String? systemInstruction,
    List<Map<String, String>> history = const [],
    String? apiKey,
    String? model,
    List<Map<String, dynamic>>? tools,
    GeminiImageInput? image,
    int? maxOutputTokens,
  }) async {
    calls++;
    return const GeminiResult(
      model: 'gemini-2.5-flash',
      statusCode: 408,
      message: 'Timeout',
      diagnosticCode: 'timeout',
    );
  }
}

void main() {
  late AppDatabase database;

  setUp(() => database = createInMemoryDatabaseForTests());
  tearDown(() => database.close());

  test(
    'Gemini mode + sapaan + pertanyaan pendek tetap memanggil Gemini',
    () async {
      final gemini = _SingleFakeGemini(
        const GeminiResult(
          model: 'gemini-2.5-flash',
          statusCode: 200,
          message: 'ok',
          text: 'Jawaban Gemini untuk pertanyaan pendek.',
        ),
      );
      final interpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(),
        geminiService: gemini,
      );

      final intent = await interpreter.interpret(
        'Mau investasi apa sekarang?',
        lastAssistantMessage:
            'Hai! Ada yang bisa kubantu terkait keuangan keluarga hari ini?',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 1);
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
    },
  );

  test(
    'Gemini mode + perintah Aktivitas tetap memanggil Gemini lalu jadi draft',
    () async {
      final gemini = _SingleFakeGemini(
        const GeminiResult(
          model: 'gemini-2.5-flash',
          statusCode: 200,
          message: 'ok',
          text: '{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"activity","title":"Lari Pagi","durationMinutes":30}}',
        ),
      );
      final interpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(),
        geminiService: gemini,
      );

      final intent = await interpreter.interpret(
        'buat aktivitas Lari Pagi 30 menit',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 1);
      expect(intent.draft, isNotNull);
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
    },
  );

  test('JSON capability non-allowlist ditolak tanpa eksekusi dan tanpa panggilan kedua', () async {
    final gemini = _SingleFakeGemini(
      const GeminiResult(
        model: 'gemini-2.5-flash',
        statusCode: 200,
        message: 'ok',
        text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.unknown","arguments":{"period":"current_month"}}',
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      config: _FakeConfig(),
      geminiService: gemini,
    );

    final intent = await interpreter.interpret(
      'Tolong cek sesuatu.',
      routingMode: FfmAssistantRoutingMode.geminiCloud,
    );

    expect(gemini.calls, 1);
    expect(intent.response, contains('tidak diizinkan'));
    expect(intent.draft, isNull);
  });

  test(
    'capability read menghasilkan fakta bounded untuk panggilan kedua Gemini',
    () async {
      final gemini = _TwoCallFakeGemini(
        const GeminiResult(
          model: 'gemini-2.5-flash',
          statusCode: 200,
          message: 'ok',
          text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.summary","arguments":{"period":"current_month"}}',
        ),
        const GeminiResult(
          model: 'gemini-2.5-flash',
          statusCode: 200,
          message: 'ok',
          text: 'Berdasarkan ringkasan FFM, keuanganmu stabil.',
        ),
      );
      final interpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(),
        geminiService: gemini,
      );

      final intent = await interpreter.interpret(
        'Bagaimana kondisi keuangan bulan ini?',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 2);
      expect(
        gemini.finalInstruction,
        contains('HASIL CAPABILITY LOKAL TERVERIFIKASI'),
      );
      expect(
        gemini.finalInstruction,
        contains('Financial snapshot lokal bounded'),
      );
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
      expect(intent.pluginMetadata?['usedReadCapability'], 'read.summary');
    },
  );

  test('JSON mutasi tidak persist tanpa konfirmasi', () async {
    final gemini = _SingleFakeGemini(
      const GeminiResult(
        model: 'gemini-2.5-flash',
        statusCode: 200,
        message: 'ok',
        text: '{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"transaction","kind":"expense","amount":50000,"title":"Makan","category":"Makanan","fromAccount":"Tunai","date":"2026-08-28"}}',
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      config: _FakeConfig(),
      geminiService: gemini,
    );

    final intent = await interpreter.interpret(
      'catat pengeluaran makan 50rb',
      routingMode: FfmAssistantRoutingMode.geminiCloud,
    );

    expect(intent.draft, isNotNull);
    // Pastikan tidak ada transaksi terpersist sebelum konfirmasi
    final rows = await database.select(database.transactions).get();
    expect(rows, isEmpty);
  });

  test('riwayat tidak tertimpa sapaan saat sheet dibuka ulang', () async {
    final gemini = _SingleFakeGemini(
      const GeminiResult(
        model: 'gemini-2.5-flash',
        statusCode: 200,
        message: 'ok',
        text: 'Jawaban Gemini.',
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      config: _FakeConfig(),
      geminiService: gemini,
    );

    // Simulasi sheet dibuka ulang dengan conversationHistory terisi,
    // lastAssistantMessage adalah sapaan generic, tapi history harus menang
    final intent = await interpreter.interpret(
      'lanjutkan pembahasan tadi',
      conversationHistory:
          'User: berapa saldo?\nAssistant: Saldo tunai Rp1.000.000',
      lastAssistantMessage: 'Hai! Ada yang bisa kubantu?',
      routingMode: FfmAssistantRoutingMode.geminiCloud,
    );

    expect(gemini.calls, 1);
    expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
  });

  test('timeout/format JSON buruk fallback jujur tanpa mutasi', () async {
    final gemini = _ThrowingFakeGemini();
    final interpreter = FfmAssistantInterpreter(
      database,
      config: _FakeConfig(),
      geminiService: gemini,
    );

    final intent = await interpreter.interpret(
      'halo',
      routingMode: FfmAssistantRoutingMode.geminiCloud,
    );

    expect(gemini.calls, 1);
    expect(intent.draft, isNull);
    expect(intent.responseOrigin, FfmAssistantResponseOrigin.cloudError);
    final rows = await database.select(database.transactions).get();
    expect(rows, isEmpty);
  });

  test(
    'Tahap A: executor menghentikan alur saat capability gagal dibaca',
    () async {
      final gemini = _TwoCallFakeGemini(
        const GeminiResult(
          model: 'gemini-2.5-flash',
          statusCode: 200,
          message: 'ok',
          text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.transactions","arguments":{"period":"current_month","startDate":"2026-07-01","endDate":"2026-07-10"}}',
        ),
        const GeminiResult(
          model: 'gemini-2.5-flash',
          statusCode: 500,
          message: 'Data lokal tidak dapat dibaca dengan aman.',
        ),
      );
      final interpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(),
        geminiService: gemini,
        clock: () => DateTime(2026, 8, 15),
      );

      final intent = await interpreter.interpret(
        'cek transaksi',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 2);
      expect(intent.response, contains('tidak dapat dibaca'));
      expect(intent.draft, isNull);
      final rows = await database.select(database.transactions).get();
      expect(rows, isEmpty);
    },
  );

  test(
    'Tahap A: Gemini gagal pada panggilan kedua fallback cloudError',
    () async {
      final gemini = _TwoCallFakeGemini(
        const GeminiResult(
          model: 'gemini-2.5-flash',
          statusCode: 200,
          message: 'ok',
          text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.summary","arguments":{"period":"current_month"}}',
        ),
        const GeminiResult(
          model: 'gemini-2.5-flash',
          statusCode: 500,
          message: 'Internal error',
          diagnosticCode: 'chatError',
        ),
      );
      final interpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(),
        geminiService: gemini,
      );

      final intent = await interpreter.interpret(
        'ringkasan bulan ini',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 2);
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.cloudError);
      expect(intent.draft, isNull);
    },
  );

  test('Tahap A: JSON capability rusak ditolak sebelum executor', () async {
    final gemini = _SingleFakeGemini(
      const GeminiResult(
        model: 'gemini-2.5-flash',
        statusCode: 200,
        message: 'ok',
        text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.transactions","arguments":{"period":"current_month","unknownArg":"x"}}',
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      config: _FakeConfig(),
      geminiService: gemini,
    );

    final intent = await interpreter.interpret(
      'cek transaksi',
      routingMode: FfmAssistantRoutingMode.geminiCloud,
    );

    expect(gemini.calls, 1);
    expect(intent.response, contains('tidak diizinkan'));
    expect(intent.draft, isNull);
  });

  test('Tahap A: filter tanggal lintas bulan diteruskan dengan aman', () async {
    final gemini = _TwoCallFakeGemini(
      const GeminiResult(
        model: 'gemini-2.5-flash',
        statusCode: 200,
        message: 'ok',
        text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.transactions","arguments":{"period":"current_month","startDate":"2026-07-31","endDate":"2026-08-05"}}',
      ),
      const GeminiResult(
        model: 'gemini-2.5-flash',
        statusCode: 200,
        message: 'ok',
        text: 'Berikut ringkasan transaksi pada rentang yang diminta.',
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      config: _FakeConfig(),
      geminiService: gemini,
      clock: () => DateTime(2026, 8, 15),
    );

    final intent = await interpreter.interpret(
      'cek transaksi lintas bulan',
      routingMode: FfmAssistantRoutingMode.geminiCloud,
    );

    expect(gemini.calls, 2);
    expect(intent.response, contains('Berikut ringkasan transaksi'));
    expect(intent.draft, isNull);
  });
}
