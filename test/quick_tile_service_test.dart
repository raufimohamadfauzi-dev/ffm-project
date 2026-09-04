import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_widget_protocol.dart';

void main() {
  group('Quick Settings Tile & Widget Action Parsing', () {
    test('parse wireName quick_note ke FfmAssistantWidgetAction.quickNote', () {
      final action = FfmAssistantWidgetAction.fromWireName('quick_note');
      expect(action, equals(FfmAssistantWidgetAction.quickNote));
      expect(action?.wireName, equals('quick_note'));
    });

    test('parse wireName scan_nfc ke FfmAssistantWidgetAction.scanNfc', () {
      final action = FfmAssistantWidgetAction.fromWireName('scan_nfc');
      expect(action, equals(FfmAssistantWidgetAction.scanNfc));
      expect(action?.wireName, equals('scan_nfc'));
    });

    test('parse wireName assistant ke FfmAssistantWidgetAction.openAssistant', () {
      final action = FfmAssistantWidgetAction.fromWireName('assistant');
      expect(action, equals(FfmAssistantWidgetAction.openAssistant));
    });

    test('parse wireName tidak dikenal => return null', () {
      final action = FfmAssistantWidgetAction.fromWireName('unknown_tile_action');
      expect(action, isNull);
    });
  });
}
