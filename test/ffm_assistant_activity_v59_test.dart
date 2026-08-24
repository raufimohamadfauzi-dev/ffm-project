import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/activity/domain/activity_voice.dart';
import 'package:ffm_manager/features/activity/domain/entities/activity_entity.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

ActivitySessionEntity _activeSession(String id, String title) =>
    ActivitySessionEntity(
      id: id,
      householdId: 'local-household',
      title: title,
      category: 'lainnya',
      startedAt: DateTime(2026, 8, 22, 8),
      status: ActivitySessionStatus.active,
      createdAt: DateTime(2026, 8, 22, 8),
    );

void main() {
  const parser = ActivityVoiceParser();

  test('Asisten mempreview mulai aktivitas tanpa ID sesi', () {
    final intent = parser.parse('Mulai belanja pasar');

    expect(intent.type, ActivityVoiceIntentType.start);
    expect(intent.targetTitle, 'Belanja Pasar');
    expect(intent.canConfirm, isTrue);
  });

  test('Asisten menghubungkan aktivitas anak ke induk aktif yang benar', () {
    final intent = parser.parse(
      'Mulai makan di dalam perjalanan',
      activeSessions: [_activeSession('perjalanan', 'Perjalanan')],
    );

    expect(intent.type, ActivityVoiceIntentType.startChild);
    expect(intent.targetTitle, 'Makan');
    expect(intent.parentSessionId, 'perjalanan');
    expect(intent.canConfirm, isTrue);
  });

  test('Asisten meminta nama saat menyelesaikan beberapa aktivitas aktif', () {
    final intent = parser.parse(
      'Selesai',
      activeSessions: [
        _activeSession('perjalanan', 'Perjalanan'),
        _activeSession('makan', 'Makan'),
      ],
    );

    expect(intent.type, ActivityVoiceIntentType.finish);
    expect(intent.canConfirm, isFalse);
    expect(intent.ambiguityReason, contains('2 aktivitas'));
  });

  test('Asisten mempreview update aktivitas ke sesi aktif yang tepat', () {
    final intent = parser.parse(
      'Perjalanan sudah sampai pasar',
      activeSessions: [_activeSession('perjalanan', 'Perjalanan')],
    );

    expect(intent.type, ActivityVoiceIntentType.checkpoint);
    expect(intent.targetSessionId, 'perjalanan');
    expect(intent.checkpointLabel, 'Pasar');
    expect(intent.canConfirm, isTrue);
  });

  test(
    'entry chat dapat membawa proposal Aktivitas terpisah dari draft uang',
    () {
      final proposal = parser.parse('Mulai belanja pasar');
      final entry = FfmAssistantChatEntry(
        isUser: false,
        text: 'Cek dulu aktivitasnya.',
        activityIntent: proposal,
      );

      expect(entry.intent, isNull);
      expect(entry.activityIntent?.canConfirm, isTrue);
    },
  );
}
