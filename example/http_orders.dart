import 'dart:async';
import 'dart:io' as io;

import 'package:durable_outbox/durable_outbox.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as path_provider;

/// Simple HTTP client implementation.
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

      final response =
          await request.close().timeout(timeout ?? const Duration(seconds: 15));
      final responseBody =
          await response.transform(const io.SystemEncoding().decoder).join();

      // Convert HttpHeaders to Map
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

Future<void> main() async {
  final appDir = await path_provider.getApplicationDocumentsDirectory();
  final dbPath = path.join(appDir.path, 'orders_outbox.db');

  final outbox = DurableOutbox(
    store: SqliteStore(dbPath: dbPath),
    transport: HttpTransport(
      endpoint: Uri.parse('https://api.example.com/orders'),
      authHeaders: () async => {'Authorization': 'Bearer your-token-here'},
      client: SimpleHttpClient(),
    ),
    config: const OutboxConfig(
      concurrency: 3,
      autoStart: true,
    ),
  );

  await outbox.init();

  // Enqueue multiple orders
  for (var i = 1; i <= 5; i++) {
    await outbox.enqueue(
      channel: 'orders',
      payload: {
        'action': 'create',
        'orderId': 'o-$i',
        'items': ['item1', 'item2'],
      },
      idempotencyKey: 'orders:o-$i',
      priority: i, // Higher priority for later orders
    );
    print('Enqueued order o-$i');
  }

  // Manually trigger processing
  await outbox.drain();

  // Watch state
  outbox.watch().listen((state) {
    print(
      'State: paused=${state.isPaused}, running=${state.isRunning}, queued=${state.queuedCount}',
    );
  });

  // Wait for processing
  await Future.delayed(const Duration(seconds: 10));

  await outbox.close();
}
