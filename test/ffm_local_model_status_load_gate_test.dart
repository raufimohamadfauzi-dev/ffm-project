import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/data/ffm_local_model_status_load_gate.dart';

void main() {
  test('menolak load kedua saat load pertama masih berjalan', () async {
    final gate = FfmLocalModelStatusLoadGate();
    final firstCompleter = Completer<String>();

    final first = gate.run(() => firstCompleter.future);
    final second = await gate.run(() async => 'tidak boleh berjalan');

    expect(gate.isRunning, isTrue);
    expect(second, isNull);
    firstCompleter.complete('selesai');
    expect(await first, 'selesai');
    expect(gate.isRunning, isFalse);
  });

  test('meneruskan timeout agar UI dapat mematikan spinner', () async {
    final gate = FfmLocalModelStatusLoadGate(
      timeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      gate.run(() => Completer<void>().future),
      throwsA(isA<TimeoutException>()),
    );
  });
}
