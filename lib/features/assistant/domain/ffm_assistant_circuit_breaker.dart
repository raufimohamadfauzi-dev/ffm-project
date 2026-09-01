class FfmAssistantCircuitBreaker {
  FfmAssistantCircuitBreaker({
    this.failureThreshold = 3,
    this.cooldown = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int failureThreshold;
  final Duration cooldown;
  final DateTime Function() _now;
  final Map<String, _CircuitState> _states = <String, _CircuitState>{};

  bool canExecute(String capabilityId) {
    final state = _states[capabilityId];
    if (state == null) return true;
    final openUntil = state.openUntil;
    if (openUntil == null) return true;
    if (!_now().isBefore(openUntil)) {
      state.openUntil = null;
      return true;
    }
    return false;
  }

  void recordSuccess(String capabilityId) {
    _states.remove(capabilityId);
  }

  void recordFailure(String capabilityId) {
    final state = _states.putIfAbsent(capabilityId, _CircuitState.new);
    state.failures++;
    if (state.failures >= failureThreshold) {
      state.openUntil = _now().add(cooldown);
    }
  }
}

class _CircuitState {
  int failures = 0;
  DateTime? openUntil;
}
