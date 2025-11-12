/// Status of an outbox entry.
enum OutboxEntryStatus {
  queued,
  processing,
  done,
  failed,
}

/// Represents a single entry in the outbox queue.
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

  final String id;
  final String channel;
  final Object payload;
  final Map<String, String>? headers;
  final String? idempotencyKey;
  final int priority;
  final int attempt;
  final DateTime? nextAttemptAt;
  final DateTime createdAt;
  final OutboxEntryStatus status;
  final String? error;

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
class SendResult {
  const SendResult({
    required this.success,
    this.permanentlyFailed = false,
    this.error,
    this.retryAfter,
  });

  final bool success;
  final bool permanentlyFailed;
  final String? error;
  final DateTime? retryAfter;
}

/// State of the outbox.
class OutboxState {
  const OutboxState({
    required this.isPaused,
    required this.isRunning,
    required this.queuedCount,
    required this.processingCount,
    required this.failedCount,
  });

  final bool isPaused;
  final bool isRunning;
  final int queuedCount;
  final int processingCount;
  final int failedCount;
}
