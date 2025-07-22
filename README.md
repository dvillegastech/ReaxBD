# ReaxDB

[![pub package](https://img.shields.io/pub/v/reaxdb_dart.svg)](https://pub.dev/packages/reaxdb_dart)
[![GitHub stars](https://img.shields.io/github/stars/dvillegastech/ReaxBD.svg)](https://github.com/dvillegastech/ReaxBD/stargazers)
[![GitHub license](https://img.shields.io/github/license/dvillegastech/ReaxBD.svg)](https://github.com/dvillegastech/ReaxBD/blob/main/LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-%E2%9D%A4-blue)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux-blue)](https://flutter.dev)

The fastest NoSQL database for Dart / Flutter. Store millions of records with 21,000+ writes per second, instant reads from cache, and built-in encryption. Perfect for offline-first apps, real-time sync, and large datasets. Works on all platforms with zero native dependencies.

**Keywords:** Flutter database, NoSQL, offline-first, local storage, cache, encryption, ACID transactions, real-time sync, embedded database, key-value store, document database, high performance, zero dependencies

## 🆕 What's New in v1.2.3 (July 20, 2025)
- **CRITICAL FIX** - Fixed data persistence between application sessions
- **WAL Recovery** - Data now properly restores when reopening database
- **Stability** - Fixed async operations and operation ordering
- **Thanks** - Special thanks to Ray Caruso for reporting the persistence bug

### Previous v1.2.2 (July 15, 2025)
- **Bug Fixes** - Fixed pub.dev issues
- **Documentation** - Added API docs
- **Code Quality** - Better error handling

### Previous v1.2.0 (July 11, 2025)
- **WASM Compatibility** - Full support for Dart's WASM runtime
- **Enhanced Encryption API** - New `EncryptionType` enum for better control
- **AES-256 Performance** - 40% faster AES encryption (138-180ms vs 237ms)
- **WAL Recovery Fix** - Improved Write-Ahead Log reliability
- **Automatic Fallbacks** - Smart encryption fallbacks for WASM environments

### Previous v1.1.1
- **Secondary Indexes** - Query any field with lightning speed
- **Query Builder** - Powerful API for complex queries
- **Range Queries** - Find documents between values
- **Auto Index Updates** - Indexes stay in sync automatically

### Previous v1.0.1
- **4.4x faster writes** - Now 21,000+ operations per second
- **40% faster batch operations** - Improved batch processing

## Features

- **High Performance**: Zero-copy serialization and multi-level caching system
- **Security**: Built-in AES encryption with customizable keys
- **ACID Transactions**: Full transaction support with isolation levels
- **Concurrent Operations**: Connection pooling and batch processing
- **Mobile Optimized**: Hybrid storage engine designed for mobile devices
- **Real-time Streams**: Live data change notifications with pattern matching
- **Data Persistence**: Reliable WAL-based persistence across app sessions

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  reaxdb_dart: ^1.2.3
```

Then run:

```bash
flutter pub get
```

or

```bash
dart pub get
```

## Quick Start

### Opening a Database

```dart
import 'package:reaxdb_dart/reaxdb_dart.dart';

// Basic usage
final db = await ReaxDB.open('my_database');

// With custom configuration
final config = DatabaseConfig(
  memtableSizeMB: 16,
  pageSize: 8192,
  l1CacheSize: 2000,
  l2CacheSize: 10000,
  l3CacheSize: 50000,
  compressionEnabled: true,
  syncWrites: false,
  encryptionType: EncryptionType.aes256, // New encryption API
);

final db = await ReaxDB.open(
  'my_database',
  config: config,
  encryptionKey: 'your-encryption-key',
);
```

### Basic Operations

```dart
// Store data
await db.put('user:123', {
  'name': 'John Doe',
  'email': 'john@example.com',
  'age': 30,
});

// Retrieve data
final user = await db.get('user:123');
print(user); // {name: John Doe, email: john@example.com, age: 30}

// Delete data
await db.delete('user:123');

// Close database
await db.close();

// Data persists between sessions (v1.2.3+)
final db2 = await ReaxDB.open('my_database');
final persistedUser = await db2.get('user:123');
// persistedUser is null because it was deleted
```

### Secondary Indexes (NEW!)

```dart
// Create indexes for fast queries
await db.createIndex('users', 'email');
await db.createIndex('users', 'age');

// Query by any indexed field
final user = await db.collection('users')
    .whereEquals('email', 'john@example.com')
    .findOne();

// Range queries
final youngUsers = await db.collection('users')
    .whereBetween('age', 18, 30)
    .orderBy('age')
    .find();

// Complex queries
final results = await db.collection('users')
    .whereEquals('city', 'New York')
    .whereGreaterThan('age', 21)
    .limit(10)
    .find();
```

### Batch Operations

```dart
// Batch write for better performance
await db.putBatch({
  'user:1': {'name': 'Alice', 'age': 25},
  'user:2': {'name': 'Bob', 'age': 30},
  'user:3': {'name': 'Charlie', 'age': 35},
});

// Batch read
final users = await db.getBatch(['user:1', 'user:2', 'user:3']);
```

### Transactions

```dart
final txn = await db.beginTransaction();

try {
  await txn.put('account:1', {'balance': 1000});
  await txn.put('account:2', {'balance': 500});
  
  // Transfer money
  final account1 = await txn.get('account:1');
  final account2 = await txn.get('account:2');
  
  await txn.put('account:1', {'balance': account1['balance'] - 100});
  await txn.put('account:2', {'balance': account2['balance'] + 100});
  
  await txn.commit();
} catch (e) {
  await txn.rollback();
  rethrow;
}
```

### Real-time Data Streams

```dart
// Listen to all changes
final subscription = db.watchAll().listen((event) {
  print('${event.type}: ${event.key} = ${event.value}');
});

// Listen to specific patterns
final userStream = db.watchPattern('user:*').listen((event) {
  print('User updated: ${event.key}');
});

// Don't forget to cancel subscriptions
subscription.cancel();
userStream.cancel();
```

### Advanced Features

#### Atomic Operations

```dart
// Compare and swap
final success = await db.compareAndSwap('counter', 0, 1);
if (success) {
  print('Counter incremented');
}
```

#### Performance Monitoring

```dart
final stats = db.getPerformanceStats();
print('Cache hit ratio: ${stats['cache']['total_hit_ratio']}');

final dbInfo = await db.getDatabaseInfo();
print('Database size: ${dbInfo['database']['size']} bytes');
print('Total entries: ${dbInfo['database']['entries']}');
```

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `memtableSizeMB` | 4 | Memory table size in megabytes |
| `pageSize` | 4096 | Storage page size in bytes |
| `l1CacheSize` | 1000 | Level 1 cache maximum entries |
| `l2CacheSize` | 5000 | Level 2 cache maximum entries |
| `l3CacheSize` | 10000 | Level 3 cache maximum entries |
| `compressionEnabled` | true | Enable data compression |
| `syncWrites` | true | Synchronous write operations |
| `maxImmutableMemtables` | 4 | Maximum immutable memtables |

## Performance Characteristics

- **Read Performance**: 333,333 operations/second (~0.003ms latency)
- **Write Performance**: 21,276 operations/second (~0.047ms latency)
- **Batch Operations**: 3,676 operations/second
- **Cache Hits**: 555,555 operations/second (~0.002ms latency)
- **Large Files**: 4.8 GB/s write, 1.9 GB/s read
- **Concurrent Operations**: Up to 10 simultaneous operations
- **Memory Efficiency**: Multi-level caching with automatic promotion
- **Storage Efficiency**: LSM Tree with automatic compaction

## Security

ReaxDB provides built-in encryption support with multiple algorithms:

```dart
// AES-256 encryption (most secure)
final db = await ReaxDB.open(
  'secure_database',
  config: DatabaseConfig.withAes256Encryption(),
  encryptionKey: 'your-256-bit-encryption-key',
);

// XOR encryption (faster, good for performance-critical apps)
final db = await ReaxDB.open(
  'fast_secure_database',
  config: DatabaseConfig.withXorEncryption(),
  encryptionKey: 'your-encryption-key',
);

// Custom encryption configuration
final config = DatabaseConfig(
  memtableSizeMB: 8,
  pageSize: 4096,
  l1CacheSize: 1000,
  l2CacheSize: 5000,
  l3CacheSize: 10000,
  compressionEnabled: true,
  syncWrites: true,
  maxImmutableMemtables: 4,
  cacheSize: 50,
  enableCache: true,
  encryptionType: EncryptionType.aes256, // none, xor, or aes256
);

final db = await ReaxDB.open(
  'custom_secure_database',
  config: config,
  encryptionKey: 'your-encryption-key',
);
```

### Encryption Types

- **`EncryptionType.none`**: No encryption (fastest)
- **`EncryptionType.xor`**: XOR encryption (fast, moderate security)
- **`EncryptionType.aes256`**: AES-256-GCM encryption (secure, slower)

All data is encrypted at rest when an encryption type other than `none` is specified.

### WASM Compatibility

ReaxDB is compatible with Dart's WASM runtime, but with some limitations:

- **Native Performance**: Uses PointyCastle for optimized AES-256 encryption (~138-180ms)
- **WASM Fallback**: Automatically switches to HMAC-based encryption in WASM environments
- **Security Note**: WASM fallback provides authentication but reduced cryptographic strength
- **Recommendation**: Use XOR encryption for WASM deployments requiring high performance

```dart
// For WASM environments, consider using XOR encryption
final db = await ReaxDB.open(
  'wasm_database',
  encryptionType: EncryptionType.xor, // Better WASM performance
  encryptionKey: 'your-encryption-key',
);
```

The library automatically detects WASM runtime and provides appropriate warnings when using AES-256 encryption.

## Architecture

ReaxDB uses a hybrid storage architecture combining:

- **LSM Tree**: Optimized for write-heavy workloads
- **B+ Tree**: Fast range queries and ordered access
- **Multi-level Cache**: L1 (object), L2 (page), L3 (query) caching
- **Write-Ahead Log**: Durability and crash recovery
- **Connection Pooling**: Concurrent operation management

## Error Handling

```dart
try {
  final value = await db.get('nonexistent-key');
} on DatabaseException catch (e) {
  print('Database error: ${e.message}');
} catch (e) {
  print('Unexpected error: $e');
}
```

## Best Practices

1. **Use batch operations** for multiple writes to improve performance
2. **Enable compression** for storage efficiency with large datasets  
3. **Configure cache sizes** based on your application's memory constraints
4. **Use transactions** for operations that must be atomic
5. **Close databases** properly to ensure data persistence
6. **Monitor performance** using built-in statistics methods

## Closing the Database

```dart
await db.close();
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please read our contributing guidelines and submit pull requests to our repository.

## Support the Project

If you find ReaxDB useful, please consider supporting its development:

<a href="https://buymeacoffee.com/dvillegas" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

Your support helps maintain and improve ReaxDB!

## Support

For issues, questions, or contributions, please visit our [GitHub repository](https://github.com/dvillegastech/ReaxBD) or contact our support team.