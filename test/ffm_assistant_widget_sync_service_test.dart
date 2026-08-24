import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/data/ffm_assistant_widget_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'updateSummary mengirim payload ringkas melalui channel widget',
    () async {
      const channel = MethodChannel('ffm/widget_test');
      Map<Object?, Object?>? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'updateWidgetState') {
              received = Map<Object?, Object?>.from(call.arguments as Map);
              return true;
            }
            return false;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final service = FfmAssistantWidgetSyncService(channel: channel);
      final result = await service.updateSummary(
        title: '  FFM\nRingkasan ',
        subtitle: 'Masuk   Rp1 jt\nKeluar Rp500 rb',
      );

      expect(result, isTrue);
      expect(received?['title'], 'FFM Ringkasan');
      expect(received?['subtitle'], 'Masuk Rp1 jt Keluar Rp500 rb');
    },
  );
}
