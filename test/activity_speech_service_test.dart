import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/activity/data/services/activity_speech_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ffm/activity_speech');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('final transcript hanya diterima sekali per sesi', () {
    final gate = ActivitySpeechFinalGate();
    final session = gate.begin();

    expect(
      gate.accept(session: session, text: '  Catat kopi! ', isFinal: false),
      isTrue,
    );
    expect(
      gate.accept(session: session, text: 'Catat kopi!', isFinal: true),
      isTrue,
    );
    expect(gate.acceptedFinalFingerprint, 'catat kopi');
    expect(
      gate.accept(session: session, text: 'catat kopi', isFinal: true),
      isFalse,
    );
    expect(gate.accept(session: session, text: '   ', isFinal: true), isFalse);

    gate.invalidate();
    expect(
      gate.accept(session: session, text: 'catat kopi', isFinal: true),
      isFalse,
    );
  });

  test(
    'mengambil dan memilih suara lokal perangkat tanpa membaca data FFM',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'voices':
            return [
              {
                'name': 'id-id-local',
                'locale': 'id-ID',
                'quality': 'kualitas tinggi',
              },
            ];
          case 'selectedVoice':
            return 'id-id-local';
          case 'selectVoice':
          case 'resume':
          case 'isSpeaking':
            return true;
          case 'stop':
            return true;
        }
        return null;
      });
      final service = ActivitySpeechService();

      final voices = await service.availableVoices();

      expect(voices, hasLength(1));
      expect(voices.single.label, 'id-id-local • kualitas tinggi');
      expect(await service.selectedVoiceName(), 'id-id-local');
      expect(await service.selectVoice('id-id-local'), isTrue);
      expect(await service.resumeSpeaking(), isTrue);
      expect(await service.isSpeaking(), isTrue);
      await service.stopSpeaking();
      expect(
        calls.map((call) => call.method),
        containsAll(<String>[
          'voices',
          'selectedVoice',
          'selectVoice',
          'resume',
          'isSpeaking',
          'stop',
        ]),
      );
      expect(
        calls.singleWhere((call) => call.method == 'selectVoice').arguments,
        {'name': 'id-id-local'},
      );
    },
  );
}
