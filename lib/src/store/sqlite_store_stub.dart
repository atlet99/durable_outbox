// Stub implementation for non-Flutter platforms
import '../models.dart';
import 'store.dart';

/// SQLite implementation of [OutboxStore].
///
/// This is a stub implementation. For Flutter projects, use the actual
/// SqliteStore from sqlite_store.dart which requires sqflite package.
class SqliteStore implements OutboxStore {
  SqliteStore({required String dbPath}) {
    throw UnsupportedError(
      'SqliteStore requires Flutter and sqflite package. '
      'Add sqflite to your pubspec.yaml dependencies.',
    );
  }

  @override
  Future<void> init() => throw UnsupportedError('Not supported');

  @override
  Future<void> insert(OutboxEntry entry) =>
      throw UnsupportedError('Not supported');

  @override
  Future<void> update(OutboxEntry entry) =>
      throw UnsupportedError('Not supported');

  @override
  Future<void> markDone(String id) => throw UnsupportedError('Not supported');

  @override
  Future<void> markFailed(String id, String error, {DateTime? nextAttempt}) =>
      throw UnsupportedError('Not supported');

  @override
  Future<List<OutboxEntry>> pickForProcessing(int limit, DateTime now) =>
      throw UnsupportedError('Not supported');

  @override
  Future<void> clear({String? channel}) =>
      throw UnsupportedError('Not supported');

  @override
  Stream<int> watchCount({String? channel}) =>
      throw UnsupportedError('Not supported');

  Future<void> close() => throw UnsupportedError('Not supported');
}
