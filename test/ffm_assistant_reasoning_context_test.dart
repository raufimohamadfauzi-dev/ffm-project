import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_reasoning_context.dart';

void main() {
  test('reasoning context bounded dan tidak membawa newline mentah', () {
    final context = FfmAssistantReasoningContext(
      request: 'buat laporan\nuntuk bulan ini',
      capturedAt: DateTime(2026, 8, 23),
      currentPage: FfmAssistantDestination.monthlyReport,
      pageSummary: 'Ringkasan lokal\nberisi angka privat',
      activeFilters: const {'periode': 'bulan ini'},
      capabilityIds: const ['read.transactions', 'export.report'],
      approvedUserContext: 'user_preference: format = ringkas',
      modelReady: true,
      previousStepResults: const ['adapter lokal selesai'],
    );

    final prompt = context.toBoundedPrompt(maxCharacters: 800);
    expect(prompt.length, lessThanOrEqualTo(800));
    expect(prompt, contains('Ringkasan bulanan'));
    expect(prompt, contains('read.transactions'));
    expect(prompt, contains('SLM lokal siap: ya'));
    expect(prompt, isNot(contains('\nberisi')));
    expect(prompt, contains('preview dan konfirmasi'));
  });

  test('step result baru dibatasi dan context awal tidak dimutasi', () {
    final context = FfmAssistantReasoningContext(
      request: 'cek transaksi',
      capturedAt: DateTime(2026, 8, 23),
      previousStepResults: const ['pertama'],
    );

    final next = context.withStepResult('kedua');
    expect(context.previousStepResults, ['pertama']);
    expect(next.previousStepResults, ['pertama', 'kedua']);
  });
}
