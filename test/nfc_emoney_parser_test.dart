import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/nfc_bridge.dart';
import 'package:ffm_manager/features/assistant/data/nfc_card_repository.dart';
import 'package:ffm_manager/features/assistant/data/payment_draft_repository.dart';
import 'package:ffm_manager/features/assistant/data/payment_notification_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NfcCardScanResult', () {
    test('formater balance dan label kartu Mandiri e-Money', () {
      const scan = NfcCardScanResult(
        cardId: 'MANDIRI-12345678',
        balance: 80000.0,
        cardType: 'mandiri_emoney',
        success: true,
      );

      expect(scan.cardTypeLabel, equals('Mandiri e-Money'));
      expect(scan.formattedBalance, equals('Rp 80.000'));
    });

    test('formater balance dan label kartu BCA Flazz', () {
      const scan = NfcCardScanResult(
        cardId: 'FLAZZ-87654321',
        balance: 150000.0,
        cardType: 'flazz_bca',
        success: true,
      );

      expect(scan.cardTypeLabel, equals('BCA Flazz'));
      expect(scan.formattedBalance, equals('Rp 150.000'));
    });
  });

  group('NfcCardRepository Engine Adaptasi Saldo', () {
    late PaymentDraftRepository draftRepo;
    late NfcCardRepository nfcRepo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      draftRepo = PaymentDraftRepository();
      nfcRepo = NfcCardRepository(draftRepo);
    });

    test('Scan 1 (Baseline Kartu Baru) => Simpan saldo tanpa membuat draft',
        () async {
      const scan1 = NfcCardScanResult(
        cardId: 'MANDIRI-1001',
        balance: 100000.0,
        cardType: 'mandiri_emoney',
        success: true,
      );

      final res1 = await nfcRepo.processCardScan(scan1);

      expect(res1.isBaseline, isTrue);
      expect(res1.previousBalance, isNull);
      expect(res1.newBalance, equals(100000.0));
      expect(res1.difference, equals(0.0));
      expect(res1.draft, isNull);

      final accounts = await nfcRepo.getCardAccounts();
      expect(accounts.length, equals(1));
      expect(accounts.first.lastKnownBalance, equals(100000.0));
    });

    test('Scan 2 (Pengeluaran Tol/Parkir) => Buat PaymentDraft Debit', () async {
      // Baseline 100.000
      const scan1 = NfcCardScanResult(
        cardId: 'MANDIRI-1001',
        balance: 100000.0,
        cardType: 'mandiri_emoney',
        success: true,
      );
      await nfcRepo.processCardScan(scan1);

      // Scan 2: Saldo turun menjadi 80.000 (Pengeluaran 20.000)
      const scan2 = NfcCardScanResult(
        cardId: 'MANDIRI-1001',
        balance: 80000.0,
        cardType: 'mandiri_emoney',
        success: true,
      );
      final res2 = await nfcRepo.processCardScan(scan2);

      expect(res2.isBaseline, isFalse);
      expect(res2.previousBalance, equals(100000.0));
      expect(res2.newBalance, equals(80000.0));
      expect(res2.difference, equals(20000.0));
      expect(res2.draft, isNotNull);
      expect(res2.draft!.amount, equals(20000.0));
      expect(res2.draft!.mutationType, equals(PaymentMutationType.debit));

      final pendingDrafts = await draftRepo.getPendingDrafts();
      expect(pendingDrafts.length, equals(1));
      expect(pendingDrafts.first.amount, equals(20000.0));
    });

    test('Scan 3 (Top-Up / Isi Ulang) => Buat PaymentDraft Credit', () async {
      // Baseline 80.000
      const scan1 = NfcCardScanResult(
        cardId: 'FLAZZ-2002',
        balance: 80000.0,
        cardType: 'flazz_bca',
        success: true,
      );
      await nfcRepo.processCardScan(scan1);

      // Scan 2: Saldo naik menjadi 180.000 (Top-Up 100.000)
      const scan2 = NfcCardScanResult(
        cardId: 'FLAZZ-2002',
        balance: 180000.0,
        cardType: 'flazz_bca',
        success: true,
      );
      final res2 = await nfcRepo.processCardScan(scan2);

      expect(res2.isBaseline, isFalse);
      expect(res2.difference, equals(-100000.0)); // Negatif artinya top-up
      expect(res2.draft, isNotNull);
      expect(res2.draft!.amount, equals(100000.0));
      expect(res2.draft!.mutationType, equals(PaymentMutationType.credit));
    });

    test('Scan 4 (Saldo Sama) => Tidak buat draft', () async {
      const scan1 = NfcCardScanResult(
        cardId: 'TAPCASH-3003',
        balance: 50000.0,
        cardType: 'bni_tapcash',
        success: true,
      );
      await nfcRepo.processCardScan(scan1);

      // Scan ulang dengan saldo sama
      const scan2 = NfcCardScanResult(
        cardId: 'TAPCASH-3003',
        balance: 50000.0,
        cardType: 'bni_tapcash',
        success: true,
      );
      final res2 = await nfcRepo.processCardScan(scan2);

      expect(res2.difference, equals(0.0));
      expect(res2.draft, isNull);
    });

    test('Kartu terdeteksi tanpa saldo tidak membuat draft nominal', () async {
      const scan1 = NfcCardScanResult(
        cardId: 'DEBIT-4004',
        balance: 0.0,
        cardType: 'bank_card',
        success: true,
        balanceAvailable: false,
      );
      await nfcRepo.processCardScan(scan1);

      const scan2 = NfcCardScanResult(
        cardId: 'DEBIT-4004',
        balance: 0.0,
        cardType: 'bank_card',
        success: true,
        balanceAvailable: false,
      );
      final result = await nfcRepo.processCardScan(scan2);

      expect(result.balanceAvailable, isFalse);
      expect(result.draft, isNull);
      expect(await draftRepo.getAllDrafts(), isEmpty);
    });

    test('Scan pertama pada bulan baru menjadi baseline baru', () async {
      var now = DateTime(2026, 9, 30, 12);
      final monthlyRepo = NfcCardRepository(draftRepo, clock: () => now);
      await monthlyRepo.processCardScan(
        const NfcCardScanResult(
          cardId: 'MONTHLY-5005',
          balance: 100000,
          cardType: 'mandiri_emoney',
          success: true,
        ),
      );

      now = DateTime(2026, 10, 1, 8);
      final result = await monthlyRepo.processCardScan(
        const NfcCardScanResult(
          cardId: 'MONTHLY-5005',
          balance: 50000,
          cardType: 'mandiri_emoney',
          success: true,
        ),
      );

      expect(result.isBaseline, isTrue);
      expect(result.difference, 0);
      expect(result.draft, isNull);
    });

    test('menyimpan metadata dan snapshot scan hanya ke database NFC', () async {
      final database = AppDatabase(NativeDatabase.memory());
      final repository = NfcCardRepository(
        draftRepo,
        database: database,
        householdId: 'migration-household',
      );

      await repository.processCardScan(
        const NfcCardScanResult(
          cardId: 'DATABASE-1',
          balance: 75000,
          cardType: 'mandiri_emoney',
          success: true,
        ),
      );

      final cards = await database.select(database.nfcCardAccounts).get();
      final snapshots = await database.select(database.nfcScanSnapshots).get();
      expect(cards, hasLength(1));
      expect(cards.single.cardType, 'mandiri_emoney');
      expect(cards.single.cardUidHash, isNot('DATABASE-1'));
      expect(snapshots, hasLength(1));
      await database.close();
    });

    test('scan database kedua membuat satu draft dari selisih saldo', () async {
      final database = AppDatabase(NativeDatabase.memory());
      var now = DateTime(2026, 9, 10, 8);
      final repository = NfcCardRepository(
        draftRepo,
        database: database,
        householdId: 'database-household',
        clock: () => now,
      );
      const initial = NfcCardScanResult(
        cardId: 'DATABASE-2',
        balance: 100000,
        cardType: 'mandiri_emoney',
        success: true,
      );
      await repository.processCardScan(initial);
      now = now.add(const Duration(hours: 1));
      final result = await repository.processCardScan(
        const NfcCardScanResult(
          cardId: 'DATABASE-2',
          balance: 80000,
          cardType: 'mandiri_emoney',
          success: true,
        ),
      );

      expect(result.draft?.amount, 20000);
      expect(await draftRepo.getPendingDrafts(), hasLength(1));
      expect(await database.select(database.accounts).get(), hasLength(1));
      expect(await database.select(database.nfcScanSnapshots).get(), hasLength(2));
      await database.close();
    });

    test('updateCardAlias memperbarui alias kartu di nfcCardAccounts dan accounts', () async {
      final database = AppDatabase(NativeDatabase.memory());
      final repository = NfcCardRepository(
        draftRepo,
        database: database,
        householdId: 'alias-household',
      );

      const scan = NfcCardScanResult(
        cardId: 'MANDIRI-ALIAS-99',
        balance: 150000,
        cardType: 'mandiri_emoney',
        success: true,
      );
      await repository.processCardScan(scan);

      // Pastikan akun terbentuk
      var cards = await repository.getCardAccounts();
      expect(cards, hasLength(1));
      expect(cards.first.displayName, 'Mandiri e-Money');

      // Update alias kartu menjadi nama kustom
      final updated = await repository.updateCardAlias('MANDIRI-ALIAS-99', 'e-Money Pajero Ayah');
      expect(updated, isTrue);

      // Cek di domain model repository
      cards = await repository.getCardAccounts();
      expect(cards.first.displayName, 'e-Money Pajero Ayah');
      expect(cards.first.issuer, 'e-Money Pajero Ayah');

      // Cek di SQLite database: nfcCardAccounts & accounts
      final dbCards = await database.select(database.nfcCardAccounts).get();
      expect(dbCards.single.issuer, 'e-Money Pajero Ayah');

      final dbAccounts = await database.select(database.accounts).get();
      expect(dbAccounts.single.name, 'e-Money Pajero Ayah');

      await database.close();
    });

    test('Scan kartu dengan history transaksi APDU membuat historyDrafts', () async {
      final database = AppDatabase(NativeDatabase.memory());
      final repository = NfcCardRepository(
        draftRepo,
        database: database,
        householdId: 'history-household',
      );

      final historyItems = [
        const NfcTransactionLogItem(
          recordIndex: 1,
          amount: 15000,
        ),
        const NfcTransactionLogItem(
          recordIndex: 2,
          amount: 5000,
        ),
      ];

      final scanWithHistory = NfcCardScanResult(
        cardId: 'MANDIRI-HIST-1',
        balance: 80000,
        cardType: 'mandiri_emoney',
        success: true,
        history: historyItems,
      );

      final res = await repository.processCardScan(scanWithHistory);

      expect(res.isBaseline, isTrue);
      expect(res.historyDrafts, hasLength(2));
      expect(res.historyDrafts.first.amount, 15000);
      expect(res.historyDrafts.first.rawBody, contains('#1'));
      expect(res.historyDrafts.last.amount, 5000);
      expect(res.historyDrafts.last.rawBody, contains('#2'));

      final pendingDrafts = await draftRepo.getPendingDrafts();
      expect(pendingDrafts, hasLength(2));

      await database.close();
    });

    test('Scan hari ini lalu scan besok tidak menduplikasi draft yang sudah dikonfirmasi', () async {
      final database = AppDatabase(NativeDatabase.memory());
      var currentTime = DateTime(2026, 9, 5, 10, 0);
      final repository = NfcCardRepository(
        draftRepo,
        database: database,
        householdId: 'dedup-household',
        clock: () => currentTime,
      );

      const historyItems = [
        NfcTransactionLogItem(
          recordIndex: 1,
          amount: 15000,
          rawHex: '0102030405060708090A0B0C0D0E0F10',
        ),
      ];

      // Hari ini: Scan pertama kali
      final scanToday = NfcCardScanResult(
        cardId: 'MANDIRI-DEDUP-1',
        balance: 85000,
        cardType: 'mandiri_emoney',
        success: true,
        history: historyItems,
      );
      final resToday = await repository.processCardScan(scanToday);
      expect(resToday.historyDrafts, hasLength(1));

      // Pengguna mengonfirmasi draft menjadi transaksi
      final draftId = resToday.historyDrafts.first.id;
      await draftRepo.updateStatus(draftId, PaymentDraftStatus.confirmed);
      expect(await draftRepo.getPendingDrafts(), isEmpty);

      // Besok: 24 jam kemudian kartu di-scan lagi dengan saldo dan log chip yang masih sama
      currentTime = currentTime.add(const Duration(hours: 24));
      final scanTomorrow = NfcCardScanResult(
        cardId: 'MANDIRI-DEDUP-1',
        balance: 85000,
        cardType: 'mandiri_emoney',
        success: true,
        history: historyItems,
      );
      final resTomorrow = await repository.processCardScan(scanTomorrow);

      // Saldo sama => tidak ada draft saldo baru
      expect(resTomorrow.draft, isNull);
      // Log chip sama & sudah pernah dikonfirmasi => tidak dibuatkan draft duplikat
      expect(resTomorrow.historyDrafts, isEmpty);
      expect(await draftRepo.getPendingDrafts(), isEmpty);

      await database.close();
    });

    test('Parsing URI NDEF Smart Tag Trigger ffm://action', () {
      const fuelUriString = 'ffm://action?type=fuel&title=Bensin&category=Transportasi';
      final fuelUri = Uri.parse(fuelUriString);
      expect(fuelUri.scheme, 'ffm');
      expect(fuelUri.host, 'action');
      expect(fuelUri.queryParameters['type'], 'fuel');
      expect(fuelUri.queryParameters['title'], 'Bensin');
      expect(fuelUri.queryParameters['category'], 'Transportasi');

      const voiceUriString = 'ffm://action?type=voice_assistant';
      final voiceUri = Uri.parse(voiceUriString);
      expect(voiceUri.scheme, 'ffm');
      expect(voiceUri.queryParameters['type'], 'voice_assistant');

      const timerUriString = 'ffm://action?type=timer_activity&title=Sesi+Kerja+Tani';
      final timerUri = Uri.parse(timerUriString);
      expect(timerUri.scheme, 'ffm');
      expect(timerUri.queryParameters['type'], 'timer_activity');
      expect(timerUri.queryParameters['title'], 'Sesi Kerja Tani');
    });
  });
}
