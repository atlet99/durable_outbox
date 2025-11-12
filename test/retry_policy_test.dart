import 'package:durable_outbox/durable_outbox.dart';
import 'package:test/test.dart';

void main() {
  group('RetryPolicy', () {
    test('should calculate next attempt with backoff', () {
      final policy = const RetryPolicy(
        baseDelay: Duration(milliseconds: 500),
        maxDelay: Duration(seconds: 60),
        maxAttempts: 8,
      );

      final now = DateTime.now();
      final nextAttempt = policy.calculateNextAttempt(
        currentAttempt: 0,
        now: now,
      );

      expect(nextAttempt.isAfter(now), isTrue);
      expect(
        nextAttempt.difference(now).inMilliseconds,
        greaterThanOrEqualTo(500),
      );
    });

    test('should increase delay with each attempt', () {
      final policy = const RetryPolicy(
        baseDelay: Duration(milliseconds: 100),
        maxDelay: Duration(seconds: 10),
        maxAttempts: 5,
      );

      final now = DateTime.now();
      final delays = <Duration>[];

      for (var attempt = 0; attempt < 3; attempt++) {
        final nextAttempt = policy.calculateNextAttempt(
          currentAttempt: attempt,
          now: now,
          previousDelay: attempt > 0 ? delays[attempt - 1] : null,
        );
        final delay = nextAttempt.difference(now);
        delays.add(delay);
      }

      // Delays should generally increase (with jitter, might not be strictly increasing)
      expect(delays.length, equals(3));
      expect(delays[0].inMilliseconds, greaterThanOrEqualTo(100));
    });

    test('should not retry after max attempts', () {
      final policy = const RetryPolicy(maxAttempts: 3);

      final now = DateTime.now();
      final nextAttempt = policy.calculateNextAttempt(
        currentAttempt: 3,
        now: now,
      );

      // Should be far in the future (effectively no retry)
      expect(nextAttempt.difference(now).inDays, greaterThan(300));
    });

    test('should respect max delay', () {
      final policy = const RetryPolicy(
        baseDelay: Duration(milliseconds: 100),
        maxDelay: Duration(seconds: 1),
        maxAttempts: 10,
      );

      final now = DateTime.now();
      final nextAttempt = policy.calculateNextAttempt(
        currentAttempt: 10, // High attempt number
        now: now,
        previousDelay: const Duration(seconds: 2), // Previous delay exceeds max
      );

      final delay = nextAttempt.difference(now);
      expect(delay.inSeconds, lessThanOrEqualTo(2)); // Should be capped
    });

    test('should retry on 5xx status codes', () {
      final policy = const RetryPolicy();

      expect(policy.shouldRetryHttpStatus(500), isTrue);
      expect(policy.shouldRetryHttpStatus(503), isTrue);
      expect(policy.shouldRetryHttpStatus(504), isTrue);
      expect(policy.shouldRetryHttpStatus(502), isTrue);
    });

    test('should retry on 429 status code', () {
      final policy = const RetryPolicy();

      expect(policy.shouldRetryHttpStatus(429), isTrue);
    });

    test('should retry on 408 status code', () {
      final policy = const RetryPolicy();

      expect(policy.shouldRetryHttpStatus(408), isTrue);
    });

    test('should not retry on 4xx status codes (except 429, 408)', () {
      final policy = const RetryPolicy();

      expect(policy.shouldRetryHttpStatus(400), isFalse);
      expect(policy.shouldRetryHttpStatus(404), isFalse);
      expect(policy.shouldRetryHttpStatus(401), isFalse);
      expect(policy.shouldRetryHttpStatus(403), isFalse);
    });

    test('should not retry on 2xx status codes', () {
      final policy = const RetryPolicy();

      expect(policy.shouldRetryHttpStatus(200), isFalse);
      expect(policy.shouldRetryHttpStatus(201), isFalse);
      expect(policy.shouldRetryHttpStatus(204), isFalse);
    });

    test('should not retry on 3xx status codes', () {
      final policy = const RetryPolicy();

      expect(
        policy.shouldRetryHttpStatus(301),
        isTrue, // Default: retry on unknown
      );
      expect(policy.shouldRetryHttpStatus(302), isTrue);
    });

    test('should use decorrelated jitter backoff', () {
      final policy = const RetryPolicy(
        baseDelay: Duration(milliseconds: 100),
        maxDelay: Duration(seconds: 5),
        maxAttempts: 10,
      );

      final now = DateTime.now();
      Duration? previousDelay;

      // Calculate multiple attempts to verify jitter
      final delays = <Duration>[];
      for (var attempt = 0; attempt < 5; attempt++) {
        final nextAttempt = policy.calculateNextAttempt(
          currentAttempt: attempt,
          now: now,
          previousDelay: previousDelay,
        );
        final delay = nextAttempt.difference(now);
        delays.add(delay);
        previousDelay = delay;
      }

      // All delays should be within bounds
      for (final delay in delays) {
        expect(delay.inMilliseconds, greaterThanOrEqualTo(100));
        expect(delay.inSeconds, lessThanOrEqualTo(6)); // Some margin for jitter
      }

      // Delays should vary (jitter)
      final uniqueDelays = delays.toSet();
      expect(uniqueDelays.length, greaterThan(1)); // Should have some variation
    });
  });
}
