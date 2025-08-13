# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2025-08-11

### Changed
- **Pure Dart Package**: Converted from Flutter-specific to pure Dart package - no longer requires Flutter SDK
- Package can now be used in any Dart environment (CLI, server, web, Flutter)
- **Note**: This is NOT a breaking change - all existing Flutter code continues to work

### Added
- **Configurable Logging System**: Multi-level logging with console, file, and memory outputs
- **Reactive Streams**: Advanced stream operators including:
  - `debounce()` - Delay events until a pause in emissions
  - `throttle()` - Limit event frequency
  - `buffer()` - Collect multiple events before emitting
  - `take()` and `skip()` - Control number of events
  - `map()` - Transform event data
- **Enhanced Query Builder**:
  - Aggregation functions: COUNT, SUM, AVG, MIN, MAX, DISTINCT
  - GROUP BY operations with multiple aggregations
  - Full-text search capabilities
  - Batch update operations
  - Batch delete operations
  - Improved scanning for large datasets (up to 1000 IDs)
- **Advanced Transaction Features**:
  - Transaction isolation levels (ReadUncommitted, ReadCommitted, RepeatableRead, Serializable)
  - Read-only transactions with write protection
  - Savepoints for partial rollback
  - Nested transactions
  - Automatic retry logic with exponential backoff
  - Transaction timeout support
  - Transaction statistics and monitoring
- **Enhanced Transaction Manager**:
  - `withTransaction()` - Automatic transaction management with retry
  - `beginEnhancedTransaction()` - Create transactions with advanced features
  - `beginReadOnlyTransaction()` - Create read-only transactions
  - Active transaction tracking
  - Bulk transaction closure

### Improved
- **Query Performance**: Extended collection scanning from 20 to 1000 IDs
- **Test Coverage**: Added comprehensive tests for all new features
- **API Documentation**: Enhanced documentation with examples for new features
- **Error Handling**: Better error messages and transaction failure handling

### Fixed
- Transaction retry logic now properly implements exponential backoff
- Query aggregation test expectations corrected
- Enhanced transaction tests now pass 100%

### Acknowledgments
- Special thanks to [@TechWithDunamis](https://github.com/TechWithDunamis) for the pure Dart conversion (PR #4)

## [1.2.3] - 2025-07-20

### Fixed
- **CRITICAL**: Fixed data persistence between application sessions
- WAL recovery now properly restores data on database reopening
- Fixed async operations in WAL write operations
- Fixed operation ordering to maintain data consistency
- Improved tombstone handling for deleted entries

### Acknowledgments
- Thanks to Ray Caruso for reporting the critical persistence bug

## [1.2.2] - 2025-07-15

### Fixed
- Fixed pub.dev static analysis issues
- Better error handling in code
- Improved code quality

### Added
- API documentation for all public methods

## [1.2.1] - 2025-07-15

### Fixed
- Minor fixes and code improvements

## [1.2.0] - 2025-07-11

### Added
- **WASM Compatibility**: Full support for Dart's WASM runtime with automatic fallback encryption
- **Enhanced Encryption API**: New `EncryptionType` enum for better encryption control
- **Encryption Factory Methods**: `DatabaseConfig.withXorEncryption()` and `DatabaseConfig.withAes256Encryption()`
- **WASM Fallback Encryption**: HMAC-based encryption for WASM environments when PointyCastle is unavailable
- **Runtime Detection**: Automatic detection of WASM runtime with appropriate warnings
- **Encryption Metadata**: Enhanced metadata including runtime environment and fallback status

### Improved
- **AES-256 Performance**: 40% faster AES encryption (138-180ms vs 237ms) using PointyCastle 4.0.0
- **WAL Recovery**: Fixed Write-Ahead Log recovery issues with proper pending write flushing
- **Code Documentation**: Updated README with new encryption API examples and WASM compatibility section

### Fixed
- **WAL Test Failures**: Resolved race conditions in Write-Ahead Log tests
- **Tombstone Recovery**: Fixed delete entry recovery in WAL mixed operations
- **Async Flush Issues**: Improved pending write flushing in WAL close operations

### Technical
- **Conditional Imports**: Smart import system for WASM compatibility
- **Fallback Implementation**: WASM-compatible encryption using only Dart's built-in crypto library
- **API Compatibility**: Maintains backward compatibility while adding new features

## [1.1.1] - 2025-06-15

### Added
- **Secondary Indexes**: Query any field with lightning speed
- **Query Builder**: Powerful API for complex queries  
- **Range Queries**: Find documents between values
- **Auto Index Updates**: Indexes stay in sync automatically

### Improved
- **Query Performance**: Significant improvements in indexed queries
- **Index Management**: Better index creation and maintenance

## [1.0.1] - 2025-05-20

### Added
- **4.4x faster writes**: Now 21,000+ operations per second
- **40% faster batch operations**: Improved batch processing

### Improved
- **Write Performance**: Major optimizations in write operations
- **Batch Processing**: Enhanced batch operation efficiency

## [1.0.0] - 2025-05-01

### Added
- Initial release of ReaxDB
- **High Performance**: Zero-copy serialization and multi-level caching system
- **Security**: Built-in encryption with customizable keys
- **ACID Transactions**: Full transaction support with isolation levels
- **Concurrent Operations**: Connection pooling and batch processing
- **Mobile Optimized**: Hybrid storage engine designed for mobile devices
- **Real-time Streams**: Live data change notifications with pattern matching