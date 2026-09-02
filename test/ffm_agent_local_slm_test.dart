import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/network/gemini_service.dart';
import 'package:ffm_manager/core/network/supabase_config.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_answer_composer.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_financial_snapshot_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_local_model_gateway.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/hijri/domain/hijri_calendar_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_gemini_read_capability_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

class _FakeComposer implements FfmAssistantAnswerComposer {
  _FakeComposer([this.answer]);

  String? answer;
  bool needsFacts = true;
  String? lastFacts;
  String? lastQuestion;

  @override
  Future<String?> composeGroundedAnswer({
    required String question,
    required String facts,
  }) async {
    lastQuestion = question;
    lastFacts = facts;
    return answer;
  }
}

class _FakeProposalGateway implements FfmAssistantLocalModelGateway {
  const _FakeProposalGateway();

  @override
  Future<FfmAssistantModelProposal?> propose({required String input}) async {
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
  }) async => const FfmAssistantModelProposal(
    intent: FfmAssistantIntentType.help,
    confidence: .9,
    notes: 'Jawaban bantuan dari proposal SLM.',
  );
}

class _CountingGateway
    implements FfmAssistantLocalModelGateway, FfmAssistantAnswerComposer {
  final String answer;
  int proposeCalls = 0;
  int composeCalls = 0;

  _CountingGateway(this.answer);

  @override
  Future<FfmAssistantModelProposal?> propose({required String input}) async {
    proposeCalls++;
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
  }) async {
    proposeCalls++;
    return null;
  }

  @override
  Future<String?> composeGroundedAnswer({
    required String question,
    required String facts,
  }) async {
    composeCalls++;
    return answer;
  }
}

class _FakeConfig extends SupabaseConfig {
  @override
  Future<String?> getGeminiKey() async => 'test-key';

  @override
  Future<String?> getGeminiModel() async => 'gemini-2.5-flash';

  @override
  Future<bool> isGeminiVerified() async => true;
}

class _FakeGemini extends GeminiService {
  int calls = 0;

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
    return const GeminiResult(
      model: 'gemini-2.5-flash',
      statusCode: 200,
      message: 'ok',
      text: 'Jawaban Gemini.',
    );
  }
}

class _ReadRequestGemini extends GeminiService {
  int calls = 0;
  String? finalInstruction;

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
    if (calls == 1) {
      return const GeminiResult(
        model: 'gemini-2.5-flash',
        statusCode: 200,
        message: 'ok',
        text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.summary","arguments":{"period":"current_month"}}',
      );
    }
    finalInstruction = systemInstruction;
    return const GeminiResult(
      model: 'gemini-2.5-flash',
      statusCode: 200,
      message: 'ok',
      text: 'Berdasarkan ringkasan FFM, data bulan ini masih perlu dilengkapi.',
    );
  }
}

class _ForbiddenReadRequestGemini extends GeminiService {
  int calls = 0;

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
    return const GeminiResult(
      model: 'gemini-2.5-flash',
      statusCode: 200,
      message: 'ok',
      text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"mutate.save_draft","arguments":{}}',
    );
  }
}

class _TransactionReadRequestGemini extends GeminiService {
  int calls = 0;
  String? finalInstruction;

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
    if (calls == 1) {
      return const GeminiResult(
        model: 'gemini-2.5-flash',
        statusCode: 200,
        message: 'ok',
        text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.transactions","arguments":{"period":"current_month"}}',
      );
    }
    finalInstruction = systemInstruction;
    return const GeminiResult(
      model: 'gemini-2.5-flash',
      statusCode: 200,
      message: 'ok',
      text: 'Berikut ringkasan transaksi yang tersedia.',
    );
  }
}

class _DateRangeReadRequestGemini extends GeminiService {
  int calls = 0;
  String? finalInstruction;

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
    if (calls == 1) {
      return const GeminiResult(
        model: 'gemini-2.5-flash',
        statusCode: 200,
        message: 'ok',
        text: '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.transactions","arguments":{"period":"current_month","startDate":"2026-08-10","endDate":"2026-08-20"}}',
      );
    }
    finalInstruction = systemInstruction;
    return const GeminiResult(
      model: 'gemini-2.5-flash',
      statusCode: 200,
      message: 'ok',
      text: 'Berikut rangkuman transaksi pada rentang yang diminta.',
    );
  }
}

void main() {
  late AppDatabase database;

  setUp(() {
    database = createInMemoryDatabaseForTests();
  });

  tearDown(() async {
    await database.close();
  });

  test('mode Agent memakai composer SLM untuk pertanyaan bebas', () async {
    final composer = _FakeComposer('Ringkasan transaksi sudah siap.');
    final interpreter = FfmAssistantInterpreter(
      database,
      answerComposer: composer,
      slmReadyCheck: () async => true,
    );

    final intent = await interpreter.interpret(
      'jarak bumi ke bulan berapa kilometer?',
      routingMode: FfmAssistantRoutingMode.agent,
      currentDestination: FfmAssistantDestination.summary,
      pageContext: 'Halaman utama FFM hari ini.',
    );

    expect(intent.type, FfmAssistantIntentType.queryData);
    expect(intent.responseOrigin, FfmAssistantResponseOrigin.localSlm);
    expect(intent.responseMode, FfmAssistantResponseMode.localModel);
    expect(intent.response, 'Ringkasan transaksi sudah siap.');
  });

  test(
    'mode Agent memakai proposal gateway saat composer tak tersedia',
    () async {
      final gateway = const _FakeProposalGateway();
      final interpreter = FfmAssistantInterpreter(
        database,
        modelGateway: gateway,
        slmReadyCheck: () async => true,
      );

      final intent = await interpreter.interpret(
        'apa ibu kota negara Madagaskar?',
        routingMode: FfmAssistantRoutingMode.agent,
      );

      expect(intent.responseOrigin, FfmAssistantResponseOrigin.localSlm);
      expect(intent.responseMode, FfmAssistantResponseMode.localModel);
      expect(intent.response, 'Jawaban bantuan dari proposal SLM.');
      expect(intent.type, FfmAssistantIntentType.help);
    },
  );

  test(
    'mode Agent yang SLM-nya gagal jatuh ke unknown tanpa pindah provider',
    () async {
      final composer = _FakeComposer(null);
      final interpreter = FfmAssistantInterpreter(
        database,
        answerComposer: composer,
        slmReadyCheck: () async => true,
      );

      final intent = await interpreter.interpret(
        'ular mana yang paling berbisa di dunia?',
        routingMode: FfmAssistantRoutingMode.agent,
      );

      expect(intent.type, FfmAssistantIntentType.unknown);
      expect(
        intent.responseOrigin,
        isNot(FfmAssistantResponseOrigin.geminiCloud),
      );
    },
  );

  test(
    'mode Agent tidak memanggil Gemini walau Gemini sudah diverifikasi',
    () async {
      final gemini = _FakeGemini();
      final slm = _CountingGateway('Jawaban SLM yang natural.');
      final interpreter = FfmAssistantInterpreter(
        database,
        modelGateway: slm,
        answerComposer: slm,
        geminiService: gemini,
        config: _FakeConfig(),
        slmReadyCheck: () async => true,
      );

      final intent = await interpreter.interpret(
        'berapa suhu rata-rata planet mars?',
        routingMode: FfmAssistantRoutingMode.agent,
        currentDestination: FfmAssistantDestination.summary,
        pageContext: 'Halaman utama FFM hari ini.',
      );

      expect(gemini.calls, 0);
      expect(slm.composeCalls, 1);
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.localSlm);
    },
  );

  test('mode Gemini tetap tidak memakai SLM untuk pertanyaan bebas', () async {
    final gemini = _FakeGemini();
    final slm = _CountingGateway('Jawaban SLM.');
    final interpreter = FfmAssistantInterpreter(
      database,
      modelGateway: slm,
      answerComposer: slm,
      geminiService: gemini,
      config: _FakeConfig(),
      slmReadyCheck: () async => true,
    );

    final intent = await interpreter.interpret(
      'apa ibu kota negara Madagaskar?',
      routingMode: FfmAssistantRoutingMode.geminiCloud,
    );

    expect(gemini.calls, 1);
    expect(slm.composeCalls, 0);
    expect(slm.proposeCalls, 0);
    expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
  });

  test(
    'mode Gemini tidak membiarkan sapaan lokal menelan pertanyaan pendek',
    () async {
      final gemini = _FakeGemini();
      final interpreter = FfmAssistantInterpreter(
        database,
        geminiService: gemini,
        config: _FakeConfig(),
      );

      final intent = await interpreter.interpret(
        'Mau investasi apa sekarang?',
        lastAssistantMessage:
            'Hai! Ada yang bisa kubantu terkait keuangan keluarga hari ini?',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 1);
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
      expect(intent.response, 'Jawaban Gemini.');
    },
  );

  test(
    'dialog Agent hanya menangani respons afirmatif yang berdiri sendiri',
    () async {
      final interpreter = FfmAssistantInterpreter(database);

      final intent = await interpreter.interpret(
        'Mau investasi apa sekarang?',
        lastAssistantMessage:
            'Hai! Ada yang bisa kubantu terkait keuangan keluarga hari ini?',
        routingMode: FfmAssistantRoutingMode.agent,
      );

      expect(intent.response, isNot(contains('Sip! Aku siap membantu')));
    },
  );

  test(
    'Gemini hanya dapat meminta read.summary lalu menerima fakta bounded',
    () async {
      final gemini = _ReadRequestGemini();
      final interpreter = FfmAssistantInterpreter(
        database,
        geminiService: gemini,
        config: _FakeConfig(),
      );

      final intent = await interpreter.interpret(
        'Bagaimana kondisi keuangan saya bulan ini?',
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
      expect(intent.response, contains('Berdasarkan ringkasan FFM'));
      expect(intent.pluginMetadata?['usedReadCapability'], 'read.summary');
    },
  );

  test(
    'request capability mutasi Gemini ditolak tanpa panggilan kedua',
    () async {
      final gemini = _ForbiddenReadRequestGemini();
      final interpreter = FfmAssistantInterpreter(
        database,
        geminiService: gemini,
        config: _FakeConfig(),
      );

      final intent = await interpreter.interpret(
        'Tolong catat pengeluaran.',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 1);
      expect(intent.response, contains('Capability Gemini tidak diizinkan'));
      expect(intent.draft, isNull);
    },
  );

  test(
    'Gemini dapat meminta digest transaksi bounded bulan berjalan',
    () async {
      final gemini = _TransactionReadRequestGemini();
      final interpreter = FfmAssistantInterpreter(
        database,
        geminiService: gemini,
        config: _FakeConfig(),
      );

      final intent = await interpreter.interpret(
        'Transaksi terakhir bulan ini bagaimana?',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 2);
      expect(
        gemini.finalInstruction,
        contains('Transaction digest lokal bounded'),
      );
      expect(intent.pluginMetadata?['usedReadCapability'], 'read.transactions');
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
    },
  );

  test('Gemini dapat meminta rentang tanggal transaksi bounded', () async {
    final gemini = _DateRangeReadRequestGemini();
    final interpreter = FfmAssistantInterpreter(
      database,
      geminiService: gemini,
      config: _FakeConfig(),
      clock: () => DateTime(2026, 8, 28),
    );

    final intent = await interpreter.interpret(
      'Bagaimana transaksi pertengahan bulan ini?',
      routingMode: FfmAssistantRoutingMode.geminiCloud,
    );

    expect(gemini.calls, 2);
    expect(gemini.finalInstruction, contains('rentang=2026-08-10..2026-08-20'));
    expect(intent.pluginMetadata?['usedReadCapability'], 'read.transactions');
  });

  test('filter capability transaksi menolak rentang di luar bulan atau terlalu panjang', () async {
    final outsideMonth =
        FfmAssistantProposalJsonService.parseReadCapabilityRequest(
          '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.transactions","arguments":{"period":"current_month","startDate":"2026-07-31","endDate":"2026-08-01"}}',
        );
    final tooLong = FfmAssistantProposalJsonService.parseReadCapabilityRequest(
      '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.transactions","arguments":{"period":"current_month","startDate":"2026-08-01","endDate":"2026-08-20"}}',
    );

    expect(outsideMonth.request, isNotNull);
    await expectLater(
      FfmGeminiReadCapabilityService(
        FfmAssistantFinancialSnapshotService(
          database,
          HijriCalendarService(database),
        ),
      ).execute(
        outsideMonth.request!,
        householdId: 'test-household',
        now: DateTime(2026, 8, 28),
      ),
      throwsA(isA<StateError>()),
    );
    expect(tooLong.request, isNull);
    expect(tooLong.error, contains('maksimal 14 hari'));
  });

  test('Gemini hanya boleh meminta capability baca yang ada di allowlist bounded', () {
    expect(FfmAssistantProposalJsonService.geminiReadCapabilityIds, {
      'read.summary',
      'read.transactions',
      'read.hijriDate',
      'read.goals',
      'read.liabilities',
      'read.debts',
      'read.receivables',
      'read.receivable',
      'read.activity',
      'read.activities',
      'read.reminders',
      'read.reminder',
      'read.assets',
      'read.asset',
      'read.budget',
      'read.budgets',
    });

    for (final capabilityId in const [
      'read.accounts',
      'read.categories',
      'mutate.transaction',
      'mutate.save_draft',
    ]) {
      final result = FfmAssistantProposalJsonService.parseReadCapabilityRequest(
        '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"$capabilityId","arguments":{}}',
      );

      expect(result.request, isNull, reason: capabilityId);
      expect(result.error, contains('tidak diizinkan'), reason: capabilityId);
    }
  });

  test('FfmGeminiReadCapabilityService dapat mengeksekusi digest target, hutang, piutang, dan aktivitas', () async {
    final service = FfmGeminiReadCapabilityService(
      FfmAssistantFinancialSnapshotService(
        database,
        HijriCalendarService(database),
      ),
    );

    final goalsReq = FfmAssistantProposalJsonService.parseReadCapabilityRequest(
      '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.goals","arguments":{}}',
    );
    expect(goalsReq.request, isNotNull);
    final goalsDigest = await service.execute(
      goalsReq.request!,
      householdId: 'test-household',
      now: DateTime(2026, 8, 28),
    );
    expect(goalsDigest, contains('Goals digest'));

    final debtsReq = FfmAssistantProposalJsonService.parseReadCapabilityRequest(
      '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.liabilities","arguments":{}}',
    );
    expect(debtsReq.request, isNotNull);
    final debtsDigest = await service.execute(
      debtsReq.request!,
      householdId: 'test-household',
      now: DateTime(2026, 8, 28),
    );
    expect(debtsDigest, contains('Liabilities digest'));

    final recReq = FfmAssistantProposalJsonService.parseReadCapabilityRequest(
      '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.receivables","arguments":{}}',
    );
    expect(recReq.request, isNotNull);
    final recDigest = await service.execute(
      recReq.request!,
      householdId: 'test-household',
      now: DateTime(2026, 8, 28),
    );
    expect(recDigest, contains('Receivables digest'));

    final actReq = FfmAssistantProposalJsonService.parseReadCapabilityRequest(
      '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.activities","arguments":{}}',
    );
    expect(actReq.request, isNotNull);
    final actDigest = await service.execute(
      actReq.request!,
      householdId: 'test-household',
      now: DateTime(2026, 8, 28),
    );
    expect(actDigest, contains('Activities digest'));
  });

  test(
    'SLM yang tidak siap tidak dipanggil dan tetap unknown di mode Agent',
    () async {
      final slm = _CountingGateway('Jawaban SLM.');
      final interpreter = FfmAssistantInterpreter(
        database,
        modelGateway: slm,
        answerComposer: slm,
        slmReadyCheck: () async => false,
      );

      final intent = await interpreter.interpret(
        'berapa suhu rata-rata di kutub utara?',
        routingMode: FfmAssistantRoutingMode.agent,
      );

      expect(slm.composeCalls, 0);
      expect(slm.proposeCalls, 0);
      expect(intent.type, FfmAssistantIntentType.unknown);
    },
  );

  test(
    'perintah bayar tanpa nominal dibuat draft oleh rule, bukan dijawab bebas',
    () async {
      final slm = _CountingGateway('Jangan dipakai untuk perintah bayar.');
      final gemini = _FakeGemini();
      final interpreter = FfmAssistantInterpreter(
        database,
        modelGateway: slm,
        answerComposer: slm,
        geminiService: gemini,
        config: _FakeConfig(),
        slmReadyCheck: () async => true,
      );

      final intent = await interpreter.interpret(
        'bayar tagihan listrik dari Tunai',
        routingMode: FfmAssistantRoutingMode.agent,
      );

      expect(slm.composeCalls, 0);
      expect(gemini.calls, 0);
      expect(intent.draft, isNotNull);
      expect(intent.draft?.kind, FfmAssistantDraftKind.expense);
    },
  );

  test('pertanyaan opini berisi kata arah tetap diteruskan ke Gemini (gate deny mutasi ditujukan ke teks bebas tetap kontrak service)', () async {
    final gemini = _FakeGemini();
    final slm = _CountingGateway('Jangan dipakai untuk pertanyaan opini.');
    final interpreter = FfmAssistantInterpreter(
      database,
      modelGateway: slm,
      answerComposer: slm,
      geminiService: gemini,
      config: _FakeConfig(),
      slmReadyCheck: () async => true,
    );

    final intent = await interpreter.interpret(
      'Menurut kamu, sebaiknya saya jual motor ini?',
      routingMode: FfmAssistantRoutingMode.geminiCloud,
    );

    expect(gemini.calls, 1);
    expect(slm.composeCalls, 0);
    expect(slm.proposeCalls, 0);
    expect(intent.draft, isNull);
    expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
  });
}
