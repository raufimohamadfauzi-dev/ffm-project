import 'package:flutter/services.dart';

import 'ffm_local_model_service.dart';
import 'ffm_staging_status.dart';

class FfmBackgroundDownloadStatus {
  const FfmBackgroundDownloadStatus({
    required this.role,
    required this.fileName,
    required this.state,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.localPath,
    this.diskBytes,
    this.parentExists,
    this.reason,
  });

  final String role;
  final String fileName;
  final String state;
  final int receivedBytes;
  final int totalBytes;
  final String? localPath;
  final int? diskBytes;
  final bool? parentExists;
  final String? reason;

  bool get isComplete => state == 'complete';
  bool get isFailed => state == 'failed';
  double? get fraction => totalBytes <= 0 ? null : receivedBytes / totalBytes;

  bool isAlreadyInStaging(FfmStagingStatus staging) => switch (role) {
    'language_model' => staging.hasModel,
    'multimodal_projector' => staging.hasProjector,
    _ => false,
  };

  bool needsStagingImport(FfmStagingStatus staging) =>
      isComplete &&
      localPath != null &&
      localPath!.isNotEmpty &&
      !isAlreadyInStaging(staging);

  factory FfmBackgroundDownloadStatus.fromMap(Map<Object?, Object?> map) =>
      FfmBackgroundDownloadStatus(
        role: '${map['role'] ?? ''}',
        fileName: '${map['fileName'] ?? ''}',
        state: '${map['state'] ?? 'unknown'}',
        receivedBytes: (map['receivedBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
        localPath: map['localPath'] as String?,
        diskBytes: (map['diskBytes'] as num?)?.toInt(),
        parentExists: map['parentExists'] as bool?,
        reason: map['reason'] as String?,
      );
}

class FfmBackgroundDownloadService {
  const FfmBackgroundDownloadService();

  static const _channel = MethodChannel('ffm_local_model_bridge');

  Future<List<FfmBackgroundDownloadStatus>> start() async {
    final raw = await _channel.invokeMethod<List<Object?>>(
      'startBackgroundBundleDownload',
      {
        'bundleId': 'qwen2-vl-2b-instruct-iq4-nl-v1',
        'modelUrl': FfmQwen2VlBundle.modelUrl,
        'modelFileName': FfmQwen2VlBundle.modelFileName,
        'projectorUrl': FfmQwen2VlBundle.projectorUrl,
        'projectorFileName': FfmQwen2VlBundle.projectorFileName,
      },
    );
    return _parse(raw);
  }

  Future<List<FfmBackgroundDownloadStatus>> status() async {
    final raw = await _channel.invokeMethod<List<Object?>>(
      'backgroundBundleStatus',
    );
    return _parse(raw);
  }

  Future<void> cancel() =>
      _channel.invokeMethod<void>('cancelBackgroundBundleDownload');

  List<FfmBackgroundDownloadStatus> _parse(List<Object?>? raw) =>
      (raw ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map(FfmBackgroundDownloadStatus.fromMap)
          .toList(growable: false);
}
