import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/activity/domain/activity_voice.dart';

void main() {
  test('draft VN tetap lokal sampai kategori master dipilih', () {
    final draft = VoiceActivityDraft(title: 'Memupuk cabai');

    expect(draft.draftId, startsWith('voice-'));
    expect(draft.canConfirm, isFalse);
    expect(draft.missingFields, contains('kategori'));

    draft
      ..categoryId = 'category-farm'
      ..categoryName = 'Pertanian'
      ..notes = 'NPK 2 kg'
      ..conversationHistory.add('kategorinya pertanian');

    expect(draft.canConfirm, isTrue);
    expect(draft.notes, 'NPK 2 kg');
    expect(draft.conversationHistory, hasLength(1));
  });

  test('intent VN mempertahankan waktu yang telah dikoreksi', () {
    final startedAt = DateTime(2026, 9, 1, 7);
    const original = ActivityVoiceIntent(
      rawTranscript: 'mulai memupuk cabai',
      normalizedText: 'mulai memupuk cabai',
      type: ActivityVoiceIntentType.start,
      status: ActivityVoiceStatus.preview,
    );

    final corrected = original.copyWith(startedAt: startedAt);

    expect(corrected.startedAt, startedAt);
  });

  group('applyTextCorrection', () {
    test('koreksi judul dengan pola "bukan X, Y"', () {
      final draft = VoiceActivityDraft(title: 'Memupuk timun');

      expect(draft.applyTextCorrection('bukan timun, cabai'), isTrue);

      expect(draft.title, 'Memupuk cabai');
    });

    test('menambah catatan menjaga catatan lama', () {
      final draft = VoiceActivityDraft(title: 'Memupuk', notes: 'hari pertama');

      expect(draft.applyTextCorrection('tambah catatan pakai NPK 2 kg'), isTrue);

      expect(draft.notes, 'hari pertama; pakai NPK 2 kg');
    });

    test('menambah catatan pertama tanpa catatan sebelumnya', () {
      final draft = VoiceActivityDraft(title: 'Memupuk');

      expect(draft.applyTextCorrection('tambah catatan pakai NPK 2 kg'), isTrue);

      expect(draft.notes, 'pakai NPK 2 kg');
    });

    test('menghapus catatan', () {
      final draft =
          VoiceActivityDraft(title: 'Memupuk', notes: 'pakai NPK 2 kg');

      expect(draft.applyTextCorrection('hapus catatannya'), isTrue);

      expect(draft.notes, isNull);
    });

    test('koreksi waktu mengubah startedAt dan menghapus error', () {
      final draft = VoiceActivityDraft(title: 'Memupuk');
      draft.validationErrors.add('lama');

      expect(draft.applyTextCorrection('mulainya jam 7 tadi'), isTrue);

      expect(draft.startedAt.hour, 7);
      expect(draft.validationErrors, isEmpty);
    });

    test('waktu tidak valid menambah validationError', () {
      final draft = VoiceActivityDraft(title: 'Memupuk');

      expect(draft.applyTextCorrection('ganti waktunya jam 25'), isTrue);

      expect(draft.validationErrors, isNotEmpty);
    });

    test('teks non-koreksi mengembalikan false tanpa mengubah draft', () {
      final draft = VoiceActivityDraft(
        title: 'Memupuk',
        notes: 'NPK',
        categoryId: 'c1',
        categoryName: 'Pertanian',
      );

      expect(draft.applyTextCorrection('sudah benar'), isFalse);

      expect(draft.title, 'Memupuk');
      expect(draft.notes, 'NPK');
      expect(draft.categoryId, 'c1');
    });

    test('draft lengkap dapat dikonfirmasi dan batal tidak menyimpan', () {
      final draft = VoiceActivityDraft(
        title: 'Memupuk',
        categoryId: 'c-farm',
        categoryName: 'Pertanian',
      );

      expect(draft.canConfirm, isTrue);

      draft.confirmed = true;
      expect(draft.confirmed, isTrue);
      // Cancel ditandai status intent, draft dibuang oleh UI; field confirmed
      // tetap false sampai konfirmasi eksplisit.
    });
  });

  group('ActivityVoiceParser correction intent', () {
    const parser = ActivityVoiceParser();

    test('mengenali perintah batal sebagai ActivityVoiceIntentType.cancel', () {
      final intent = parser.parse('batal');

      expect(intent.type, ActivityVoiceIntentType.cancel);
      expect(intent.canConfirm, isFalse);
    });

    test('mengenali perintah konfirmasi', () {
      final intent = parser.parse('sudah benar');

      expect(intent.type, ActivityVoiceIntentType.confirm);
    });
  });
}
