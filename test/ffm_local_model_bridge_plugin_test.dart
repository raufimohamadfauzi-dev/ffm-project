import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/data/ffm_local_model_bridge_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ffm_local_model_bridge');
  final log = <MethodCall>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          log.add(call);
          switch (call.method) {
            case 'initNative':
              return 0;
            case 'destroyNative':
              return null;
            case 'generateSingleShotNative':
              return '{"status":"mocked"}';
            default:
              return null;
          }
        });
  });

  tearDown(() {
    log.clear();
  });

  test('initNative mengirim argumen yang benar', () async {
    await FfmLocalModelBridgePlugin.initNative(
      modelPath: '/path/model.gguf',
      mmprojPath: '/path/mmproj.gguf',
    );
    expect(log, hasLength(1));
    expect(log.first.method, 'initNative');
    expect(log.first.arguments['modelPath'], '/path/model.gguf');
    expect(log.first.arguments['mmprojPath'], '/path/mmproj.gguf');
  });

  test('generateSingleShotNative mengirim prompt dan path gambar', () async {
    final res = await FfmLocalModelBridgePlugin.generateSingleShotNative(
      systemPrompt: 'sys',
      userPrompt: 'user',
      imagePath: '/path/img.jpg',
    );
    expect(res, '{"status":"mocked"}');
    expect(log, hasLength(1));
    expect(log.first.method, 'generateSingleShotNative');
    expect(log.first.arguments['systemPrompt'], 'sys');
    expect(log.first.arguments['imagePath'], '/path/img.jpg');
  });
}
