import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/ffm_assistant_page_context.dart';

void main() {
  test('controller menyediakan snapshot capability untuk halaman aktif', () {
    final controller = FfmAssistantPageContextController();
    addTearDown(controller.dispose);

    final token = Object();
    controller.activate(
      token,
      FfmAssistantDestination.transactions,
      dataSummary: 'Transaksi bulan berjalan',
      activeFilters: const {'period': 'month'},
    );

    final snapshot = controller.currentSnapshot;
    expect(snapshot?.destination, FfmAssistantDestination.transactions);
    expect(snapshot?.dataSummary, 'Transaksi bulan berjalan');
    expect(snapshot?.activeFilters['period'], 'month');
    expect(snapshot?.capabilityIds, contains('read.transactions'));
    expect(snapshot?.capabilityIds, contains('draft.expense'));

    controller.deactivate(token);
    expect(controller.currentSnapshot, isNull);
    expect(controller.value, isNull);
  });
}
