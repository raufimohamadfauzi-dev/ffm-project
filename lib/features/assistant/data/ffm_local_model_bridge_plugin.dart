import 'package:flutter/services.dart';

class FfmLocalModelBridgePlugin {
  const FfmLocalModelBridgePlugin._();

  static const MethodChannel _channel = MethodChannel('ffm_local_model_bridge');

  static Future<void> initNative({required String modelPath}) async {
    final result = await _channel.invokeMethod<int>('initNative', {
      'modelPath': modelPath,
    });
    if (result != 0) {
      throw Exception('Gagal inisialisasi native model: kode $result');
    }
  }

  static Future<void> destroyNative() async {
    await _channel.invokeMethod<void>('destroyNative');
  }

  static Future<String> generateSingleShotNative({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    final result = await _channel.invokeMethod<String>(
      'generateSingleShotNative',
      {
        'systemPrompt': systemPrompt,
        'userPrompt': userPrompt,
      },
    );
    if (result == null) {
      throw Exception('Native bridge mengembalikan null');
    }
    return result;
  }
}
