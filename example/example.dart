import 'dart:async';
import 'dart:io' as io;

import 'package:durable_outbox/durable_outbox.dart';
import 'package:path/path.dart' as path;

/// Simple HTTP client implementation for the example.
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
  // Use a temporary directory for the database
  final tempDir = io.Directory.systemTemp;
  final dbPath = path.join(tempDir.path, 'outbox.db');

  // Create outbox with SQLite store
  final outbox = DurableOutbox(
    store: SqliteStore(dbPath: dbPath),
    transport: HttpTransport(
      endpoint: Uri.parse('https://api.example.com/outbox'),
      authHeaders: () async => {'Authorization': 'Bearer your-token-here'},
      client: SimpleHttpClient(),
    ),
    config: const OutboxConfig(
      concurrency: 3,
      autoStart: true,
      pauseOnNoNetwork: false,
    ),
  );

  await outbox.init();

  // Enqueue an entry
  final id = await outbox.enqueue(
    channel: 'orders',
    payload: {'action': 'create', 'orderId': 'o-123'},
    idempotencyKey: 'orders:o-123',
  );

  print('Enqueued entry with ID: $id');

  // Watch queue count
  outbox.store.watchCount(channel: 'orders').listen((count) {
    print('Queue count: $count');
  });

  // Wait a bit for processing
  await Future.delayed(const Duration(seconds: 5));

  // Cleanup
  await outbox.close();
}
