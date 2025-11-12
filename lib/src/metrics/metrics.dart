/// Interface for metrics collection.
abstract class MetricsSink {
  /// Records a counter metric.
  void counter(String name, {int value = 1, Map<String, String>? tags});

  /// Records a gauge metric.
  void gauge(String name, double value, {Map<String, String>? tags});

  /// Records a histogram/timing metric.
  void timing(String name, Duration duration, {Map<String, String>? tags});
}

/// No-op implementation of [MetricsSink].
class NoOpMetricsSink implements MetricsSink {
  const NoOpMetricsSink();

  @override
  void counter(String name, {int value = 1, Map<String, String>? tags}) {}

  @override
  void gauge(String name, double value, {Map<String, String>? tags}) {}

  @override
  void timing(String name, Duration duration, {Map<String, String>? tags}) {}
}
