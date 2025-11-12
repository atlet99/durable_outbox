import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models.dart';
import 'store.dart';

/// SQLite implementation of [OutboxStore].
class SqliteStore implements OutboxStore {
  SqliteStore({required this.dbPath});

  final String dbPath;
  Database? _db;
  final StreamController<int> _countController =
      StreamController<int>.broadcast();

  @override
  Future<void> init() async {
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
    );

    // Start watching for changes
    _startWatching();
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
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

    await db.execute('''
      CREATE INDEX idx_status_next_attempt 
      ON outbox_entries(status, next_attempt_at)
    ''');

    await db.execute('''
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

    await db.insert(
      'outbox_entries',
      _entryToMap(entry),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notifyCount();
  }

  @override
  Future<void> update(OutboxEntry entry) async {
    final db = _db;
    if (db == null) {
      throw StateError('Store not initialized. Call init() first.');
    }

    await db.update(
      'outbox_entries',
      _entryToMap(entry),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
    _notifyCount();
  }

  @override
  Future<void> markDone(String id) async {
    final db = _db;
    if (db == null) {
      throw StateError('Store not initialized. Call init() first.');
    }

    await db.update(
      'outbox_entries',
      {
        'status': OutboxEntryStatus.done.name,
        'error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
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

    await db.update(
      'outbox_entries',
      {
        'status': OutboxEntryStatus.failed.name,
        'error': error,
        'next_attempt_at': nextAttempt?.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _notifyCount();
  }

  @override
  Future<List<OutboxEntry>> pickForProcessing(int limit, DateTime now) async {
    final db = _db;
    if (db == null) {
      throw StateError('Store not initialized. Call init() first.');
    }

    final nowMs = now.millisecondsSinceEpoch;
    final rows = await db.query(
      'outbox_entries',
      where: 'status = ? AND (next_attempt_at IS NULL OR next_attempt_at <= ?)',
      whereArgs: [OutboxEntryStatus.queued.name, nowMs],
      orderBy: 'priority DESC, created_at ASC',
      limit: limit,
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
      await db.delete(
        'outbox_entries',
        where: 'channel = ?',
        whereArgs: [channel],
      );
    } else {
      await db.delete('outbox_entries');
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
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM outbox_entries WHERE channel = ?',
        [channel],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    }

    final result = await db.rawQuery('SELECT COUNT(*) as count FROM outbox_entries');
    return Sqflite.firstIntValue(result) ?? 0;
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

  OutboxEntry _mapToEntry(Map<String, Object?> map) {
    return OutboxEntry(
      id: map['id'] as String,
      channel: map['channel'] as String,
      payload: jsonDecode(map['payload'] as String),
      headers: map['headers'] != null
          ? Map<String, String>.from(jsonDecode(map['headers'] as String))
          : null,
      idempotencyKey: map['idempotency_key'] as String?,
      priority: map['priority'] as int,
      attempt: map['attempt'] as int,
      nextAttemptAt: map['next_attempt_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['next_attempt_at'] as int)
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      status: OutboxEntryStatus.values.firstWhere(
        (e) => e.name == map['status'] as String,
      ),
      error: map['error'] as String?,
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
    await _db?.close();
    _db = null;
  }
}
