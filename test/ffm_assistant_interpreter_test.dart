import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/activity/domain/entities/activity_entity.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
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

  test(
    'membuat draft edit kategori aktivitas dengan field kategori eksplisit',
    () async {
      final now = DateTime(2026, 8, 21, 10);
      await database
          .into(database.activitySessions)
          .insert(
            ActivitySessionsCompanion.insert(
              id: 'market',
              householdId: AppContext.householdId,
              title: 'Belanja pasar',
              category: const Value('Keluarga'),
              kind: const Value('timer'),
              startedAt: now.subtract(const Duration(hours: 1)),
              endedAt: Value(now),
              status: const Value('completed'),
              createdAt: now.subtract(const Duration(hours: 1)),
            ),
          );

      final intent = await interpreter.interpret(
        'ubah kategori aktivitas belanja pasar jadi kebun',
      );

      expect(intent.type, FfmAssistantIntentType.editActivity);
      expect(intent.draft?.kind, FfmAssistantDraftKind.activityEdit);
      expect(intent.draft?.title, 'Belanja pasar');
      expect(intent.draft?.categoryName, 'kebun');
      expect(intent.draft?.formValues['category'], 'kebun');
      expect(intent.draft?.formValues['targetId'], 'market');
    },
  );

  test('mengenali perintah menuju navbar Lainnya dan halaman PIN', () async {
    final otherMenu = await interpreter.interpret('Buka navbar lainnya');
    final pin = await interpreter.interpret('Pergi ke halaman PIN');

    expect(otherMenu.type, FfmAssistantIntentType.openPage);
    expect(otherMenu.destination, FfmAssistantDestination.otherMenu);
    expect(pin.type, FfmAssistantIntentType.openPage);
    expect(pin.destination, FfmAssistantDestination.appSecurity);
  });

  test('menjawab daftar halaman lokal', () async {
    final intent = await interpreter.interpret('Ada menu apa saja?');

    expect(intent.type, FfmAssistantIntentType.listPages);
    expect(intent.response, contains('Hutang & piutang'));
    expect(intent.response, contains('Ringkasan'));
  });

  test('pertanyaan umum tidak diambil alih katalog halaman aktif', () async {
    final intent = await interpreter.interpret(
      'apa itu?',
      currentDestination: FfmAssistantDestination.otherMenu,
    );

    expect(intent.destination, isNot(FfmAssistantDestination.otherMenu));
    expect(intent.response, isNot(contains('Lainnya berisi jalan')));
  });

  test('menjawab jam dari waktu lokal perangkat yang sedang dipakai', () async {
    final localInterpreter = FfmAssistantInterpreter(
      database,
      clock: () => DateTime(2026, 8, 21, 14, 30),
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
      clock: () => DateTime(2026, 8, 21, 14, 30),
    );

    final intent = await localInterpreter.interpret(
      '90 hari lagi tanggal berapa?',
    );

    expect(intent.type, FfmAssistantIntentType.calendarQuery);
    expect(intent.response, contains('19 November 2026'));
    expect(intent.draft, isNull);
  });

  test('menjawab hari dan tanggal Masehi besok dari waktu lokal', () async {
    final localInterpreter = FfmAssistantInterpreter(
      database,
      clock: () => DateTime(2026, 8, 21, 14, 30),
    );

    final intent = await localInterpreter.interpret('Besok hari apa?');

    expect(intent.type, FfmAssistantIntentType.calendarQuery);
    expect(intent.response, contains('Besok Sabtu, 22 Agustus 2026'));
    expect(intent.draft, isNull);
  });

  test('menjelaskan identitas Asisten dan batas keamanan draft', () async {
    final intent = await interpreter.interpret('Kamu siapa dan bisa apa?');

    expect(intent.type, FfmAssistantIntentType.assistantIdentity);
    expect(intent.response, contains('Asisten FFM'));
    expect(intent.response, contains('menyiapkan preview laporan'));
    expect(intent.response, contains('tidak ada autosave'));
    expect(intent.response, contains('Rafi Sinkkat'));
    expect(intent.draft, isNull);
  });

  test('mengenali variasi pertanyaan kemampuan Asisten', () async {
    final intent = await interpreter.interpret(
      'kemampuan asisten itu bagaimana?',
    );

    expect(intent.type, FfmAssistantIntentType.assistantIdentity);
    expect(intent.response, contains('Yang bisa kulakukan sekarang'));
    expect(intent.response, contains('tidak ada autosave'));
  });

  test('mengarahkan pertanyaan identitas pengguna ke profil lokal', () async {
    final intent = await interpreter.interpret('saya itu siapa?');

    expect(intent.type, FfmAssistantIntentType.queryData);
    expect(intent.response, contains('Profil Pribadi'));
    expect(intent.response, contains('Profil Personalisasi Asisten'));
    expect(intent.draft, isNull);
  });

  test('memandu setup berdasarkan data utama yang masih kosong', () async {
    final intent = await interpreter.interpret('Harus mulai dari mana?');

    expect(intent.type, FfmAssistantIntentType.setupGuide);
    expect(intent.response, contains('rekening aktif'));
    expect(intent.response, contains('Catat transaksi pertama'));
    expect(intent.draft, isNull);
  });

  test('mendeteksi Data Utama kosong dari database lokal', () async {
    await database.delete(database.accounts).go();

    final intent = await interpreter.interpret('data utama kosong');

    expect(intent.type, FfmAssistantIntentType.setupGuide);
    expect(intent.response, contains('belum ada rekening aktif'));
    expect(intent.response, contains('Tambah rekening yang dipakai'));
    expect(intent.response, contains('Kategori aktif:'));
    expect(intent.draft, isNull);
  });

  test(
    'menjawab kelengkapan Data Utama dari query lokal sebelum setup umum',
    () async {
      final intent = await interpreter.interpret('data utama sudah terisi?');

      expect(intent.type, FfmAssistantIntentType.queryData);
      expect(intent.response, contains('Kelengkapan Data Utama'));
      expect(intent.response, contains('kategori aktif'));
      expect(intent.draft, isNull);
    },
  );

  test('menjawab field profil personalisasi yang belum lengkap', () async {
    final intent = await interpreter.interpret('apakah profil sudah lengkap?');

    expect(intent.type, FfmAssistantIntentType.queryData);
    expect(intent.response, contains('Kelengkapan Profil Asisten'));
    expect(intent.response, contains('nama/panggilan'));
    expect(intent.draft, isNull);
  });

  test('menjawab isi Data Utama dari katalog, bukan fallback', () async {
    final intent = await interpreter.interpret('ada apa saja di data utama?');

    expect(intent.type, FfmAssistantIntentType.featureHelp);
    expect(intent.destination, FfmAssistantDestination.masterData);
    expect(intent.response, contains('enam bagian'));
    expect(intent.draft, isNull);
  });

  test(
    'memahami pertanyaan kemampuan ekspor PDF dari sinonim katalog',
    () async {
      final intent = await interpreter.interpret('bisa buat file pdf?');

      expect(intent.type, FfmAssistantIntentType.featureHelp);
      expect(intent.destination, FfmAssistantDestination.backup);
      expect(intent.response, startsWith('Ya. Ekspor & cadangan'));
      expect(intent.draft, isNull);
    },
  );

  test('proposal JSON rekening hanya membuat rancangan yang jelas', () {
    const proposal = '''
{
  "formatVersion": "ffm-assistant-proposal-v1",
  "proposal": {
    "type": "master_data",
    "target": "rekening",
    "name": "SeaBank",
    "fields": {"accountType": "bank", "openingBalance": "600000"},
    "note": "Buka form, cek dulu, lalu simpan sendiri."
  }
}
''';

    final parsed = FfmAssistantProposalJsonService.parse(
      proposal,
      createdAt: DateTime(2026, 8, 22),
    );

    expect(parsed.isProposal, isTrue);
    expect(parsed.error, isNull);
    expect(parsed.draft, isNotNull);
    expect(parsed.draft!.kind, FfmAssistantDraftKind.masterData);
    expect(parsed.draft!.title, 'SeaBank');
    expect(parsed.draft!.categoryName, 'rekening');
    expect(parsed.draft!.formValues['accountType'], 'bank');
    expect(parsed.draft!.formValues['openingBalance'], '600000');
  });

  test('klarifikasi JSON LLM tidak berubah menjadi rancangan kosong', () {
    const proposal = '''
{
  "formatVersion": "ffm-assistant-proposal-v1",
  "proposal": null,
  "clarification": "Rekeningnya mau jenis bank, tunai, atau e-wallet?"
}
''';

    final parsed = FfmAssistantProposalJsonService.parse(
      proposal,
      createdAt: DateTime(2026, 8, 22),
    );

    expect(parsed.isProposal, isTrue);
    expect(parsed.draft, isNull);
    expect(parsed.error, 'Rekeningnya mau jenis bank, tunai, atau e-wallet?');
  });

  test(
    'proposal JSON muncul sebagai rancangan Data Utama, bukan simpan',
    () async {
      const proposal = '''
{
  "formatVersion": "ffm-assistant-proposal-v1",
  "proposal": {
    "type": "master_data",
    "target": "kategori",
    "name": "Belanja Dapur",
    "fields": {"type": "pengeluaran", "defaultBudgetPeriod": "mingguan"}
  }
}
''';

      final intent = await interpreter.interpret(proposal);

      expect(intent.type, FfmAssistantIntentType.createMasterData);
      expect(intent.destination, FfmAssistantDestination.masterData);
      expect(intent.draft, isNotNull);
      expect(intent.draft!.title, 'Belanja Dapur');
      expect(intent.draft!.formValues['type'], 'expense');
      expect(intent.draft!.formValues['defaultBudgetPeriod'], 'weekly');
    },
  );

  test('menjawab pertanyaan pertama penggunaan dengan panduan lokal', () async {
    final intent = await interpreter.interpret(
      'pertamakali saya harus apa di aplikasi ini?',
    );

    expect(intent.type, FfmAssistantIntentType.setupGuide);
    expect(intent.response, contains('Data Utama'));
    expect(intent.response, contains('Catat transaksi pertama'));
    expect(intent.draft, isNull);
  });

  test(
    'menjawab langkah yang perlu dilakukan sekarang tanpa membuat draft',
    () async {
      final intent = await interpreter.interpret('sekarang saya harus apa?');

      expect(intent.type, FfmAssistantIntentType.setupGuide);
      expect(intent.response, contains('Kita mulai dari yang paling kepake'));
      expect(intent.response, contains('Catat transaksi pertama'));
      expect(intent.draft, isNull);
    },
  );

  test('menjawab tanggal Hijriah dari waktu lokal perangkat', () async {
    final localInterpreter = FfmAssistantInterpreter(
      database,
      clock: () => DateTime(2026, 8, 22, 10, 37),
    );

    final intent = await localInterpreter.interpret(
      'tanggal berapa sekarang? hijriah',
    );

    expect(intent.type, FfmAssistantIntentType.calendarQuery);
    expect(intent.response, contains('Tanggal Hijriah sekarang:'));
    expect(intent.response, contains('Kalender Hijriah FFM'));
    expect(intent.draft, isNull);
  });

  test('menjawab tanggal Hijriah besok dari waktu lokal perangkat', () async {
    final localInterpreter = FfmAssistantInterpreter(
      database,
      clock: () => DateTime(2026, 8, 22, 10, 37),
    );

    final intent = await localInterpreter.interpret(
      'Besok tanggal hijriah berapa?',
    );

    expect(intent.type, FfmAssistantIntentType.calendarQuery);
    expect(intent.response, contains('Tanggal Hijriah besok:'));
    expect(intent.response, contains('Kalender Hijriah FFM'));
    expect(intent.draft, isNull);
  });

  test('menjawab pertanyaan tentang profil pribadi dan rutinitas', () async {
    await (database.into(database.userPreferences)).insert(
      UserPreferencesCompanion.insert(
        id: 'pref-1',
        householdId: AppContext.householdId,
        preferenceKey: 'profile_occupation',
        preferenceValue: 'Petani cengkeh',
        updatedAt: DateTime.now(),
      ),
    );

    final intent = await interpreter.interpret('apa pekerjaan saya?');

    expect(intent.type, FfmAssistantIntentType.queryData);
    expect(intent.response, contains('Petani cengkeh'));
    expect(intent.response, contains('Profil & Kebiasaan'));
    expect(intent.draft, isNull);
  });

  test('menjawab pertanyaan tentang riwayat aktivitas dan kebiasaan', () async {
    await (database.into(database.activityEntries)).insert(
      ActivityEntriesCompanion.insert(
        id: 'entry-1',
        householdId: AppContext.householdId,
        title: 'Panen Mingguan',
        activityType: const Value('Rutinitas'),
        startedAt: DateTime.now().subtract(const Duration(days: 1)),
        createdAt: DateTime.now(),
      ),
    );

    final intent = await interpreter.interpret('apa kebiasaan kegiatan saya?');

    expect(intent.type, FfmAssistantIntentType.queryData);
    expect(intent.response, contains('Riwayat Aktivitas'));
    expect(intent.response, contains('Panen Mingguan'));
    expect(intent.draft, isNull);
  });

  test(
    'menjawab query analisis kemampuan cicilan (Loan Affordability)',
    () async {
      final intent = await interpreter.interpret(
        'berapa cicilan maksimal yang aman untuk saya?',
      );

      expect(intent.type, FfmAssistantIntentType.queryData);
      expect(intent.response, contains('Kemampuan Pinjaman'));
      expect(intent.response, contains('30%'));
      expect(intent.draft, isNull);
    },
  );

  test('mengenali frasa hijri dan islam sebagai permintaan Hijriah', () async {
    final localInterpreter = FfmAssistantInterpreter(
      database,
      clock: () => DateTime(2026, 8, 22, 10, 37),
    );

    for (final request in const [
      'hari ini hijri berapa?',
      'tanggal islam sekarang?',
    ]) {
      final intent = await localInterpreter.interpret(request);

      expect(intent.type, FfmAssistantIntentType.calendarQuery);
      expect(intent.response, contains('Kalender Hijriah FFM'));
      expect(intent.draft, isNull);
    }
  });

  test(
    'fallback yang belum dipahami tetap singkat dan mengarahkan latihan',
    () async {
      final intent = await interpreter.interpret(
        'apa arti kalimat buatan xyz?',
      );

      expect(intent.type, FfmAssistantIntentType.unknown);
      expect(intent.response, contains('belum punya jawaban yang pas'));
      expect(intent.response, contains('Benarkan & kirim ulang'));
      expect(intent.response, contains('Pengetahuan Asisten'));
      expect(intent.response, contains('salin atau ekspor'));
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

  test('menjawab status fitur non-data secara jujur dari katalog', () async {
    final intent = await interpreter.interpret(
      'apakah cadangan saya sudah lengkap?',
    );

    expect(intent.type, FfmAssistantIntentType.featureHelp);
    expect(intent.destination, FfmAssistantDestination.backup);
    expect(intent.response, contains('bukan section data'));
    expect(intent.draft, isNull);
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

  test('menyebutkan halaman aktif dari konteks UI tanpa query data', () async {
    final intent = await interpreter.interpret(
      'saya sedang di halaman apa?',
      currentDestination: FfmAssistantDestination.transactions,
    );

    expect(intent.type, FfmAssistantIntentType.help);
    expect(intent.destination, FfmAssistantDestination.transactions);
    expect(intent.draft, isNull);
    expect(
      intent.response,
      startsWith('Sekarang kamu ada di halaman Transaksi.'),
    );
  });

  test('memeriksa anggaran tanpa membuat draft atau menyimpan data', () async {
    final intent = await interpreter.interpret('Cek anggaran saya');

    expect(intent.type, FfmAssistantIntentType.financialWarnings);
    expect(intent.destination, FfmAssistantDestination.budget);
    expect(intent.draft, isNull);
    expect(intent.response, contains('Belum ada anggaran aktif'));
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

  test('membuat draft perkenalan diri dari perintah profil', () async {
    final intent = await interpreter.interpret(
      'buat profil saya: nama Rudi, pekerjaan petani, rutinitas panen jumat',
    );

    expect(intent.type, FfmAssistantIntentType.createProfile);
    expect(intent.destination, FfmAssistantDestination.assistantProfile);
    expect(intent.draft?.kind, FfmAssistantDraftKind.profile);
    expect(intent.draft?.title, 'Perkenalan Diri');
    expect(intent.needsClarification, isTrue);
    expect(intent.clarification, contains('tujuan'));
    expect(intent.response, isNull);
  });

  test('jawaban lanjutan melengkapi draft profil yang tertahan', () async {
    final initial = await interpreter.interpret(
      'buat profil saya: nama Rudi, pekerjaan petani, rutinitas panen jumat',
    );
    final pending = FfmAssistantPendingDialog(
      originalRequest: initial.rawText,
      prompt: initial.clarification!,
      missingFields: const ['tujuan'],
      draft: initial.draft,
    );

    final resolved = await interpreter.resolvePendingDialog(
      'tujuan saya menabung untuk rumah',
      pending,
    );

    expect(resolved.single.needsClarification, isFalse);
    expect(resolved.single.draft?.formValues['Nama'], 'Rudi');
    expect(resolved.single.draft?.formValues['Tujuan'], 'menabung untuk rumah');
    expect(await database.select(database.userPreferences).get(), isEmpty);
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

  test('membuat draft Data Utama, mengarahkan Anggaran manual, pengingat, dan aktivitas', () async {
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
    expect(budget.draft, isNull);
    expect(budget.response, contains('belum diizinkan'));
    expect(reminder.type, FfmAssistantIntentType.createReminder);
    expect(reminder.destination, FfmAssistantDestination.reminders);
    expect(activity.type, FfmAssistantIntentType.createActivity);
    expect(activity.destination, FfmAssistantDestination.activity);
    expect(activity.needsConfirmation, isTrue);

    expect(await database.select(database.envelopeBudgets).get(), isEmpty);
    expect(await database.select(database.activitySessions).get(), isEmpty);
  });

  test('pindah ke halaman tanpa kata menu tetap membuka tujuan', () async {
    final intent = await interpreter.interpret('Pindah ke Data Utama');

    expect(intent.type, FfmAssistantIntentType.openPage);
    expect(intent.destination, FfmAssistantDestination.masterData);
  });

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

  test(
    'perintah majemuk yang ambigu meminta klarifikasi tanpa menebak draft',
    () async {
      final result = await interpreter.interpretMany(
        'transfer 50 ribu dari Tunai lalu beli makan 20 ribu',
      );

      expect(result, hasLength(2));
      final transfer = result.first;
      expect(transfer.type, FfmAssistantIntentType.createTransfer);
      expect(transfer.needsClarification, isTrue);
      expect(transfer.clarification, contains('rekening tujuan'));
      expect(transfer.draft?.toAccountName, isNull);

      final expense = result.last;
      expect(expense.type, FfmAssistantIntentType.createExpense);
      expect(expense.draft?.amount, 20000);
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

  test('parser kata-bilangan menangani angka majemuk tanpa membuang sisa', () {
    expect(FfmAssistantAmountParser.parse('dua ratus ribu'), 200000);
    expect(FfmAssistantAmountParser.parse('tiga puluh lima ribu'), 35000);
    expect(FfmAssistantAmountParser.parse('dua ribu lima ratus'), 2500);
    expect(
      FfmAssistantAmountParser.parse('seratus dua puluh lima ribu'),
      125000,
    );
    expect(FfmAssistantAmountParser.parse('satu juta dua ratus ribu'), 1200000);
    expect(FfmAssistantAmountParser.parse('dua juta lima ratus ribu'), 2500000);
    expect(FfmAssistantAmountParser.parse('lima belas ribu'), 15000);
    expect(FfmAssistantAmountParser.parse('satu setengah juta'), 1500000);
    expect(FfmAssistantAmountParser.parse('seribu lima ratus'), 1500);
    expect(FfmAssistantAmountParser.parse('semiliar'), 1000000000);
  });

  test('menjelaskan status Gemini saat pertanyaan butuh cloud', () async {
    final intent = await interpreter.interpret('Berapa harga cabai hari ini?');

    expect(intent.responseOrigin, FfmAssistantResponseOrigin.cloudError);
    expect(
      intent.response,
      contains('Koneksi ke otak AI saya (Gemini) belum siap'),
    );
    expect(intent.response, contains('Setup Sekarang'));
  });

  test(
    'Pilar 1: Multi-Action Chaining memecah perintah majemuk dengan "dan"',
    () async {
      final intents = await interpreter.interpretMany(
        'catat belanja 50 ribu dari Tunai dan transfer 100 ribu dari SeaBank ke Tunai',
      );

      expect(intents, hasLength(2));
      expect(intents.first.type, FfmAssistantIntentType.createExpense);
      expect(intents.first.draft?.amount, 50000);
      expect(intents.last.type, FfmAssistantIntentType.createTransfer);
      expect(intents.last.draft?.amount, 100000);
    },
  );

  test(
    'Pilar 2: Coreference resolution memahami rujukan "dari situ"',
    () async {
      // 1. Simpan entitas SeaBank
      await interpreter.interpret('catat belanja 50 ribu dari SeaBank');
      // 2. Gunakan kata rujukan "dari situ"
      final intent = await interpreter.interpret(
        'beli bensin 20 ribu dari situ',
      );

      expect(intent.type, FfmAssistantIntentType.createExpense);
      expect(intent.draft?.amount, 20000);
      expect(intent.draft?.fromAccountName, 'SeaBank');
    },
  );

  test(
    'menjelaskan fitur kalender perangkat dan Hijriah secara informatif',
    () async {
      final calendarIntent = await interpreter.interpret(
        'kalender perangkat ada apa saja?',
      );
      expect(calendarIntent.type, FfmAssistantIntentType.calendarQuery);
      expect(calendarIntent.response, contains('Kalender di FFM & Perangkat'));
      expect(calendarIntent.response, contains('Kalender Masehi'));
      expect(calendarIntent.response, contains('Kalender Hijriah'));
    },
  );

  test(
    'merutekan identitas aplikasi dan kemampuan gambar tanpa jadi unknown',
    () async {
      final app = await interpreter.interpret('aplikasi apa ini?');
      final image = await interpreter.interpret('bisa lihat gambar?');

      expect(app.type, FfmAssistantIntentType.assistantIdentity);
      // Fitur pembacaan gambar/struk sudah dihapus: pertanyaan kemampuan
      // gambar dijawab jujur sebagai bantuan teks, bukan unknown.
      expect(image.type, FfmAssistantIntentType.help);
      expect(image.response, contains('hanya menerima perintah teks'));
    },
  );

  test('Cash satu kata meminta klarifikasi tanpa action plan', () async {
    final intent = await interpreter.interpret('cash');

    expect(intent.type, FfmAssistantIntentType.help);
    expect(intent.clarification, contains('Maksud Cash'));
    expect(const FfmAssistantActionPlanner().planFor(intent), isNull);
  });

  test('verifikasi Cash membaca rekening aktif dan tidak menyusun read-plan transaksi', () async {
    final intent = await interpreter.interpret('sudah saya tambahkan cash');

    expect(intent.type, FfmAssistantIntentType.help);
    expect(intent.response, contains('satu rekening Cash yang aktif'));
    expect(const FfmAssistantActionPlanner().planFor(intent), isNull);
  });

  test(
    'status Gemini mengarah ke Dashboard dan navigasi anggaran tetap eksplisit',
    () async {
      final status = await interpreter.interpret(
        'sekarang sudah terhubung Gemini?',
      );
      final budget = await interpreter.interpret('cek halaman anggaran');

      expect(status.type, FfmAssistantIntentType.help);
      expect(status.destination, FfmAssistantDestination.intelligenceDashboard);
      expect(status.response, contains('Dashboard Intelligence'));
      expect(budget.type, FfmAssistantIntentType.openPage);
      expect(budget.destination, FfmAssistantDestination.budget);
    },
  );

  test(
    'pertanyaan anggaran hampir habis memakai query peringatan lokal',
    () async {
      final intent = await interpreter.interpret(
        'Apakah ada anggaran yang hampir habis?',
      );

      expect(intent.type, FfmAssistantIntentType.financialWarnings);
      expect(intent.destination, FfmAssistantDestination.budget);
      expect(intent.response, contains('Belum ada anggaran aktif'));
    },
  );

  test(
    'panduan awal ditangani sebagai setup flow berbasis data lokal',
    () async {
      final intent = await interpreter.interpret('sekarang saya harus apa?');

      expect(intent.type, isNot(FfmAssistantIntentType.unknown));
      expect(intent.response, isNotEmpty);
    },
  );

  test(
    'jalur VN memakai interpreter yang menghasilkan draft aktivitas tanpa menulis database',
    () async {
      final intent = await interpreter.interpret(
        'mulai memupuk timun',
        currentDestination: FfmAssistantDestination.activity,
        activitySnapshot: ActivityLiveSnapshot(
          activeSessions: const [],
        ),
      );

      expect(intent.draft, isNotNull);
      expect(intent.draft!.kind, FfmAssistantDraftKind.activity);
      expect(intent.draft!.title, isNotEmpty);
      expect(intent.type, isNot(FfmAssistantIntentType.unknown));
    },
  );

  test('menjawab pertanyaan identitas pembuat dan konsep data lokal', () async {
    final creatorIntent = await interpreter.interpret(
      'siapa yang membuat kamu?',
    );
    expect(creatorIntent.type, FfmAssistantIntentType.assistantIdentity);
    expect(creatorIntent.response, contains('Rafi Sinkkat'));

    final rafiIntent = await interpreter.interpret('rafi sinkkat siapa?');
    expect(rafiIntent.type, FfmAssistantIntentType.assistantIdentity);
    expect(rafiIntent.response, contains('Rafi Sinkkat'));

    final dataLokalIntent = await interpreter.interpret('data lokal?');
    expect(dataLokalIntent.type, FfmAssistantIntentType.help);
    expect(dataLokalIntent.response, contains('Data Lokal'));
    expect(dataLokalIntent.response, contains('100% Offline'));
  });
}
