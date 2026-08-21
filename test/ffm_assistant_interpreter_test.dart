import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  late dynamic database;
  late FfmAssistantInterpreter interpreter;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    interpreter = FfmAssistantInterpreter(database);
    await database
        .into(database.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'seabank',
            householdId: AppContext.householdId,
            name: 'SeaBank',
            type: 'bank',
            createdAt: DateTime(2026, 8, 1),
          ),
        );
    await database
        .into(database.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'tunai',
            householdId: AppContext.householdId,
            name: 'Tunai',
            type: 'cash',
            createdAt: DateTime(2026, 8, 1),
          ),
        );
  });

  tearDown(() async => database.close());

  test(
    'mengenali halaman dari kata yang berbeda tetapi maksudnya sama',
    () async {
      final intent = await interpreter.interpret('Tolong buka halaman budget');

      expect(intent.type, FfmAssistantIntentType.openPage);
      expect(intent.destination, FfmAssistantDestination.budget);
      expect(intent.needsConfirmation, isFalse);
    },
  );

  test('menjawab daftar halaman lokal', () async {
    final intent = await interpreter.interpret('Ada menu apa saja?');

    expect(intent.type, FfmAssistantIntentType.listPages);
    expect(intent.response, contains('Hutang & piutang'));
    expect(intent.response, contains('Ringkasan'));
  });

  test('memahami typo aman dan statistik transaksi minggu ini', () async {
    final intent = await interpreter.interpret(
      'ada berapa teansaksi minggu ini?',
    );

    expect(intent.type, FfmAssistantIntentType.transactionStats);
    expect(intent.normalizedText, contains('transaksi minggu ini'));
    expect(intent.response, startsWith('Minggu ini'));
  });

  test('membiarkan kata yang tidak dikenali agar nama tidak ditebak', () async {
    final intent = await interpreter.interpret('buka halaman zayra');

    expect(intent.type, FfmAssistantIntentType.unknown);
    expect(intent.normalizedText, contains('zayra'));
  });

  test('menjawab konteks ringkasan dari halaman yang sedang dibuka', () async {
    final intent = await interpreter.interpret(
      'di sini ada data apa?',
      currentDestination: FfmAssistantDestination.summary,
    );

    expect(intent.type, FfmAssistantIntentType.transactionStats);
    expect(intent.destination, FfmAssistantDestination.summary);
    expect(intent.response, startsWith('Kamu lagi di Ringkasan.'));
  });

  test('memeriksa anggaran tanpa membuat draft atau menyimpan data', () async {
    final intent = await interpreter.interpret('Cek anggaran saya');

    expect(intent.type, FfmAssistantIntentType.financialWarnings);
    expect(intent.destination, FfmAssistantDestination.budget);
    expect(intent.draft, isNull);
    expect(intent.response, contains('Belum ada peringatan'));
  });

  test('membuat draft transfer SeaBank ke Tunai dengan biaya admin', () async {
    final intent = await interpreter.interpret(
      'Pindahkan 500 ribu dari SeaBank ke Tunai admin 3 ribu',
    );

    expect(intent.type, FfmAssistantIntentType.createTransfer);
    expect(intent.destination, FfmAssistantDestination.transactions);
    expect(intent.draft?.kind, FfmAssistantDraftKind.transfer);
    expect(intent.draft?.amount, 500000);
    expect(intent.draft?.adminFee, 3000);
    expect(intent.draft?.fromAccountName, 'SeaBank');
    expect(intent.draft?.toAccountName, 'Tunai');
    expect(intent.needsClarification, isFalse);
  });

  test(
    'meminta informasi yang kurang daripada membuat hutang sembarang',
    () async {
      final intent = await interpreter.interpret('Catat hutang ke Budi');

      expect(intent.type, FfmAssistantIntentType.createLiability);
      expect(intent.draft?.partyName, 'Budi');
      expect(intent.needsClarification, isTrue);
      expect(intent.clarification, contains('nominal'));
    },
  );

  test(
    'membelah beberapa perintah menjadi draft terpisah tanpa simpan otomatis',
    () async {
      final intents = await interpreter.interpretMany(
        'Pemasukan panen 1 juta ke SeaBank; beli BBM 50 ribu dari Tunai',
      );

      expect(intents, hasLength(2));
      expect(intents.first.type, FfmAssistantIntentType.createIncome);
      expect(intents.first.draft?.amount, 1000000);
      expect(intents.last.type, FfmAssistantIntentType.createExpense);
      expect(intents.last.draft?.amount, 50000);
      final transactions = await database.select(database.transactions).get();
      expect(transactions, isEmpty);
    },
  );

  test('memahami angka Bahasa Indonesia dan perintah berurutan', () async {
    final intents = await interpreter.interpretMany(
      'hasil panen seratus dua puluh lima ribu ke SeaBank terus beli BBM satu setengah juta dari Tunai',
    );

    expect(intents, hasLength(2));
    expect(intents.first.type, FfmAssistantIntentType.createIncome);
    expect(intents.first.draft?.amount, 125000);
    expect(intents.last.type, FfmAssistantIntentType.createExpense);
    expect(intents.last.draft?.amount, 1500000);
  });

  test('mendukung nominal pecahan dan menolak arah pinjaman ambigu', () async {
    expect(FfmAssistantAmountParser.parse('1,5 juta'), 1500000);
    expect(FfmAssistantAmountParser.parse('setengah juta'), 500000);

    final intent = await interpreter.interpret('Budi pinjam tiga ratus ribu');
    expect(intent.type, FfmAssistantIntentType.unknown);
    expect(intent.clarification, contains('hutang'));
    expect(intent.clarification, contains('piutang'));
  });
}
