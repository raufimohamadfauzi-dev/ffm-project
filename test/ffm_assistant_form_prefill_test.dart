import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_form_prefill.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  test('mapper transaksi hanya mengirim nilai prefill yang aman', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 8, 28),
        amount: 50000,
        fromAccountName: 'Tunai',
        categoryName: 'Makan',
        note: 'Makan siang',
        date: DateTime(2026, 8, 28),
      ),
    );

    expect(prefill.target, FfmAssistantDestination.transactions);
    expect(prefill.values['amount'], '50000');
    expect(prefill.values['fromAccountName'], 'Tunai');
    expect(prefill.values.containsKey('token'), isFalse);
    expect(prefill.isReady, isTrue);
  });

  test('mapper transfer yang kurang rekening tujuan meminta perbaikan', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.transfer,
        createdAt: DateTime(2026, 8, 28),
        amount: 50000,
        fromAccountName: 'Tunai',
      ),
    );

    expect(prefill.target, FfmAssistantDestination.transactions);
    expect(prefill.missingFields, contains('rekening tujuan'));
    expect(prefill.isReady, isFalse);
  });

  test('mapper anggaran dengan nominal dan kategori', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.budget,
        createdAt: DateTime(2026, 8, 28),
        amount: 500000,
        categoryName: 'Makan',
      ),
    );

    expect(prefill.target, FfmAssistantDestination.budget);
    expect(prefill.values['amount'], '500000');
    expect(prefill.values['categoryName'], 'Makan');
    expect(prefill.isReady, isTrue);
  });

  test('mapper anggaran tanpa nominal meminta perbaikan', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.budget,
        createdAt: DateTime(2026, 8, 28),
        categoryName: 'Makan',
      ),
    );

    expect(prefill.target, FfmAssistantDestination.budget);
    expect(prefill.missingFields, contains('nominal'));
    expect(prefill.isReady, isFalse);
  });

  test('mapper master data dengan nama dan tipe', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.masterData,
        createdAt: DateTime(2026, 8, 28),
        title: 'BCA',
        categoryName: 'rekening',
      ),
    );

    expect(prefill.target, FfmAssistantDestination.masterData);
    expect(prefill.values['title'], 'BCA');
    expect(prefill.values['categoryName'], 'rekening');
  });

  test('mapper master data tanpa nama meminta perbaikan', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.masterData,
        createdAt: DateTime(2026, 8, 28),
        categoryName: 'rekening',
      ),
    );

    expect(prefill.target, FfmAssistantDestination.masterData);
    expect(prefill.missingFields, contains('nama'));
    expect(prefill.isReady, isFalse);
  });

  test('prefill check mengidentifikasi field yang hilang', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 8, 28),
      ),
    );

    expect(prefill.missingFields, isNotEmpty);
    expect(prefill.missingFields, contains('nominal'));
  });

  test('prefill check mengidentifikasi warning', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.transfer,
        createdAt: DateTime(2026, 8, 28),
        amount: 50000,
        fromAccountName: 'Tunai',
        toAccountName: 'Tunai',
      ),
    );

    expect(prefill.warnings, isNotEmpty);
  });

  test('prefill values tidak mengandung field sensitif', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 8, 28),
        amount: 50000,
        fromAccountName: 'Tunai',
        categoryName: 'Makan',
      ),
    );

    expect(prefill.values.containsKey('token'), isFalse);
    expect(prefill.values.containsKey('pin'), isFalse);
    expect(prefill.values.containsKey('password'), isFalse);
    expect(prefill.values.containsKey('secret'), isFalse);
  });
}
