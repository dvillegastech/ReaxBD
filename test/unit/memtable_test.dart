import 'package:test/test.dart';
import 'package:reaxdb_dart/src/core/storage/memtable.dart';
import 'dart:typed_data';

void main() {
  group('MemTable Tests', () {
    late MemTable memtable;

    setUp(() {
      memtable = MemTable(maxSize: 1024); // 1KB max size
    });

    test('should store and retrieve data', () {
      final key = [116, 101, 115, 116]; // "test" in bytes
      final value = Uint8List.fromList([1, 2, 3, 4, 5]);

      memtable.put(key, value);
      final retrieved = memtable.get(key);

      expect(retrieved, equals(value));
    });

    test('should update existing key', () {
      final key = [107, 101, 121]; // "key" in bytes
      final value1 = Uint8List.fromList([1, 2, 3]);
      final value2 = Uint8List.fromList([4, 5, 6]);

      memtable.put(key, value1);
      expect(memtable.get(key), equals(value1));

      memtable.put(key, value2);
      expect(memtable.get(key), equals(value2));
    });

    test('should delete key with tombstone', () {
      final key = [100, 101, 108]; // "del" in bytes
      final value = Uint8List.fromList([42]);

      memtable.put(key, value);
      expect(memtable.get(key), equals(value));

      memtable.delete(key);
      expect(memtable.get(key), isNull);
    });

    test('should track size correctly', () {
      expect(memtable.size, equals(0));

      final key1 = [49]; // "1"
      final key2 = [50]; // "2"
      memtable.put(key1, Uint8List.fromList([1]));
      memtable.put(key2, Uint8List.fromList([2]));

      expect(memtable.size, equals(2));

      memtable.delete(key1);
      expect(memtable.size, equals(2)); // Still 2 because tombstone counts
    });

    test('should report when full', () {
      expect(memtable.isFull, isFalse);

      // Fill memtable with large data to exceed 1KB
      for (int i = 0; i < 20; i++) {
        final key = [105, i]; // Different keys
        final largeValue = Uint8List(60); // 60 bytes each = 1200 bytes total
        memtable.put(key, largeValue);

        if (memtable.isFull) break;
      }

      expect(memtable.isFull, isTrue);
    });

    test('should clear all data', () {
      // Add some data
      for (int i = 0; i < 5; i++) {
        memtable.put([105, i], Uint8List.fromList([i]));
      }

      expect(memtable.isEmpty, isFalse);
      expect(memtable.size, greaterThan(0));

      memtable.clear();

      expect(memtable.isEmpty, isTrue);
      expect(memtable.size, equals(0));
      expect(memtable.memoryUsage, equals(0));
    });

    test('should get entries excluding tombstones', () {
      final key1 = [49]; // "1"
      final key2 = [50]; // "2"
      final key3 = [51]; // "3"

      memtable.put(key1, Uint8List.fromList([1]));
      memtable.put(key2, Uint8List.fromList([2]));
      memtable.put(key3, Uint8List.fromList([3]));
      memtable.delete(key2); // Add tombstone

      final entries = memtable.entries;
      expect(entries.length, equals(2)); // Excludes tombstone
      // Convert List<int> keys for comparison
      final keyStrings =
          entries.keys.map((k) => String.fromCharCodes(k)).toSet();
      expect(keyStrings.contains(String.fromCharCodes(key1)), isTrue);
      expect(keyStrings.contains(String.fromCharCodes(key2)), isFalse);
      expect(keyStrings.contains(String.fromCharCodes(key3)), isTrue);
    });

    test('should get all entries including tombstones', () {
      final key1 = [49]; // "1"
      final key2 = [50]; // "2"

      memtable.put(key1, Uint8List.fromList([1]));
      memtable.put(key2, Uint8List.fromList([2]));
      memtable.delete(key2);

      final allEntries = memtable.allEntries;
      expect(allEntries.length, equals(2));
      // Check if key2 exists and has empty value (tombstone)
      final hasKey2 = allEntries.keys.any(
        (k) => String.fromCharCodes(k) == String.fromCharCodes(key2),
      );
      expect(hasKey2, isTrue);

      final key2Value =
          allEntries.entries
              .firstWhere(
                (e) =>
                    String.fromCharCodes(e.key) == String.fromCharCodes(key2),
              )
              .value;
      expect(key2Value, isNull); // Tombstone
    });

    test('should get range of entries', () {
      // Add keys that will be sorted: "a", "b", "c", "d", "e"
      memtable.put([97], Uint8List.fromList([1])); // "a"
      memtable.put([98], Uint8List.fromList([2])); // "b"
      memtable.put([99], Uint8List.fromList([3])); // "c"
      memtable.put([100], Uint8List.fromList([4])); // "d"
      memtable.put([101], Uint8List.fromList([5])); // "e"

      // Get range from "b" to "d"
      final range = memtable.getRange([98], [101]);

      expect(range.length, equals(3)); // b, c, d
      final rangeKeys = range.keys.map((k) => String.fromCharCodes(k)).toSet();
      expect(rangeKeys.contains('b'), isTrue);
      expect(rangeKeys.contains('c'), isTrue);
      expect(rangeKeys.contains('d'), isTrue);
      expect(rangeKeys.contains('e'), isFalse); // Exclusive end
    });

    test('should handle batch operations', () {
      final batchData = <List<int>, Uint8List>{
        [49]: Uint8List.fromList([10]),
        [50]: Uint8List.fromList([20]),
        [51]: Uint8List.fromList([30]),
      };

      memtable.putBatch(batchData);

      expect(memtable.size, equals(3));
      expect(memtable.get([49]), equals(Uint8List.fromList([10])));
      expect(memtable.get([50]), equals(Uint8List.fromList([20])));
      expect(memtable.get([51]), equals(Uint8List.fromList([30])));
    });

    test('should handle batch get operations', () {
      memtable.put([49], Uint8List.fromList([10]));
      memtable.put([50], Uint8List.fromList([20]));
      memtable.put([51], Uint8List.fromList([30]));

      final keys = [
        [49],
        [50],
        [51],
        [52],
      ]; // 52 doesn't exist
      final results = memtable.getBatch(keys);

      expect(results.length, equals(4));
      // Check results by finding matching keys
      final key49Result =
          results.entries
              .firstWhere((e) => String.fromCharCodes(e.key) == '1')
              .value;
      final key50Result =
          results.entries
              .firstWhere((e) => String.fromCharCodes(e.key) == '2')
              .value;
      final key51Result =
          results.entries
              .firstWhere((e) => String.fromCharCodes(e.key) == '3')
              .value;
      final key52Entry =
          results.entries
              .where((e) => String.fromCharCodes(e.key) == '4')
              .toList();
      final key52Result = key52Entry.isEmpty ? null : key52Entry.first.value;

      expect(key49Result, equals(Uint8List.fromList([10])));
      expect(key50Result, equals(Uint8List.fromList([20])));
      expect(key51Result, equals(Uint8List.fromList([30])));
      expect(key52Result, isNull);
    });

    test('should scan by prefix', () {
      // Add keys with prefix
      memtable.put('user:1'.codeUnits, Uint8List.fromList([1]));
      memtable.put('user:2'.codeUnits, Uint8List.fromList([2]));
      memtable.put('post:1'.codeUnits, Uint8List.fromList([3]));

      final userEntries = memtable.scanPrefix('user:'.codeUnits);

      expect(userEntries.length, equals(2));
      expect(userEntries.values.first, equals(Uint8List.fromList([1])));
      expect(userEntries.values.last, equals(Uint8List.fromList([2])));
    });

    test('should get first and last keys', () {
      expect(memtable.firstKey, isNull);
      expect(memtable.lastKey, isNull);

      memtable.put([98], Uint8List.fromList([2])); // "b"
      memtable.put([97], Uint8List.fromList([1])); // "a"
      memtable.put([99], Uint8List.fromList([3])); // "c"

      expect(memtable.firstKey, equals([97])); // "a"
      expect(memtable.lastKey, equals([99])); // "c"
    });

    test('should track memory usage accurately', () {
      expect(memtable.memoryUsage, equals(0));

      final key = [107, 101, 121]; // "key"
      final value = Uint8List(100);

      memtable.put(key, value);

      // Memory usage should include key length + value length
      expect(memtable.memoryUsage, greaterThanOrEqualTo(103));
    });

    test('should handle key caching optimization', () {
      // Test with small keys (direct conversion)
      final smallKey = List.generate(10, (i) => i);
      memtable.put(smallKey, Uint8List.fromList([1]));
      expect(memtable.get(smallKey), equals(Uint8List.fromList([1])));

      // Test with large keys (should use caching)
      final largeKey = List.generate(50, (i) => i);
      memtable.put(largeKey, Uint8List.fromList([2]));
      expect(memtable.get(largeKey), equals(Uint8List.fromList([2])));
    });

    test('should provide accurate statistics', () {
      // Fill to 50% capacity
      for (int i = 0; i < 5; i++) {
        memtable.put([i], Uint8List(50));
      }

      final stats = memtable.getStats();

      expect(stats['entries'], equals(5));
      expect(stats['memoryUsage'], greaterThan(250));
      expect(stats['maxSize'], equals(1024));
      expect(stats['utilizationPercent'], isA<String>());
      expect(double.parse(stats['utilizationPercent']), greaterThan(20));
      expect(double.parse(stats['utilizationPercent']), lessThan(40));
    });
  });
}
