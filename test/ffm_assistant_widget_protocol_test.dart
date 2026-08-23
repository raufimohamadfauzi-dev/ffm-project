import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_widget_protocol.dart';

void main() {
  test('wire action widget hanya mengenali action allowlist', () {
    expect(
      FfmAssistantWidgetAction.fromWireName('summary'),
      FfmAssistantWidgetAction.readSummary,
    );
    expect(FfmAssistantWidgetAction.fromWireName('unknown_capability'), isNull);
  });

  test('request kedaluwarsa dan mutation diarahkan ke aplikasi', () {
    final request = FfmAssistantWidgetRequest(
      requestId: 'widget-1',
      action: FfmAssistantWidgetAction.openAssistant,
      createdAt: DateTime(2026, 8, 23),
      expiresAt: DateTime(2026, 8, 22),
    );
    expect(request.isExpired, isTrue);

    const result = FfmAssistantWidgetResult(
      requestId: 'widget-2',
      status: FfmAssistantWidgetResultStatus.awaitingConfirmation,
      message: 'Buka preview dulu.',
    );
    expect(result.shouldOpenApp, isTrue);
  });
}
