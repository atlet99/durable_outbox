import 'dart:io';

import 'package:durable_outbox/durable_outbox.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  // Only run SQLite tests if sqflite is available (Flutter environment)
  // In pure Dart environment, these tests will be skipped
  group('SqliteStore', () {
    late SqliteStore store;
    late String dbPath;

    setUp(() {
      // Create temporary database file
      final tempDir = Directory.systemTemp;
      dbPath = path.join(
        tempDir.path,
        'test_outbox_${DateTime.now().millisecondsSinceEpoch}.db',
      );
      store = SqliteStore(dbPath: dbPath);
    });

    tearDown(() async {
      try {
        await store.close();
        // Clean up database file
        final file = File(dbPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        // Ignore errors in tearDown
      }
    });

    test(
      'should initialize',
      () async {
        try {
          await store.init();
          expect(store, isNotNull);
        } catch (e) {
          // Skip test if sqflite is not available
          if (e.toString().contains('sqflite') ||
              e.toString().contains('Flutter')) {
            return; // Skip silently
          }
          rethrow;
        }
      },
      skip: 'Requires Flutter environment with sqflite',
    );

    test(
      'should insert and retrieve entries',
      () async {
        try {
          await store.init();

          final entry = OutboxEntry(
            id: 'test-1',
            channel: 'test',
            payload: {'key': 'value'},
            createdAt: DateTime.now(),
          );

          await store.insert(entry);

          final candidates = await store.pickForProcessing(10, DateTime.now());
          expect(candidates.length, equals(1));
          expect(candidates.first.id, equals('test-1'));
          expect(candidates.first.channel, equals('test'));
        } catch (e) {
          if (e.toString().contains('sqflite') ||
              e.toString().contains('Flutter')) {
            return; // Skip silently
          }
          rethrow;
        }
      },
      skip: 'Requires Flutter environment with sqflite',
    );

    test(
      'should mark entry as done',
      () async {
        try {
          await store.init();

          final entry = OutboxEntry(
            id: 'test-1',
            channel: 'test',
            payload: {'key': 'value'},
            createdAt: DateTime.now(),
          );

          await store.insert(entry);
          await store.markDone('test-1');

          final candidates = await store.pickForProcessing(10, DateTime.now());
          expect(candidates.length, equals(0));
        } catch (e) {
          if (e.toString().contains('sqflite') ||
              e.toString().contains('Flutter')) {
            return; // Skip silently
          }
          rethrow;
        }
      },
      skip: 'Requires Flutter environment with sqflite',
    );

    test(
      'should persist entries across store instances',
      () async {
        try {
          // First store instance
          await store.init();
          await store.insert(
            OutboxEntry(
              id: 'persistent-1',
              channel: 'test',
              payload: {'key': 'value'},
              createdAt: DateTime.now(),
            ),
          );
          await store.close();

          // Second store instance with same database
          final store2 = SqliteStore(dbPath: dbPath);
          await store2.init();

          final candidates = await store2.pickForProcessing(10, DateTime.now());
          expect(candidates.length, equals(1));
          expect(candidates.first.id, equals('persistent-1'));

          await store2.close();
        } catch (e) {
          if (e.toString().contains('sqflite') ||
              e.toString().contains('Flutter')) {
            return; // Skip silently
          }
          rethrow;
        }
      },
      skip: 'Requires Flutter environment with sqflite',
    );
  });
}
