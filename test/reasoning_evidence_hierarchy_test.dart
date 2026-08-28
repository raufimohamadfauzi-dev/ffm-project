import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_reasoning_context.dart';

void main() {
  test('bounded reasoning context declares authoritative evidence hierarchy', () {
    final context = FfmAssistantReasoningContext(
      request: 'berapa saldo saya',
      capturedAt: DateTime(2026, 8, 28),
      pageSummary: 'Saldo rekening: Rp500.000',
      approvedUserContext: 'User pernah mengatakan saldo sekitar Rp2.000.000',
    );

    final prompt = context.toBoundedPrompt();

    expect(
      prompt,
      contains('SQL/application snapshot dan page snapshot adalah authoritative'),
    );
    expect(
      prompt,
      contains('memory cloud dan riwayat percakapan adalah non-authoritative'),
    );
  });
}
