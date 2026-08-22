import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  late dynamic database;
  late FfmAssistantInterpreter interpreter;

  test('sesi chat menyimpan riwayat dan antrean sampai direset eksplisit', () {
    final session = FfmAssistantChatSession();
    final intent = FfmAssistantIntent(
      rawText: 'buka transaksi',
      normalizedText: 'buka transaksi',
      type: FfmAssistantIntentType.openPage,
      confidence: 1,
    );
    session.entries.add(
      const FfmAssistantChatEntry(isUser: true, text: 'buka transaksi'),
    );
    session.queuedIntents.add(intent);
    session.lastAssistantText = 'Siap, pindah ke Transaksi.';

    expect(session.entries, hasLength(2));
    expect(session.queuedIntents, hasLength(1));
    expect(session.lastAssistantText, isNotNull);

    session.reset();

    expect(session.entries, hasLength(1));
    expect(session.entries.single.text, contains('Chat sudah direset'));
    expect(session.queuedIntents, isEmpty);
    expect(session.lastAssistantText, isNull);
  });

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

  test('menjawab jam dari waktu lokal perangkat yang sedang dipakai', () async {
    final localInterpreter = FfmAssistantInterpreter(
      database,
      null,
      () => DateTime(2026, 8, 21, 14, 30),
    );

    final intent = await localInterpreter.interpret('Sekarang jam berapa?');

    expect(intent.type, FfmAssistantIntentType.calendarQuery);
    expect(intent.response, contains('14.30'));
    expect(intent.response, contains('21 Agustus 2026'));
    expect(intent.response, contains('waktu lokal HP'));
    expect(intent.draft, isNull);
  });

  test('menghitung 90 hari lagi dari tanggal lokal perangkat', () async {
    final localInterpreter = FfmAssistantInterpreter(
      database,
      null,
      () => DateTime(2026, 8, 21, 14, 30),
    );

    final intent = await localInterpreter.interpret(
      '90 hari lagi tanggal berapa?',
    );

    expect(intent.type, FfmAssistantIntentType.calendarQuery);
    expect(intent.response, contains('19 November 2026'));
    expect(intent.draft, isNull);
  });

  test('menjelaskan identitas Asisten dan batas keamanan draft', () async {
    final intent = await interpreter.interpret('Kamu siapa dan bisa apa?');

    expect(intent.type, FfmAssistantIntentType.assistantIdentity);
    expect(intent.response, contains('Asisten FFM'));
    expect(intent.response, contains('waktu lokal HP'));
    expect(intent.response, contains('tidak menyimpan'));
    expect(intent.draft, isNull);
  });

  test('memandu setup berdasarkan data utama yang masih kosong', () async {
    final intent = await interpreter.interpret('Harus mulai dari mana?');

    expect(intent.type, FfmAssistantIntentType.setupGuide);
    expect(intent.response, contains('rekening aktif'));
    expect(intent.response, contains('Catat transaksi pertama'));
    expect(intent.draft, isNull);
  });

  test('menjawab pertanyaan pertama penggunaan dengan panduan lokal', () async {
    final intent = await interpreter.interpret(
      'pertamakali saya harus apa di aplikasi ini?',
    );

    expect(intent.type, FfmAssistantIntentType.setupGuide);
    expect(intent.response, contains('Data Utama'));
    expect(intent.response, contains('Catat transaksi pertama'));
    expect(intent.draft, isNull);
  });

  test('menjawab tanggal Hijriah dari waktu lokal perangkat', () async {
    final localInterpreter = FfmAssistantInterpreter(
      database,
      null,
      () => DateTime(2026, 8, 22, 10, 37),
    );

    final intent = await localInterpreter.interpret(
      'tanggal berapa sekarang? hijriah',
    );

    expect(intent.type, FfmAssistantIntentType.calendarQuery);
    expect(intent.response, startsWith('Sekarang '));
    expect(intent.response, contains('Kalender Hijriah FFM'));
    expect(intent.draft, isNull);
  });

  test(
    'fallback yang belum dipahami tetap singkat dan mengarahkan latihan',
    () async {
      final intent = await interpreter.interpret(
        'apa arti kalimat buatan xyz?',
      );

      expect(intent.type, FfmAssistantIntentType.unknown);
      expect(intent.response, contains('belum punya jawaban yang pas'));
      expect(intent.response, contains('Ajarkan Asisten'));
      expect(intent.response, isNot(contains('Pindahkan')));
      expect(intent.draft, isNull);
    },
  );

  test('menjelaskan fungsi tag tanpa membuat data', () async {
    final intent = await interpreter.interpret('Fungsi tag buat apa?');

    expect(intent.type, FfmAssistantIntentType.featureHelp);
    expect(intent.response, contains('bukan kategori'));
    expect(intent.draft, isNull);
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

  test('memilih kategori aktif yang cocok untuk draft pengeluaran', () async {
    await database
        .into(database.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'rokok',
            householdId: AppContext.householdId,
            name: 'Rokok',
            type: 'expense',
            createdAt: DateTime(2026, 8, 1),
          ),
        );

    final intent = await interpreter.interpret(
      'catat belanja rokok 25 ribu dari Tunai',
    );

    expect(intent.type, FfmAssistantIntentType.createExpense);
    expect(intent.draft?.categoryName, 'Rokok');
    expect(intent.response, contains('Kategori Rokok'));
  });

  test('membuat draft aset dan target tanpa menyimpan data otomatis', () async {
    final asset = await interpreter.interpret(
      'Tambah aset motor senilai 15 juta',
    );
    final goal = await interpreter.interpret(
      'Buat target biaya sekolah 5 juta',
    );

    expect(asset.type, FfmAssistantIntentType.createAsset);
    expect(asset.destination, FfmAssistantDestination.assets);
    expect(asset.draft?.kind, FfmAssistantDraftKind.asset);
    expect(asset.draft?.amount, 15000000);
    expect(asset.needsConfirmation, isTrue);
    expect(goal.type, FfmAssistantIntentType.createGoal);
    expect(goal.destination, FfmAssistantDestination.goals);
    expect(goal.draft?.kind, FfmAssistantDraftKind.goal);
    expect(goal.draft?.amount, 5000000);

    expect(await database.select(database.assets).get(), isEmpty);
    expect(await database.select(database.goals).get(), isEmpty);
  });

  test(
    'membuat draft form Data Utama, anggaran, pengingat, dan aktivitas',
    () async {
      final category = await interpreter.interpret(
        'Tambah kategori Belanja Kebun',
      );
      final budget = await interpreter.interpret('Atur anggaran 350 ribu');
      final reminder = await interpreter.interpret(
        'Buat pengingat bayar listrik',
      );
      final activity = await interpreter.interpret(
        'Mulai aktivitas pergi ke pasar',
      );

      expect(category.type, FfmAssistantIntentType.createMasterData);
      expect(category.destination, FfmAssistantDestination.masterData);
      expect(category.draft?.categoryName, 'kategori');
      expect(budget.type, FfmAssistantIntentType.createBudget);
      expect(budget.destination, FfmAssistantDestination.budget);
      expect(budget.draft?.amount, 350000);
      expect(reminder.type, FfmAssistantIntentType.createReminder);
      expect(reminder.destination, FfmAssistantDestination.reminders);
      expect(activity.type, FfmAssistantIntentType.createActivity);
      expect(activity.destination, FfmAssistantDestination.activity);
      expect(activity.needsConfirmation, isTrue);

      expect(await database.select(database.envelopeBudgets).get(), isEmpty);
      expect(await database.select(database.activitySessions).get(), isEmpty);
    },
  );

  test(
    'analisa minggu ini hanya memakai nominal transaksi yang tersimpan',
    () async {
      final now = DateTime.now();
      await database
          .into(database.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'makan',
              householdId: AppContext.householdId,
              name: 'Makan',
              type: 'expense',
              createdAt: now,
            ),
          );
      await database
          .into(database.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'belanja-mingguan',
              householdId: AppContext.householdId,
              type: 'expense',
              categoryId: const Value('makan'),
              amount: -27500,
              date: now,
              recordedAt: now,
              createdAt: now,
            ),
          );

      final intent = await interpreter.interpret(
        'Analisa pengeluaran minggu ini',
      );

      expect(intent.type, FfmAssistantIntentType.weeklyAnalysis);
      expect(intent.response, contains('Rp27.500'));
      expect(intent.response, contains('Makan'));
      expect(
        intent.response,
        contains('transfer tidak masuk hitungan arus kas'),
      );
    },
  );

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

  test('menjelaskan batas saat pertanyaan butuh data di luar FFM', () async {
    final intent = await interpreter.interpret('Berapa harga cabai hari ini?');

    expect(intent.type, FfmAssistantIntentType.unknown);
    expect(intent.clarification, contains('akses internet'));
    expect(intent.clarification, contains('tersimpan di FFM'));
  });
}
