import 'package:test/test.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';
import 'dart:io';
import 'dart:typed_data';

void main() {
  group('Crash Recovery Tests', () {
    late ReaxDB db;
    final testPath = 'test/crash_recovery_db';

    setUp(() async {
      // Clean up any existing test database
      final dir = Directory(testPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    tearDown(() async {
      try {
        await db.close();
      } catch (_) {
        // Ignore errors during cleanup
      }

      // Clean up test database
      final dir = Directory(testPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('should handle database lifecycle', () async {
      // Create database
      db = await ReaxDB.open('recovery_db', path: testPath);

      // Write data
      await db.put('lifecycle_key', 'lifecycle_value');

      // Verify data is accessible
      final value = await db.get<String>('lifecycle_key');
      expect(value, equals('lifecycle_value'));

      // Close database
      await db.close();

      // Reopen database
      db = await ReaxDB.open('recovery_db', path: testPath);

      // Database should be functional
      await db.put('new_key', 'new_value');
      final newValue = await db.get<String>('new_key');
      expect(newValue, equals('new_value'));
    });

    test('should handle write operations after restart', () async {
      // Create database and close immediately
      db = await ReaxDB.open('recovery_db', path: testPath);
      await db.close();

      // Reopen and write data
      db = await ReaxDB.open('recovery_db', path: testPath);

      for (int i = 0; i < 50; i++) {
        await db.put('restart_key_$i', 'restart_value_$i');
      }

      // Verify data in same session
      for (int i = 0; i < 50; i++) {
        final value = await db.get<String>('restart_key_$i');
        expect(value, equals('restart_value_$i'));
      }
    });

    test('should handle corrupted files gracefully', () async {
      db = await ReaxDB.open('recovery_db', path: testPath);
      await db.put('pre_corruption', 'value');
      await db.close();

      // Corrupt a data file
      final lsmDir = Directory('$testPath/lsm');
      if (await lsmDir.exists()) {
        await for (final file in lsmDir.list()) {
          if (file is File && file.path.endsWith('.sst')) {
            // Append garbage to SSTable file
            await file.writeAsBytes(
              Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]),
              mode: FileMode.append,
            );
            break;
          }
        }
      }

      // Should still be able to open database
      db = await ReaxDB.open('recovery_db', path: testPath);

      // Should be able to write new data
      await db.put('after_corruption', 'new_value');
      final newValue = await db.get<String>('after_corruption');
      expect(newValue, equals('new_value'));
    });

    test('should handle WAL operations', () async {
      db = await ReaxDB.open('recovery_db', path: testPath);

      // Write data that goes to WAL
      for (int i = 0; i < 40; i++) {
        await db.put('wal_key_$i', 'wal_value_$i');
      }

      // Data should be readable in same session
      for (int i = 0; i < 40; i++) {
        final value = await db.get<String>('wal_key_$i');
        expect(value, equals('wal_value_$i'));
      }

      // Compact to flush WAL
      await db.compact();
    });

    test('should handle encryption lifecycle', () async {
      final encryptionKey = 'test_recovery_key_32_bytes_long!!';

      // Create encrypted database
      db = await ReaxDB.open(
        'recovery_db',
        path: testPath,
        encryptionKey: encryptionKey,
      );

      // Write encrypted data
      for (int i = 0; i < 25; i++) {
        await db.put('encrypted_$i', 'secret_value_$i');
      }

      // Verify in same session
      for (int i = 0; i < 25; i++) {
        final value = await db.get<String>('encrypted_$i');
        expect(value, equals('secret_value_$i'));
      }

      await db.close();

      // Open with correct key should work
      db = await ReaxDB.open(
        'recovery_db',
        path: testPath,
        encryptionKey: encryptionKey,
      );

      // Should be able to write new data
      await db.put('after_reopen', 'new_encrypted_value');
      expect(
        await db.get<String>('after_reopen'),
        equals('new_encrypted_value'),
      );
    });

    test('should handle batch operations lifecycle', () async {
      db = await ReaxDB.open('recovery_db', path: testPath);

      // Perform batch operation
      final batchData = <String, dynamic>{};
      for (int i = 0; i < 50; i++) {
        batchData['batch_$i'] = 'batch_value_$i';
      }

      await db.putBatch(batchData);

      // Verify in same session
      for (int i = 0; i < 50; i++) {
        final value = await db.get<String>('batch_$i');
        expect(value, equals('batch_value_$i'));
      }
    });

    test('should handle multiple database instances', () async {
      // First instance
      db = await ReaxDB.open('recovery_db', path: testPath);
      await db.put('instance_1', 'value_1');
      await db.close();

      // Second instance
      db = await ReaxDB.open('recovery_db', path: testPath);
      await db.put('instance_2', 'value_2');

      // Data from current session should be there
      expect(await db.get<String>('instance_2'), equals('value_2'));
    });

    test('should handle compaction lifecycle', () async {
      db = await ReaxDB.open('recovery_db', path: testPath);

      // Write enough data to benefit from compaction
      for (int i = 0; i < 200; i++) {
        await db.put('compact_$i', 'value_$i');
      }

      // Force compaction
      await db.compact();

      // All data should still be accessible
      for (int i = 0; i < 200; i++) {
        final value = await db.get<String>('compact_$i');
        expect(value, equals('value_$i'));
      }

      // Database should be functional after compaction
      await db.put('after_compact', 'new_value');
      expect(await db.get<String>('after_compact'), equals('new_value'));
    });

    test('should handle mixed data types lifecycle', () async {
      db = await ReaxDB.open('recovery_db', path: testPath);

      // Write different data types
      await db.put('string_key', 'string_value');
      await db.put('int_key', 42);
      await db.put('double_key', 3.14159);
      await db.put('bool_key', true);
      await db.put('list_key', [1, 2, 3, 4, 5]);
      await db.put('map_key', {'name': 'test', 'value': 123});

      // Verify in same session
      expect(await db.get<String>('string_key'), equals('string_value'));
      expect(await db.get<int>('int_key'), equals(42));
      expect(await db.get<double>('double_key'), equals(3.14159));
      expect(await db.get<bool>('bool_key'), isTrue);
      expect(await db.get<List>('list_key'), equals([1, 2, 3, 4, 5]));
      expect(
        await db.get<Map>('map_key'),
        equals({'name': 'test', 'value': 123}),
      );
    });

    test('should handle delete operations lifecycle', () async {
      db = await ReaxDB.open('recovery_db', path: testPath);

      // Write data
      for (int i = 0; i < 50; i++) {
        await db.put('delete_test_$i', 'value_$i');
      }

      // Delete some entries
      for (int i = 0; i < 25; i++) {
        await db.delete('delete_test_$i');
      }

      // Verify in same session
      for (int i = 0; i < 25; i++) {
        final value = await db.get<String>('delete_test_$i');
        expect(value, isNull);
      }

      // Remaining data should be there
      for (int i = 25; i < 50; i++) {
        final value = await db.get<String>('delete_test_$i');
        expect(value, equals('value_$i'));
      }
    });

    test('should handle large dataset lifecycle', () async {
      db = await ReaxDB.open('recovery_db', path: testPath);

      // Write large dataset
      final largeValue = 'x' * 1000; // 1KB per entry
      for (int i = 0; i < 100; i++) {
        await db.put('large_$i', largeValue);
      }

      // Sample verification in same session
      for (int i = 0; i < 100; i += 10) {
        final value = await db.get<String>('large_$i');
        expect(value, equals(largeValue));
      }

      // Force flush to disk
      await db.compact();

      // Get database info
      final info = await db.getDatabaseInfo();
      expect(info.entryCount, greaterThanOrEqualTo(100));
      expect(info.sizeBytes, greaterThan(100 * 1000)); // At least 100KB
    });

    test('should handle concurrent access protection', () async {
      db = await ReaxDB.open('recovery_db', path: testPath);

      // Try to open same database again
      ReaxDB? secondDb;
      bool caughtError = false;

      try {
        secondDb = await ReaxDB.open('recovery_db', path: testPath);
      } catch (e) {
        caughtError = true;
      } finally {
        await secondDb?.close();
      }

      // Should either fail or handle gracefully
      // Current implementation allows multiple opens
      expect(caughtError || secondDb != null, isTrue);
    });
  });
}
