import 'dart:async';
import 'dart:io' as io;

import 'package:durable_outbox/durable_outbox.dart';
import 'package:path/path.dart' as path;

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
  final tempDir = io.Directory.systemTemp;
  final dbPath = path.join(tempDir.path, 'analytics_outbox.db');

  final outbox = DurableOutbox(
    store: SqliteStore(dbPath: dbPath),
    transport: HttpTransport(
      endpoint: Uri.parse('https://api.example.com/analytics'),
      authHeaders: () async => {'Authorization': 'Bearer your-token-here'},
      client: SimpleHttpClient(),
    ),
    config: const OutboxConfig(
      concurrency: 2,
      autoStart: true,
    ),
  );

  await outbox.init();

  // Enqueue analytics events with low priority and delayed start
  await outbox.enqueue(
    channel: 'analytics',
    payload: {
      'event': 'page_view',
      'page': '/home',
      'timestamp': DateTime.now().toIso8601String(),
    },
    priority: -1, // Low priority
    notBefore: DateTime.now().add(const Duration(minutes: 5)), // Delayed start
  );

  print('Enqueued analytics event (will start in 5 minutes)');

  // Watch queue count
  outbox.store.watchCount(channel: 'analytics').listen((count) {
    print('Analytics queue count: $count');
  });

  // Wait a bit
  await Future.delayed(const Duration(seconds: 2));

  await outbox.close();
}
