import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/transaction/domain/usecases/transaction_crud_usecases.dart';

void main() {
  final now = DateTime(2026, 8, 24, 9);
  late AppDatabase database;
  late FfmAssistantInterpreter interpreter;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seed({required String id, required String note}) =>
      SaveTransaction(database)(
        TransactionEntity(
          id: id,
          householdId: AppContext.householdId,
          date: now,
          amount: -15000,
          owner: 'Keluarga',
          categoryId: null,
          note: note,
          recordedAt: now,
          updatedAt: now,
        ),
      );

  test(
    'update transaksi membuat draft lokal tanpa write sebelum konfirmasi',
    () async {
      await seed(id: 'coffee', note: 'kopi pagi');

      final intent = await interpreter.interpret(
        'ubah transaksi kopi jadi 25000',
      );

      expect(intent.type, FfmAssistantIntentType.updateTransaction);
      expect(intent.destination, FfmAssistantDestination.transactions);
      expect(intent.draft?.kind, FfmAssistantDraftKind.transactionUpdate);
      expect(intent.draft?.amount, 25000);
      expect(intent.draft?.formValues['targetId'], 'coffee');
      expect(intent.needsConfirmation, isTrue);
      final row = await GetTransaction(database)(
        AppContext.householdId,
        'coffee',
      );
      expect(row?.transaction.amount, -15000);
    },
  );

  test(
    'resolver tidak memilih transaksi secara diam-diam ketika target ambigu',
    () async {
      await seed(id: 'coffee-a', note: 'kopi pagi');
      await seed(id: 'coffee-b', note: 'kopi sore');

      final intent = await interpreter.interpret('hapus transaksi kopi');

      expect(intent.type, FfmAssistantIntentType.deleteTransaction);
      expect(intent.draft, isNull);
      expect(intent.clarification, contains('menemukan 2 transaksi'));
    },
  );

  test(
    'archive dan delete membuat draft berbeda yang tetap menunggu konfirmasi',
    () async {
      await seed(id: 'market', note: 'pasar minggu');

      final archive = await interpreter.interpret('arsipkan transaksi pasar');
      final delete = await interpreter.interpret('hapus transaksi pasar');

      expect(archive.type, FfmAssistantIntentType.archiveTransaction);
      expect(archive.draft?.kind, FfmAssistantDraftKind.transactionArchive);
      expect(archive.needsConfirmation, isTrue);
      expect(delete.type, FfmAssistantIntentType.deleteTransaction);
      expect(delete.draft?.kind, FfmAssistantDraftKind.transactionDelete);
      expect(delete.needsConfirmation, isTrue);
    },
  );
}
