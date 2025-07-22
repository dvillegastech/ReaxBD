import 'package:test/test.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

void main() {
  group('Performance Benchmark Tests', () {
    late ReaxDB db;
    final testPath = 'test/benchmark_db';
    final random = Random();

    setUp(() async {
      // Clean up any existing test database
      final dir = Directory(testPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }

      // Create database
      db = await ReaxDB.open('benchmark_db', path: testPath);
    });

    tearDown(() async {
      await db.close();

      // Clean up test database
      final dir = Directory(testPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('should measure write performance', () async {
      const iterations = 1000;
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < iterations; i++) {
        await db.put('write_key_$i', 'value_$i');
      }

      stopwatch.stop();
      final writeTime = stopwatch.elapsedMilliseconds;
      final writeThroughput = iterations / (writeTime / 1000.0);

      print('Write Performance:');
      print('  Total time: ${writeTime}ms');
      print('  Throughput: ${writeThroughput.toStringAsFixed(2)} ops/sec');
      print(
        '  Avg latency: ${(writeTime / iterations).toStringAsFixed(3)}ms',
      );

      // Performance assertions
      expect(writeTime, lessThan(5000)); // Should complete in < 5 seconds
      expect(writeThroughput, greaterThan(200)); // At least 200 ops/sec
    });

    test('should measure read performance', () async {
      // Pre-populate data
      for (int i = 0; i < 1000; i++) {
        await db.put('read_key_$i', 'value_$i');
      }

      const iterations = 1000;
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < iterations; i++) {
        await db.get<String>('read_key_$i');
      }

      stopwatch.stop();
      final readTime = stopwatch.elapsedMilliseconds;
      final readThroughput = iterations / (readTime / 1000.0);

      print('Read Performance:');
      print('  Total time: ${readTime}ms');
      print('  Throughput: ${readThroughput.toStringAsFixed(2)} ops/sec');
      print(
        '  Avg latency: ${(readTime / iterations).toStringAsFixed(3)}ms',
      );

      // Performance assertions
      expect(readTime, lessThan(2000)); // Reads should be faster
      expect(readThroughput, greaterThan(500)); // At least 500 ops/sec
    });

    test('should measure mixed workload performance', () async {
      const iterations = 1000;
      int reads = 0;
      int writes = 0;
      int deletes = 0;

      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < iterations; i++) {
        final operation = random.nextInt(3);

        switch (operation) {
          case 0: // Write
            await db.put('mixed_key_${i % 500}', 'value_$i');
            writes++;
            break;
          case 1: // Read
            await db.get<String>('mixed_key_${i % 500}');
            reads++;
            break;
          case 2: // Delete
            await db.delete('mixed_key_${i % 500}');
            deletes++;
            break;
        }
      }

      stopwatch.stop();
      final totalTime = stopwatch.elapsedMilliseconds;
      final throughput = iterations / (totalTime / 1000.0);

      print('Mixed Workload Performance:');
      print('  Total time: ${totalTime}ms');
      print(
        '  Operations: $reads reads, $writes writes, $deletes deletes',
      );
      print('  Throughput: ${throughput.toStringAsFixed(2)} ops/sec');
      print(
        '  Avg latency: ${(totalTime / iterations).toStringAsFixed(3)}ms',
      );

      expect(totalTime, lessThan(5000));
      expect(throughput, greaterThan(200));
    });

    test('should measure batch write performance', () async {
      const batchSize = 50;
      const batches = 10;

      final stopwatch = Stopwatch()..start();

      for (int batch = 0; batch < batches; batch++) {
        final batchData = <String, dynamic>{};
        for (int i = 0; i < batchSize; i++) {
          batchData['batch_${batch}_key_$i'] = 'batch_${batch}_value_$i';
        }
        await db.putBatch(batchData);
        // Small delay between batches to avoid conflicts
        await Future.delayed(Duration(milliseconds: 10));
      }

      stopwatch.stop();
      final totalTime = stopwatch.elapsedMilliseconds;
      final totalOps = batchSize * batches;
      final throughput = totalOps / (totalTime / 1000.0);

      print('Batch Write Performance:');
      print('  Total time: ${totalTime}ms');
      print('  Total operations: $totalOps');
      print('  Throughput: ${throughput.toStringAsFixed(2)} ops/sec');
      print(
        '  Avg batch time: ${(totalTime / batches).toStringAsFixed(2)}ms',
      );

      expect(throughput, greaterThan(500)); // Adjusted for delays
    });

    test('should measure large value performance', () async {
      final largeValue = Uint8List(100 * 1024); // 100KB
      for (int i = 0; i < largeValue.length; i++) {
        largeValue[i] = random.nextInt(256);
      }

      const iterations = 100;

      // Write performance
      final writeStopwatch = Stopwatch()..start();
      for (int i = 0; i < iterations; i++) {
        await db.put('large_key_$i', largeValue);
      }
      writeStopwatch.stop();

      // Read performance
      final readStopwatch = Stopwatch()..start();
      for (int i = 0; i < iterations; i++) {
        await db.get<List>('large_key_$i');
      }
      readStopwatch.stop();

      final writeTime = writeStopwatch.elapsedMilliseconds;
      final readTime = readStopwatch.elapsedMilliseconds;
      final writeMBps = (iterations * 100 / 1024.0) / (writeTime / 1000.0);
      final readMBps = (iterations * 100 / 1024.0) / (readTime / 1000.0);

      print('Large Value Performance (100KB values):');
      print(
        '  Write time: ${writeTime}ms (${writeMBps.toStringAsFixed(2)} MB/s)',
      );
      print(
        '  Read time: ${readTime}ms (${readMBps.toStringAsFixed(2)} MB/s)',
      );

      expect(writeMBps, greaterThan(10)); // At least 10 MB/s write
      expect(readMBps, greaterThan(20)); // At least 20 MB/s read
    });

    test('should measure cache hit performance', () async {
      // Populate cache
      const key = 'cache_test_key';
      const value = 'cache_test_value';
      await db.put(key, value);

      // Warm up cache
      await db.get<String>(key);

      const iterations = 10000;
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < iterations; i++) {
        await db.get<String>(key);
      }

      stopwatch.stop();
      final totalTime = stopwatch.elapsedMilliseconds;
      final avgLatency = totalTime / iterations;
      final throughput = iterations / (totalTime / 1000.0);

      print('Cache Hit Performance:');
      print('  Total time: ${totalTime}ms');
      print('  Avg latency: ${avgLatency.toStringAsFixed(3)}ms');
      print('  Throughput: ${throughput.toStringAsFixed(2)} ops/sec');

      expect(avgLatency, lessThan(0.5)); // Sub-millisecond for cache hits
      expect(throughput, greaterThan(2000)); // Very high for cache hits
    });

    test('should measure compaction impact', () async {
      // Write data to trigger compaction
      const preCompactionOps = 500;
      for (int i = 0; i < preCompactionOps; i++) {
        await db.put('compact_key_$i', 'compact_value_$i');
      }

      // Measure performance before compaction
      final beforeStopwatch = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        await db.get<String>('compact_key_${i * 5}');
      }
      beforeStopwatch.stop();
      final beforeTime = beforeStopwatch.elapsedMilliseconds;

      // Compact
      final compactStopwatch = Stopwatch()..start();
      await db.compact();
      compactStopwatch.stop();
      final compactTime = compactStopwatch.elapsedMilliseconds;

      // Measure performance after compaction
      final afterStopwatch = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        await db.get<String>('compact_key_${i * 5}');
      }
      afterStopwatch.stop();
      final afterTime = afterStopwatch.elapsedMilliseconds;

      print('Compaction Impact:');
      print('  Compaction time: ${compactTime}ms');
      print('  Read time before: ${beforeTime}ms');
      print('  Read time after: ${afterTime}ms');
      print(
        '  Improvement: ${((beforeTime - afterTime) / beforeTime * 100).toStringAsFixed(1)}%',
      );

      expect(compactTime, lessThan(5000)); // Compaction should be reasonable
    });

    test('should measure encryption overhead', () async {
      await db.close();

      // Create encrypted database
      db = await ReaxDB.open(
        'benchmark_db',
        path: testPath,
        encryptionKey: 'benchmark_encryption_key_32bytes!',
      );

      const iterations = 500;
      final encryptedStopwatch = Stopwatch()..start();

      for (int i = 0; i < iterations; i++) {
        await db.put('encrypted_key_$i', 'encrypted_value_$i');
      }

      for (int i = 0; i < iterations; i++) {
        await db.get<String>('encrypted_key_$i');
      }

      encryptedStopwatch.stop();
      final encryptedTime = encryptedStopwatch.elapsedMilliseconds;

      await db.close();

      // Compare with non-encrypted
      db = await ReaxDB.open('benchmark_db', path: testPath);

      final plainStopwatch = Stopwatch()..start();

      for (int i = 0; i < iterations; i++) {
        await db.put('plain_key_$i', 'plain_value_$i');
      }

      for (int i = 0; i < iterations; i++) {
        await db.get<String>('plain_key_$i');
      }

      plainStopwatch.stop();
      final plainTime = plainStopwatch.elapsedMilliseconds;

      final overhead = ((encryptedTime - plainTime) / plainTime * 100);

      print('Encryption Overhead:');
      print('  Plain time: ${plainTime}ms');
      print('  Encrypted time: ${encryptedTime}ms');
      print('  Overhead: ${overhead.toStringAsFixed(1)}%');

      expect(
        overhead,
        lessThanOrEqualTo(100),
      ); // Less than or equal to 100% overhead
    });

    test('should measure zero-copy serialization performance', () async {
      const iterations = 1000;

      // Test different data types
      final testData = [
        'String value for testing',
        42,
        3.14159,
        true,
        List.generate(100, (i) => i),
        {'key': 'value', 'number': 123},
      ];

      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < iterations; i++) {
        final data = testData[i % testData.length];
        await db.put('serialize_key_$i', data);
      }

      for (int i = 0; i < iterations; i++) {
        await db.get('serialize_key_$i');
      }

      stopwatch.stop();
      final totalTime = stopwatch.elapsedMilliseconds;
      final throughput = (iterations * 2) / (totalTime / 1000.0);

      print('Zero-Copy Serialization Performance:');
      print('  Total time: ${totalTime}ms');
      print('  Throughput: ${throughput.toStringAsFixed(2)} ops/sec');

      expect(throughput, greaterThan(1000)); // Fast serialization
    });

    test('should measure database statistics performance', () async {
      // Populate database
      for (int i = 0; i < 1000; i++) {
        await db.put('stats_key_$i', 'stats_value_$i');
      }

      // Measure statistics gathering
      final statsStopwatch = Stopwatch()..start();
      await db.getStatistics();
      statsStopwatch.stop();

      final infoStopwatch = Stopwatch()..start();
      await db.getDatabaseInfo();
      infoStopwatch.stop();

      final perfStopwatch = Stopwatch()..start();
      db.getPerformanceStats();
      perfStopwatch.stop();

      print('Statistics Performance:');
      print('  getStatistics: ${statsStopwatch.elapsedMilliseconds}ms');
      print('  getDatabaseInfo: ${infoStopwatch.elapsedMilliseconds}ms');
      print(
        '  getPerformanceStats: ${perfStopwatch.elapsedMilliseconds}ms',
      );

      // Should be fast operations
      expect(statsStopwatch.elapsedMilliseconds, lessThan(100));
      expect(infoStopwatch.elapsedMilliseconds, lessThan(100));
      expect(perfStopwatch.elapsedMilliseconds, lessThan(10));
    });
  });
}
