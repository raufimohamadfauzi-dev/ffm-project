import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/network/gemini_service.dart';
import 'package:ffm_manager/core/network/supabase_config.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

class _FakeConfig extends SupabaseConfig {
  @override
  Future<String?> getGeminiKey() async => 'test-key';

  @override
  Future<String?> getGeminiModel() async => 'gemini-2.5-flash';

  @override
  Future<bool> isGeminiVerified() async => true;
}

class _CapturingGemini extends GeminiService {
  String? systemInstruction;

  @override
  Future<GeminiResult> chat({
    required String prompt,
    String? systemInstruction,
    List<Map<String, String>> history = const [],
    String? apiKey,
    String? model,
  }) async {
    this.systemInstruction = systemInstruction;
    return const GeminiResult(
      model: 'gemini-2.5-flash',
      statusCode: 200,
      message: 'ok',
      text: 'Jawaban Gemini.',
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

  test(
    'context Gemini memakai snapshot agregat dan bukan raw transaction rows',
    () async {
      final now = DateTime(2026, 8, 23);
      await database
          .into(database.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'income-context',
              householdId: AppContext.householdId,
              type: 'income',
              amount: 8000000,
              date: now,
              recordedAt: now,
              createdAt: now,
              note: const Value('Rahasia keluarga'),
            ),
          );
      await database
          .into(database.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'expense-context',
              householdId: AppContext.householdId,
              type: 'expense',
              amount: -3000000,
              date: now,
              recordedAt: now,
              createdAt: now,
            ),
          );
      await database
          .into(database.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'seabank-context',
              householdId: AppContext.householdId,
              name: 'SeaBank',
              type: 'bank',
              openingBalance: const Value(987654),
              createdAt: now,
            ),
          );
      await database
          .into(database.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'food-context',
              householdId: AppContext.householdId,
              name: 'Belanja Pasar',
              type: 'expense',
              createdAt: now,
            ),
          );

      final gemini = _CapturingGemini();
      final interpreter = FfmAssistantInterpreter(
        database,
        geminiService: gemini,
        config: _FakeConfig(),
        clock: () => now,
      );

      final intent = await interpreter.interpret(
        'uraikan pendapatan keluarga secara konseptual',
      );

      expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
      expect(gemini.systemInstruction, contains('income=8000000'));
      expect(gemini.systemInstruction, contains('expenses=3000000'));
      expect(gemini.systemInstruction, contains('quality=sufficient'));
      expect(gemini.systemInstruction, contains('rekening_aktif=SeaBank'));
      expect(gemini.systemInstruction, contains('kategori_aktif='));
      expect(gemini.systemInstruction, contains('Belanja Pasar'));
      expect(gemini.systemInstruction, contains('nama saja; tanpa saldo'));
      expect(gemini.systemInstruction, isNot(contains('987654')));
      expect(gemini.systemInstruction, isNot(contains('Rahasia keluarga')));
    },
  );
}
