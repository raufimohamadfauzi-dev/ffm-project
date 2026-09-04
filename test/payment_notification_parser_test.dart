import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/data/payment_notification_parser.dart';
import 'package:ffm_manager/features/assistant/data/payment_draft_repository.dart';

void main() {
  group('PaymentNotificationParser', () {
    // -------------------------------------------------------------------------
    // Ekstraksi nominal
    // -------------------------------------------------------------------------

    group('ekstraksi nominal', () {
      test('format Rp 45.000', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.bca',
          title: 'BCA Mobile',
          body: 'Pembayaran QRIS ke KOPI KENANGAN berhasil. Rp 45.000',
        );
        expect(result, isNotNull);
        expect(result!.amount, equals(45000.0));
      });

      test('format Rp. 120.500', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.bankmandiri.livin',
          title: "Livin' Mandiri",
          body: 'Transfer ke BUDI berhasil sebesar Rp. 120.500',
        );
        expect(result, isNotNull);
        expect(result!.amount, equals(120500.0));
      });

      test('format IDR 50,000', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'id.dana',
          title: 'DANA',
          body: 'Pembayaran berhasil. IDR 50,000 ke INDOMARET',
        );
        expect(result, isNotNull);
        expect(result!.amount, equals(50000.0));
      });

      test('nominal tidak ada => return null', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.bca',
          title: 'BCA Mobile',
          body: 'Verifikasi akun Anda telah berhasil.',
        );
        expect(result, isNull);
      });
    });

    // -------------------------------------------------------------------------
    // Deteksi merchant
    // -------------------------------------------------------------------------

    group('deteksi merchant', () {
      test('pola QRIS ke MERCHANT', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.bca',
          title: 'BCA Mobile',
          body: 'QRIS ke KOPI KENANGAN berhasil Rp 25.000',
        );
        expect(result, isNotNull);
        expect(result!.merchantName, equals('KOPI KENANGAN'));
      });

      test('pola di MERCHANT', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'ovo.id',
          title: 'OVO',
          body: 'Kamu telah membayar Rp 24.000 di INDOMARET berhasil.',
        );
        expect(result, isNotNull);
        expect(result!.merchantName, equals('INDOMARET'));
      });

      test('pola Transfer ke NAMA', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'id.co.bri.brimo',
          title: 'BRImo',
          body: 'Transfer ke BUDI SANTOSO berhasil Rp 150.000',
        );
        expect(result, isNotNull);
        expect(result!.merchantName, equals('BUDI SANTOSO'));
      });
    });

    // -------------------------------------------------------------------------
    // Deteksi jenis mutasi
    // -------------------------------------------------------------------------

    group('deteksi jenis mutasi', () {
      test('debit: pembayaran QRIS', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.bca',
          title: 'BCA Mobile',
          body: 'Pembayaran QRIS ke ALFAMART berhasil Rp 33.000',
        );
        expect(result, isNotNull);
        expect(result!.mutationType, equals(PaymentMutationType.debit));
      });

      test('credit: top-up e-wallet', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.gojek.app',
          title: 'GoPay',
          body: 'Top-up berhasil Rp 100.000 masuk ke GoPay Anda',
        );
        expect(result, isNotNull);
        expect(result!.mutationType, equals(PaymentMutationType.credit));
      });
    });

    // -------------------------------------------------------------------------
    // Saran kategori
    // -------------------------------------------------------------------------

    group('saran kategori', () {
      test('kopi kenangan => Makanan & Minuman', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.bca',
          title: 'BCA',
          body: 'QRIS ke KOPI KENANGAN berhasil Rp 28.000',
        );
        expect(result?.suggestedCategory, equals('Makanan & Minuman'));
      });

      test('indomaret => Belanja & Ritel', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'ovo.id',
          title: 'OVO',
          body: 'Bayar Rp 55.000 di INDOMARET berhasil.',
        );
        expect(result?.suggestedCategory, equals('Belanja & Ritel'));
      });

      test('spbu => Transportasi', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.bca',
          title: 'BCA',
          body: 'QRIS ke SPBU PERTAMINA berhasil Rp 80.000',
        );
        expect(result?.suggestedCategory, equals('Transportasi'));
      });

      test('merchant tidak dikenal => suggestedCategory null', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.bca',
          title: 'BCA',
          body: 'Transfer ke BUDI SANTOSO berhasil Rp 200.000',
        );
        expect(result, isNotNull);
        expect(result!.suggestedCategory, isNull);
      });
    });

    // -------------------------------------------------------------------------
    // Label akun
    // -------------------------------------------------------------------------

    group('labelFor', () {
      test('com.bca => BCA Mobile', () {
        expect(PaymentNotificationParser.labelFor('com.bca'), equals('BCA Mobile'));
      });
      test('ovo.id => OVO', () {
        expect(PaymentNotificationParser.labelFor('ovo.id'), equals('OVO'));
      });
      test('id.dana => DANA', () {
        expect(PaymentNotificationParser.labelFor('id.dana'), equals('DANA'));
      });
      test('com.shopee.id => ShopeePay', () {
        expect(PaymentNotificationParser.labelFor('com.shopee.id'), equals('ShopeePay'));
      });
      test('package tidak dikenal => kembalikan package itu sendiri', () {
        expect(PaymentNotificationParser.labelFor('com.unknown.app'), equals('com.unknown.app'));
      });
    });

    // -------------------------------------------------------------------------
    // Anti false-positive: notifikasi non-pembayaran
    // -------------------------------------------------------------------------

    group('non-pembayaran => null', () {
      test('notifikasi promo tanpa nominal Rp', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.bca',
          title: 'BCA Mobile',
          body: 'Dapatkan cashback 10% untuk transaksi weekend ini!',
        );
        expect(result, isNull);
      });

      test('notifikasi umum tanpa nominal', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.gojek.app',
          title: 'GoPay',
          body: 'Transaksi Anda sedang diproses.',
        );
        expect(result, isNull);
      });

      test('notifikasi kosong', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.bca',
          title: '',
          body: '',
        );
        expect(result, isNull);
      });
    });
  });

  // ---------------------------------------------------------------------------
  // PaymentDraft formattedAmount
  // ---------------------------------------------------------------------------

  group('PaymentDraft.formattedAmount', () {
    PaymentDraft makeDraft(double amount) => PaymentDraft(
          id: 'test',
          sourceApp: 'com.bca',
          rawTitle: '',
          rawBody: '',
          amount: amount,
          merchantName: '',
          mutationType: PaymentMutationType.debit,
          createdAt: DateTime.now(),
        );

    test('45000 => Rp 45.000', () {
      expect(makeDraft(45000).formattedAmount, equals('Rp 45.000'));
    });

    test('1500000 => Rp 1.500.000', () {
      expect(makeDraft(1500000).formattedAmount, equals('Rp 1.500.000'));
    });

    test('500 => Rp 500', () {
      expect(makeDraft(500).formattedAmount, equals('Rp 500'));
    });
  });
}
