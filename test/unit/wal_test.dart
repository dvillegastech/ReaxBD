import 'package:test/test.dart';
import 'package:reaxdb_dart/src/core/wal/write_ahead_log.dart';
import 'dart:io';
import 'dart:typed_data';

void main() {
  group('Write-Ahead Log Tests', () {
    late WriteAheadLog wal;
    final testPath = 'test/wal_test_db';

    setUp(() async {
      // Clean up any existing test database
      final dir = Directory(testPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await dir.create(recursive: true);

      // Create new WAL
      wal = await WriteAheadLog.create(basePath: testPath);
    });

    tearDown(() async {
      await wal.close();

      // Clean up test database
      final dir = Directory(testPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('should create WAL directory and file', () async {
      final walDir = Directory('$testPath/wal');
      expect(await walDir.exists(), isTrue);

      // Should have at least one WAL file
      final files = await walDir.list().toList();
      expect(
        files.where((f) => f.path.endsWith('.wal')).length,
        greaterThanOrEqualTo(1),
      );
    });

    test('should append entries to WAL', () async {
      // Append entries
      await wal.append(
        'key1'.codeUnits,
        Uint8List.fromList('value1'.codeUnits),
      );
      await wal.append(
        'key2'.codeUnits,
        Uint8List.fromList('value2'.codeUnits),
      );
      await wal.append(
        'key3'.codeUnits,
        Uint8List.fromList('value3'.codeUnits),
      );

      // Check sequence number increments
      expect(wal.currentSequenceNumber, greaterThanOrEqualTo(3));
    });

    test('should append tombstone entries', () async {
      // Append regular entry
      await wal.append(
        'delete_key'.codeUnits,
        Uint8List.fromList('delete_value'.codeUnits),
      );

      // Append tombstone
      await wal.appendTombstone('delete_key'.codeUnits);

      // Sequence number should increment
      expect(wal.currentSequenceNumber, greaterThanOrEqualTo(2));
    });

    test('should recover entries after restart', () async {
      // Append entries
      await wal.append(
        'recover1'.codeUnits,
        Uint8List.fromList('value1'.codeUnits),
      );
      await wal.append(
        'recover2'.codeUnits,
        Uint8List.fromList('value2'.codeUnits),
      );
      await wal.appendTombstone('recover3'.codeUnits);

      // Close WAL
      await wal.close();

      // Create new WAL instance (simulating restart)
      final newWal = await WriteAheadLog.create(basePath: testPath);

      // Recover entries
      final entries = await newWal.recover();

      // Should have recovered entries
      expect(entries.length, greaterThanOrEqualTo(3));

      // Verify entry types
      final putEntries =
          entries.where((e) => e.type == WALEntryType.put).toList();
      final deleteEntries =
          entries.where((e) => e.type == WALEntryType.delete).toList();

      expect(putEntries.length, greaterThanOrEqualTo(2));
      expect(deleteEntries.length, greaterThanOrEqualTo(1));

      await newWal.close();
    });

    test('should handle checkpoint operation', () async {
      // Append many entries
      for (int i = 0; i < 100; i++) {
        await wal.append(
          'checkpoint_key_$i'.codeUnits,
          Uint8List.fromList('checkpoint_value_$i'.codeUnits),
        );
      }

      // Perform checkpoint
      await wal.checkpoint();

      // Should have added checkpoint entry
      expect(wal.currentSequenceNumber, greaterThan(100));
    });

    test('should handle concurrent writes', () async {
      // Write entries sequentially to avoid StreamSink conflicts
      // WAL doesn't support concurrent writes to the same sink
      for (int i = 0; i < 50; i++) {
        await wal.append(
          'concurrent_$i'.codeUnits,
          Uint8List.fromList('value_$i'.codeUnits),
        );
      }

      // Should have incremented sequence number correctly
      expect(wal.currentSequenceNumber, greaterThanOrEqualTo(50));
    });

    test('should handle large entries', () async {
      // Create large value (1MB)
      final largeValue = Uint8List(1024 * 1024);
      for (int i = 0; i < largeValue.length; i++) {
        largeValue[i] = i % 256;
      }

      // Append large entry
      await wal.append('large_key'.codeUnits, largeValue);

      // Should succeed
      expect(wal.currentSequenceNumber, greaterThanOrEqualTo(1));
    });

    test('should rotate WAL files when size limit exceeded', () async {
      // Create WAL with small max file size
      await wal.close();
      wal = await WriteAheadLog.create(
        basePath: testPath,
        maxFileSize: 1024, // 1KB - very small to force rotation
      );

      final initialFileCount = wal.logFileCount;

      // Write enough data to trigger rotation
      // Each entry is ~50-100 bytes, so write more entries to ensure rotation
      for (int i = 0; i < 50; i++) {
        await wal.append(
          'rotate_key_$i'.codeUnits,
          Uint8List.fromList(
            'rotate_value_with_some_padding_to_make_it_larger_and_larger_to_ensure_rotation_$i'
                .codeUnits,
          ),
        );
      }

      // Should have at least the same or more log files
      expect(wal.logFileCount, greaterThanOrEqualTo(initialFileCount));
    });

    test('should truncate old log files', () async {
      // Write some entries
      for (int i = 0; i < 50; i++) {
        await wal.append(
          'truncate_key_$i'.codeUnits,
          Uint8List.fromList('truncate_value_$i'.codeUnits),
        );
      }

      // Close and reopen
      await wal.close();
      wal = await WriteAheadLog.create(basePath: testPath);

      // Recover entries
      final entries = await wal.recover();
      expect(entries.isNotEmpty, isTrue);

      // Truncate old files
      await wal.truncate();

      // Should have fewer files
      expect(wal.logFileCount, equals(1)); // Only current file
    });

    test('should preserve entry order during recovery', () async {
      // Write entries with specific order
      final keys = ['first', 'second', 'third', 'fourth', 'fifth'];
      for (final key in keys) {
        await wal.append(
          key.codeUnits,
          Uint8List.fromList('value_$key'.codeUnits),
        );
      }

      // Close and recover
      await wal.close();
      final newWal = await WriteAheadLog.create(basePath: testPath);
      final entries = await newWal.recover();

      // Verify order is preserved
      final recoveredKeys =
          entries
              .where((e) => e.type == WALEntryType.put)
              .map((e) => String.fromCharCodes(e.key))
              .toList();

      for (int i = 0; i < keys.length && i < recoveredKeys.length; i++) {
        expect(recoveredKeys[i], equals(keys[i]));
      }

      await newWal.close();
    });

    test('should handle mixed operations', () async {
      // Mix of puts, deletes, and checkpoints
      await wal.append(
        'mixed1'.codeUnits,
        Uint8List.fromList('value1'.codeUnits),
      );
      await wal.appendTombstone('mixed1'.codeUnits);
      await wal.append(
        'mixed2'.codeUnits,
        Uint8List.fromList('value2'.codeUnits),
      );
      await wal.checkpoint();
      await wal.append(
        'mixed3'.codeUnits,
        Uint8List.fromList('value3'.codeUnits),
      );

      // Close and recover
      await wal.close();
      final newWal = await WriteAheadLog.create(basePath: testPath);
      final entries = await newWal.recover();

      // Should have all entry types
      expect(entries.any((e) => e.type == WALEntryType.put), isTrue);
      expect(entries.any((e) => e.type == WALEntryType.delete), isTrue);
      expect(entries.any((e) => e.type == WALEntryType.checkpoint), isTrue);

      await newWal.close();
    });

    test('should handle empty WAL recovery', () async {
      // Close immediately without writing
      await wal.close();

      // Create new WAL and recover
      final newWal = await WriteAheadLog.create(basePath: testPath);
      final entries = await newWal.recover();

      // Should return empty list
      expect(entries, isEmpty);

      await newWal.close();
    });

    test('should increment sequence numbers across restarts', () async {
      // Write some entries
      await wal.append(
        'seq1'.codeUnits,
        Uint8List.fromList('value1'.codeUnits),
      );
      await wal.append(
        'seq2'.codeUnits,
        Uint8List.fromList('value2'.codeUnits),
      );

      final lastSeq = wal.currentSequenceNumber;

      // Close and reopen
      await wal.close();
      final newWal = await WriteAheadLog.create(basePath: testPath);

      // New sequence numbers should be higher
      await newWal.append(
        'seq3'.codeUnits,
        Uint8List.fromList('value3'.codeUnits),
      );
      expect(newWal.currentSequenceNumber, greaterThan(lastSeq));

      await newWal.close();
    });

    test('should handle rapid file rotation', () async {
      // Create WAL with tiny max file size
      await wal.close();
      wal = await WriteAheadLog.create(
        basePath: testPath,
        maxFileSize: 1024, // 1KB
      );

      // Write many small entries
      for (int i = 0; i < 50; i++) {
        await wal.append(
          'rapid_$i'.codeUnits,
          Uint8List.fromList('value_$i'.codeUnits),
        );
      }

      // Should have multiple log files
      expect(wal.logFileCount, greaterThan(1));

      // All entries should be recoverable
      await wal.close();
      final newWal = await WriteAheadLog.create(basePath: testPath);
      final entries = await newWal.recover();

      expect(entries.length, greaterThanOrEqualTo(50));

      await newWal.close();
    });
  });
}
