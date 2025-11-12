import 'dart:async';

import 'package:uuid/uuid.dart';

import 'metrics/metrics.dart';
import 'models.dart';
import 'runtime/scheduler.dart';
import 'store/memory_store.dart';
import 'store/store.dart';
import 'transport/transport.dart';

const _uuid = Uuid();

/// Main facade for durable outbox functionality.
class DurableOutbox {
  DurableOutbox({
    required this.store,
    required this.transport,
    OutboxConfig config = const OutboxConfig(),
    MetricsSink? metrics,
  })  : _config = config,
        _metrics = metrics ?? const NoOpMetricsSink();

  final OutboxStore store;
  final OutboxTransport transport;
  final OutboxConfig _config;
  final MetricsSink _metrics;

  OutboxScheduler? _scheduler;
  bool _initialized = false;

  /// Initializes the outbox (initializes store, starts scheduler if autoStart is enabled).
  Future<void> init() async {
    if (_initialized) {
      return;
    }

    await store.init();

    _scheduler = OutboxScheduler(
      store: store,
      transport: transport,
      retryPolicy: _config.retry,
      config: _config,
      metrics: _metrics,
    );

    if (_config.autoStart) {
      await _scheduler!.start();
    }

    _initialized = true;
  }

  /// Enqueues a new entry for delivery.
  ///
  /// Returns the entry ID.
  Future<String> enqueue({
    required String channel,
    required Object payload,
    Map<String, String>? headers,
    String? idempotencyKey,
    int priority = 0,
    DateTime? notBefore,
  }) async {
    if (!_initialized) {
      throw StateError('Outbox not initialized. Call init() first.');
    }

    final id = _generateId();
    final now = DateTime.now();
    final nextAttempt = notBefore ?? now;

    final entry = OutboxEntry(
      id: id,
      channel: channel,
      payload: payload,
      headers: headers,
      idempotencyKey: idempotencyKey,
      priority: priority,
      attempt: 0,
      nextAttemptAt: nextAttempt,
      createdAt: now,
      status: OutboxEntryStatus.queued,
    );

    await store.insert(entry);
    _metrics.counter('outbox.enqueued', tags: {'channel': channel});

    if (_config.autoStart && _scheduler != null) {
      _scheduler!.resume();
    }

    return id;
  }

  /// Manually triggers processing of queued entries.
  Future<void> drain() async {
    if (!_initialized) {
      throw StateError('Outbox not initialized. Call init() first.');
    }

    if (_scheduler != null) {
      await _scheduler!.drain();
    }
  }

  /// Pauses the scheduler.
  void pause() {
    _scheduler?.pause();
  }

  /// Resumes the scheduler.
  void resume() {
    _scheduler?.resume();
  }

  /// Clears entries, optionally filtered by channel.
  Future<void> clear({String? channel}) async {
    await store.clear(channel: channel);
    _metrics.counter(
      'outbox.cleared',
      tags: channel != null ? {'channel': channel} : null,
    );
  }

  /// Watches the outbox state.
  Stream<OutboxState> watch() {
    // Simple implementation: combine store counts with scheduler state
    return store.watchCount().map((count) {
      final isPaused = _scheduler?.isPaused ?? false;
      final isRunning = _scheduler?.isRunning ?? false;

      // For MVP, we'll use total count as queued count
      // In future versions, we can track status-specific counts
      return OutboxState(
        isPaused: isPaused,
        isRunning: isRunning,
        queuedCount: count,
        processingCount: 0, // TODO: track processing count
        failedCount: 0, // TODO: track failed count
      );
    });
  }

  String _generateId() {
    return _uuid.v4();
  }

  /// Closes the outbox and releases resources.
  Future<void> close() async {
    _scheduler?.stop();
    if (store is MemoryStore) {
      (store as MemoryStore).close();
    } else {
      // Try to close if store has close method (e.g., SqliteStore)
      // Use dynamic to avoid requiring SqliteStore type at compile time
      try {
        final storeType = store.runtimeType.toString();
        if (storeType == 'SqliteStore') {
          await (store as dynamic).close();
        }
      } catch (_) {
        // Ignore if close method doesn't exist or store doesn't support it
      }
    }
  }
}
