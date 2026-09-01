class FfmAssistantExecutionLimits {
  const FfmAssistantExecutionLimits._();

  static const maxConcurrentInference = 1;
  static const maxExecutionsPerStep = 1;
  static const maxStepsPerPlan = 8;
  static const maxActivePlansPerRequest = 1;
  static const maxSubCommandsPerMessage = 3;

  static const tooComplexMessage =
      'Permintaan ini terlalu kompleks untuk diproses sekaligus. Coba pecah jadi beberapa pertanyaan ya.';
}

enum FfmAssistantBudgetBlockReason {
  tooManySubCommands,
  tooManySteps,
  tooManyActivePlans,
  stepAlreadyExecuted,
  tokenBudgetExceeded,
  costBudgetExceeded,
}
