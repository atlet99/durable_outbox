import 'metrics.dart';

/// Console implementation of [MetricsSink] for debugging.
class ConsoleMetricsSink implements MetricsSink {
  const ConsoleMetricsSink();

  @override
  void counter(String name, {int value = 1, Map<String, String>? tags}) {
    final tagsStr = tags != null ? ' ${tags.toString()}' : '';
    print('[METRIC] counter: $name = $value$tagsStr');
  }

  @override
  void gauge(String name, double value, {Map<String, String>? tags}) {
    final tagsStr = tags != null ? ' ${tags.toString()}' : '';
    print('[METRIC] gauge: $name = $value$tagsStr');
  }

  @override
  void timing(String name, Duration duration, {Map<String, String>? tags}) {
    final tagsStr = tags != null ? ' ${tags.toString()}' : '';
    print('[METRIC] timing: $name = ${duration.inMilliseconds}ms$tagsStr');
  }
}
