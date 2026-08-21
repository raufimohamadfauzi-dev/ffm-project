import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/activity/domain/activity_voice.dart';
import 'package:ffm_manager/features/activity/domain/entities/activity_entity.dart';

void main() {
  final parser = const ActivityVoiceParser();
  final startedAt = DateTime(2026, 8, 21, 8);

  ActivitySessionEntity session(
    String id,
    String title, {
    String? parentSessionId,
  }) => ActivitySessionEntity(
    id: id,
    householdId: 'local-household',
    title: title,
    category: 'Lainnya',
    parentSessionId: parentSessionId,
    startedAt: startedAt,
    status: ActivitySessionStatus.active,
    createdAt: startedAt,
  );

  test('mengenali mulai aktivitas dan menunggu konfirmasi', () {
    final intent = parser.parse('Saya mulai makan');

    expect(intent.type, ActivityVoiceIntentType.start);
    expect(intent.targetTitle, 'Makan');
    expect(intent.canConfirm, isTrue);
  });

  test('mengenali makan selesai dan mengikat ke sesi aktif', () {
    final intent = parser.parse(
      'makan selesai',
      activeSessions: [session('makan-1', 'Makan')],
    );

    expect(intent.type, ActivityVoiceIntentType.finish);
    expect(intent.targetSessionId, 'makan-1');
    expect(intent.canConfirm, isTrue);
  });

  test('mengenali aktivitas anak di dalam sesi induk', () {
    final intent = parser.parse(
      'mulai makan di dalam perjalanan',
      activeSessions: [session('travel-1', 'Perjalanan')],
    );

    expect(intent.type, ActivityVoiceIntentType.startChild);
    expect(intent.targetTitle, 'Makan');
    expect(intent.parentSessionId, 'travel-1');
    expect(intent.canConfirm, isTrue);
  });

  test('mengenali checkpoint menuju tempat', () {
    final intent = parser.parse(
      'update perjalanan sampai pasar',
      activeSessions: [session('travel-1', 'Perjalanan')],
    );

    expect(intent.type, ActivityVoiceIntentType.checkpoint);
    expect(intent.targetSessionId, 'travel-1');
    expect(intent.checkpointLabel, 'Pasar');
    expect(intent.canConfirm, isTrue);
  });

  test('checkpoint singkat memakai satu aktivitas aktif yang tersedia', () {
    final intent = parser.parse(
      'sampai pasar',
      activeSessions: [session('travel-1', 'Perjalanan')],
    );

    expect(intent.type, ActivityVoiceIntentType.checkpoint);
    expect(intent.targetSessionId, 'travel-1');
    expect(intent.targetTitle, 'Perjalanan');
    expect(intent.checkpointLabel, 'Pasar');
    expect(intent.canConfirm, isTrue);
  });

  test('selesai tanpa nama memakai satu aktivitas aktif yang tersedia', () {
    final intent = parser.parse(
      'selesai',
      activeSessions: [session('makan-1', 'Makan')],
    );

    expect(intent.type, ActivityVoiceIntentType.finish);
    expect(intent.targetSessionId, 'makan-1');
    expect(intent.targetTitle, 'Makan');
    expect(intent.canConfirm, isTrue);
  });

  test('OK dan batal menjadi token konfirmasi terpisah', () {
    final confirmWithoutDraft = parser.parse('OK');

    expect(confirmWithoutDraft.type, ActivityVoiceIntentType.confirm);
    expect(confirmWithoutDraft.canConfirm, isFalse);
    expect(parser.parse('jangan jadi').type, ActivityVoiceIntentType.cancel);
  });

  test('nama sama yang aktif bersamaan tidak langsung dipilih', () {
    final intent = parser.parse(
      'makan selesai',
      activeSessions: [
        session('makan-1', 'Makan'),
        session('makan-2', 'Makan'),
      ],
    );

    expect(intent.targetSessionId, isNull);
    expect(intent.ambiguityReason, isNotNull);
    expect(intent.canConfirm, isFalse);
  });

  test(
    'checkpoint tanpa nama tetap meminta pilihan saat beberapa sesi aktif',
    () {
      final intent = parser.parse(
        'sudah sampai pasar',
        activeSessions: [
          session('travel-1', 'Perjalanan'),
          session('work-1', 'Kerja'),
        ],
      );

      expect(intent.targetSessionId, isNull);
      expect(intent.ambiguityReason, contains('Ada 2 aktivitas'));
      expect(intent.ambiguityReason, contains('Perjalanan'));
      expect(intent.ambiguityReason, contains('Kerja'));
      expect(intent.canConfirm, isFalse);
    },
  );
}
