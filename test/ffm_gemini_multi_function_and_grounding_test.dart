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
    GeminiImageInput? image,
    int? maxOutputTokens,
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
    GeminiImageInput? image,
    int? maxOutputTokens,
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

    test(
      'Gemini mengembalikan satu function call diproses dengan sukses',
      () async {
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
      },
    );

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

    test(
      'Grounding validator meloloskan klaim angka yang ada dalam readEvidence',
      () {
        const toolEvidence = 'Saldo total: 1500000, pengeluaran: 350000';

        final error = FfmAssistantGroundingValidator.validatePlainText(
          geminiText: 'Saldo Anda saat ini tercatat sebesar Rp 1.500.000.',
          verifiedFacts: null,
          analysisFacts: null,
          capabilityEvidence: toolEvidence,
        );

        expect(error, isNull);
      },
    );
  });

  group('F2 Multi-Step Bounded Tool Loop', () {
    test('Gemini memanggil beberapa read capability berurutan dan seluruh evidence terakumulasi', () async {
      var callCount = 0;
      final multiStepGemini = _CustomStepGeminiService((step) {
        callCount++;
        if (step == 1) {
          return GeminiResult(
            model: 'gemini-2.5-flash',
            statusCode: 200,
            message: 'OK',
            functionCalls: const [
              GeminiFunctionCall(
                name: 'read_data',
                args: {'capabilityId': 'read.summary'},
              ),
            ],
          );
        } else if (step == 2) {
          return GeminiResult(
            model: 'gemini-2.5-flash',
            statusCode: 200,
            message: 'OK',
            functionCalls: const [
              GeminiFunctionCall(
                name: 'read_data',
                args: {'capabilityId': 'read.goals'},
              ),
            ],
          );
        }
        return const GeminiResult(
          model: 'gemini-2.5-flash',
          statusCode: 200,
          message: 'OK',
          text: 'Arus kas Anda Rp 2.000.000 cukup untuk target tabungan Rp 500.000.',
        );
      });

      final multiMockService = _DynamicMockReadCapabilityService({
        'read.summary': 'Ringkasan: Arus kas bersih 2000000',
        'read.goals': 'Target: Target tabungan 500000 tercapai 60%',
      });

      final orchestrator = FfmGeminiCloudOrchestrator(
        gemini: multiStepGemini,
        config: _TestConfig(),
        readCapabilities: multiMockService,
        clock: () => DateTime(2026, 9, 3),
      );

      final result = await orchestrator.run(
        userText: 'Apakah arus kas saya cukup untuk target bulan ini?',
        boundedContext: 'konteks dummy',
        householdId: 'test-household',
      );

      expect(result.ok, isTrue);
      expect(callCount, 3);
      expect(result.usedReadCapability, contains('read.summary'));
      expect(result.usedReadCapability, contains('read.goals'));
      expect(result.readEvidence, contains('Arus kas bersih 2000000'));
      expect(result.readEvidence, contains('Target tabungan 500000'));
      expect(
        result.text,
        'Arus kas Anda Rp 2.000.000 cukup untuk target tabungan Rp 500.000.',
      );

      // Grounding validation mencakup angka dari kedua evidence
      final groundError = FfmAssistantGroundingValidator.validatePlainText(
        geminiText: result.text!,
        verifiedFacts: null,
        analysisFacts: null,
        capabilityEvidence: result.readEvidence,
      );
      expect(groundError, isNull);
    });

    test(
      'Perulangan capability yang identik dihentikan oleh proteksi anti-loop',
      () async {
        var callCount = 0;
        final loopingGemini = _CustomStepGeminiService((_) {
          callCount++;
          return const GeminiResult(
            model: 'gemini-2.5-flash',
            statusCode: 200,
            message: 'OK',
            functionCalls: [
              GeminiFunctionCall(
                name: 'read_data',
                args: {'capabilityId': 'read.summary'},
              ),
            ],
          );
        });

        final orchestrator = FfmGeminiCloudOrchestrator(
          gemini: loopingGemini,
          config: _TestConfig(),
          readCapabilities: _MockReadCapabilityService('Ringkasan data'),
          clock: () => DateTime(2026, 9, 3),
        );

        final result = await orchestrator.run(
          userText: 'cek ringkasan terus menerus',
          boundedContext: 'konteks dummy',
          householdId: 'test-household',
        );

        expect(result.ok, isTrue);
        // Dipanggil 2 kali (awal + 1 retry identik yang langsung di-break)
        expect(callCount, 2);
        expect(result.usedReadCapability, 'read.summary');
      },
    );

    test('Repeated read.dailyNotes request tidak mengembalikan JSON mentah dan mengisi teks dengan evidence lokal', () async {
      final loopingTextGemini = _CustomStepGeminiService((_) {
        return const GeminiResult(
          model: 'gemini-2.5-flash',
          statusCode: 200,
          message: 'OK',
          text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.dailyNotes","arguments":{}}',
        );
      });

      final orchestrator = FfmGeminiCloudOrchestrator(
        gemini: loopingTextGemini,
        config: _TestConfig(),
        readCapabilities: _MockReadCapabilityService(
          'Panen 100kg apel pada 14 September',
        ),
        clock: () => DateTime(2026, 9, 3),
      );

      final result = await orchestrator.run(
        userText: 'catatan harian isinya apa saja terbaru',
        boundedContext: 'konteks dummy',
        householdId: 'test-household',
      );

      expect(result.ok, isTrue);
      expect(result.text, isNot(contains('read_capability_request')));
      expect(result.text, contains('Panen 100kg apel pada 14 September'));
    });

    test('Anti-loop atau fallback reminder digest membersihkan karakter pipa dan kode error Flutter', () async {
      final loopingGemini = _CustomStepGeminiService((_) {
        return const GeminiResult(
          model: 'gemini-2.5-flash',
          statusCode: 200,
          message: 'OK',
          functionCalls: [
            GeminiFunctionCall(
              name: 'read_data',
              args: {'capabilityId': 'read.reminders'},
            ),
          ],
        );
      });

      const rawEvidence =
          'Reminders digest (pengingat aktif): Pengingat Panen Pepaya & Cek Keuangan|waktu=18/09/2026 08:00|ulang=sekali|catatan=FLUTTER_UNHANDLED_ERROR: Invalid argument(s): string is not well-formed UTF-16; Beli Token Listrik|waktu=19/09/2026 10:00|ulang=bulanan|catatan=Token PLN.';

      final orchestrator = FfmGeminiCloudOrchestrator(
        gemini: loopingGemini,
        config: _TestConfig(),
        readCapabilities: _MockReadCapabilityService(rawEvidence),
        clock: () => DateTime(2026, 9, 18),
      );

      final result = await orchestrator.run(
        userText: 'sekarang di halaman pengingat ada berapa alaram aktif?',
        boundedContext: 'konteks dummy',
        householdId: 'test-household',
      );

      expect(result.ok, isTrue);
      expect(result.text, isNot(contains('|waktu=')));
      expect(result.text, isNot(contains('|ulang=')));
      expect(result.text, isNot(contains('FLUTTER_UNHANDLED_ERROR')));
      expect(result.text, contains('Pengingat Panen Pepaya & Cek Keuangan'));
      expect(result.text, contains('Beli Token Listrik'));
      expect(result.text, contains('18/09/2026 08:00'));
    });
  });
}

class _CustomStepGeminiService extends GeminiService {
  _CustomStepGeminiService(this.handler);
  final GeminiResult Function(int step) handler;
  var stepCount = 0;

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
    stepCount++;
    return handler(stepCount);
  }
}

class _DynamicMockReadCapabilityService extends FfmGeminiReadCapabilityService {
  _DynamicMockReadCapabilityService(this.evidences)
    : super(_FakeSnapshotService());
  final Map<String, String> evidences;

  @override
  Future<String> execute(
    FfmAssistantReadCapabilityRequest request, {
    required String householdId,
    required DateTime now,
  }) async {
    return evidences[request.capabilityId] ?? 'Evidence kosong';
  }
}
