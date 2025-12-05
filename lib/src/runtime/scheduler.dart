import 'dart:async';

import '../metrics/metrics.dart';
import '../models.dart';
import '../retry_policy.dart';
import '../store/store.dart';
import '../transport/transport.dart';

/// Scheduler that processes outbox entries.
class OutboxScheduler {
  OutboxScheduler({
    required this.store,
    required this.transport,
    required this.retryPolicy,
    required this.config,
    this.metrics = const NoOpMetricsSink(),
  });

  final OutboxStore store;
  final OutboxTransport transport;
  final RetryPolicy retryPolicy;
  final OutboxConfig config;
  final MetricsSink metrics;

  bool _isRunning = false;
  bool _isPaused = false;
  Timer? _heartbeatTimer;
  final Set<String> _processing = {};

  /// Whether the scheduler is currently running.
  bool get isRunning => _isRunning;

  /// Whether the scheduler is currently paused.
  bool get isPaused => _isPaused;

  /// Starts the scheduler.
  Future<void> start() async {
    if (_isRunning) {
      return;
    }

    _isRunning = true;
    _isPaused = false;
    _startHeartbeat();
    await _tick();
  }

  /// Stops the scheduler.
  void stop() {
    _isRunning = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Pauses the scheduler.
  void pause() {
    _isPaused = true;
  }

  /// Resumes the scheduler.
  void resume() {
    _isPaused = false;
    if (_isRunning) {
      _tick();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(config.heartbeat, (_) {
      if (_isRunning && !_isPaused) {
        _tick();
      }
    });
  }

  /// Manually triggers a processing tick.
  Future<void> drain() async {
    // Temporarily enable processing for drain
    final wasRunning = _isRunning;
    final wasPaused = _isPaused;
    if (!_isRunning) {
      _isRunning = true;
      _isPaused = false;
    }
    try {
      // Keep processing until no more entries are available
      int previousProcessingCount = -1;
      while (true) {
        await _tick();
        // Wait for current batch to complete
        while (_processing.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
        // Check if there are more entries to process
        final entries = await store.pickForProcessing(
          config.concurrency,
          DateTime.now(),
        );
        if (entries.isEmpty) {
          break; // No more entries to process
        }
        // Prevent infinite loop if processing count doesn't change
        if (_processing.length == previousProcessingCount &&
            _processing.isEmpty) {
          break;
        }
        previousProcessingCount = _processing.length;
      }
    } finally {
      // Restore original state
      if (!wasRunning) {
        _isRunning = false;
        _isPaused = wasPaused;
      }
    }
  }

  Future<void> _tick() async {
    if (_isPaused || !_isRunning) {
      return;
    }

    // Check for stuck entries (processing for too long)
    await _unlockStuckEntries();

    // Pick entries for processing
    final entries = await store.pickForProcessing(
      config.concurrency - _processing.length,
      DateTime.now(),
    );

    // Process entries
    for (final entry in entries) {
      if (_processing.length >= config.concurrency) {
        break;
      }

      if (_processing.contains(entry.id)) {
        continue;
      }

      _processEntry(entry);
    }
  }

  Future<void> _unlockStuckEntries() async {
    // This would require tracking processing start time
    // For MVP, we'll skip this and rely on lockTimeout in config
  }

  Future<void> _processEntry(OutboxEntry entry) async {
    _processing.add(entry.id);

    try {
      // Mark as processing
      await store.update(entry.copyWith(status: OutboxEntryStatus.processing));
      metrics.counter('outbox.processing', tags: {'channel': entry.channel});

      // Send via transport
      final startTime = DateTime.now();
      final result = await transport.send(entry);
      final duration = DateTime.now().difference(startTime);

      metrics.timing(
        'outbox.send.duration',
        duration,
        tags: {'channel': entry.channel},
      );

      if (result.success) {
        // Success: mark as done
        await store.markDone(entry.id);
        metrics.counter('outbox.success', tags: {'channel': entry.channel});
      } else if (result.permanentlyFailed) {
        // Permanent failure: mark as failed
        await store.markFailed(entry.id, result.error ?? 'Permanent failure');
        metrics.counter(
          'outbox.failed',
          tags: {'channel': entry.channel, 'reason': 'permanent'},
        );
      } else {
        // Transient failure: schedule retry
        final nextAttempt = retryPolicy.calculateNextAttempt(
          currentAttempt: entry.attempt + 1,
          now: DateTime.now(),
          previousDelay: entry.nextAttemptAt?.difference(entry.createdAt),
        );

        await store.update(
          entry.copyWith(
            status: OutboxEntryStatus.queued,
            attempt: entry.attempt + 1,
            nextAttemptAt: nextAttempt,
            error: result.error,
          ),
        );
        metrics.counter(
          'outbox.retry',
          tags: {
            'channel': entry.channel,
            'attempt': '${entry.attempt + 1}',
          },
        );
      }
    } catch (e) {
      // Unexpected error: schedule retry
      final nextAttempt = retryPolicy.calculateNextAttempt(
        currentAttempt: entry.attempt + 1,
        now: DateTime.now(),
        previousDelay: entry.nextAttemptAt?.difference(entry.createdAt),
      );

      await store.update(
        entry.copyWith(
          status: OutboxEntryStatus.queued,
          attempt: entry.attempt + 1,
          nextAttemptAt: nextAttempt,
          error: e.toString(),
        ),
      );
      metrics.counter('outbox.error', tags: {'channel': entry.channel});
    } finally {
      _processing.remove(entry.id);
    }
  }
}

/// Configuration for outbox behavior.
///
/// Controls how the outbox processes entries, including retry behavior,
/// concurrency, and scheduling options.
class OutboxConfig {
  const OutboxConfig({
    this.retry = const RetryPolicy(),
    this.concurrency = 3,
    this.autoStart = true,
    this.lockTimeout = const Duration(minutes: 5),
    this.heartbeat = const Duration(seconds: 1),
    this.pauseOnNoNetwork = false,
  });

  /// Retry policy for failed entries.
  final RetryPolicy retry;

  /// Maximum number of entries to process concurrently.
  final int concurrency;

  /// Whether to automatically start processing when entries are enqueued.
  final bool autoStart;

  /// Maximum time an entry can be in "processing" status before being reset.
  final Duration lockTimeout;

  /// Interval between processing cycles.
  final Duration heartbeat;

  /// Whether to pause processing when network is unavailable.
  final bool pauseOnNoNetwork;
}
