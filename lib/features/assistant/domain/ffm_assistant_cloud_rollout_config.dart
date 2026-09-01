/// Rollout internal untuk jalur context-first Gemini Cloud.
///
/// Default aktif. Release darurat dapat menonaktifkannya dengan
/// `--dart-define=FFM_GEMINI_CONTEXT_FIRST=false` tanpa mengaktifkan jalur cloud
/// lama yang tidak memiliki grounding envelope.
abstract final class FfmAssistantCloudRolloutConfig {
  static const contextFirstEnabled = bool.fromEnvironment(
    'FFM_GEMINI_CONTEXT_FIRST',
    defaultValue: true,
  );
}
