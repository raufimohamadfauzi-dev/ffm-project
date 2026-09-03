import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_fuzzy_matcher.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_query_tools.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_tool.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('regresi Asisten FFM v63', () {
    test('fuzzy matcher menerima typo dekat dan menolak kandidat ambigu', () {
      final near = FfmAssistantFuzzyMatcher.bestUnique<String>(
        'ada berapa transakdi minggu ini',
        const ['ada berapa transaksi minggu ini'],
        textOf: (value) => value,
      );
      final ambiguous = FfmAssistantFuzzyMatcher.bestUnique<String>(
        'cek saldo',
        const ['cek saldo seabank', 'cek saldo tunai'],
        textOf: (value) => value,
        minimumScore: .50,
      );

      expect(near?.value, 'ada berapa transaksi minggu ini');
      expect(near?.score, greaterThanOrEqualTo(.84));
      expect(ambiguous, isNull);
    });

    test('fuzzy matcher mengenali pertukaran huruf bersebelahan', () {
      final score = FfmAssistantFuzzyMatcher.similarity('pni', 'pin');

      expect(score, greaterThan(.40));
    });

    test(
      'action kontekstual hanya membentuk rancangan dan butuh halaman',
      () async {
        final registry = FfmAssistantContextualActionRegistry(
          clock: () => DateTime(2026, 8, 22, 9),
        );

        final withoutContext = await registry.buildDraft(
          input: 'tambah motor ini',
          activePage: null,
        );
        final assetDraft = await registry.buildDraft(
          input: 'tambah aset motor ini',
          activePage: FfmAssistantDestination.assets,
        );

        expect(withoutContext, isNull);
        expect(assetDraft, isNotNull);
        expect(assetDraft!.kind, FfmAssistantDraftKind.asset);
        expect(assetDraft.title, 'motor');
        expect(assetDraft.createdAt, DateTime(2026, 8, 22, 9));
      },
    );

    test('query saldo membaca database lokal tanpa mengubah data', () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      await database
          .into(database.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'seabank-v63',
              householdId: AppContext.householdId,
              name: 'SeaBank',
              type: 'bank',
              createdAt: DateTime(2026, 8, 22),
            ),
          );
      final before = await database.select(database.accounts).get();
      final registry = FfmAssistantQueryRegistry(
        database,
        clock: () => DateTime(2026, 8, 22, 9),
      );

      final answer = await registry.tryAnswer(
        'saldo seabank',
        householdId: AppContext.householdId,
      );
      final after = await database.select(database.accounts).get();

      expect(answer, isNotNull);
      expect(answer!.title, 'Saldo SeaBank');
      expect(answer.message, contains('Saldo buku SeaBank'));
      expect(after, hasLength(before.length));
      expect(after.single.id, before.single.id);
    });

    test('query belanja rokok membaca item dan menghitung total periode', () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      final date = DateTime(2026, 8, 22, 9);
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-rokok-v63',
              householdId: AppContext.householdId,
              type: 'expense',
              amount: -45000,
              date: date,
              recordedAt: date,
              categoryId: const drift.Value('cat-belanja'),
              createdAt: date,
            ),
          );
      await database.into(database.transactionItems).insert(
            TransactionItemsCompanion.insert(
              id: 'item-rokok-v63',
              transactionId: 'tx-rokok-v63',
              itemName: 'Rokok kretek',
              qty: const drift.Value(2),
              price: const drift.Value(22500),
              amount: const drift.Value(45000),
              createdAt: date,
            ),
          );

      final registry = FfmAssistantQueryRegistry(
        database,
        clock: () => date,
      );
      final answer = await registry.tryAnswer(
        'berapa belanja rokok minggu ini',
        householdId: AppContext.householdId,
      );

      expect(answer, isNotNull);
      expect(answer!.title, 'Belanja rokok');
      expect(answer.message, contains('Rp45.000'));
      expect(answer.message, contains('2'));
    });
  });
}
