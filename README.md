# durable_outbox

**Reliable offline queue library with guaranteed delivery for Flutter/Dart applications.**

[![pub package](https://img.shields.io/pub/v/durable_outbox.svg)](https://pub.dev/packages/durable_outbox)
[![License: BSD 3-Clause](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](LICENSE)

`durable_outbox` is a robust, cross-platform offline queue library that ensures reliable delivery of events and commands to your backend, even when the network is unavailable. Built with the outbox pattern, it provides at-least-once delivery guarantees with idempotency support.

## ✨ Features

- ✅ **Offline mode**: Requests accumulate locally when network is unavailable
- ✅ **Guaranteed delivery**: At-least-once delivery with idempotency support
- ✅ **Automatic retry**: Smart retry with decorrelated jitter backoff
- ✅ **Deduplication**: Idempotency keys prevent duplicate processing
- ✅ **Pause/Resume**: Control processing on network/account/token changes
- ✅ **Plugin architecture**: HTTP, gRPC, and custom transport adapters
- ✅ **Cross-platform**: Works on mobile, desktop, web, and CLI
- ✅ **Priority queues**: Support for priority-based processing
- ✅ **Delayed execution**: Schedule entries for future processing
- ✅ **Observability**: Built-in metrics and state monitoring

## 📦 Installation

Add `durable_outbox` to your `pubspec.yaml`:

```yaml
dependencies:
  durable_outbox: ^0.1.0
```

Then run:

```bash
dart pub get
```

## 🚀 Quick Start

### Basic Usage

```dart
import 'package:durable_outbox/durable_outbox.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:path/path.dart' as path;

// Get application documents directory
final appDir = await path_provider.getApplicationDocumentsDirectory();
final dbPath = path.join(appDir.path, 'outbox.db');

// Create outbox with SQLite store
final outbox = DurableOutbox(
  store: SqliteStore(dbPath: dbPath),
  transport: HttpTransport(
    endpoint: Uri.parse('https://api.example.com/outbox'),
    authHeaders: () async => {'Authorization': 'Bearer $token'},
    client: yourHttpClient, // Your HTTP client implementation
  ),
  config: const OutboxConfig(
    concurrency: 3,
    autoStart: true,
  ),
);

await outbox.init();

// Enqueue an entry
await outbox.enqueue(
  channel: 'orders',
  payload: {'action': 'create', 'orderId': 'o-123'},
  idempotencyKey: 'orders:o-123',
);

// Entries are automatically processed in the background
```

### Simple HTTP Client Implementation

For examples, you'll need to implement the `HttpClient` interface:

```dart
import 'dart:io' as io;
import 'package:durable_outbox/durable_outbox.dart';

class SimpleHttpClient implements HttpClient {
  @override
  Future<HttpResponse> request({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    final client = io.HttpClient();
    try {
      final request = await client.openUrl(method, uri);
      headers?.forEach((key, value) {
        request.headers.set(key, value);
      });

      if (body != null) {
        request.write(body);
      }

      final response = await request.close().timeout(timeout ?? const Duration(seconds: 15));
      final responseBody = await response.transform(const io.SystemEncoding().decoder).join();

      final responseHeaders = <String, String>{};
      response.headers.forEach((key, values) {
        responseHeaders[key] = values.join(', ');
      });

      return HttpResponse(
        statusCode: response.statusCode,
        headers: responseHeaders,
        body: responseBody,
      );
    } finally {
      client.close();
    }
  }
}
```

## 🎯 Core Concepts

### Enqueueing Entries

Add entries to the queue for processing:

```dart
// Basic enqueue
final id = await outbox.enqueue(
  channel: 'orders',
  payload: {'action': 'create', 'orderId': 'o-123'},
);

// With idempotency key
await outbox.enqueue(
  channel: 'orders',
  payload: {'action': 'create', 'orderId': 'o-123'},
  idempotencyKey: 'orders:o-123',
);

// With priority (higher = processed earlier)
await outbox.enqueue(
  channel: 'analytics',
  payload: {'event': 'page_view'},
  priority: -1, // Low priority
);

// Delayed execution
await outbox.enqueue(
  channel: 'notifications',
  payload: {'message': 'Reminder'},
  notBefore: DateTime.now().add(const Duration(hours: 1)),
);
```

### Retry Policy

By default, `durable_outbox` uses **Decorrelated Jitter Backoff** for retry scheduling:

```dart
final outbox = DurableOutbox(
  store: SqliteStore(dbPath: dbPath),
  transport: HttpTransport(/* ... */),
  config: OutboxConfig(
    retry: RetryPolicy(
      baseDelay: const Duration(milliseconds: 500),
      maxDelay: const Duration(seconds: 60),
      maxAttempts: 8,
    ),
  ),
);
```

**Retry triggers:**
- Network errors (`SocketException`, `HttpException`)
- Timeout errors (`TimeoutException`)
- HTTP status codes: 429 (Too Many Requests), 5xx (Server Errors), 408 (Request Timeout)

**No retry on:**
- 4xx client errors (except 429 and 408)
- Permanent failures

### Idempotency

Each entry can have an `idempotencyKey` to prevent duplicate processing:

```dart
await outbox.enqueue(
  channel: 'orders',
  payload: {'action': 'create', 'orderId': 'o-123'},
  idempotencyKey: 'orders:o-123',
);
```

The transport automatically adds the `Idempotency-Key` header. On 409 (conflict) or server indication of "already processed", the entry is marked as done without retrying.

### Channels

Organize entries into logical queues using channels:

```dart
// Orders channel
await outbox.enqueue(
  channel: 'orders',
  payload: orderData,
);

// Analytics channel
await outbox.enqueue(
  channel: 'analytics',
  payload: analyticsData,
);

// Uploads channel
await outbox.enqueue(
  channel: 'uploads',
  payload: uploadData,
);
```

You can monitor and clear entries by channel:

```dart
// Watch count for specific channel
outbox.store.watchCount(channel: 'orders').listen((count) {
  print('Orders queue: $count');
});

// Clear specific channel
await outbox.clear(channel: 'orders');
```

### Pause and Resume

Control processing based on network state or user actions:

```dart
// Pause processing (e.g., when network is unavailable)
outbox.pause();

// Resume processing (e.g., when network is restored)
outbox.resume();

// Manually trigger processing
await outbox.drain();
```

### Monitoring

Watch queue state and counts:

```dart
// Watch overall state
outbox.watch().listen((state) {
  print('Paused: ${state.isPaused}');
  print('Running: ${state.isRunning}');
  print('Queued: ${state.queuedCount}');
  print('Processing: ${state.processingCount}');
  print('Failed: ${state.failedCount}');
});

// Watch queue count
outbox.store.watchCount(channel: 'orders').listen((count) {
  // Update UI badge
  setState(() {
    pendingOrdersCount = count;
  });
});
```

## ⚙️ Configuration

### Full Configuration Example

```dart
final outbox = DurableOutbox(
  store: SqliteStore(dbPath: dbPath),
  transport: HttpTransport(
    endpoint: Uri.parse('https://api.example.com/outbox'),
    authHeaders: () async => {
      'Authorization': 'Bearer $token',
      'X-API-Key': apiKey,
    },
    client: yourHttpClient,
    timeout: const Duration(seconds: 15),
    method: 'POST',
    sendAsJson: true,
  ),
  config: OutboxConfig(
    retry: RetryPolicy(
      baseDelay: const Duration(milliseconds: 500),
      maxDelay: const Duration(seconds: 60),
      maxAttempts: 8,
    ),
    concurrency: 3,              // Parallel processing tasks
    autoStart: true,              // Start processing on enqueue
    lockTimeout: const Duration(minutes: 5),  // Protection against hangs
    heartbeat: const Duration(seconds: 1),    // Processing tick interval
    pauseOnNoNetwork: false,     // Optional network monitoring
  ),
  metrics: ConsoleMetricsSink(), // Optional metrics
);
```

### Stores

#### SQLite Store (Mobile/Desktop)

Persistent storage using SQLite:

```dart
final store = SqliteStore(dbPath: '/path/to/outbox.db');
await store.init();
```

#### Memory Store (Testing)

In-memory storage for testing:

```dart
final store = MemoryStore();
await store.init();
```

### Transports

#### HTTP Transport

Send entries via HTTP/HTTPS:

```dart
final transport = HttpTransport(
  endpoint: Uri.parse('https://api.example.com/outbox'),
  authHeaders: () async => {'Authorization': 'Bearer $token'},
  client: yourHttpClient,
  timeout: const Duration(seconds: 15),
  method: 'POST',
  sendAsJson: true,
);
```

#### Custom Transport

Create your own transport implementation:

```dart
class GrpcTransport implements OutboxTransport {
  @override
  Future<SendResult> send(OutboxEntry entry) async {
    // Custom gRPC implementation
    try {
      // Send via gRPC
      final response = await grpcClient.send(entry.payload);
      return const SendResult(success: true);
    } catch (e) {
      return SendResult(
        success: false,
        error: e.toString(),
      );
    }
  }
}
```

## 📚 Examples

See the `example/` directory for complete examples:

- **`quick_start.dart`** - Basic usage with SQLite store
- **`http_orders.dart`** - Order processing with multiple entries
- **`analytics_lowprio.dart`** - Low-priority analytics events with delayed start

### Running Examples

```bash
# Quick start example
dart run example/quick_start.dart

# HTTP orders example
dart run example/http_orders.dart

# Analytics example
dart run example/analytics_lowprio.dart
```

## 🔧 Advanced Usage

### Custom Metrics

Track outbox metrics with custom sinks:

```dart
class CustomMetricsSink implements MetricsSink {
  @override
  void counter(String name, {int value = 1, Map<String, String>? tags}) {
    // Send to your metrics service
    metricsService.increment(name, value, tags: tags);
  }

  @override
  void gauge(String name, double value, {Map<String, String>? tags}) {
    // Record gauge metric
    metricsService.gauge(name, value, tags: tags);
  }

  @override
  void timing(String name, Duration duration, {Map<String, String>? tags}) {
    // Record timing metric
    metricsService.timing(name, duration, tags: tags);
  }
}

final outbox = DurableOutbox(
  // ...
  metrics: CustomMetricsSink(),
);
```

### Error Handling

Handle processing errors:

```dart
// Watch for failed entries
outbox.watch().listen((state) {
  if (state.failedCount > 0) {
    // Handle failed entries
    print('${state.failedCount} entries failed');
  }
});

// Clear failed entries
await outbox.clear(channel: 'orders');
```

### Lifecycle Management

Properly initialize and dispose:

```dart
final outbox = DurableOutbox(/* ... */);

// Initialize
await outbox.init();

// Use outbox
await outbox.enqueue(/* ... */);

// Cleanup when done
await outbox.close();
```

## 🛡️ Reliability

- **Idempotency**: Every entry can have an idempotency key to prevent duplicates
- **Transactions**: Store operations use transactions for consistency
- **Stuck Entry Protection**: `lockTimeout` and `heartbeat` restart hung entries
- **Error Logging**: Last error is stored with each entry for debugging
- **Retry Safety**: Retries only on transient errors, not permanent failures

## 🌐 Platform Support

| Platform          | Store                   | Status            |
| ----------------- | ----------------------- | ----------------- |
| Dart CLI / Server | `SqliteStore` (sqlite3) | ✅ Fully supported |
| Flutter Mobile    | `SqliteStore` (sqflite) | ✅ Fully supported |
| Flutter Desktop   | `SqliteStore` (sqlite3) | ✅ Fully supported |
| Flutter Web       | `MemoryStore`           | ✅ Basic support   |
| Testing           | `MemoryStore`           | ✅ Fully supported |

**Note**: For production web applications, consider implementing an IndexedDB store (planned for v0.2.0).

## 📖 API Reference

### DurableOutbox

Main outbox facade class.

**Methods:**

- `Future<void> init()` - Initialize the outbox
- `Future<String> enqueue({required String channel, required Object payload, Map<String, String>? headers, String? idempotencyKey, int priority = 0, DateTime? notBefore})` - Enqueue an entry
- `Future<void> drain()` - Manually trigger processing
- `void pause()` - Pause processing
- `void resume()` - Resume processing
- `Future<void> clear({String? channel})` - Clear entries
- `Stream<OutboxState> watch()` - Watch outbox state
- `Future<void> close()` - Clean up resources

### OutboxStore

Storage abstraction interface.

**Implementations:**

- `SqliteStore` - SQLite-based persistent storage
- `MemoryStore` - In-memory storage for testing

### OutboxTransport

Transport abstraction interface.

**Implementations:**

- `HttpTransport` - HTTP/HTTPS transport

### RetryPolicy

Configuration for retry behavior.

**Parameters:**

- `baseDelay` (default: 500ms) - Base delay for backoff
- `maxDelay` (default: 60s) - Maximum delay between retries
- `maxAttempts` (default: 8) - Maximum number of retry attempts

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the [BSD 3-Clause License](LICENSE).

## 🙏 Acknowledgments

Inspired by the outbox pattern and reliable queue systems. Built specifically for Dart/Flutter with focus on offline-first applications, guaranteed delivery, and cross-platform consistency.

---

**Made with ❤️ for the Dart community**
