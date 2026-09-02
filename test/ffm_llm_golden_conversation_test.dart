import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/network/gemini_service.dart';
import 'package:ffm_manager/core/network/supabase_config.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

class _FakeConfig extends SupabaseConfig {
  @override
  Future<String?> getGeminiKey() async => 'test-key';
  @override
  Future<String?> getGeminiModel() async => 'gemini-2.5-pro';
  @override
  Future<bool> isGeminiVerified() async => true;
}

class _FakeFailConfig extends SupabaseConfig {
  @override
  Future<String?> getGeminiKey() async => null;
  @override
  Future<String?> getGeminiModel() async => null;
  @override
  Future<bool> isGeminiVerified() async => false;
}

class _CapturingGemini extends GeminiService {
  String? lastSystemInstruction;
  String? lastPrompt;
  int calls = 0;
  final String responseText;

  _CapturingGemini(this.responseText);

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
    return GeminiResult(
      model: model ?? 'gemini-2.5-pro',
      statusCode: 200,
      message: 'ok',
      text: responseText,
    );
  }
}

void main() {
  late AppDatabase db;
  final now = DateTime(2026, 8, 15);

  setUp(() {
    db = createInMemoryDatabaseForTests();
  });

  tearDown(() async {
    await db.close();
  });

  group('Golden conversation Indonesia', () {
    test('ringkasan bulan ini', () async {
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'inc-golden',
              householdId: AppContext.householdId,
              type: 'income',
              amount: 7000000,
              date: now,
              recordedAt: now,
              createdAt: now,
            ),
          );
      final gemini = _CapturingGemini('Ringkasan: pemasukan 7jt.');
      final interpreter = FfmAssistantInterpreter(
        db,
        geminiService: gemini,
        config: _FakeConfig(),
        clock: () => now,
      );
      final intent = await interpreter.interpret(
        'ringkasan bulan ini',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
      expect(gemini.lastSystemInstruction, contains('income=7000000'));
      expect(gemini.lastSystemInstruction, contains('VERIFIED FACTS'));
    });

    test('transaksi terbaru', () async {
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'tx-golden',
              householdId: AppContext.householdId,
              type: 'expense',
              amount: 150000,
              date: now,
              recordedAt: now,
              createdAt: now,
            ),
          );
      final gemini = _CapturingGemini('Transaksi terbaru: 150rb kemarin.');
      final interpreter = FfmAssistantInterpreter(
        db,
        geminiService: gemini,
        config: _FakeConfig(),
        clock: () => now,
      );
      final intent = await interpreter.interpret(
        'transaksi terbaru minggu ini',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
      expect(
        gemini.lastSystemInstruction,
        anyOf([contains('Transaction digest'), contains('VERIFIED FACTS')]),
      );
    });

    test('rekening', () async {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'acc-golden',
              householdId: AppContext.householdId,
              name: 'BCA Golden',
              type: 'bank',
              openingBalance: const Value(1000000),
              createdAt: now,
            ),
          );
      final gemini = _CapturingGemini('Rekening aktif: BCA Golden.');
      final interpreter = FfmAssistantInterpreter(
        db,
        geminiService: gemini,
        config: _FakeConfig(),
        clock: () => now,
      );
      await interpreter.interpret(
        'rekening saya apa saja',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );
      expect(gemini.lastSystemInstruction, contains('rekening_aktif'));
      expect(gemini.lastSystemInstruction, contains('BCA Golden'));
    });

    test('anggaran', () async {
      await db
          .into(db.envelopeBudgets)
          .insert(
            EnvelopeBudgetsCompanion.insert(
              id: 'budget-golden',
              householdId: AppContext.householdId,
              name: 'Makanan Golden',
              allocated: const Value(2000000),
              periodType: const Value('monthly'),
              startDate: now,
              endDate: now.add(const Duration(days: 30)),
              createdAt: now,
            ),
          );
      final gemini = _CapturingGemini('Anggaran Makanan 2jt.');
      final interpreter = FfmAssistantInterpreter(
        db,
        geminiService: gemini,
        config: _FakeConfig(),
        clock: () => now,
      );
      await interpreter.interpret(
        'anggaran makanan bulan ini',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );
      expect(
        gemini.lastSystemInstruction,
        anyOf([
          contains('anggaran'),
          contains('Anggaran'),
          contains('allocated'),
        ]),
      );
    });

    test('target', () async {
      await db
          .into(db.goals)
          .insert(
            GoalsCompanion.insert(
              id: 'goal-golden',
              householdId: AppContext.householdId,
              name: 'Liburan Golden',
              targetAmount: 10000000,
              createdAt: now,
              isActive: const Value(true),
            ),
          );
      final gemini = _CapturingGemini('Target Liburan 10jt progress 0.');
      final interpreter = FfmAssistantInterpreter(
        db,
        geminiService: gemini,
        config: _FakeConfig(),
        clock: () => now,
      );
      await interpreter.interpret(
        'target liburan saya',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );
      expect(
        gemini.lastSystemInstruction,
        anyOf([contains('target'), contains('Target'), contains('Liburan')]),
      );
    });

    test('analisis', () async {
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'ana-1',
              householdId: AppContext.householdId,
              type: 'expense',
              amount: 500000,
              date: now,
              recordedAt: now,
              createdAt: now,
            ),
          );
      final gemini = _CapturingGemini('Analisis: tren naik.');
      final interpreter = FfmAssistantInterpreter(
        db,
        geminiService: gemini,
        config: _FakeConfig(),
        clock: () => now,
      );
      final intent = await interpreter.interpret(
        'analisis pengeluaran bulan ini',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
      expect(
        gemini.lastSystemInstruction,
        anyOf([contains('ANALYSIS FACTS'), contains('Verified')]),
      );
    });

    test('koreksi Data Utama dengan draft aktif', () async {
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.masterData,
        createdAt: now,
        title: 'Kategori Lama',
        categoryName: 'kategori',
        note: 'note lama',
      );
      final gemini = _CapturingGemini('Siap koreksi kategori.');
      final interpreter = FfmAssistantInterpreter(
        db,
        geminiService: gemini,
        config: _FakeConfig(),
        clock: () => now,
      );
      await interpreter.interpret(
        'ganti nama kategori jadi Kategori Baru',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
        activeDraft: draft,
      );
      expect(gemini.lastSystemInstruction, contains('ACTIVE DRAFT'));
      expect(gemini.lastSystemInstruction, contains('Kategori Lama'));
    });

    test('koreksi transaksi dengan draft aktif', () async {
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: now,
        amount: 50000,
        title: 'Makan',
        fromAccountName: 'Tunai',
        categoryName: 'Makan',
        date: now,
      );
      final gemini = _CapturingGemini('Siap koreksi transaksi.');
      final interpreter = FfmAssistantInterpreter(
        db,
        geminiService: gemini,
        config: _FakeConfig(),
        clock: () => now,
      );
      await interpreter.interpret(
        'koreksi nominal jadi 75000',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
        activeDraft: draft,
      );
      expect(gemini.lastSystemInstruction, contains('ACTIVE DRAFT'));
      expect(gemini.lastSystemInstruction, contains('50000'));
    });

    test('cancel', () async {
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: now,
        amount: 10000,
        title: 'Test',
        fromAccountName: 'Tunai',
        categoryName: 'Lain',
        date: now,
      );
      final interpreter = FfmAssistantInterpreter(
        db,
        geminiService: _CapturingGemini('ok'),
        config: _FakeConfig(),
        clock: () => now,
      );
      final intent = await interpreter.interpret(
        'batalkan',
        activeDraft: draft,
      );
      expect(intent.type, FfmAssistantIntentType.cancel);
    });

    test('provider unavailable fallback jujur', () async {
      final interpreter = FfmAssistantInterpreter(
        db,
        geminiService: _CapturingGemini('should not be called'),
        config: _FakeFailConfig(),
        clock: () => now,
      );
      final intent = await interpreter.interpret(
        'ringkasan bulan ini',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.cloudError);
      expect(
        intent.response,
        anyOf([contains('Gemini'), contains('belum siap')]),
      );
    });
  });
}
