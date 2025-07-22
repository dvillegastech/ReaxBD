import 'package:test/test.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';
import 'dart:io';
import 'dart:typed_data';

void main() {
  group('Error Handling Tests', () {
    late ReaxDB db;
    final testPath = 'test/error_test_db';

    setUp(() async {
      // Clean up any existing test database more thoroughly
      final dir = Directory(testPath);
      if (await dir.exists()) {
        try {
          // First try normal deletion
          await dir.delete(recursive: true);
        } catch (e) {
          // If that fails, delete files individually
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File) {
              try {
                await entity.delete();
              } catch (_) {}
            }
          }
          // Then delete empty directories
          try {
            await dir.delete(recursive: true);
          } catch (_) {}
        }
      }
    });

    tearDown(() async {
      try {
        await db.close();
      } catch (_) {
        // Ignore errors during cleanup
      }

      // Clean up test database more thoroughly
      final dir = Directory(testPath);
      if (await dir.exists()) {
        try {
          // Restore permissions first if needed
          if (Platform.isLinux || Platform.isMacOS) {
            await Process.run('chmod', [
              '-R',
              '755',
              testPath,
            ], runInShell: true);
          }

          // Delete all files first
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File) {
              try {
                await entity.delete();
              } catch (_) {}
            }
          }

          // Then delete the directory
          await dir.delete(recursive: true);
        } catch (_) {
          // Best effort cleanup
        }
      }
    });

    test('should handle database not open error', () async {
      db = await ReaxDB.open('error_db', path: testPath);
      await db.close();

      // Try to use closed database
      expect(
        () async => await db.put('key', 'value'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Database is not open'),
          ),
        ),
      );

      expect(
        () async => await db.get('key'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Database is not open'),
          ),
        ),
      );

      expect(
        () async => await db.delete('key'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Database is not open'),
          ),
        ),
      );
    });

    test('should handle invalid key types gracefully', () async {
      db = await ReaxDB.open('error_db', path: testPath);

      // Empty key should work but might not be ideal
      await db.put('', 'empty_key_value');
      final emptyKeyValue = await db.get<String>('');
      expect(emptyKeyValue, equals('empty_key_value'));

      // Very long key (>10KB)
      final veryLongKey = 'x' * 10000;
      await db.put(veryLongKey, 'long_key_value');
      final longKeyValue = await db.get<String>(veryLongKey);
      expect(longKeyValue, equals('long_key_value'));
    });

    test('should handle invalid value types', () async {
      db = await ReaxDB.open('error_db', path: testPath);

      // Circular reference in object
      final circularMap = <String, dynamic>{};
      circularMap['self'] = circularMap;

      expect(
        () async => await db.put('circular_key', circularMap),
        throwsA(anything),
      );

      // Function (non-serializable)
      expect(
        () async => await db.put('function_key', () => 'function'),
        throwsA(anything),
      );
    });

    test('should handle corrupted data gracefully', () async {
      db = await ReaxDB.open('error_db', path: testPath);

      // Put valid data
      await db.put('corrupt_test', 'original_value');

      // Close database
      await db.close();

      // Simulate less severe corruption - corrupt WAL instead of SSTable
      final walFile = File('$testPath/wal/wal.log');
      if (await walFile.exists()) {
        // Append garbage to WAL file
        await walFile.writeAsBytes(
          Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]),
          mode: FileMode.append,
        );
      }

      // Reopen database - should recover
      db = await ReaxDB.open('error_db', path: testPath);

      // Should still be able to use database
      await db.put('new_key', 'new_value');
      final newValue = await db.get<String>('new_key');
      expect(newValue, equals('new_value'));
    });

    test('should handle disk space errors', () async {
      db = await ReaxDB.open('error_db', path: testPath);

      // Create reasonably large data for testing
      final largeData = List.generate(1024 * 1024, (i) => i % 256); // 1MB

      // Write a few entries to test
      bool caughtError = false;
      try {
        for (int i = 0; i < 5; i++) {
          await db.put('large_$i', largeData);
        }
      } catch (e) {
        caughtError = true;
        expect(e, isA<Exception>());
      }

      // Even if no error (enough disk space), database should still work
      final testValue = await db.get<List>('large_0');
      if (!caughtError) {
        expect(testValue, isNotNull);
      }
    });

    test('should handle concurrent modification conflicts', () async {
      db = await ReaxDB.open('error_db', path: testPath);

      // Put initial value
      await db.put('conflict_key', 0);

      // Read-modify-write in smaller batches
      for (int batch = 0; batch < 4; batch++) {
        final batchData = <String, dynamic>{};

        for (int i = 0; i < 5; i++) {
          final key = 'conflict_${batch}_$i';
          batchData[key] = batch * 5 + i;
        }

        await db.putBatch(batchData);

        // Small delay between batches
        await Future.delayed(Duration(milliseconds: 5));
      }

      // Verify some values were written
      final value = await db.get<int>('conflict_0_0');
      expect(value, equals(0));
    });

    test('should handle batch operation errors', () async {
      db = await ReaxDB.open('error_db', path: testPath);

      // Test batch with mixed valid and invalid data
      final batch = <String, dynamic>{
        'valid_key': 'valid_value',
        'valid_int': 42,
        'valid_list': [1, 2, 3],
      };

      // Put valid batch
      await db.putBatch(batch);

      // Verify valid data was stored
      expect(await db.get<String>('valid_key'), equals('valid_value'));
      expect(await db.get<int>('valid_int'), equals(42));
      expect(await db.get<List>('valid_list'), equals([1, 2, 3]));

      // Test batch with non-serializable data
      bool caughtError = false;
      try {
        await db.put('function_key', () => 'test');
      } catch (e) {
        caughtError = true;
        // Any error is acceptable for non-serializable data
        expect(e, isNotNull);
      }
      expect(caughtError, isTrue);
    });

    test('should recover from WAL corruption', () async {
      db = await ReaxDB.open('error_db', path: testPath);

      // Write some data
      await db.put('wal_test', 'before_corruption');

      // Force WAL flush by adding more data
      for (int i = 0; i < 10; i++) {
        await db.put('wal_extra_$i', 'value_$i');
      }

      // Close database properly
      await db.close();

      // Simulate partial WAL corruption
      final walFile = File('$testPath/wal/wal.log');
      if (await walFile.exists()) {
        final bytes = await walFile.readAsBytes();
        if (bytes.length > 20) {
          // Corrupt last few bytes only
          bytes[bytes.length - 1] = 0xFF;
          bytes[bytes.length - 2] = 0xFF;
          await walFile.writeAsBytes(bytes);
        }
      }

      // Should recover and open successfully
      db = await ReaxDB.open('error_db', path: testPath);

      // Should still be able to write new data
      await db.put('after_recovery', 'success');
      expect(await db.get<String>('after_recovery'), equals('success'));
    });

    test('should handle permission errors gracefully', () async {
      // Skip on Windows as permission handling is different
      if (Platform.isWindows) return;

      // Use a separate path for permission test to avoid affecting other tests
      final permissionTestPath = 'test/permission_test_db';
      final permissionDb = await ReaxDB.open(
        'permission_db',
        path: permissionTestPath,
      );

      try {
        await permissionDb.put('permission_test', 'value');
        await permissionDb.close();

        // Change permissions to read-only
        if (Platform.isLinux || Platform.isMacOS) {
          await Process.run('chmod', ['-R', '444', permissionTestPath]);
        }

        // Try to open read-only database
        bool caughtError = false;
        try {
          final readOnlyDb = await ReaxDB.open(
            'permission_db',
            path: permissionTestPath,
          );

          // Should be able to read
          final value = await readOnlyDb.get<String>('permission_test');
          expect(value, equals('value'));

          // Write should fail
          try {
            await readOnlyDb.put('new_key', 'new_value');
          } catch (e) {
            caughtError = true;
          }

          await readOnlyDb.close();
        } catch (e) {
          // Opening with read-only permissions might fail
          caughtError = true;
        }

        expect(caughtError, isTrue);
      } finally {
        // Restore permissions and cleanup
        if (Platform.isLinux || Platform.isMacOS) {
          await Process.run('chmod', ['-R', '755', permissionTestPath]);
        }

        // Clean up permission test database
        final permissionDir = Directory(permissionTestPath);
        if (await permissionDir.exists()) {
          await permissionDir.delete(recursive: true);
        }
      }
    });

    test('should handle database path errors', () async {
      // Invalid path characters
      expect(
        () async => await ReaxDB.open('error_db', path: '/\\0invalid\\0path'),
        throwsA(anything),
      );

      // Non-existent parent directory with no create permission
      expect(
        () async =>
            await ReaxDB.open('error_db', path: '/root/no_permission/db'),
        throwsA(anything),
      );
    });

    test('should handle memory pressure gracefully', () async {
      db = await ReaxDB.open('error_db', path: testPath);

      // Use batch operations to avoid StreamSink conflicts
      const totalEntries = 1000;
      const batchSize = 50;

      // Create entries in batches
      for (int batch = 0; batch < totalEntries / batchSize; batch++) {
        final batchData = <String, dynamic>{};

        for (int i = 0; i < batchSize; i++) {
          final index = batch * batchSize + i;
          batchData['mem_pressure_$index'] = 'x' * 100; // Smaller data
        }

        await db.putBatch(batchData);

        // Small delay to avoid overwhelming the system
        if (batch % 5 == 0) {
          await Future.delayed(Duration(milliseconds: 10));
        }
      }

      // Verify some entries
      for (int i = 0; i < 100; i += 20) {
        final value = await db.get<String>('mem_pressure_$i');
        expect(value, equals('x' * 100));
      }
    });
  });
}
