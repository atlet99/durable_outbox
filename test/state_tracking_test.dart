import 'package:durable_outbox/durable_outbox.dart';
import 'package:test/test.dart';

void main() {
  group('Enhanced State Tracking', () {
    late MemoryStore store;

    setUp(() async {
      store = MemoryStore();
      await store.init();
    });

    tearDown(() {
      store.close();
    });

    test('getCountsByStatus returns empty map for empty store', () async {
      final counts = await store.getCountsByStatus();
      expect(counts, isEmpty);
    });

    test('getCountsByStatus tracks queued entries', () async {
      final entry = OutboxEntry(
        id: '1',
        channel: 'test',
        payload: {'data': 'test'},
        createdAt: DateTime.now(),
        status: OutboxEntryStatus.queued,
      );

      await store.insert(entry);

      final counts = await store.getCountsByStatus();
      expect(counts[OutboxEntryStatus.queued], equals(1));
      expect(counts[OutboxEntryStatus.processing], isNull);
      expect(counts[OutboxEntryStatus.done], isNull);
      expect(counts[OutboxEntryStatus.failed], isNull);
    });

    test('getCountsByStatus tracks multiple statuses', () async {
      final entries = [
        OutboxEntry(
          id: '1',
          channel: 'test',
          payload: {'data': 'test1'},
          createdAt: DateTime.now(),
          status: OutboxEntryStatus.queued,
        ),
        OutboxEntry(
          id: '2',
          channel: 'test',
          payload: {'data': 'test2'},
          createdAt: DateTime.now(),
          status: OutboxEntryStatus.queued,
        ),
        OutboxEntry(
          id: '3',
          channel: 'test',
          payload: {'data': 'test3'},
          createdAt: DateTime.now(),
          status: OutboxEntryStatus.processing,
        ),
        OutboxEntry(
          id: '4',
          channel: 'test',
          payload: {'data': 'test4'},
          createdAt: DateTime.now(),
          status: OutboxEntryStatus.done,
        ),
        OutboxEntry(
          id: '5',
          channel: 'test',
          payload: {'data': 'test5'},
          createdAt: DateTime.now(),
          status: OutboxEntryStatus.failed,
        ),
      ];

      for (final entry in entries) {
        await store.insert(entry);
      }

      final counts = await store.getCountsByStatus();
      expect(counts[OutboxEntryStatus.queued], equals(2));
      expect(counts[OutboxEntryStatus.processing], equals(1));
      expect(counts[OutboxEntryStatus.done], equals(1));
      expect(counts[OutboxEntryStatus.failed], equals(1));
    });

    test('getCountsByStatus filters by channel', () async {
      final entries = [
        OutboxEntry(
          id: '1',
          channel: 'orders',
          payload: {'data': 'test1'},
          createdAt: DateTime.now(),
          status: OutboxEntryStatus.queued,
        ),
        OutboxEntry(
          id: '2',
          channel: 'analytics',
          payload: {'data': 'test2'},
          createdAt: DateTime.now(),
          status: OutboxEntryStatus.queued,
        ),
        OutboxEntry(
          id: '3',
          channel: 'orders',
          payload: {'data': 'test3'},
          createdAt: DateTime.now(),
          status: OutboxEntryStatus.processing,
        ),
      ];

      for (final entry in entries) {
        await store.insert(entry);
      }

      final ordersCounts = await store.getCountsByStatus(channel: 'orders');
      expect(ordersCounts[OutboxEntryStatus.queued], equals(1));
      expect(ordersCounts[OutboxEntryStatus.processing], equals(1));

      final analyticsCounts =
          await store.getCountsByStatus(channel: 'analytics');
      expect(analyticsCounts[OutboxEntryStatus.queued], equals(1));
      expect(analyticsCounts[OutboxEntryStatus.processing], isNull);
    });

    test('watchCountsByStatus emits updates on changes', () async {
      final stream = store.watchCountsByStatus();
      final emittedCounts = <Map<OutboxEntryStatus, int>>[];

      final subscription = stream.listen(emittedCounts.add);

      // Wait for initial emission
      await Future.delayed(const Duration(milliseconds: 50));
      expect(emittedCounts.length, equals(1));
      expect(emittedCounts[0], isEmpty);

      // Add queued entry
      await store.insert(
        OutboxEntry(
          id: '1',
          channel: 'test',
          payload: {'data': 'test'},
          createdAt: DateTime.now(),
          status: OutboxEntryStatus.queued,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(emittedCounts.length, greaterThan(1));
      expect(emittedCounts.last[OutboxEntryStatus.queued], equals(1));

      // Update to processing
      await store.update(
        OutboxEntry(
          id: '1',
          channel: 'test',
          payload: {'data': 'test'},
          createdAt: DateTime.now(),
          status: OutboxEntryStatus.processing,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(emittedCounts.last[OutboxEntryStatus.queued], isNull);
      expect(emittedCounts.last[OutboxEntryStatus.processing], equals(1));

      await subscription.cancel();
    });

    test('DurableOutbox.watch() provides accurate state counts', () async {
      final outbox = DurableOutbox(
        store: store,
        transport: _MockTransport(),
        config: const OutboxConfig(autoStart: false),
      );

      await outbox.init();

      final states = <OutboxState>[];
      final subscription = outbox.watch().listen(states.add);

      // Wait for initial state
      await Future.delayed(const Duration(milliseconds: 50));
      expect(states.length, equals(1));
      expect(states[0].queuedCount, equals(0));
      expect(states[0].processingCount, equals(0));
      expect(states[0].failedCount, equals(0));

      // Enqueue entry
      await outbox.enqueue(channel: 'test', payload: {'data': 'test'});

      await Future.delayed(const Duration(milliseconds: 50));
      expect(states.last.queuedCount, equals(1));
      expect(states.last.processingCount, equals(0));

      await subscription.cancel();
      await outbox.close();
    });
  });
}

// Mock transport for testing
class _MockTransport implements OutboxTransport {
  @override
  Future<SendResult> send(OutboxEntry entry) async {
    return const SendResult(success: true);
  }
}
