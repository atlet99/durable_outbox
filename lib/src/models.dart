/// Status of an outbox entry.
enum OutboxEntryStatus {
  queued,
  processing,
  done,
  failed,
}

/// Represents a single entry in the outbox queue.
///
/// Each entry contains the data to be sent, along with metadata
/// for processing, retries, and idempotency.
class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.channel,
    required this.payload,
    this.headers,
    this.idempotencyKey,
    this.priority = 0,
    this.attempt = 0,
    this.nextAttemptAt,
    required this.createdAt,
    this.status = OutboxEntryStatus.queued,
    this.error,
  });

  /// Unique identifier for this entry.
  final String id;

  /// Channel name for categorizing entries.
  final String channel;

  /// Payload data to be sent (will be JSON-encoded if using HttpTransport).
  final Object payload;

  /// Optional HTTP headers to include with the request.
  final Map<String, String>? headers;

  /// Optional idempotency key for preventing duplicate processing.
  final String? idempotencyKey;

  /// Priority level (higher numbers = higher priority).
  final int priority;

  /// Number of processing attempts made.
  final int attempt;

  /// Scheduled time for the next retry attempt.
  final DateTime? nextAttemptAt;

  /// Timestamp when this entry was created.
  final DateTime createdAt;

  /// Current status of this entry.
  final OutboxEntryStatus status;

  /// Last error message, if any.
  final String? error;

  /// Creates a copy of this entry with the given fields replaced.
  OutboxEntry copyWith({
    String? id,
    String? channel,
    Object? payload,
    Map<String, String>? headers,
    String? idempotencyKey,
    int? priority,
    int? attempt,
    DateTime? nextAttemptAt,
    DateTime? createdAt,
    OutboxEntryStatus? status,
    String? error,
  }) {
    return OutboxEntry(
      id: id ?? this.id,
      channel: channel ?? this.channel,
      payload: payload ?? this.payload,
      headers: headers ?? this.headers,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      priority: priority ?? this.priority,
      attempt: attempt ?? this.attempt,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      error: error ?? this.error,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is OutboxEntry && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// Result of sending an entry via transport.
///
/// Used by [OutboxTransport] to indicate the outcome of a send operation.
class SendResult {
  const SendResult({
    required this.success,
    this.permanentlyFailed = false,
    this.error,
    this.retryAfter,
  });

  /// Whether the send operation was successful.
  final bool success;

  /// Whether the failure is permanent and should not be retried.
  final bool permanentlyFailed;

  /// Error message if the send failed.
  final String? error;

  /// Suggested time to retry after (e.g., from Retry-After header).
  final DateTime? retryAfter;
}

/// State of the outbox.
///
/// Represents the current operational state and queue statistics.
class OutboxState {
  const OutboxState({
    required this.isPaused,
    required this.isRunning,
    required this.queuedCount,
    required this.processingCount,
    required this.failedCount,
  });

  /// Whether processing is currently paused.
  final bool isPaused;

  /// Whether the scheduler is currently running.
  final bool isRunning;

  /// Number of entries waiting to be processed.
  final int queuedCount;

  /// Number of entries currently being processed.
  final int processingCount;

  /// Number of entries that have permanently failed.
  final int failedCount;
}
