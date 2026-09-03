import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/network/gemini_service.dart';
import 'package:ffm_manager/core/network/supabase_config.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

class _FakeConfig extends SupabaseConfig {
  _FakeConfig();

  @override
  Future<String?> getGeminiKey() async => 'test-key';

  @override
  Future<String?> getGeminiModel() async => 'gemini-2.5-flash';

  @override
  Future<bool> isGeminiVerified() async => true;

  @override
  Future<String> getLlmMode() async => 'agent';
}

class _FakeGemini extends GeminiService {
  _FakeGemini(this.result);

  final GeminiResult result;
  var calls = 0;
  String? receivedSystemInstruction;

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
    receivedSystemInstruction = systemInstruction;
    return result;
  }
}

void main() {
  late AppDatabase database;
  late FfmAssistantInterpreter interpreter;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    interpreter = FfmAssistantInterpreter(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('context switching: explicit intent mengalahkan page context', () {
    test(
      'Halaman Target + "catat pemasukan 500 rb" → transaction income',
      () async {
        final intent = await interpreter.interpret(
          'catat pemasukan 500 rb',
          currentDestination: FfmAssistantDestination.goals,
        );

        expect(intent.type, FfmAssistantIntentType.createIncome);
        expect(intent.draft?.kind, FfmAssistantDraftKind.income);
        expect(intent.draft?.amount, 500000);
      },
    );

    test(
      'Halaman Aktivitas + "catat pengeluaran pupuk 150 rb" → expense',
      () async {
        final intent = await interpreter.interpret(
          'catat pengeluaran pupuk 150 rb',
          currentDestination: FfmAssistantDestination.activity,
        );

        expect(intent.type, FfmAssistantIntentType.createExpense);
        expect(intent.draft?.kind, FfmAssistantDraftKind.expense);
        expect(intent.draft?.amount, 150000);
        expect(intent.draft?.note?.contains('pupuk'), isTrue);
      },
    );

    test('Halaman Transaksi + "buat target 20 juta" → goal', () async {
      final intent = await interpreter.interpret(
        'buat target 20 juta liburan',
        currentDestination: FfmAssistantDestination.transactions,
      );

      expect(intent.type, FfmAssistantIntentType.createGoal);
      expect(intent.draft?.kind, FfmAssistantDraftKind.goal);
      expect(intent.draft?.amount, 20000000);
    });
  });

  group('single transaction: nominal + entity generik', () {
    test('catat pemasukan 500 rb dari cabai → income 500000 + cabai', () async {
      final intent = await interpreter.interpret(
        'catat pemasukan 500 rb dari cabai',
      );

      expect(intent.type, FfmAssistantIntentType.createIncome);
      expect(intent.draft?.kind, FfmAssistantDraftKind.income);
      expect(intent.draft?.amount, 500000);
      expect(intent.draft?.note?.toLowerCase(), contains('cabai'));
    });

    test(
      'catat pemasukan 600 rb dari bansos → income 600000 + bansos',
      () async {
        final intent = await interpreter.interpret(
          'catat pemasukan 600 rb dari bansos',
        );

        expect(intent.type, FfmAssistantIntentType.createIncome);
        expect(intent.draft?.kind, FfmAssistantDraftKind.income);
        expect(intent.draft?.amount, 600000);
        expect(intent.draft?.note?.toLowerCase(), contains('bansos'));
      },
    );

    test('catat pengeluaran pupuk 150 rb → expense 150000 + pupuk', () async {
      final intent = await interpreter.interpret(
        'catat pengeluaran pupuk 150 rb',
      );

      expect(intent.type, FfmAssistantIntentType.createExpense);
      expect(intent.draft?.kind, FfmAssistantDraftKind.expense);
      expect(intent.draft?.amount, 150000);
      expect(intent.draft?.note?.toLowerCase(), contains('pupuk'));
    });
  });

  group('multi transaction: satu kalimat menjadi draft terpisah', () {
    test(
      'catat pemasukan 500 rb dari cabai dan 600 rb dari bansos → 2 draft',
      () async {
        final result = await interpreter.interpretMany(
          'catat pemasukan 500 rb dari cabai dan 600 rb dari bansos',
        );

        expect(result.intents, hasLength(2));
        for (final intent in result.intents) {
          expect(intent.type, FfmAssistantIntentType.createIncome);
          expect(intent.draft?.kind, FfmAssistantDraftKind.income);
        }
        final amounts = result.intents.map((e) => e.draft?.amount).toSet();
        expect(amounts, containsAll(<int?>{500000, 600000}));
        final notes = result.intents
            .map((e) => e.draft?.note?.toLowerCase() ?? '')
            .join(' | ');
        expect(notes, contains('cabai'));
        expect(notes, contains('bansos'));
      },
    );
  });

  group(
    'pending draft safety: explicit new intent tidak diserap draft lama',
    () {
      test('active goal draft + "catat pemasukan 500 rb" diklasifikasi mutationProposal, bukan draftReview', () async {
        final gemini = _FakeGemini(
          const GeminiResult(
            model: 'gemini-2.5-flash',
            statusCode: 200,
            message: 'ok',
            text: 'Baik, saya buat draft pemasukan.',
          ),
        );
        final cloudInterpreter = FfmAssistantInterpreter(
          database,
          config: _FakeConfig(),
          geminiService: gemini,
        );

        await cloudInterpreter.interpret(
          'catat pemasukan 500 rb',
          routingMode: FfmAssistantRoutingMode.geminiCloud,
          activeDraft: FfmAssistantDraft(
            kind: FfmAssistantDraftKind.goal,
            createdAt: DateTime(2026, 8, 31),
            title: 'Beli Motor',
            amount: 20000000,
          ),
        );

        expect(gemini.calls, greaterThanOrEqualTo(1));
        expect(
          gemini.receivedSystemInstruction,
          contains('"requestClass":"mutationProposal"'),
        );
        expect(
          gemini.receivedSystemInstruction,
          isNot(contains('"requestClass":"draftReview"')),
        );
      });

      test('agent mode: pending goal kurang nominal + explicit transaction → transaksi baru', () async {
        final pending = FfmAssistantPendingDialog(
          originalRequest: 'buat target liburan',
          prompt: 'Berapa nominal targetnya?',
          missingFields: const ['nominal'],
          draft: FfmAssistantDraft(
            kind: FfmAssistantDraftKind.goal,
            createdAt: DateTime(2026, 8, 31),
            title: 'liburan',
          ),
        );

        final resolved = await interpreter.resolvePendingDialog(
          'catat pemasukan 500 rb',
          pending,
        );

        expect(resolved, hasLength(1));
        expect(resolved.single.type, FfmAssistantIntentType.createIncome);
        expect(resolved.single.draft?.kind, FfmAssistantDraftKind.income);
        expect(resolved.single.draft?.amount, 500000);
      });

      test('agent mode: pending expense kurang nominal + nominal saja → melengkapi draft lama', () async {
        final pending = FfmAssistantPendingDialog(
          originalRequest: 'catat pengeluaran pupuk',
          prompt: 'Berapa nominalnya?',
          missingFields: const ['nominal'],
          draft: FfmAssistantDraft(
            kind: FfmAssistantDraftKind.expense,
            createdAt: DateTime(2026, 8, 31),
            note: 'catat pengeluaran pupuk',
          ),
        );

        final resolved = await interpreter.resolvePendingDialog(
          '500 ribu',
          pending,
        );

        expect(resolved, hasLength(1));
        expect(resolved.single.draft?.kind, FfmAssistantDraftKind.expense);
        expect(resolved.single.draft?.amount, 500000);
      });

      test(
        'active transaction draft + follow-up nominal saja tetap draftReview',
        () async {
          final gemini = _FakeGemini(
            const GeminiResult(
              model: 'gemini-2.5-flash',
              statusCode: 200,
              message: 'ok',
              text: 'Baik, nominalnya saya isi 500 ribu.',
            ),
          );
          final cloudInterpreter = FfmAssistantInterpreter(
            database,
            config: _FakeConfig(),
            geminiService: gemini,
          );

          await cloudInterpreter.interpret(
            '500 ribu',
            routingMode: FfmAssistantRoutingMode.geminiCloud,
            activeDraft: FfmAssistantDraft(
              kind: FfmAssistantDraftKind.expense,
              createdAt: DateTime(2026, 8, 31),
              title: 'Belanja',
            ),
          );

          expect(gemini.calls, greaterThanOrEqualTo(1));
          expect(
            gemini.receivedSystemInstruction,
            contains('"requestClass":"draftReview"'),
          );
        },
      );
    },
  );

  group('periode anggaran tepat sasaran', () {
    test('atur anggaran makan 350 ribu per bulan → draft monthly', () async {
      final intent = await interpreter.interpret(
        'atur anggaran makan 350 ribu per bulan',
      );

      expect(intent.type, FfmAssistantIntentType.createBudget);
      expect(intent.draft?.kind, FfmAssistantDraftKind.budget);
      expect(intent.draft?.amount, 350000);
      expect(intent.draft?.formValues['periodType'], 'monthly');
      expect(intent.response, contains('bulanan'));
    });

    test('atur anggaran bensin 200 ribu mingguan → draft weekly', () async {
      final intent = await interpreter.interpret(
        'atur anggaran bensin 200 ribu mingguan',
      );

      expect(intent.type, FfmAssistantIntentType.createBudget);
      expect(intent.draft?.formValues['periodType'], 'weekly');
      expect(intent.response, contains('mingguan'));
    });

    test(
      'tanpa isyarat periode → periodType null (form pakai default)',
      () async {
        final intent = await interpreter.interpret(
          'atur anggaran makan 350 ribu',
        );

        expect(intent.type, FfmAssistantIntentType.createBudget);
        expect(intent.draft?.formValues.containsKey('periodType'), isFalse);
      },
    );

    test('proposal budget membawa period ke formValues', () {
      final monthly = FfmAssistantProposalJsonService.parse(
        '{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"budget","title":"Makan","amount":350000,"period":"monthly"}}',
        createdAt: DateTime(2026, 8, 31),
      );
      expect(monthly.draft?.formValues['periodType'], 'monthly');

      final alias = FfmAssistantProposalJsonService.parse(
        '{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"budget","title":"Makan","amount":350000,"period":"bulanan"}}',
        createdAt: DateTime(2026, 8, 31),
      );
      expect(alias.draft?.formValues['periodType'], 'monthly');

      final unknown = FfmAssistantProposalJsonService.parse(
        '{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"budget","title":"Makan","amount":350000,"period":"sekali-sekali"}}',
        createdAt: DateTime(2026, 8, 31),
      );
      expect(unknown.draft?.formValues.containsKey('periodType'), isFalse);
    });
  });

  group('orkestrator memahami semantik anggaran', () {
    test('instruksi Gemini memuat aturan daya tersedia dan periode', () async {
      final gemini = _FakeGemini(
        const GeminiResult(
          model: 'gemini-2.5-flash',
          statusCode: 200,
          message: 'ok',
          text: 'Anggaranmu masih aman.',
        ),
      );
      final cloudInterpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(),
        geminiService: gemini,
      );

      await cloudInterpreter.interpret(
        'bagaimana kondisi anggaran saya bulan ini',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, greaterThanOrEqualTo(1));
      expect(gemini.receivedSystemInstruction, contains('SEMANTIK ANGGARAN'));
      expect(gemini.receivedSystemInstruction, contains('daya tersedia'));
      expect(
        gemini.receivedSystemInstruction,
        contains('tidak pernah reset otomatis'),
      );
    });
  });

  group('error handling: pesan internal parser tidak bocor ke user', () {
    test(
      'invalid proposal tidak menampilkan jenis internal yang tidak didukung',
      () async {
        final gemini = _FakeGemini(
          const GeminiResult(
            model: 'gemini-2.5-flash',
            statusCode: 200,
            message: 'unsupported type',
            text: '{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"tidak_ada_jenis"}}',
          ),
        );
        final cloudInterpreter = FfmAssistantInterpreter(
          database,
          config: _FakeConfig(),
          geminiService: gemini,
        );

        final intent = await cloudInterpreter.interpret(
          'buat sesuatu yang aneh',
          routingMode: FfmAssistantRoutingMode.geminiCloud,
        );

        expect(gemini.calls, greaterThanOrEqualTo(1));
        expect(
          intent.response,
          isNot(contains('Jenis proposal belum didukung. Gunakan master_data')),
        );
        expect(intent.response, isNot(contains('JSON proposal belum valid')));
        // Invalid proposal tidak boleh berubah menjadi domain acak.
        expect(intent.type, FfmAssistantIntentType.unknown);
        expect(intent.draft, isNull);
        // Harus memunculkan tanggapan ramah yang meminta user mengurai ulang.
        expect(intent.response, isNotEmpty);
      },
    );

    test('format JSON buruk diganti pesan ramah, bukan teks teknis', () async {
      final gemini = _FakeGemini(
        const GeminiResult(
          model: 'gemini-2.5-flash',
          statusCode: 200,
          message: 'bad json',
          text: 'ini teks biasa tanpa konten JSON proposal',
        ),
      );
      final cloudInterpreter = FfmAssistantInterpreter(
        database,
        config: _FakeConfig(),
        geminiService: gemini,
      );

      final intent = await cloudInterpreter.interpret(
        'catat beli makan 50rb',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, greaterThanOrEqualTo(1));
      expect(intent.response, isNot(contains('Salin ulang hasil LLM')));
    });
  });
}
