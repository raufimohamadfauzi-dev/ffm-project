import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

/// Regresi: "isi saldo / top up e-wallet" harus menjadi draft transfer,
/// bukan jawaban cek saldo dan bukan unknown berhuruf rusak.
void main() {
  late AppDatabase database;
  late FfmAssistantInterpreter interpreter;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    interpreter = FfmAssistantInterpreter(database);
    await database.into(database.accounts).insert(
          AccountsCompanion.insert(
            id: 'gopay',
            householdId: AppContext.householdId,
            name: 'GoPay',
            type: 'ewallet',
            createdAt: DateTime(2026, 8, 1),
          ),
        );
    await database.into(database.accounts).insert(
          AccountsCompanion.insert(
            id: 'bca',
            householdId: AppContext.householdId,
            name: 'BCA',
            type: 'bank',
            createdAt: DateTime(2026, 8, 1),
          ),
        );
  });

  tearDown(() async => database.close());

  test('isi saldo gopay + nominal menjadi draft transfer ke GoPay', () async {
    final intent = await interpreter.interpret('isi saldo gopay 50000');

    expect(intent.type, FfmAssistantIntentType.createTransfer);
    expect(intent.draft?.kind, FfmAssistantDraftKind.transfer);
    expect(intent.draft?.toAccountName, 'GoPay');
    expect(intent.draft?.amount, 50000);
    // Sumber belum disebut -> interpreter meminta klarifikasi,
    // sehingga needsClarification=true dan needsConfirmation=false.
    expect(intent.needsClarification, isTrue);
    expect(intent.clarification, isNotNull);
  });

  test('top up gopay dari bca mengisi asal dan tujuan dengan benar', () async {
    final intent = await interpreter.interpret('top up gopay 50000 dari bca');

    expect(intent.type, FfmAssistantIntentType.createTransfer);
    expect(intent.draft?.kind, FfmAssistantDraftKind.transfer);
    expect(intent.draft?.toAccountName, 'GoPay');
    expect(intent.draft?.fromAccountName, 'BCA');
    expect(intent.draft?.amount, 50000);
    expect(intent.needsConfirmation, isTrue);
  });

  test('cek saldo asli tetap menjadi pertanyaan saldo, bukan draft', () async {
    final intent = await interpreter.interpret('berapa saldo gopay?');

    expect(intent.draft, isNull);
    expect(intent.type, FfmAssistantIntentType.queryData);
  });
}
