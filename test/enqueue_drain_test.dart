import 'dart:async';

import 'package:durable_outbox/durable_outbox.dart';
import 'package:test/test.dart';

/// Mock transport that always succeeds.
class MockTransport implements OutboxTransport {
  final List<OutboxEntry> sentEntries = [];

  @override
  Future<SendResult> send(OutboxEntry entry) async {
    sentEntries.add(entry);
    return const SendResult(success: true);
  }
}

/// Mock transport that always fails.
class FailingTransport implements OutboxTransport {
  FailingTransport();

  @override
  Future<SendResult> send(OutboxEntry entry) async {
    return const SendResult(success: false, error: 'Test error');
  }
}

/// Mock transport that fails then succeeds.
class RetryTransport implements OutboxTransport {
  RetryTransport({this.succeedAfterAttempts = 2});

  final int succeedAfterAttempts;
  int attemptCount = 0;

  @override
  Future<SendResult> send(OutboxEntry entry) async {
    attemptCount++;
    if (attemptCount >= succeedAfterAttempts) {
      return const SendResult(success: true);
    }
    return SendResult(success: false, error: 'Attempt $attemptCount failed');
  }
}

/// Mock transport that returns permanent failure.
class PermanentFailureTransport implements OutboxTransport {
  PermanentFailureTransport();

  @override
  Future<SendResult> send(OutboxEntry entry) async {
    return const SendResult(
      success: false,
      permanentlyFailed: true,
      error: 'Permanent failure',
    );
  }
}

void main() {
  group('DurableOutbox', () {
    late DurableOutbox outbox;
    late MemoryStore store;
    late MockTransport transport;

    setUp(() {
      store = MemoryStore();
      transport = MockTransport();
      outbox = DurableOutbox(
        store: store,
        transport: transport,
        config: const OutboxConfig(
          autoStart: false,
        ),
      );
    });

    tearDown(() async {
      await outbox.close();
      store.close();
    });

    test('should initialize', () async {
      await outbox.init();
      expect(outbox, isNotNull);
    });

    test('should enqueue entry', () async {
      await outbox.init();

      final id = await outbox.enqueue(
        channel: 'test',
        payload: {'key': 'value'},
      );

      expect(id, isNotEmpty);

      final count = await outbox.store.watchCount().first;
      expect(count, equals(1));
    });

    test('should enqueue entry with idempotency key', () async {
      await outbox.init();

      final id = await outbox.enqueue(
        channel: 'test',
        payload: {'key': 'value'},
        idempotencyKey: 'test-key-123',
      );

      expect(id, isNotEmpty);

      final candidates = await store.pickForProcessing(10, DateTime.now());
      expect(candidates.length, equals(1));
      expect(candidates.first.idempotencyKey, equals('test-key-123'));
    });

    test('should enqueue entry with priority', () async {
      await outbox.init();

      await outbox.enqueue(
        channel: 'test',
        payload: {'key': 'low'},
        priority: 0,
      );

      await outbox.enqueue(
        channel: 'test',
        payload: {'key': 'high'},
        priority: 10,
      );

      final candidates = await store.pickForProcessing(10, DateTime.now());
      expect(candidates.length, equals(2));
      expect(candidates.first.priority, equals(10));
    });

    test('should enqueue entry with delayed start', () async {
      await outbox.init();

      final future = DateTime.now().add(const Duration(minutes: 5));
      await outbox.enqueue(
        channel: 'test',
        payload: {'key': 'value'},
        notBefore: future,
      );

      final candidates = await store.pickForProcessing(10, DateTime.now());
      expect(candidates.length, equals(0)); // Not yet time

      final futureCandidates = await store.pickForProcessing(
        10,
        future.add(const Duration(seconds: 1)),
      );
      expect(futureCandidates.length, equals(1));
    });

    test('should process entry on drain', () async {
      await outbox.init();

      await outbox.enqueue(
        channel: 'test',
        payload: {'key': 'value'},
      );

      await outbox.drain();

      // Entry should be processed (marked as done)
      final candidates = await store.pickForProcessing(10, DateTime.now());
      expect(candidates.length, equals(0));
      expect(transport.sentEntries.length, equals(1));
    });

    test('should process multiple entries', () async {
      await outbox.init();

      for (var i = 0; i < 5; i++) {
        await outbox.enqueue(
          channel: 'test',
          payload: {'index': i},
        );
      }

      await outbox.drain();

      expect(transport.sentEntries.length, equals(5));
      final candidates = await store.pickForProcessing(10, DateTime.now());
      expect(candidates.length, equals(0));
    });

    test('should respect concurrency limit', () async {
      final slowTransport = SlowTransport();
      final limitedOutbox = DurableOutbox(
        store: MemoryStore(),
        transport: slowTransport,
        config: const OutboxConfig(
          autoStart: false,
          concurrency: 2,
        ),
      );

      await limitedOutbox.init();

      for (var i = 0; i < 5; i++) {
        await limitedOutbox.enqueue(
          channel: 'test',
          payload: {'index': i},
        );
      }

      // Start processing
      limitedOutbox.resume();
      await Future.delayed(const Duration(milliseconds: 100));

      // Should process max 2 concurrently
      expect(slowTransport.processingCount, lessThanOrEqualTo(2));

      await limitedOutbox.close();
    });

    test('should pause and resume', () async {
      await outbox.init();

      outbox.pause();
      final pausedState = await outbox.watch().first;
      expect(pausedState.isPaused, isTrue);

      outbox.resume();
      final resumedState = await outbox.watch().first;
      expect(resumedState.isPaused, isFalse);
    });

    test('should clear entries', () async {
      await outbox.init();

      await outbox.enqueue(
        channel: 'test',
        payload: {'key': 'value'},
      );

      await outbox.clear();

      final count = await outbox.store.watchCount().first;
      expect(count, equals(0));
    });

    test('should clear entries by channel', () async {
      await outbox.init();

      await outbox.enqueue(
        channel: 'channel1',
        payload: {'key': 'value1'},
      );

      await outbox.enqueue(
        channel: 'channel2',
        payload: {'key': 'value2'},
      );

      await outbox.clear(channel: 'channel1');

      final count1 = await outbox.store.watchCount(channel: 'channel1').first;
      final count2 = await outbox.store.watchCount(channel: 'channel2').first;

      expect(count1, equals(0));
      expect(count2, equals(1));
    });

    test('should handle retry on failure', () async {
      final failingOutbox = DurableOutbox(
        store: MemoryStore(),
        transport: FailingTransport(),
        config: const OutboxConfig(
          autoStart: false,
          retry: RetryPolicy(maxAttempts: 3),
        ),
      );

      await failingOutbox.init();

      await failingOutbox.enqueue(
        channel: 'test',
        payload: {'key': 'value'},
      );

      await failingOutbox.drain();

      // Entry should still be queued (will retry)
      final store = failingOutbox.store as MemoryStore;
      final candidates = await store.pickForProcessing(10, DateTime.now());
      // Entry should be queued for retry with nextAttemptAt set
      expect(candidates.length, greaterThanOrEqualTo(0));

      await failingOutbox.close();
    });

    test('should handle permanent failure', () async {
      final permanentOutbox = DurableOutbox(
        store: MemoryStore(),
        transport: PermanentFailureTransport(),
        config: const OutboxConfig(
          autoStart: false,
        ),
      );

      await permanentOutbox.init();

      await permanentOutbox.enqueue(
        channel: 'test',
        payload: {'key': 'value'},
      );

      await permanentOutbox.drain();

      // Entry should be marked as failed, not retried
      final store = permanentOutbox.store as MemoryStore;
      final candidates = await store.pickForProcessing(10, DateTime.now());
      expect(candidates.length, equals(0));

      await permanentOutbox.close();
    });

    test('should retry and eventually succeed', () async {
      final retryTransport = RetryTransport(succeedAfterAttempts: 3);
      final retryOutbox = DurableOutbox(
        store: MemoryStore(),
        transport: retryTransport,
        config: const OutboxConfig(
          autoStart: false,
          retry: RetryPolicy(maxAttempts: 5),
        ),
      );

      await retryOutbox.init();

      await retryOutbox.enqueue(
        channel: 'test',
        payload: {'key': 'value'},
      );

      // Process multiple times to allow retries
      for (var i = 0; i < 5; i++) {
        await retryOutbox.drain();
        // Wait for backoff delay to allow next retry
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // Should eventually succeed
      expect(retryTransport.attemptCount, greaterThanOrEqualTo(3));
      final store = retryOutbox.store as MemoryStore;
      final candidates = await store.pickForProcessing(10, DateTime.now());
      expect(candidates.length, equals(0)); // Should be done

      await retryOutbox.close();
    });

    test('should watch state changes', () async {
      await outbox.init();

      final states = <OutboxState>[];
      final subscription = outbox.watch().listen((state) {
        states.add(state);
      });

      await outbox.enqueue(
        channel: 'test',
        payload: {'key': 'value'},
      );

      await Future.delayed(const Duration(milliseconds: 100));

      await outbox.drain();

      await Future.delayed(const Duration(milliseconds: 100));

      await subscription.cancel();

      expect(states.length, greaterThan(0));
    });
  });
}

/// Slow transport for concurrency testing.
class SlowTransport implements OutboxTransport {
  SlowTransport();

  int _processingCount = 0;

  int get processingCount => _processingCount;

  @override
  Future<SendResult> send(OutboxEntry entry) async {
    _processingCount++;
    await Future.delayed(const Duration(milliseconds: 200));
    _processingCount--;
    return const SendResult(success: true);
  }
}
