// ignore_for_file: unused_element_parameter
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/network/gemini_service.dart';
import 'package:ffm_manager/core/network/supabase_config.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/chat/ffm_assistant_process_disclosure.dart';

class _FakeConfig extends SupabaseConfig {
  _FakeConfig();
  @override
  Future<String?> getGeminiKey() async => 'test-key';
  @override
  Future<String?> getGeminiModel() async => 'gemini-2.5-flash';
  @override
  Future<bool> isGeminiVerified() async => true;
  @override
  Future<String> getLlmMode() async => 'gemini';
}

class _FakeGemini extends GeminiService {
  _FakeGemini(this.result);
  final GeminiResult result;
  @override
  Future<GeminiResult> chat({
    required String prompt,
    String? systemInstruction,
    List<Map<String, String>> history = const [],
    String? apiKey,
    String? model,
  }) async =>
      result;
}

void main() {
  late AppDatabase database;
  setUp(() => database = createInMemoryDatabaseForTests());
  tearDown(() => database.close());

  test('Tahap B: draft Gemini terlihat sebagai Menunggu konfirmasi', () async {
    final gemini = _FakeGemini(
      const GeminiResult(
        model: 'gemini-2.5-flash',
        statusCode: 200,
        message: 'ok',
        text:
            '{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"transaction","kind":"expense","amount":25000,"title":"Kopi","category":"Makanan","fromAccount":"Tunai","date":"2026-08-28"}}',
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      config: _FakeConfig(),
      geminiService: gemini,
    );
    final intent = await interpreter.interpret(
      'catat kopi 25rb',
      routingMode: FfmAssistantRoutingMode.geminiCloud,
    );
    expect(intent.draft, isNotNull);
    // UI sheet harus menampilkan draft sebagai Menunggu konfirmasi, bukan langsung disimpan
    expect(intent.type, isNot(FfmAssistantIntentType.unknown));
    final rows = await database.select(database.transactions).get();
    expect(rows, isEmpty, reason: 'draft tidak boleh persist sebelum konfirmasi');
  });

  test('Tahap B: capability yang dipakai hanya sebagai metadata aman', () async {
    const trace = FfmAssistantProcessTrace(
      origin: FfmAssistantResponseOrigin.geminiCloud,
      elapsed: Duration(milliseconds: 100),
      events: [],
      pluginCategory: 'read.summary',
    );
    expect(trace.pluginCategory, isNot(contains('SELECT')));
    expect(trace.pluginCategory, isNot(contains('rekening')));
  });

  testWidgets('Tahap B: error Gemini tidak menyebut data lokal', (tester) async {
    const trace = FfmAssistantProcessTrace(
      origin: FfmAssistantResponseOrigin.cloudError,
      elapsed: Duration(milliseconds: 10),
      events: [],
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FfmAssistantProcessDisclosure(trace: trace))),
    );
    expect(find.textContaining('Gemini Cloud gagal'), findsOneWidget);
    expect(find.textContaining('Data lokal FFM'), findsNothing);
  });

  testWidgets('Tahap B: jawaban lokal tidak menyebut Gemini', (tester) async {
    const trace = FfmAssistantProcessTrace(
      origin: FfmAssistantResponseOrigin.agentOrchestrator,
      elapsed: Duration(milliseconds: 10),
      events: [],
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FfmAssistantProcessDisclosure(trace: trace))),
    );
    expect(find.textContaining('Data lokal FFM'), findsOneWidget);
    expect(find.textContaining('Gemini Cloud'), findsNothing);
  });
}
