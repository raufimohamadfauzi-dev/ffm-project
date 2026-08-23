import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/presentation/widgets/ffm_agent_status_indicator.dart';

void main() {
  test('status agent mencerminkan event lokal tanpa klaim palsu', () {
    final controller = FfmAgentStatusController();

    expect(controller.value.isActive, isFalse);
    expect(controller.value.message, contains('siap'));

    controller.working('Membaca transaksi secara lokal...');
    expect(controller.value.isActive, isTrue);
    expect(controller.value.message, 'Membaca transaksi secara lokal...');

    controller.done('Transaksi tersimpan.');
    expect(controller.value.isActive, isFalse);
    expect(controller.value.isError, isFalse);

    controller.failed('Transaksi belum berhasil disimpan.');
    expect(controller.value.isActive, isFalse);
    expect(controller.value.isError, isTrue);

    controller.idle();
    expect(controller.value.isError, isFalse);
  });
}
