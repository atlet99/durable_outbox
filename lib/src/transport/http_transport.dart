import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models.dart';
import '../utils/idempotency.dart';
import 'transport.dart';

/// HTTP client interface for making requests.
abstract class HttpClient {
  Future<HttpResponse> request({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  });
}

/// HTTP response wrapper.
class HttpResponse {
  const HttpResponse({
    required this.statusCode,
    this.headers,
    this.body,
  });

  final int statusCode;
  final Map<String, String>? headers;
  final String? body;
}

/// HTTP implementation of [OutboxTransport].
class HttpTransport implements OutboxTransport {
  HttpTransport({
    required this.endpoint,
    required this.authHeaders,
    required this.client,
    this.timeout = const Duration(seconds: 15),
    this.method = 'POST',
    this.sendAsJson = true,
  });

  final Uri endpoint;
  final FutureOr<Map<String, String>> Function()? authHeaders;
  final HttpClient client;
  final Duration timeout;
  final String method;
  final bool sendAsJson;

  @override
  Future<SendResult> send(OutboxEntry entry) async {
    try {
      final headers = <String, String>{};

      // Add auth headers if provided
      if (authHeaders != null) {
        final auth = await authHeaders!();
        headers.addAll(auth);
      }

      // Add idempotency key if present
      if (entry.idempotencyKey != null &&
          isValidIdempotencyKey(entry.idempotencyKey)) {
        headers[idempotencyKeyHeader] = entry.idempotencyKey!;
      }

      // Add custom headers from entry
      if (entry.headers != null) {
        headers.addAll(entry.headers!);
      }

      // Set content type for JSON
      if (sendAsJson) {
        headers['Content-Type'] = 'application/json';
      }

      // Prepare body
      Object? body;
      if (sendAsJson) {
        body = jsonEncode(entry.payload);
      } else {
        body = entry.payload;
      }

      // Make request
      final response = await client.request(
        method: method,
        uri: endpoint,
        headers: headers,
        body: body,
        timeout: timeout,
      );

      // Handle response
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const SendResult(success: true);
      }

      // Handle idempotency conflict (409)
      if (response.statusCode == 409) {
        // Server indicates already processed, treat as success
        return const SendResult(success: true);
      }

      // Handle rate limiting (429)
      if (response.statusCode == 429) {
        final retryAfter = _parseRetryAfter(response.headers);
        return SendResult(
          success: false,
          error: 'Rate limited',
          retryAfter: retryAfter,
        );
      }

      // Handle client errors (4xx) - don't retry
      if (response.statusCode >= 400 && response.statusCode < 500) {
        return SendResult(
          success: false,
          permanentlyFailed: true,
          error: 'Client error: ${response.statusCode}',
        );
      }

      // Handle server errors (5xx) - retry
      if (response.statusCode >= 500) {
        return SendResult(
          success: false,
          error: 'Server error: ${response.statusCode}',
        );
      }

      // Unknown status code
      return SendResult(
        success: false,
        error: 'Unknown status code: ${response.statusCode}',
      );
    } on TimeoutException catch (e) {
      return SendResult(
        success: false,
        error: 'Request timeout: ${e.message}',
      );
    } on SocketException catch (e) {
      return SendResult(
        success: false,
        error: 'Network error: ${e.message}',
      );
    } catch (e) {
      return SendResult(
        success: false,
        error: 'Unexpected error: $e',
      );
    }
  }

  DateTime? _parseRetryAfter(Map<String, String>? headers) {
    if (headers == null) {
      return null;
    }

    final retryAfter = headers['retry-after'];
    if (retryAfter == null) {
      return null;
    }

    // Try to parse as seconds
    final seconds = int.tryParse(retryAfter);
    if (seconds != null) {
      return DateTime.now().add(Duration(seconds: seconds));
    }

    // Could also parse as HTTP date, but keeping it simple for now
    return null;
  }
}
