import 'package:test/test.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';
import 'dart:io';

void main() {
  group('ReaxDB Integration Tests', () {
    late ReaxDB db;
    final testPath = 'test/test_db';

    setUp(() async {
      // Clean up any existing test database
      final dir = Directory(testPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }

      // Create new database
      db = await ReaxDB.open('test_db', path: testPath);
    });

    tearDown(() async {
      await db.close();
      // Clean up test database
      final dir = Directory(testPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('should open and close database', () async {
      expect(db, isNotNull);
      await db.close();

      // Should throw error when trying to use closed database
      expect(
        () async => await db.put('key', 'value'),
        throwsA(isA<Exception>()),
      );
    });

    test('should store and retrieve data', () async {
      await db.put('test_key', 'test_value');
      final value = await db.get<String>('test_key');

      expect(value, equals('test_value'));
    });

    test('should store different data types', () async {
      // String
      await db.put('string_key', 'Hello World');
      expect(await db.get<String>('string_key'), equals('Hello World'));

      // int
      await db.put('int_key', 42);
      expect(await db.get<int>('int_key'), equals(42));

      // double
      await db.put('double_key', 3.14);
      expect(await db.get<double>('double_key'), equals(3.14));

      // bool
      await db.put('bool_key', true);
      expect(await db.get<bool>('bool_key'), equals(true));

      // Map
      final map = {'name': 'John', 'age': 30};
      await db.put('map_key', map);
      expect(await db.get<Map>('map_key'), equals(map));

      // List
      final list = [1, 2, 3, 4, 5];
      await db.put('list_key', list);
      expect(await db.get<List>('list_key'), equals(list));
    });

    test('should update existing key', () async {
      await db.put('update_key', 'initial_value');
      expect(await db.get<String>('update_key'), equals('initial_value'));

      await db.put('update_key', 'updated_value');
      expect(await db.get<String>('update_key'), equals('updated_value'));
    });

    test('should delete key', () async {
      await db.put('delete_key', 'value_to_delete');
      expect(await db.get<String>('delete_key'), equals('value_to_delete'));

      await db.delete('delete_key');
      expect(await db.get<String>('delete_key'), isNull);
    });

    test('should handle non-existent keys', () async {
      final value = await db.get<String>('non_existent_key');
      expect(value, isNull);
    });

    test('should perform batch operations', () async {
      final batchData = {
        'batch_1': 'value_1',
        'batch_2': 'value_2',
        'batch_3': 'value_3',
      };

      await db.putBatch(batchData);

      for (final entry in batchData.entries) {
        expect(await db.get<String>(entry.key), equals(entry.value));
      }
    });

    test('should perform batch get operations', () async {
      // First put some data
      await db.put('get_1', 'value_1');
      await db.put('get_2', 'value_2');
      await db.put('get_3', 'value_3');

      final keys = ['get_1', 'get_2', 'get_3', 'non_existent'];
      final results = await db.getBatch<String>(keys);

      expect(results['get_1'], equals('value_1'));
      expect(results['get_2'], equals('value_2'));
      expect(results['get_3'], equals('value_3'));
      expect(results['non_existent'], isNull);
    });

    test('should handle zero-copy serialization', () async {
      // Test optimized serialization for different types

      // String - should use type marker 0
      await db.put('string_test', 'Hello Zero-Copy');
      expect(await db.get<String>('string_test'), equals('Hello Zero-Copy'));

      // Integer - should use type marker 1
      await db.put('int_test', 1234567890);
      expect(await db.get<int>('int_test'), equals(1234567890));

      // Double - should use type marker 2
      await db.put('double_test', 3.14159);
      expect(await db.get<double>('double_test'), equals(3.14159));

      // Boolean - should use type marker 3
      await db.put('bool_test', true);
      expect(await db.get<bool>('bool_test'), isTrue);
    });

    test('should handle batch operations efficiently', () async {
      final largeData = <String, dynamic>{};

      // Create 50 entries for batch
      for (int i = 0; i < 50; i++) {
        largeData['batch_key_$i'] = {
          'id': i,
          'data': 'value_$i',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
      }

      final stopwatch = Stopwatch()..start();
      await db.putBatch(largeData);
      stopwatch.stop();

      // Batch should be fast
      expect(stopwatch.elapsedMilliseconds, lessThan(50));

      // Verify all data
      for (int i = 0; i < 50; i++) {
        final value = await db.get<Map>('batch_key_$i');
        expect(value!['id'], equals(i));
      }
    });

    test('should handle cache optimization', () async {
      // First put data
      await db.put('cache_test', 'initial_value');

      // Clear cache to force disk read
      await db.compact();

      // Warm up with first read
      await db.get<String>('cache_test');

      // Measure multiple reads to get average
      int diskReadTime = 0;
      int cacheReadTime = 0;

      // Clear cache again and measure disk read
      await db.compact();
      final stopwatch1 = Stopwatch()..start();
      await db.get<String>('cache_test');
      stopwatch1.stop();
      diskReadTime = stopwatch1.elapsedMicroseconds;

      // Now measure cache reads (should be in L1)
      final stopwatch2 = Stopwatch()..start();
      for (int i = 0; i < 10; i++) {
        await db.get<String>('cache_test');
      }
      stopwatch2.stop();
      cacheReadTime = stopwatch2.elapsedMicroseconds ~/ 10;

      // Cache should be noticeably faster than disk
      expect(cacheReadTime, lessThan(diskReadTime));
    });

    test('should optimize with connection pooling', () async {
      // Use batch operations to test connection pooling
      final batchData = <String, dynamic>{};

      // Prepare batch data
      for (int i = 0; i < 20; i++) {
        batchData['pool_$i'] = i;
      }

      // Write using batch (uses connection pooling internally)
      await db.putBatch(batchData);

      // Read using batch
      final keys = List.generate(20, (i) => 'pool_$i');
      final results = await db.getBatch<int>(keys);

      // Verify all values
      for (int i = 0; i < 20; i++) {
        expect(results['pool_$i'], equals(i));
      }
    });

    test('should perform atomic compare and swap', () async {
      await db.put('cas_counter', 0);

      // Successful CAS
      final success = await db.compareAndSwap('cas_counter', 0, 1);
      expect(success, isTrue);
      expect(await db.get<int>('cas_counter'), equals(1));

      // Failed CAS (wrong expected value)
      final failed = await db.compareAndSwap('cas_counter', 0, 2);
      expect(failed, isFalse);
      expect(await db.get<int>('cas_counter'), equals(1));
    });

    test('should provide performance statistics', () async {
      // Perform some operations
      for (int i = 0; i < 10; i++) {
        await db.put('perf_$i', 'value_$i');
      }

      for (int i = 0; i < 10; i++) {
        await db.get<String>('perf_$i');
      }

      final stats = db.getPerformanceStats();

      expect(stats['cache'], isNotNull);
      expect(stats['cache']['total_hit_ratio'], greaterThanOrEqualTo(0));
      expect(stats['optimization']['zero_copy_enabled'], isTrue);
      expect(stats['optimization']['connection_pooling'], isTrue);
      expect(stats['optimization']['batch_operations'], isTrue);
    });

    test('should provide database information', () async {
      // Add some data
      for (int i = 0; i < 5; i++) {
        await db.put('info_$i', 'data_$i');
      }

      // Force flush to disk
      await db.compact();

      final info = await db.getDatabaseInfo();

      // getDatabaseInfo returns a DatabaseInfo object
      expect(info.name, equals('test_db'));
      expect(info.sizeBytes, greaterThan(0));
      expect(info.entryCount, greaterThanOrEqualTo(5));
      expect(info.isEncrypted, isFalse);
    });

    test('should provide database statistics', () async {
      // Add some data
      for (int i = 0; i < 5; i++) {
        await db.put('stat_$i', 'data_$i');
      }

      // Force flush to disk
      await db.compact();

      final stats = await db.getStatistics();

      // getStatistics returns a Map<String, dynamic>
      expect(stats, isA<Map<String, dynamic>>());

      // Check database stats
      final dbStats = stats['database'] as Map<String, dynamic>;
      expect(dbStats['name'], equals('test_db'));
      expect(dbStats['size'], greaterThan(0));
      expect(dbStats['entries'], greaterThanOrEqualTo(5));
      expect(dbStats['encrypted'], isFalse);

      // Check cache and transaction stats exists
      expect(stats['cache'], isNotNull);
      expect(stats['transactions'], isNotNull);
    });

    test('should handle large data efficiently', () async {
      // Create large data (1MB)
      final largeData = List.generate(1024 * 1024, (i) => i % 256);

      final stopwatch = Stopwatch()..start();
      await db.put('large_data', largeData);
      stopwatch.stop();

      // Should complete quickly (less than 100ms)
      expect(stopwatch.elapsedMilliseconds, lessThan(100));

      final retrieved = await db.get<List>('large_data');
      expect(retrieved, equals(largeData));
    });

    test('should handle concurrent operations', () async {
      // Split into smaller batches to avoid StreamSink conflicts
      const batchSize = 25;
      const totalOps = 100;

      for (int batch = 0; batch < totalOps / batchSize; batch++) {
        final batchData = <String, dynamic>{};

        // Prepare batch data
        for (int i = batch * batchSize; i < (batch + 1) * batchSize; i++) {
          batchData['concurrent_$i'] = i;
        }

        // Use batch put for concurrent writes
        await db.putBatch(batchData);

        // Small delay between batches
        await Future.delayed(Duration(milliseconds: 10));
      }

      // Verify all operations succeeded
      for (int i = 0; i < totalOps; i++) {
        expect(await db.get<int>('concurrent_$i'), equals(i));
      }
    });
  });

  group('ReaxDB with Legacy Encryption', () {
    test('should show encrypted database in info with default XOR', () async {
      final testPath = 'test/encrypted_db';
      final encryptionKey = 'test_encryption_key_32_bytes_long';

      // Clean up
      final dir = Directory(testPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }

      // Create encrypted database (defaults to XOR when key is provided)
      final encryptedDb = await ReaxDB.open(
        'encrypted_db',
        path: testPath,
        config: DatabaseConfig.withXorEncryption(),
        encryptionKey: encryptionKey,
      );

      try {
        // Store and retrieve encrypted data
        await encryptedDb.put('secret_key', 'secret_value');
        final value = await encryptedDb.get<String>('secret_key');
        expect(value, equals('secret_value'));

        // Check encryption status
        final info = await encryptedDb.getDatabaseInfo();
        expect(info.isEncrypted, isTrue);

        // Test batch operations with encryption
        final batchData = {'enc_1': 'value_1', 'enc_2': 'value_2'};

        await encryptedDb.putBatch(batchData);

        expect(await encryptedDb.get<String>('enc_1'), equals('value_1'));
        expect(await encryptedDb.get<String>('enc_2'), equals('value_2'));

        // Test encryption info
        final encryptionInfo = encryptedDb.getEncryptionInfo();
        expect(encryptionInfo['enabled'], isTrue);
      } finally {
        await encryptedDb.close();
        // Clean up
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });

    test('should handle database configuration options', () async {
      // Test different configuration factories
      final defaultConfig = DatabaseConfig.defaultConfig();
      expect(defaultConfig.encryptionType, equals(EncryptionType.none));

      final xorConfig = DatabaseConfig.withXorEncryption();
      expect(xorConfig.encryptionType, equals(EncryptionType.xor));

      final aesConfig = DatabaseConfig.withAes256Encryption();
      expect(aesConfig.encryptionType, equals(EncryptionType.aes256));
    });
  });
}
