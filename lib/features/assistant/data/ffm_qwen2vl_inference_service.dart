import 'dart:convert';

import 'package:ffm_manager/features/assistant/data/ffm_local_inference_queue.dart';
import 'package:ffm_manager/features/assistant/data/ffm_local_model_bridge_plugin.dart';
import 'package:ffm_manager/features/assistant/data/ffm_local_proposal.dart';
import 'package:ffm_manager/features/assistant/data/ffm_slm_health_monitor.dart';

class FfmQwen2VlInferenceService {
  FfmQwen2VlInferenceService(
    this._queue, {
    FfmSlmHealthMonitor? healthMonitor,
  }) : _healthMonitor = healthMonitor;

  final FfmSingleInferenceQueue _queue;
  final FfmSlmHealthMonitor? _healthMonitor;

  bool get isBusy => _queue.isBusy;

  Future<String> generateJson({
    required String systemPrompt,
    required String userPrompt,
    String? imagePath,
  }) async {
    if (_healthMonitor?.shouldSkipInference == true) {
      throw Exception('SLM circuit breaker aktif. Coba lagi beberapa menit.');
    }

    final stopwatch = Stopwatch()..start();
    try {
      final result = await _queue.enqueue((token) async {
        token.throwIfCancelled();
        return FfmLocalModelBridgePlugin.generateSingleShotNative(
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          imagePath: imagePath,
        );
      });
      stopwatch.stop();
      await _healthMonitor?.recordSuccess(
        latencyMs: stopwatch.elapsedMilliseconds,
        responseLength: result.length,
      );
      return result;
    } catch (e) {
      stopwatch.stop();
      if (e is! FfmInferenceCancelledException) {
        await _healthMonitor?.recordFailure(
          latencyMs: stopwatch.elapsedMilliseconds,
          errorType: e.runtimeType.toString(),
        );
      }
      rethrow;
    }
  }

  Future<String?> tryGenerateJsonWhenIdle({
    required String systemPrompt,
    required String userPrompt,
    String? imagePath,
  }) {
    if (_queue.isBusy) return Future<String?>.value();
    if (_healthMonitor?.shouldSkipInference == true) {
      return Future<String?>.value();
    }
    return _queue.enqueue((token) async {
      token.throwIfCancelled();
      final stopwatch = Stopwatch()..start();
      try {
        final result = await FfmLocalModelBridgePlugin.generateSingleShotNative(
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          imagePath: imagePath,
        );
        stopwatch.stop();
        await _healthMonitor?.recordSuccess(
          latencyMs: stopwatch.elapsedMilliseconds,
          responseLength: result.length,
        );
        return result;
      } catch (e) {
        stopwatch.stop();
        if (e is! FfmInferenceCancelledException) {
          await _healthMonitor?.recordFailure(
            latencyMs: stopwatch.elapsedMilliseconds,
            errorType: e.runtimeType.toString(),
          );
        }
        rethrow;
      }
    });
  }

  Future<FfmLocalProposalParseResult> generateProposal({
    required String systemPrompt,
    required String userPrompt,
    String? imagePath,
  }) async {
    final responseJson = await generateJson(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      imagePath: imagePath,
    );

    final decoded = jsonDecode(responseJson);
    if (decoded is Map<String, dynamic> && decoded.containsKey('error')) {
      throw Exception(decoded['error']);
    }

    return FfmLocalProposalParser.parse(responseJson);
  }
}
