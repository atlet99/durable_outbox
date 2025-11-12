import '../models.dart';

/// Abstract interface for outbox storage.
///
/// Implementations provide persistent or in-memory storage for outbox entries.
/// See [SqliteStore] for SQLite-based storage and [MemoryStore] for in-memory storage.
abstract class OutboxStore {
  /// Initializes the store (e.g., creates tables, opens database).
  ///
  /// Must be called before using any other methods.
  Future<void> init();

  /// Inserts a new entry into the store.
  Future<void> insert(OutboxEntry entry);

  /// Updates an existing entry.
  Future<void> update(OutboxEntry entry);

  /// Marks an entry as done.
  Future<void> markDone(String id);

  /// Marks an entry as failed with error message and optional next attempt time.
  Future<void> markFailed(
    String id,
    String error, {
    DateTime? nextAttempt,
  });

  /// Picks entries ready for processing.
  ///
  /// Returns entries with status=queued and nextAttemptAt <= now,
  /// ordered by priority (desc) and createdAt (asc).
  Future<List<OutboxEntry>> pickForProcessing(int limit, DateTime now);

  /// Clears entries, optionally filtered by channel.
  Future<void> clear({String? channel});

  /// Watches the count of entries, optionally filtered by channel.
  Stream<int> watchCount({String? channel});
}
