import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });
}
