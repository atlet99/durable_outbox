import '../models.dart';

/// Abstract interface for sending outbox entries to a backend.
///
/// Implementations handle the actual delivery of entries to external systems.
/// See [HttpTransport] for HTTP/HTTPS delivery.
abstract class OutboxTransport {
  /// Sends an entry to the backend.
  ///
  /// Returns a [SendResult] indicating success, failure, or need for retry.
  ///
  /// The outbox scheduler will use this result to determine whether to
  /// mark the entry as done, retry it, or mark it as permanently failed.
  Future<SendResult> send(OutboxEntry entry);
}
