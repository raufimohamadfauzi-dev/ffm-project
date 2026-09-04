enum FfmAssistantWidgetAction {
  openAssistant('assistant'),
  quickNote('quick_note'),
  scanNfc('scan_nfc'),
  readSummary('summary'),
  openTransactions('transaction'),
  openScan('scan'),
  openActivity('activity'),
  openBudget('budget'),
  openModelSetup('model');

  const FfmAssistantWidgetAction(this.wireName);

  final String wireName;

  static FfmAssistantWidgetAction? fromWireName(String value) {
    for (final action in values) {
      if (action.wireName == value) return action;
    }
    return null;
  }
}

enum FfmAssistantWidgetResultStatus {
  accepted,
  needsApp,
  awaitingConfirmation,
  completed,
  failed,
  expired,
}

class FfmAssistantWidgetRequest {
  const FfmAssistantWidgetRequest({
    required this.requestId,
    required this.action,
    required this.createdAt,
    this.parameters = const <String, Object?>{},
    this.expiresAt,
  });

  final String requestId;
  final FfmAssistantWidgetAction action;
  final DateTime createdAt;
  final Map<String, Object?> parameters;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && !DateTime.now().isBefore(expiresAt!);
}

class FfmAssistantWidgetResult {
  const FfmAssistantWidgetResult({
    required this.requestId,
    required this.status,
    required this.message,
  });

  final String requestId;
  final FfmAssistantWidgetResultStatus status;
  final String message;

  bool get shouldOpenApp =>
      status == FfmAssistantWidgetResultStatus.needsApp ||
      status == FfmAssistantWidgetResultStatus.awaitingConfirmation;
}
