import 'dart:async';

import '../models.dart';
import 'store.dart';

/// In-memory implementation of [OutboxStore] for testing.
class MemoryStore implements OutboxStore {
  MemoryStore();

  final Map<String, OutboxEntry> _entries = {};
  final StreamController<int> _countController =
      StreamController<int>.broadcast();

  @override
  Future<void> init() async {
    // No-op for in-memory store
  }

  @override
  Future<void> insert(OutboxEntry entry) async {
    _entries[entry.id] = entry;
    _notifyCount();
  }

  @override
  Future<void> update(OutboxEntry entry) async {
    if (_entries.containsKey(entry.id)) {
      _entries[entry.id] = entry;
      _notifyCount();
    }
  }

  @override
  Future<void> markDone(String id) async {
    final entry = _entries[id];
    if (entry != null) {
      _entries[id] = entry.copyWith(status: OutboxEntryStatus.done);
      _notifyCount();
    }
  }

  @override
  Future<void> markFailed(
    String id,
    String error, {
    DateTime? nextAttempt,
  }) async {
    final entry = _entries[id];
    if (entry != null) {
      // If nextAttempt is provided, status should be queued for retry
      // Otherwise, it's a permanent failure
      _entries[id] = entry.copyWith(
        status: nextAttempt != null
            ? OutboxEntryStatus.queued
            : OutboxEntryStatus.failed,
        error: error,
        nextAttemptAt: nextAttempt,
      );
      _notifyCount();
    }
  }

  @override
  Future<List<OutboxEntry>> pickForProcessing(int limit, DateTime now) async {
    final candidates = _entries.values
        .where(
          (e) =>
              e.status == OutboxEntryStatus.queued &&
              (e.nextAttemptAt == null ||
                  e.nextAttemptAt!.isBefore(now) ||
                  e.nextAttemptAt!.isAtSameMomentAs(now)),
        )
        .toList();

    candidates.sort((a, b) {
      // Sort by priority (desc), then createdAt (asc)
      final priorityDiff = b.priority.compareTo(a.priority);
      if (priorityDiff != 0) {
        return priorityDiff;
      }
      return a.createdAt.compareTo(b.createdAt);
    });

    return candidates.take(limit).toList();
  }

  @override
  Future<void> clear({String? channel}) async {
    if (channel != null) {
      _entries.removeWhere((id, entry) => entry.channel == channel);
    } else {
      _entries.clear();
    }
    _notifyCount();
  }

  @override
  Stream<int> watchCount({String? channel}) {
    // Emit initial count immediately, then stream updates
    return Stream<int>.multi((controller) {
      // Emit initial count
      controller.add(_getCount(channel));

      // Listen to updates
      final subscription = _countController.stream.listen((_) {
        controller.add(_getCount(channel));
      });

      // Cancel subscription when stream is closed
      controller.onCancel = () {
        subscription.cancel();
      };
    }).distinct();
  }

  int _getCount(String? channel) {
    if (channel != null) {
      return _entries.values.where((e) => e.channel == channel).length;
    }
    return _entries.length;
  }

  void _notifyCount() {
    if (!_countController.isClosed) {
      _countController.add(_entries.length);
    }
  }

  /// Closes the store and releases resources.
  void close() {
    _countController.close();
  }
}
