/// ReaxDB - High-performance NoSQL database for Dart
library;

// Domain exports
export 'src/domain/entities/database_entity.dart';

// Core exports
export 'src/core/storage/hybrid_storage_engine.dart';
export 'src/core/cache/multi_level_cache.dart';
export 'src/core/transactions/transaction_manager.dart' hide Transaction;
export 'src/core/encryption/encryption_type.dart';
export 'src/core/encryption/encryption_engine.dart';

// Main ReaxDB class
export 'src/reaxdb.dart';
