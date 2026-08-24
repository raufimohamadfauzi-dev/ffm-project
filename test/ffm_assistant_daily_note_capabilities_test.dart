import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capabilities.dart';

void main() {
  test('allowlist Catatan Harian hanya menyediakan draft, arsip lunak, dan readback', () {
    final capabilities = FfmAssistantCapabilityRegistry.all;
    final ids = capabilities.map((item) => item.id).toSet();

    expect(ids, contains('draft.daily_note'));
    expect(ids, contains('draft.daily_note_archive'));
    expect(ids, contains('verify.daily_note_mutation'));
    expect(ids, isNot(contains('sensitive.delete_daily_note')));
    expect(ids, isNot(contains('mutate.delete_daily_note')));

    expect(
      capabilities.firstWhere((item) => item.id == 'draft.daily_note').risk,
      FfmAssistantCapabilityRisk.prepare,
    );
    expect(
      capabilities
          .firstWhere((item) => item.id == 'verify.daily_note_mutation')
          .readOnly,
      isTrue,
    );
  });
}
