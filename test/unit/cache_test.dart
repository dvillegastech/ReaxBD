import 'package:test/test.dart';
import 'package:reaxdb_dart/src/core/cache/multi_level_cache.dart';
import 'dart:typed_data';

void main() {
  group('MultiLevelCache Tests', () {
    late MultiLevelCache cache;

    setUp(() {
      cache = MultiLevelCache(
        l1MaxSize: 100,
        l1MaxMemory: 1024 * 1024, // 1MB
        l2MaxSize: 200,
        l2MaxMemory: 2 * 1024 * 1024, // 2MB
        l3MaxSize: 300,
        l3MaxMemory: 3 * 1024 * 1024, // 3MB
      );
    });

    test('should store and retrieve data from L1 cache', () {
      final key = 'test_key';
      final value = Uint8List.fromList([1, 2, 3, 4, 5]);

      cache.put(key, value, level: CacheLevel.l1);
      final retrieved = cache.get(key);

      expect(retrieved, equals(value));
    });

    test('should promote data from L2 to L1 on access', () {
      final key = 'test_key_l2';
      final value = Uint8List.fromList([10, 20, 30]);

      // Put in L2
      cache.put(key, value, level: CacheLevel.l2);

      // Get should promote to L1
      final retrieved = cache.get(key);

      expect(retrieved, equals(value));

      // Verify it's now in L1 by checking stats
      final stats = cache.getStats();
      expect(stats.l1Hits, greaterThan(0));
    });

    test('should handle multiple cache levels correctly', () {
      final keyL1 = 'key_l1';
      final keyL2 = 'key_l2';
      final keyL3 = 'key_l3';

      final valueL1 = Uint8List.fromList([1, 1, 1]);
      final valueL2 = Uint8List.fromList([2, 2, 2]);
      final valueL3 = Uint8List.fromList([3, 3, 3]);

      cache.put(keyL1, valueL1, level: CacheLevel.l1);
      cache.put(keyL2, valueL2, level: CacheLevel.l2);
      cache.put(keyL3, valueL3, level: CacheLevel.l3);

      expect(cache.get(keyL1), equals(valueL1));
      expect(cache.get(keyL2), equals(valueL2));
      expect(cache.get(keyL3), equals(valueL3));
    });

    test('should remove key from all cache levels', () {
      final key = 'remove_test';
      final value = Uint8List.fromList([42]);

      cache.put(key, value, level: CacheLevel.l1);
      cache.put(key, value, level: CacheLevel.l2);
      cache.put(key, value, level: CacheLevel.l3);

      cache.remove(key);

      expect(cache.get(key), isNull);
    });

    test('should clear all cache levels', () {
      // Add multiple entries
      for (int i = 0; i < 10; i++) {
        cache.put('key_$i', Uint8List.fromList([i]), level: CacheLevel.l1);
      }

      expect(cache.getTotalEntryCount(), greaterThan(0));

      cache.clear();

      expect(cache.getTotalEntryCount(), equals(0));
    });

    test('should invalidate entries by pattern', () {
      // Add entries with pattern
      cache.put('user:1', Uint8List.fromList([1]), level: CacheLevel.l1);
      cache.put('user:2', Uint8List.fromList([2]), level: CacheLevel.l1);
      cache.put('post:1', Uint8List.fromList([3]), level: CacheLevel.l1);

      cache.invalidatePattern('user:.*');

      expect(cache.get('user:1'), isNull);
      expect(cache.get('user:2'), isNull);
      expect(cache.get('post:1'), isNotNull);
    });

    test('should handle cache overflow correctly', () {
      // Fill L1 cache beyond capacity
      for (int i = 0; i < 150; i++) {
        cache.put('overflow_$i', Uint8List(100), level: CacheLevel.l1);
      }

      // Should not exceed max size
      final stats = cache.getStats();
      expect(stats.totalEntries, lessThanOrEqualTo(100));
    });

    test('should track cache statistics accurately', () {
      cache.put(
        'stat_test',
        Uint8List.fromList([1, 2, 3]),
        level: CacheLevel.l1,
      );

      // First get - cache hit
      cache.get('stat_test');

      // Non-existent key - cache miss
      cache.get('non_existent');

      final stats = cache.getStats();
      expect(stats.l1Hits, equals(1));
      expect(stats.l1Misses, greaterThanOrEqualTo(1));
      expect(stats.hitRatio, greaterThan(0));
    });

    test('should preload data efficiently', () {
      final preloadData = <String, Uint8List>{
        'preload_1': Uint8List.fromList([1]),
        'preload_2': Uint8List.fromList([2]),
        'preload_3': Uint8List.fromList([3]),
      };

      cache.preload(preloadData, level: CacheLevel.l2);

      expect(cache.get('preload_1'), equals(preloadData['preload_1']));
      expect(cache.get('preload_2'), equals(preloadData['preload_2']));
      expect(cache.get('preload_3'), equals(preloadData['preload_3']));
    });

    test('should return correct memory usage', () {
      final largeData = Uint8List(1000);
      cache.put('memory_test', largeData, level: CacheLevel.l1);

      expect(cache.getTotalMemoryUsage(), greaterThan(0));
      expect(cache.getTotalMemoryUsage(), greaterThanOrEqualTo(1000));
    });
  });

  group('LRUCache Tests', () {
    late LRUCache lruCache;

    setUp(() {
      lruCache = LRUCache(maxSize: 3, maxMemory: 1024);
    });

    test('should evict least recently used item when full', () {
      lruCache.put('a', Uint8List.fromList([1]));
      lruCache.put('b', Uint8List.fromList([2]));
      lruCache.put('c', Uint8List.fromList([3]));

      // Access 'a' to make it more recent
      lruCache.get('a');

      // Add new item, should evict 'b'
      lruCache.put('d', Uint8List.fromList([4]));

      expect(lruCache.get('a'), isNotNull);
      expect(lruCache.get('b'), isNull); // Evicted
      expect(lruCache.get('c'), isNotNull);
      expect(lruCache.get('d'), isNotNull);
    });

    test('should update access count on get', () {
      lruCache.put('key', Uint8List.fromList([1]));

      final initialHits = lruCache.hits;
      lruCache.get('key');

      expect(lruCache.hits, equals(initialHits + 1));
    });

    test('should track misses correctly', () {
      final initialMisses = lruCache.misses;
      lruCache.get('non_existent');

      expect(lruCache.misses, equals(initialMisses + 1));
    });
  });

  group('LFUCache Tests', () {
    late LFUCache lfuCache;

    setUp(() {
      lfuCache = LFUCache(maxSize: 3, maxMemory: 1024);
    });

    test('should evict least frequently used item when full', () {
      lfuCache.put('a', Uint8List.fromList([1]));
      lfuCache.put('b', Uint8List.fromList([2]));
      lfuCache.put('c', Uint8List.fromList([3]));

      // Access 'a' and 'b' multiple times
      lfuCache.get('a');
      lfuCache.get('a');
      lfuCache.get('b');

      // Add new item, should evict 'c' (least frequent)
      lfuCache.put('d', Uint8List.fromList([4]));

      expect(lfuCache.get('a'), isNotNull);
      expect(lfuCache.get('b'), isNotNull);
      expect(lfuCache.get('c'), isNull); // Evicted
      expect(lfuCache.get('d'), isNotNull);
    });

    test('should update frequency on access', () {
      lfuCache.put('freq_test', Uint8List.fromList([1]));

      // Access multiple times
      for (int i = 0; i < 5; i++) {
        lfuCache.get('freq_test');
      }

      // Fill cache
      lfuCache.put('other1', Uint8List.fromList([2]));
      lfuCache.put('other2', Uint8List.fromList([3]));

      // Add one more - freq_test should not be evicted due to high frequency
      lfuCache.put('other3', Uint8List.fromList([4]));

      expect(lfuCache.get('freq_test'), isNotNull);
    });

    test('should handle same frequency items correctly', () {
      // Add items with same frequency
      lfuCache.put('a', Uint8List.fromList([1]));
      lfuCache.put('b', Uint8List.fromList([2]));
      lfuCache.put('c', Uint8List.fromList([3]));

      // All have frequency 1, oldest should be evicted
      lfuCache.put('d', Uint8List.fromList([4]));

      expect(
        lfuCache.get('a'),
        isNull,
      ); // First in, first out for same frequency
    });
  });
}
