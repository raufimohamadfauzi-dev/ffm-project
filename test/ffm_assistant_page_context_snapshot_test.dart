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

  test('screen awareness memakai ringkasan generik tanpa data mentah', () {
    final snapshot = FfmAssistantPageContextSnapshot(
      destination: FfmAssistantDestination.transactions,
      capabilityIds: const ['read.transactions'],
      updatedAt: DateTime.utc(2026, 8, 24),
      dataSummary: 'Kopi Kenangan Rp25.000 pada 20 Agustus',
    );

    final prompt = FfmAssistantScreenContextPolicy.forPrompt(
      snapshot: snapshot,
    );

    expect(prompt, contains('Halaman aktif: Transaksi.'));
    expect(prompt, contains('daftar transaksi'));
    expect(prompt, isNot(contains('Kopi Kenangan')));
    expect(prompt, isNot(contains('25.000')));
    expect(prompt.length, lessThanOrEqualTo(280));
  });

  test('screen awareness membatasi halaman keamanan ke nama saja', () {
    final snapshot = FfmAssistantPageContextSnapshot(
      destination: FfmAssistantDestination.appSecurity,
      capabilityIds: const ['security.change_pin'],
      updatedAt: DateTime.utc(2026, 8, 24),
      dataSummary: 'PIN aktif dan percobaan sebelumnya gagal.',
    );

    final prompt = FfmAssistantScreenContextPolicy.forPrompt(
      snapshot: snapshot,
    );

    expect(prompt, 'Konteks layar FFM: Halaman aktif: Kunci aplikasi.');
    expect(prompt, isNot(contains('PIN')));
  });
}
