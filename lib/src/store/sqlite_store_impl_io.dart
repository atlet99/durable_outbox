import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../models.dart';
import 'store.dart';

/// SQLite implementation of [OutboxStore] using sqlite3 package.
///
/// This implementation works with pure Dart (CLI/Server) applications.
/// Provides persistent storage for outbox entries using SQLite.
///
/// Example:
/// ```dart
/// final store = SqliteStore(dbPath: '/path/to/outbox.db');
/// await store.init();
/// ```
class SqliteStore implements OutboxStore {
  SqliteStore({required this.dbPath});

  final String dbPath;
  Database? _db;
  final StreamController<int> _countController =
      StreamController<int>.broadcast();

  @override
  Future<void> init() async {
    // Ensure parent directory exists
    final file = File(dbPath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    _db = sqlite3.open(dbPath);

    // Check if tables exist, if not create them
    final tables = _db!.select('''
      SELECT name FROM sqlite_master 
      WHERE type='table' AND name='outbox_entries'
    ''');

    if (tables.isEmpty) {
      _onCreate();
    }

    // Start watching for changes
    _startWatching();
  }

  void _onCreate() {
    _db!.execute('''
      CREATE TABLE outbox_entries (
        id TEXT PRIMARY KEY,
        channel TEXT NOT NULL,
        payload TEXT NOT NULL,
        headers TEXT,
        idempotency_key TEXT,
        priority INTEGER NOT NULL DEFAULT 0,
        attempt INTEGER NOT NULL DEFAULT 0,
        next_attempt_at INTEGER,
        created_at INTEGER NOT NULL,
        status TEXT NOT NULL,
        error TEXT
      )
    ''');

    _db!.execute('''
      CREATE INDEX idx_status_next_attempt 
      ON outbox_entries(status, next_attempt_at)
    ''');

    _db!.execute('''
      CREATE INDEX idx_channel_priority_next 
      ON outbox_entries(channel, priority DESC, next_attempt_at)
    ''');
  }

  void _startWatching() {
    // Simple polling-based watch (can be improved with triggers)
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countController.isClosed) {
        timer.cancel();
        return;
      }
      _notifyCount();
    });
  }

  @override
  Future<void> insert(OutboxEntry entry) async {
    final db = _db;
    if (db == null) {
      throw StateError('Store not initialized. Call init() first.');
    }

    final map = _entryToMap(entry);
    db.execute('''
      INSERT OR REPLACE INTO outbox_entries 
      (id, channel, payload, headers, idempotency_key, priority, attempt, 
       next_attempt_at, created_at, status, error)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      map['id'],
      map['channel'],
      map['payload'],
      map['headers'],
      map['idempotency_key'],
      map['priority'],
      map['attempt'],
      map['next_attempt_at'],
      map['created_at'],
      map['status'],
      map['error'],
    ]);
    _notifyCount();
  }

  @override
  Future<void> update(OutboxEntry entry) async {
    final db = _db;
    if (db == null) {
      throw StateError('Store not initialized. Call init() first.');
    }

    final map = _entryToMap(entry);
    db.execute('''
      UPDATE outbox_entries 
      SET channel = ?, payload = ?, headers = ?, idempotency_key = ?, 
          priority = ?, attempt = ?, next_attempt_at = ?, created_at = ?, 
          status = ?, error = ?
      WHERE id = ?
    ''', [
      map['channel'],
      map['payload'],
      map['headers'],
      map['idempotency_key'],
      map['priority'],
      map['attempt'],
      map['next_attempt_at'],
      map['created_at'],
      map['status'],
      map['error'],
      entry.id,
    ]);
    _notifyCount();
  }

  @override
  Future<void> markDone(String id) async {
    final db = _db;
    if (db == null) {
      throw StateError('Store not initialized. Call init() first.');
    }

    db.execute(
      '''
      UPDATE outbox_entries 
      SET status = ?, error = NULL
      WHERE id = ?
    ''',
      [OutboxEntryStatus.done.name, id],
    );
    _notifyCount();
  }

  @override
  Future<void> markFailed(
    String id,
    String error, {
    DateTime? nextAttempt,
  }) async {
    final db = _db;
    if (db == null) {
      throw StateError('Store not initialized. Call init() first.');
    }

    // If nextAttempt is provided, status should be queued for retry
    // Otherwise, it's a permanent failure
    final status = nextAttempt != null
        ? OutboxEntryStatus.queued.name
        : OutboxEntryStatus.failed.name;

    db.execute('''
      UPDATE outbox_entries 
      SET status = ?, error = ?, next_attempt_at = ?
      WHERE id = ?
    ''', [
      status,
      error,
      nextAttempt?.millisecondsSinceEpoch,
      id,
    ]);
    _notifyCount();
  }

  @override
  Future<List<OutboxEntry>> pickForProcessing(int limit, DateTime now) async {
    final db = _db;
    if (db == null) {
      throw StateError('Store not initialized. Call init() first.');
    }

    final nowMs = now.millisecondsSinceEpoch;
    final rows = db.select(
      '''
      SELECT * FROM outbox_entries 
      WHERE status = ? AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
      ORDER BY priority DESC, created_at ASC
      LIMIT ?
    ''',
      [OutboxEntryStatus.queued.name, nowMs, limit],
    );

    return rows.map(_mapToEntry).toList();
  }

  @override
  Future<void> clear({String? channel}) async {
    final db = _db;
    if (db == null) {
      throw StateError('Store not initialized. Call init() first.');
    }

    if (channel != null) {
      db.execute('DELETE FROM outbox_entries WHERE channel = ?', [channel]);
    } else {
      db.execute('DELETE FROM outbox_entries');
    }
    _notifyCount();
  }

  @override
  Stream<int> watchCount({String? channel}) {
    // Emit initial count immediately, then stream updates
    return Stream<int>.multi((controller) {
      // Emit initial count
      _getCountAsync(channel).then((count) {
        if (!controller.isClosed) {
          controller.add(count);
        }
      });

      // Listen to updates
      final subscription = _countController.stream.listen((_) {
        _getCountAsync(channel).then((count) {
          if (!controller.isClosed) {
            controller.add(count);
          }
        });
      });

      // Cancel subscription when stream is closed
      controller.onCancel = () {
        subscription.cancel();
      };
    }).distinct();
  }

  Future<int> _getCountAsync(String? channel) async {
    final db = _db;
    if (db == null) {
      return 0;
    }

    if (channel != null) {
      final result = db.select(
        'SELECT COUNT(*) as count FROM outbox_entries WHERE channel = ?',
        [channel],
      );
      return result.isNotEmpty ? (result.first['count'] as int) : 0;
    }

    final result = db.select('SELECT COUNT(*) as count FROM outbox_entries');
    return result.isNotEmpty ? (result.first['count'] as int) : 0;
  }

  Map<String, Object?> _entryToMap(OutboxEntry entry) {
    return {
      'id': entry.id,
      'channel': entry.channel,
      'payload': jsonEncode(entry.payload),
      'headers': entry.headers != null ? jsonEncode(entry.headers) : null,
      'idempotency_key': entry.idempotencyKey,
      'priority': entry.priority,
      'attempt': entry.attempt,
      'next_attempt_at': entry.nextAttemptAt?.millisecondsSinceEpoch,
      'created_at': entry.createdAt.millisecondsSinceEpoch,
      'status': entry.status.name,
      'error': entry.error,
    };
  }

  OutboxEntry _mapToEntry(Row row) {
    return OutboxEntry(
      id: row['id'] as String,
      channel: row['channel'] as String,
      payload: jsonDecode(row['payload'] as String),
      headers: row['headers'] != null
          ? Map<String, String>.from(jsonDecode(row['headers'] as String))
          : null,
      idempotencyKey: row['idempotency_key'] as String?,
      priority: row['priority'] as int,
      attempt: row['attempt'] as int,
      nextAttemptAt: row['next_attempt_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['next_attempt_at'] as int)
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      status: OutboxEntryStatus.values.firstWhere(
        (e) => e.name == row['status'] as String,
      ),
      error: row['error'] as String?,
    );
  }

  void _notifyCount() {
    if (!_countController.isClosed) {
      _countController.add(0); // Trigger recalculation
    }
  }

  /// Closes the store and releases resources.
  Future<void> close() async {
    _countController.close();
    _db?.dispose();
    _db = null;
  }
}
