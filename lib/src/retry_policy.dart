import 'dart:async';
import 'dart:io';

import 'utils/backoff.dart';

/// Configuration for retry behavior.
///
/// Controls how failed entries are retried, including backoff strategy
/// and maximum attempt limits.
class RetryPolicy {
  const RetryPolicy({
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 60),
    this.maxAttempts = 8,
  });

  final Duration baseDelay;
  final Duration maxDelay;
  final int maxAttempts;

  /// Calculates the next attempt time based on current attempt and previous delay.
  DateTime calculateNextAttempt({
    required int currentAttempt,
    required DateTime now,
    Duration? previousDelay,
  }) {
    if (currentAttempt >= maxAttempts) {
      // Max attempts reached, don't retry
      return now.add(const Duration(days: 365));
    }

    final delay = calculateNextRetryDelay(
      base: baseDelay,
      max: maxDelay,
      previousDelay: previousDelay ?? baseDelay,
      attempt: currentAttempt,
    );

    return now.add(delay);
  }

  /// Determines if an error should be retried.
  bool shouldRetry(Object error) {
    if (error is SocketException || error is HttpException) {
      return true;
    }

    if (error is TimeoutException) {
      return true;
    }

    // For HTTP errors, check status code
    if (error is HttpException) {
      // Retry on 5xx and 429, don't retry on other 4xx
      // This will be handled in HttpTransport
      return true;
    }

    // Default: retry on unknown errors
    return true;
  }

  /// Determines if an HTTP status code should be retried.
  bool shouldRetryHttpStatus(int statusCode) {
    // Retry on server errors (5xx)
    if (statusCode >= 500) {
      return true;
    }

    // Retry on rate limiting (429)
    if (statusCode == 429) {
      return true;
    }

    // Retry on some client errors that might be transient
    if (statusCode == 408) {
      return true;
    }

    // Don't retry on other 4xx (client errors)
    if (statusCode >= 400) {
      return false;
    }

    // Success codes: don't retry
    if (statusCode >= 200 && statusCode < 300) {
      return false;
    }

    // Default: retry on unknown status codes
    return true;
  }
}
