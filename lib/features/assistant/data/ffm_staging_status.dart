class FfmStagingStatus {
  const FfmStagingStatus({required this.hasModel, required this.hasProjector});

  final bool hasModel;
  final bool hasProjector;

  bool get isReadyToCommit => hasModel && hasProjector;
  bool get isEmpty => !hasModel && !hasProjector;
}
