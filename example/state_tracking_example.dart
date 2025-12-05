import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:durable_outbox/durable_outbox.dart';

/// Example demonstrating enhanced state tracking with status-specific counts.
///
/// This example shows how to monitor the outbox state in real-time,
/// including separate counts for queued, processing, and failed entries.
void main() async {
  print('=== Enhanced State Tracking Example ===\n');

  // Create in-memory store for this example
  final store = MemoryStore();

  // Create outbox with a mock transport
  final outbox = DurableOutbox(
    store: store,
    transport: _ExampleTransport(),
    config: const OutboxConfig(
      concurrency: 2,
      autoStart: true,
      heartbeat: Duration(milliseconds: 500),
    ),
  );

  await outbox.init();

  // Watch the outbox state
  final subscription = outbox.watch().listen((state) {
    print('Outbox State:');
    print('  Paused: ${state.isPaused}');
    print('  Running: ${state.isRunning}');
    print('  Queued: ${state.queuedCount}');
    print('  Processing: ${state.processingCount}');
    print('  Failed: ${state.failedCount}');
    print('');
  });

  // Enqueue some entries
  print('Enqueueing 5 entries...\n');
  for (var i = 1; i <= 5; i++) {
    await outbox.enqueue(
      channel: 'orders',
      payload: {'orderId': 'order-$i', 'amount': i * 100},
      idempotencyKey: 'order-$i',
    );
    await Future.delayed(const Duration(milliseconds: 200));
  }

  // Wait for processing
  print('Processing entries...\n');
  await Future.delayed(const Duration(seconds: 3));

  // Get detailed counts by status
  print('Detailed status counts:');
  final counts = await store.getCountsByStatus();
  for (final entry in counts.entries) {
    print('  ${entry.key.name}: ${entry.value}');
  }
  print('');

  // Get counts for specific channel
  print('Counts for "orders" channel:');
  final ordersCounts = await store.getCountsByStatus(channel: 'orders');
  for (final entry in ordersCounts.entries) {
    print('  ${entry.key.name}: ${entry.value}');
  }
  print('');

  // Cleanup
  await subscription.cancel();
  await outbox.close();

  print('Example completed!');
}

/// Example transport that simulates processing with some failures
class _ExampleTransport implements OutboxTransport {
  int _callCount = 0;

  @override
  Future<SendResult> send(OutboxEntry entry) async {
    _callCount++;

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Simulate some failures (every 3rd call fails temporarily)
    if (_callCount % 3 == 0) {
      return const SendResult(
        success: false,
        error: 'Simulated temporary failure',
      );
    }

    // Simulate successful send
    print('✓ Sent entry ${entry.id} (${jsonEncode(entry.payload)})');
    return const SendResult(success: true);
  }
}
