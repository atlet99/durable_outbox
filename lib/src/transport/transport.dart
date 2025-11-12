import '../models.dart';

/// Abstract interface for sending outbox entries to a backend.
abstract class OutboxTransport {
  /// Sends an entry to the backend.
  ///
  /// Returns a [SendResult] indicating success, failure, or need for retry.
  Future<SendResult> send(OutboxEntry entry);
}
