import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/assistant/data/payment_draft_repository.dart';
import 'package:ffm_manager/features/assistant/data/payment_notification_parser.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/pending_payment_drafts_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PendingPaymentDraftsCard Tests', () {
    late PaymentDraftRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      if (getIt.isRegistered<PaymentDraftRepository>()) {
        getIt.unregister<PaymentDraftRepository>();
      }
      repo = PaymentDraftRepository();
      getIt.registerSingleton<PaymentDraftRepository>(repo);
    });

    tearDown(() async {
      if (getIt.isRegistered<PaymentDraftRepository>()) {
        getIt.unregister<PaymentDraftRepository>();
      }
    });

    testWidgets('renders SizedBox.shrink when there are no pending drafts',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PendingPaymentDraftsCard(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Notifikasi Pembayaran Terdeteksi'), findsNothing);
      expect(find.byType(PendingPaymentDraftsCard), findsOneWidget);
    });

    testWidgets('renders card with pending drafts for SeaBank and GoPay',
        (tester) async {
      final drafts = [
        PaymentDraft(
          id: 'draft_seabank_1',
          sourceApp: 'com.seabank.id',
          rawTitle: 'SeaBank',
          rawBody: 'Transfer masuk sebesar Rp 50.000 dari BUDI',
          amount: 50000,
          merchantName: 'BUDI',
          mutationType: PaymentMutationType.credit,
          createdAt: DateTime.now(),
          suggestedCategory: 'Lainnya',
          status: PaymentDraftStatus.pending,
        ),
        PaymentDraft(
          id: 'draft_gopay_1',
          sourceApp: 'com.gojek.app',
          rawTitle: 'GoPay',
          rawBody: 'Pembayaran QRIS Rp 25.000 ke Kopi Kenangan berhasil',
          amount: 25000,
          merchantName: 'Kopi Kenangan',
          mutationType: PaymentMutationType.debit,
          createdAt: DateTime.now(),
          suggestedCategory: 'Makanan & Minuman',
          status: PaymentDraftStatus.pending,
        ),
      ];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'ffm_payment_drafts',
        jsonEncode(drafts.map((d) => d.toJson()).toList()),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PendingPaymentDraftsCard(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Notifikasi Pembayaran Terdeteksi'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // Badge count
      expect(find.text('SeaBank'), findsOneWidget);
      expect(find.text('GoPay'), findsOneWidget);
      expect(find.text('+Rp 50.000'), findsOneWidget);
      expect(find.text('-Rp 25.000'), findsOneWidget);
      expect(find.text('Dari: BUDI'), findsOneWidget);
      expect(find.text('Ke: Kopi Kenangan'), findsOneWidget);
      expect(find.text('Simpan'), findsNWidgets(2));
      expect(find.text('Abaikan'), findsNWidgets(2));
      expect(find.text('Edit'), findsNWidgets(2));
    });

    testWidgets('dismisses a draft when Abaikan is tapped', (tester) async {
      final drafts = [
        PaymentDraft(
          id: 'draft_test_dismiss',
          sourceApp: 'com.seabank.id',
          rawTitle: 'SeaBank',
          rawBody: 'Transfer keluar Rp 10.000',
          amount: 10000,
          merchantName: '',
          mutationType: PaymentMutationType.debit,
          createdAt: DateTime.now(),
          suggestedCategory: null,
          status: PaymentDraftStatus.pending,
        ),
      ];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'ffm_payment_drafts',
        jsonEncode(drafts.map((d) => d.toJson()).toList()),
      );

      bool callbackCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PendingPaymentDraftsCard(
                onDraftProcessed: () => callbackCalled = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Notifikasi Pembayaran Terdeteksi'), findsOneWidget);

      await tester.tap(find.text('Abaikan'));
      await tester.pumpAndSettle();

      expect(callbackCalled, isTrue);
      // After dismissal, pending drafts is 0, so card disappears
      expect(find.text('Notifikasi Pembayaran Terdeteksi'), findsNothing);

      final updatedDrafts = await repo.getAllDrafts();
      expect(updatedDrafts.first.status, PaymentDraftStatus.dismissed);
    });
  });
}
