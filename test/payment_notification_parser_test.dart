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
        expect(
          PaymentNotificationParser.labelFor('com.bca'),
          equals('BCA Mobile'),
        );
      });
      test('ovo.id => OVO', () {
        expect(PaymentNotificationParser.labelFor('ovo.id'), equals('OVO'));
      });
      test('id.dana => DANA', () {
        expect(PaymentNotificationParser.labelFor('id.dana'), equals('DANA'));
      });
      test('com.shopee.id => ShopeePay', () {
        expect(
          PaymentNotificationParser.labelFor('com.shopee.id'),
          equals('ShopeePay'),
        );
      });
      test('com.seabank.id => SeaBank', () {
        expect(
          PaymentNotificationParser.labelFor('com.seabank.id'),
          equals('SeaBank'),
        );
      });
      test('com.gojek.app => GoPay', () {
        expect(
          PaymentNotificationParser.labelFor('com.gojek.app'),
          equals('GoPay'),
        );
      });
      test('com.gopay.wallet => GoPay', () {
        expect(
          PaymentNotificationParser.labelFor('com.gopay.wallet'),
          equals('GoPay'),
        );
      });
      test('package tidak dikenal => kembalikan package itu sendiri', () {
        expect(
          PaymentNotificationParser.labelFor('com.unknown.app'),
          equals('com.unknown.app'),
        );
      });
      test('aplikasi tambahan memakai label yang benar', () {
        expect(PaymentNotificationParser.labelFor('id.flip'), equals('Flip'));
        expect(
          PaymentNotificationParser.labelFor('id.dana.kasir'),
          equals('DANA Bisnis'),
        );
        expect(
          PaymentNotificationParser.labelFor('com.isaku.app'),
          equals('i.saku'),
        );
        expect(
          PaymentNotificationParser.labelFor('com.spin.app.latest'),
          equals('MotionPay'),
        );
      });
    });

    // -------------------------------------------------------------------------
    // Skenario Spesifik: SeaBank & GoPay
    // -------------------------------------------------------------------------

    group('SeaBank & GoPay real-world scenarios', () {
      test('SeaBank transfer keluar', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.seabank.id',
          title: 'Transfer Berhasil',
          body: 'Transfer sebesar Rp 75.000 ke BUDI SANTOSO berhasil.',
        );
        expect(result, isNotNull);
        expect(result!.amount, equals(75000.0));
        expect(result.accountLabel, equals('SeaBank'));
        expect(result.merchantName, equals('BUDI SANTOSO'));
        expect(result.mutationType, equals(PaymentMutationType.debit));
      });

      test('SeaBank transfer masuk (kredit)', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.seabank.id',
          title: 'Transfer Masuk',
          body: 'Transfer masuk sebesar Rp 150.000 dari SITI AISYAH telah masuk ke rekening Anda.',
        );
        expect(result, isNotNull);
        expect(result!.amount, equals(150000.0));
        expect(result.accountLabel, equals('SeaBank'));
        expect(result.merchantName, equals('SITI AISYAH'));
        expect(result.mutationType, equals(PaymentMutationType.credit));
      });

      test('SeaBank pembayaran QRIS', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.seabank.id',
          title: 'Pembayaran Berhasil',
          body: 'QRIS ke KOPI KENANGAN sebesar Rp 25.000 berhasil via SeaBank',
        );
        expect(result, isNotNull);
        expect(result!.amount, equals(25000.0));
        expect(result.accountLabel, equals('SeaBank'));
        expect(result.merchantName, equals('KOPI KENANGAN'));
        expect(result.suggestedCategory, equals('Makanan & Minuman'));
        expect(result.mutationType, equals(PaymentMutationType.debit));
      });

      test('GoPay pembayaran di merchant', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.gojek.app',
          title: 'Pembayaran Berhasil',
          body: 'Pembayaran Rp 45.000 di ALFAMART berhasil.',
        );
        expect(result, isNotNull);
        expect(result!.amount, equals(45000.0));
        expect(result.accountLabel, equals('GoPay'));
        expect(result.merchantName, equals('ALFAMART'));
        expect(result.suggestedCategory, equals('Belanja & Ritel'));
        expect(result.mutationType, equals(PaymentMutationType.debit));
      });

      test('GoPay transfer masuk', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.gopay.wallet',
          title: 'Saldo Masuk',
          body: 'Kamu menerima transfer sebesar Rp 100.000 dari AHMAD FAUZI',
        );
        expect(result, isNotNull);
        expect(result!.amount, equals(100000.0));
        expect(result.accountLabel, equals('GoPay'));
        expect(result.merchantName, equals('AHMAD FAUZI'));
        expect(result.mutationType, equals(PaymentMutationType.credit));
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

      test('info saldo dengan nominal bukan transaksi', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.seabank.id',
          title: 'SeaBank',
          body: 'Saldo rekening Anda Rp 1.250.000',
        );
        expect(result, isNull);
      });

      test('promo cashback dengan nominal bukan transaksi', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'id.flip',
          title: 'Promo Flip',
          body: 'Dapatkan cashback Rp 20.000 untuk transfer hari ini',
        );
        expect(result, isNull);
      });

      test('transaksi pending bukan transaksi berhasil', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.isaku.app',
          title: 'i.saku',
          body: 'Pembayaran sedang diproses sebesar Rp 35.000',
        );
        expect(result, isNull);
      });

      test('nominal tanpa konteks transaksi ditolak', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.honestbank.android',
          title: 'Informasi',
          body: 'Tagihan Anda Rp 500.000',
        );
        expect(result, isNull);
      });
    });

    group('aplikasi tambahan', () {
      test('Flip transfer berhasil', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'id.flip',
          title: 'Transfer Berhasil',
          body: 'Transfer ke BUDI berhasil sebesar Rp 75.000',
        );
        expect(result?.accountLabel, equals('Flip'));
        expect(result?.amount, equals(75000));
      });

      test('MotionPay pembayaran QRIS', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.spin.app.latest',
          title: 'MotionPay',
          body: 'Pembayaran QRIS ke WARUNG berhasil Rp 18.000',
        );
        expect(result?.accountLabel, equals('MotionPay'));
        expect(result?.mutationType, equals(PaymentMutationType.debit));
      });

      test('Neobank transfer berhasil', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.bnc.finance',
          title: 'Neobank',
          body: 'Transfer ke BUDI berhasil sebesar Rp 50.000',
        );
        expect(result, isNotNull);
        expect(result?.accountLabel, equals('Neobank'));
        expect(result?.amount, equals(50000.0));
        expect(result?.merchantName, equals('BUDI'));
        expect(result?.mutationType, equals(PaymentMutationType.debit));
      });

      test('Krom Bank QRIS berhasil', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'id.krom.bank',
          title: 'Krom Bank',
          body: 'Pembayaran QRIS di KOPI KENANGAN berhasil Rp 28.000',
        );
        expect(result, isNotNull);
        expect(result?.accountLabel, equals('Krom Bank'));
        expect(result?.amount, equals(28000.0));
        expect(result?.merchantName, equals('KOPI KENANGAN'));
        expect(result?.suggestedCategory, equals('Makanan & Minuman'));
        expect(result?.mutationType, equals(PaymentMutationType.debit));
      });

      test('Bank Jago QRIS berhasil', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.jago.digitalBanking',
          title: 'Bank Jago',
          body: 'Pembayaran QRIS ke STARBUCKS berhasil Rp 65.000',
        );
        expect(result, isNotNull);
        expect(result?.accountLabel, equals('Bank Jago'));
        expect(result?.amount, equals(65000.0));
        expect(result?.merchantName, equals('STARBUCKS'));
        expect(result?.suggestedCategory, equals('Makanan & Minuman'));
      });

      test('blu by BCA Digital transfer berhasil', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'id.co.bcadigital.blu',
          title: 'blu by BCA Digital',
          body: 'Transfer ke rekening SITI AMINAH sebesar Rp 100.000 berhasil',
        );
        expect(result, isNotNull);
        expect(result?.accountLabel, equals('blu BCA Digital'));
        expect(result?.amount, equals(100000.0));
        expect(result?.merchantName, equals('SITI AMINAH'));
      });

      test('Tokopedia pembayaran pesanan diverifikasi', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.tokopedia.tkpd',
          title: 'Tokopedia',
          body: 'Pembayaran pesanan Rp 150.000 telah berhasil diverifikasi.',
        );
        expect(result, isNotNull);
        expect(result?.accountLabel, equals('Tokopedia'));
        expect(result?.amount, equals(150000.0));
        expect(result?.merchantName, equals('TOKOPEDIA'));
        expect(result?.suggestedCategory, equals('Belanja & Ritel'));
        expect(result?.mutationType, equals(PaymentMutationType.debit));
      });

      test('Shopee pembayaran pesanan berhasil', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.shopee.id',
          title: 'Shopee',
          body: 'Pembayaran sebesar Rp 85.000 untuk pesanan telah berhasil.',
        );
        expect(result, isNotNull);
        expect(result?.accountLabel, equals('ShopeePay'));
        expect(result?.amount, equals(85000.0));
        expect(result?.merchantName, equals('SHOPEE'));
        expect(result?.suggestedCategory, equals('Belanja & Ritel'));
      });

      test('Lazada pembayaran pesanan selesai', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.lazada.android',
          title: 'Lazada',
          body: 'Pesanan telah dibayar! Pembayaran sebesar Rp 110.000 berhasil.',
        );
        expect(result, isNotNull);
        expect(result?.accountLabel, equals('Lazada'));
        expect(result?.amount, equals(110000.0));
        expect(result?.merchantName, equals('LAZADA'));
        expect(result?.suggestedCategory, equals('Belanja & Ritel'));
      });

      test('TikTok Shop pembayaran pesanan dikonfirmasi', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.zhiliaoapp.musically',
          title: 'TikTok Shop',
          body: 'Pembayaran pesanan Rp 95.000 telah berhasil dikonfirmasi.',
        );
        expect(result, isNotNull);
        expect(result?.accountLabel, equals('TikTok Shop'));
        expect(result?.amount, equals(95000.0));
        expect(result?.merchantName, equals('TIKTOK SHOP'));
        expect(result?.suggestedCategory, equals('Belanja & Ritel'));
      });

      test('LinkAja pembayaran QRIS sukses', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.telkom.mwallet',
          title: 'LinkAja',
          body: 'Pembayaran QRIS ke INDOMARET sebesar Rp 30.000 sukses',
        );
        expect(result, isNotNull);
        expect(result?.accountLabel, equals('LinkAja'));
        expect(result?.amount, equals(30000.0));
        expect(result?.merchantName, equals('INDOMARET'));
        expect(result?.suggestedCategory, equals('Belanja & Ritel'));
      });

      test('PayPal pembayaran terkirim', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.paypal.android.p2pmobile',
          title: 'PayPal',
          body: 'You sent Rp 150.000 to JOHN DOE.',
        );
        expect(result, isNotNull);
        expect(result?.accountLabel, equals('PayPal'));
        expect(result?.amount, equals(150000.0));
        expect(result?.merchantName, equals('JOHN DOE'));
        expect(result?.mutationType, equals(PaymentMutationType.debit));
      });

      test('Wise transfer berhasil', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.transferwise.android',
          title: 'Wise',
          body: 'Transfer ke BUDI SANTOSO berhasil sebesar Rp 250.000',
        );
        expect(result, isNotNull);
        expect(result?.accountLabel, equals('Wise'));
        expect(result?.amount, equals(250000.0));
        expect(result?.merchantName, equals('BUDI SANTOSO'));
        expect(result?.mutationType, equals(PaymentMutationType.debit));
      });

      test('DOKU pembayaran QRIS berhasil', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.doku.wallet',
          title: 'DOKU',
          body: 'Pembayaran QRIS ke KOPI KENANGAN berhasil Rp 22.000',
        );
        expect(result, isNotNull);
        expect(result?.accountLabel, equals('DOKU'));
        expect(result?.amount, equals(22000.0));
        expect(result?.merchantName, equals('KOPI KENANGAN'));
        expect(result?.suggestedCategory, equals('Makanan & Minuman'));
      });

      test('Bibit pembelian investasi berhasil', () {
        final result = PaymentNotificationParser.parse(
          packageName: 'com.bibit.bibitid',
          title: 'Bibit',
          body: 'Pembayaran pembelian reksadana sebesar Rp 100.000 berhasil.',
        );
        expect(result, isNotNull);
        expect(result?.accountLabel, equals('Bibit'));
        expect(result?.amount, equals(100000.0));
        expect(result?.merchantName, equals('BIBIT'));
        expect(result?.suggestedCategory, equals('Investasi & Finansial'));
        expect(result?.mutationType, equals(PaymentMutationType.debit));
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
