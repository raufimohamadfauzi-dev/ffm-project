import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/network/gemini_service.dart';
import 'package:ffm_manager/core/network/supabase_config.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_financial_snapshot_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_gemini_cloud_orchestrator.dart';
import 'package:ffm_manager/features/assistant/data/ffm_gemini_read_capability_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_grounding_validator.dart';

class _TestConfig extends SupabaseConfig {
  @override
  Future<String?> getGeminiKey() async => 'test-api-key';

  @override
  Future<String?> getGeminiModel() async => 'gemini-2.5-flash';

  @override
  Future<bool> isGeminiVerified() async => true;
}

class _MultiFunctionGeminiService extends GeminiService {
  _MultiFunctionGeminiService(this.functionCalls);

  final List<GeminiFunctionCall> functionCalls;

  @override
  Future<GeminiResult> chat({
    required String prompt,
    String? systemInstruction,
    List<Map<String, String>> history = const [],
    String? apiKey,
    String? model,
    List<Map<String, dynamic>>? tools,
  }) async {
    return GeminiResult(
      model: model ?? 'gemini-2.5-flash',
      statusCode: 200,
      message: 'OK',
      functionCalls: functionCalls,
    );
  }
}

class _TwoTurnGeminiService extends GeminiService {
  _TwoTurnGeminiService({
    required this.firstTurnFunctionCalls,
    required this.secondTurnText,
  });

  final List<GeminiFunctionCall> firstTurnFunctionCalls;
  final String secondTurnText;
  var callCount = 0;
  String? lastInstruction;

  @override
  Future<GeminiResult> chat({
    required String prompt,
    String? systemInstruction,
    List<Map<String, String>> history = const [],
    String? apiKey,
    String? model,
    List<Map<String, dynamic>>? tools,
  }) async {
    callCount++;
    lastInstruction = systemInstruction;
    if (callCount == 1) {
      return GeminiResult(
        model: model ?? 'gemini-2.5-flash',
        statusCode: 200,
        message: 'OK',
        functionCalls: firstTurnFunctionCalls,
      );
    }
    return GeminiResult(
      model: model ?? 'gemini-2.5-flash',
      statusCode: 200,
      message: 'OK',
      text: secondTurnText,
    );
  }
}

class _MockReadCapabilityService extends FfmGeminiReadCapabilityService {
  _MockReadCapabilityService(this.evidenceToReturn)
      : super(_FakeSnapshotService());

  final String evidenceToReturn;

  @override
  Future<String> execute(
    FfmAssistantReadCapabilityRequest request, {
    required String householdId,
    required DateTime now,
  }) async {
    return evidenceToReturn;
  }
}

class _FakeSnapshotService implements FfmAssistantFinancialSnapshotService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('P0 Multi-Function-Call Policy', () {
    test('Gemini mengembalikan lebih dari satu function call ditolak secara eksplisit', () async {
      final gemini = _MultiFunctionGeminiService([
        const GeminiFunctionCall(
          name: 'read_data',
          args: {'capabilityId': 'read.summary'},
        ),
        const GeminiFunctionCall(
          name: 'navigate',
          args: {'destination': 'summary'},
        ),
      ]);

      final orchestrator = FfmGeminiCloudOrchestrator(
        gemini: gemini,
        config: _TestConfig(),
        readCapabilities: _MockReadCapabilityService('evidence dummy'),
        clock: () => DateTime(2026, 9, 3),
      );

      final result = await orchestrator.run(
        userText: 'cek data dan buka ringkasan',
        boundedContext: 'konteks dummy',
        householdId: 'test-household',
      );

      expect(result.ok, isFalse);
      expect(result.errorMessage, contains('memanggil 2 fungsi sekaligus'));
      expect(result.errorMessage, contains('hanya satu tindakan per putaran'));
    });

    test('Gemini mengembalikan satu function call diproses dengan sukses', () async {
      final gemini = _TwoTurnGeminiService(
        firstTurnFunctionCalls: [
          const GeminiFunctionCall(
            name: 'read_data',
            args: {'capabilityId': 'read.summary'},
          ),
        ],
        secondTurnText: 'Saldo Anda adalah Rp 1.500.000.',
      );

      final orchestrator = FfmGeminiCloudOrchestrator(
        gemini: gemini,
        config: _TestConfig(),
        readCapabilities: _MockReadCapabilityService('Saldo total: 1500000'),
        clock: () => DateTime(2026, 9, 3),
      );

      final result = await orchestrator.run(
        userText: 'berapa saldo saya',
        boundedContext: 'konteks dummy',
        householdId: 'test-household',
      );

      expect(result.ok, isTrue);
      expect(result.usedReadCapability, 'read.summary');
      expect(result.readEvidence, 'Saldo total: 1500000');
      expect(result.text, 'Saldo Anda adalah Rp 1.500.000.');
    });

    test('Gemini mengembalikan function call tidak dikenal ditolak', () async {
      final gemini = _MultiFunctionGeminiService([
        const GeminiFunctionCall(name: 'delete_everything', args: {}),
      ]);

      final orchestrator = FfmGeminiCloudOrchestrator(
        gemini: gemini,
        config: _TestConfig(),
        readCapabilities: _MockReadCapabilityService('evidence dummy'),
        clock: () => DateTime(2026, 9, 3),
      );

      final result = await orchestrator.run(
        userText: 'hapus semua data',
        boundedContext: 'konteks dummy',
        householdId: 'test-household',
      );

      expect(result.ok, isFalse);
      expect(result.errorMessage, contains('tidak diizinkan'));
    });
  });

  group('P0 Carry Read Evidence into Grounding Validation', () {
    test('Grounding validator menolak klaim angka besar yang tidak ada dalam readEvidence', () {
      const toolEvidence = 'Saldo total: 1500000, pengeluaran: 350000';

      // Jawaban mengklaim angka palsu Rp 85.000.000
      final error = FfmAssistantGroundingValidator.validatePlainText(
        geminiText: 'Pengeluaran Anda bulan ini mencapai Rp 85.000.000.',
        verifiedFacts: null,
        analysisFacts: null,
        capabilityEvidence: toolEvidence,
      );

      expect(error, isNotNull);
      expect(error, contains('belum dapat diverifikasi dari data lokal'));
    });

    test('Grounding validator meloloskan klaim angka yang ada dalam readEvidence', () {
      const toolEvidence = 'Saldo total: 1500000, pengeluaran: 350000';

      final error = FfmAssistantGroundingValidator.validatePlainText(
        geminiText: 'Saldo Anda saat ini tercatat sebesar Rp 1.500.000.',
        verifiedFacts: null,
        analysisFacts: null,
        capabilityEvidence: toolEvidence,
      );

      expect(error, isNull);
    });
  });
}
