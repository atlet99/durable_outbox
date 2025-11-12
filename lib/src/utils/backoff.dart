import 'dart:math';

/// Calculates decorrelated jitter backoff delay.
///
/// Formula: sleep = min(cap, random_between(base, sleep * 3))
/// This provides decorrelated jitter which helps reduce thundering herd.
double calculateDecorrelatedJitter({
  required double base,
  required double max,
  required double previousDelay,
}) {
  final random = Random();
  final minDelay = base;
  final maxDelay = min(max, previousDelay * 3);
  return minDelay + random.nextDouble() * (maxDelay - minDelay);
}

/// Calculates next retry delay using decorrelated jitter backoff.
Duration calculateNextRetryDelay({
  required Duration base,
  required Duration max,
  required Duration previousDelay,
  required int attempt,
}) {
  if (attempt == 0) {
    return base;
  }

  final delay = calculateDecorrelatedJitter(
    base: base.inMilliseconds.toDouble(),
    max: max.inMilliseconds.toDouble(),
    previousDelay: previousDelay.inMilliseconds.toDouble(),
  );

  return Duration(milliseconds: delay.round());
}
