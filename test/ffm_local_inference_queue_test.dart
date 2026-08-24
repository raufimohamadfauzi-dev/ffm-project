import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/data/ffm_local_inference_queue.dart';

void main() {
  test('queue menjalankan operasi satu per satu', () async {
    final queue = FfmSingleInferenceQueue();
    final events = <String>[];
    final firstGate = Completer<void>();

    final first = queue.enqueueRequest((token) async {
      events.add('first-start');
      expect(queue.activeCount, 1);
      await firstGate.future;
      token.throwIfCancelled();
      events.add('first-end');
      return 1;
    });
    final second = queue.enqueueRequest((token) async {
      events.add('second-start');
      expect(queue.activeCount, 1);
      token.throwIfCancelled();
      events.add('second-end');
      return 2;
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, ['first-start']);
    expect(queue.activeCount, 1);
    firstGate.complete();

    expect(await first.future, 1);
    expect(await second.future, 2);
    expect(events, ['first-start', 'first-end', 'second-start', 'second-end']);
    expect(queue.activeCount, 0);
    expect(queue.queuedCount, 0);
  });

  test(
    'isBusy aktif sejak pekerjaan dijadwalkan sampai antrean selesai',
    () async {
      final queue = FfmSingleInferenceQueue();
      final gate = Completer<void>();

      final request = queue.enqueueRequest((_) async {
        await gate.future;
        return 1;
      });

      expect(queue.isBusy, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(queue.isBusy, isTrue);
      gate.complete();
      expect(await request.future, 1);
      expect(queue.isBusy, isFalse);
    },
  );

  test(
    'cancel sebelum giliran tidak menjalankan operasi dan idempoten',
    () async {
      final queue = FfmSingleInferenceQueue();
      final firstGate = Completer<void>();
      var secondRan = false;

      final first = queue.enqueueRequest((_) async {
        await firstGate.future;
        return 1;
      });
      final second = queue.enqueueRequest((token) async {
        secondRan = true;
        token.throwIfCancelled();
        return 2;
      });

      second.cancel();
      second.cancel();
      firstGate.complete();

      expect(await first.future, 1);
      await expectLater(
        second.future,
        throwsA(isA<FfmInferenceCancelledException>()),
      );
      expect(secondRan, isFalse);
      expect(queue.activeCount, 0);
      expect(queue.queuedCount, 0);
    },
  );
}
