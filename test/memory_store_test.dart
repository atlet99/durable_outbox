import 'package:durable_outbox/durable_outbox.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryStore', () {
    late MemoryStore store;

    setUp(() {
      store = MemoryStore();
    });

    tearDown(() {
      store.close();
    });

    test('should initialize', () async {
      await store.init();
      expect(store, isNotNull);
    });

    test('should insert and retrieve entries', () async {
      await store.init();

      final entry = OutboxEntry(
        id: 'test-1',
        channel: 'test',
        payload: {'key': 'value'},
        createdAt: DateTime.now(),
      );

      await store.insert(entry);

      final candidates = await store.pickForProcessing(10, DateTime.now());
      expect(candidates.length, equals(1));
      expect(candidates.first.id, equals('test-1'));
      expect(candidates.first.channel, equals('test'));
      expect(candidates.first.payload, equals({'key': 'value'}));
    });

    test('should update entry', () async {
      await store.init();

      final entry = OutboxEntry(
        id: 'test-1',
        channel: 'test',
        payload: {'key': 'value'},
        createdAt: DateTime.now(),
      );

      await store.insert(entry);

      final updated = entry.copyWith(
        status: OutboxEntryStatus.processing,
        attempt: 1,
      );

      await store.update(updated);

      final candidates = await store.pickForProcessing(10, DateTime.now());
      expect(candidates.length, equals(0)); // Processing entries not picked

      // Verify update
      final allEntries = await store.pickForProcessing(
        10,
        DateTime.now().add(const Duration(days: 1)),
      );
      // Entry is in processing state, so won't be picked
      expect(allEntries.length, equals(0));
    });

    test('should mark entry as done', () async {
      await store.init();

      final entry = OutboxEntry(
        id: 'test-1',
        channel: 'test',
        payload: {'key': 'value'},
        createdAt: DateTime.now(),
      );

      await store.insert(entry);
      await store.markDone('test-1');

      final candidates = await store.pickForProcessing(10, DateTime.now());
      expect(candidates.length, equals(0));
    });

    test('should mark entry as failed', () async {
      await store.init();

      final entry = OutboxEntry(
        id: 'test-1',
        channel: 'test',
        payload: {'key': 'value'},
        createdAt: DateTime.now(),
      );

      await store.insert(entry);
      await store.markFailed('test-1', 'Test error');

      final candidates = await store.pickForProcessing(10, DateTime.now());
      expect(candidates.length, equals(0));
    });

    test('should mark entry as failed with next attempt time', () async {
      await store.init();

      final entry = OutboxEntry(
        id: 'test-1',
        channel: 'test',
        payload: {'key': 'value'},
        createdAt: DateTime.now(),
      );

      await store.insert(entry);
      final nextAttempt = DateTime.now().add(const Duration(minutes: 5));
      await store.markFailed('test-1', 'Test error', nextAttempt: nextAttempt);

      final candidates = await store.pickForProcessing(10, DateTime.now());
      expect(candidates.length, equals(0)); // Not yet time for retry

      // After nextAttempt time, should be available
      final futureCandidates = await store.pickForProcessing(
        10,
        nextAttempt.add(const Duration(seconds: 1)),
      );
      expect(futureCandidates.length, equals(1));
    });

    test('should respect priority ordering', () async {
      await store.init();

      final now = DateTime.now();
      await store.insert(
        OutboxEntry(
          id: 'low',
          channel: 'test',
          payload: {},
          priority: 0,
          createdAt: now,
        ),
      );

      await store.insert(
        OutboxEntry(
          id: 'high',
          channel: 'test',
          payload: {},
          priority: 10,
          createdAt: now.add(const Duration(seconds: 1)),
        ),
      );

      final candidates = await store.pickForProcessing(10, DateTime.now());
      expect(candidates.length, equals(2));
      expect(candidates.first.id, equals('high')); // Higher priority first
      expect(candidates.last.id, equals('low'));
    });

    test('should respect createdAt ordering when priorities are equal',
        () async {
      await store.init();

      final now = DateTime.now();
      await store.insert(
        OutboxEntry(
          id: 'second',
          channel: 'test',
          payload: {},
          priority: 5,
          createdAt: now.add(const Duration(seconds: 1)),
        ),
      );

      await store.insert(
        OutboxEntry(
          id: 'first',
          channel: 'test',
          payload: {},
          priority: 5,
          createdAt: now,
        ),
      );

      final candidates = await store.pickForProcessing(10, DateTime.now());
      expect(candidates.length, equals(2));
      expect(candidates.first.id, equals('first')); // Earlier createdAt first
    });

    test('should respect nextAttemptAt delay', () async {
      await store.init();

      final now = DateTime.now();
      final future = now.add(const Duration(minutes: 5));

      await store.insert(
        OutboxEntry(
          id: 'delayed',
          channel: 'test',
          payload: {},
          nextAttemptAt: future,
          createdAt: now,
        ),
      );

      // Should not be picked before nextAttemptAt
      final candidates = await store.pickForProcessing(10, now);
      expect(candidates.length, equals(0));

      // Should be picked after nextAttemptAt
      final futureCandidates = await store.pickForProcessing(
        10,
        future.add(const Duration(seconds: 1)),
      );
      expect(futureCandidates.length, equals(1));
    });

    test('should clear entries by channel', () async {
      await store.init();

      await store.insert(
        OutboxEntry(
          id: 'test-1',
          channel: 'channel1',
          payload: {},
          createdAt: DateTime.now(),
        ),
      );

      await store.insert(
        OutboxEntry(
          id: 'test-2',
          channel: 'channel2',
          payload: {},
          createdAt: DateTime.now(),
        ),
      );

      await store.clear(channel: 'channel1');

      final candidates = await store.pickForProcessing(10, DateTime.now());
      expect(candidates.length, equals(1));
      expect(candidates.first.id, equals('test-2'));
    });

    test('should clear all entries when no channel specified', () async {
      await store.init();

      await store.insert(
        OutboxEntry(
          id: 'test-1',
          channel: 'channel1',
          payload: {},
          createdAt: DateTime.now(),
        ),
      );

      await store.insert(
        OutboxEntry(
          id: 'test-2',
          channel: 'channel2',
          payload: {},
          createdAt: DateTime.now(),
        ),
      );

      await store.clear();

      final candidates = await store.pickForProcessing(10, DateTime.now());
      expect(candidates.length, equals(0));
    });

    test('should watch count changes', () async {
      await store.init();

      final counts = <int>[];
      final subscription = store.watchCount().listen((count) {
        counts.add(count);
      });

      // Wait for initial count
      await Future.delayed(const Duration(milliseconds: 50));

      await store.insert(
        OutboxEntry(
          id: 'test-1',
          channel: 'test',
          payload: {},
          createdAt: DateTime.now(),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      await store.insert(
        OutboxEntry(
          id: 'test-2',
          channel: 'test',
          payload: {},
          createdAt: DateTime.now(),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      await store.clear();

      await Future.delayed(const Duration(milliseconds: 100));

      await subscription.cancel();

      // Should have received count updates (initial + updates)
      expect(counts.length, greaterThan(0));
    });

    test('should watch count for specific channel', () async {
      await store.init();

      await store.insert(
        OutboxEntry(
          id: 'test-1',
          channel: 'channel1',
          payload: {},
          createdAt: DateTime.now(),
        ),
      );

      await store.insert(
        OutboxEntry(
          id: 'test-2',
          channel: 'channel2',
          payload: {},
          createdAt: DateTime.now(),
        ),
      );

      // Get initial count
      final count = await store.watchCount(channel: 'channel1').first.timeout(
        const Duration(seconds: 1),
        onTimeout: () => 0,
      );
      expect(count, equals(1));
    });

    test('should limit pickForProcessing results', () async {
      await store.init();

      for (var i = 0; i < 10; i++) {
        await store.insert(
          OutboxEntry(
            id: 'test-$i',
            channel: 'test',
            payload: {},
            createdAt: DateTime.now(),
          ),
        );
      }

      final candidates = await store.pickForProcessing(5, DateTime.now());
      expect(candidates.length, equals(5));
    });

    test('should handle entries with idempotency key', () async {
      await store.init();

      final entry = OutboxEntry(
        id: 'test-1',
        channel: 'test',
        payload: {'key': 'value'},
        idempotencyKey: 'test-key-123',
        createdAt: DateTime.now(),
      );

      await store.insert(entry);

      final candidates = await store.pickForProcessing(10, DateTime.now());
      expect(candidates.length, equals(1));
      expect(candidates.first.idempotencyKey, equals('test-key-123'));
    });

    test('should handle entries with headers', () async {
      await store.init();

      final entry = OutboxEntry(
        id: 'test-1',
        channel: 'test',
        payload: {'key': 'value'},
        headers: {'X-Custom': 'value'},
        createdAt: DateTime.now(),
      );

      await store.insert(entry);

      final candidates = await store.pickForProcessing(10, DateTime.now());
      expect(candidates.length, equals(1));
      expect(candidates.first.headers, equals({'X-Custom': 'value'}));
    });
  });
}
