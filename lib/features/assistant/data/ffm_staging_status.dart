class FfmStagingStatus {
  const FfmStagingStatus({required this.hasModel});

  final bool hasModel;

  bool get isReadyToCommit => hasModel;
  bool get isEmpty => !hasModel;
}
