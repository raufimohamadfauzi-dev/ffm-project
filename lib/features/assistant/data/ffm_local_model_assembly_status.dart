enum FfmLocalModelAssemblyStage {
  idle,
  verifyingModel,
  verifyingProjector,
  committing,
  ready,
  failed,
}

class FfmLocalModelAssemblyStatus {
  const FfmLocalModelAssemblyStatus({
    required this.stage,
    required this.updatedAt,
    this.startedAt,
    this.fileName,
    this.processedBytes = 0,
    this.totalBytes = 0,
    this.errorDetail,
  });

  final FfmLocalModelAssemblyStage stage;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final String? fileName;
  final int processedBytes;
  final int totalBytes;
  final String? errorDetail;

  bool get isWorking => switch (stage) {
    FfmLocalModelAssemblyStage.verifyingModel ||
    FfmLocalModelAssemblyStage.verifyingProjector ||
    FfmLocalModelAssemblyStage.committing => true,
    _ => false,
  };

  double? get fraction => totalBytes <= 0 ? null : processedBytes / totalBytes;

  Map<String, Object?> toJson() => {
    'stage': stage.name,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (startedAt != null) 'startedAt': startedAt!.toUtc().toIso8601String(),
    if (fileName != null) 'fileName': fileName,
    'processedBytes': processedBytes,
    'totalBytes': totalBytes,
    if (errorDetail != null) 'errorDetail': errorDetail,
  };

  factory FfmLocalModelAssemblyStatus.fromJson(Map<String, dynamic> json) {
    final stage = FfmLocalModelAssemblyStage.values.firstWhere(
      (value) => value.name == json['stage'],
      orElse: () => FfmLocalModelAssemblyStage.idle,
    );
    return FfmLocalModelAssemblyStatus(
      stage: stage,
      updatedAt:
          DateTime.tryParse('${json['updatedAt']}')?.toLocal() ??
          DateTime.now(),
      startedAt: DateTime.tryParse('${json['startedAt'] ?? ''}')?.toLocal(),
      fileName: json['fileName'] as String?,
      processedBytes: (json['processedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      errorDetail: json['errorDetail'] as String?,
    );
  }
}
