import 'dart:convert';

import 'package:ffm_manager/features/assistant/data/ffm_local_inference_queue.dart';
import 'package:ffm_manager/features/assistant/data/ffm_local_model_bridge_plugin.dart';
import 'package:ffm_manager/features/assistant/data/ffm_local_proposal.dart';

class FfmQwen2VlInferenceService {
  const FfmQwen2VlInferenceService(this._queue);

  final FfmSingleInferenceQueue _queue;

  Future<FfmLocalProposalParseResult> generateProposal({
    required String systemPrompt,
    required String userPrompt,
    String? imagePath,
  }) async {
    final responseJson = await _queue.enqueue((token) async {
      // Pembatalan sebelum JNI dimulai:
      token.throwIfCancelled();

      return FfmLocalModelBridgePlugin.generateSingleShotNative(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        imagePath: imagePath,
      );
    });

    final decoded = jsonDecode(responseJson);
    if (decoded is Map<String, dynamic> && decoded.containsKey('error')) {
      throw Exception(decoded['error']);
    }

    return FfmLocalProposalParser.parse(responseJson);
  }
}
