import 'package:test/test.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';
import 'dart:io';

void main() {
  group('ReaxDB Encryption Tests', () {
    final testBasePath = 'test/encryption_test_db';

    tearDown(() async {
      // Clean up all test databases
      for (final type in ['none', 'xor', 'aes256']) {
        final dir = Directory('${testBasePath}_$type');
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });

    group('No Encryption', () {
      late ReaxDB db;
      final testPath = '${testBasePath}_none';

      setUp(() async {
        final dir = Directory(testPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }

        db = await ReaxDB.open(
          'no_encryption_db',
          path: testPath,
          config: DatabaseConfig.defaultConfig(), // No encryption by default
        );
      });

      tearDown(() async {
        await db.close();
      });

      test('should store and retrieve data without encryption', () async {
        await db.put('test_key', 'test_value');
        final value = await db.get<String>('test_key');

        expect(value, equals('test_value'));

        final info = await db.getDatabaseInfo();
        expect(info.isEncrypted, isFalse);
      });

      test('should handle complex data types without encryption', () async {
        final complexData = {
          'user': {
            'id': 123,
            'name': 'John Doe',
            'email': 'john@example.com',
            'preferences': {'theme': 'dark', 'notifications': true},
          },
          'metadata': {
            'created': DateTime.now().toIso8601String(),
            'version': '1.0.0',
          },
        };

        await db.put('complex_data', complexData);
        final retrieved = await db.get<Map>('complex_data');

        expect(retrieved, equals(complexData));
      });

      test('should provide encryption info for unencrypted database', () async {
        final encryptionInfo = db.getEncryptionInfo();

        expect(encryptionInfo['enabled'], isFalse);
        expect(encryptionInfo['type'], equals('none'));
        expect(encryptionInfo['security_level'], equals('none'));
        expect(encryptionInfo['performance_impact'], equals('none'));
      });
    });

    group('XOR Encryption', () {
      late ReaxDB db;
      final testPath = '${testBasePath}_xor';
      final encryptionKey = 'test_xor_key_for_fast_encryption';

      setUp(() async {
        final dir = Directory(testPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }

        db = await ReaxDB.open(
          'xor_encryption_db',
          path: testPath,
          config: DatabaseConfig.withXorEncryption(),
          encryptionKey: encryptionKey,
        );
      });

      tearDown(() async {
        await db.close();
      });

      test('should store and retrieve data with XOR encryption', () async {
        await db.put('secret_key', 'secret_value');
        final value = await db.get<String>('secret_key');

        expect(value, equals('secret_value'));

        final info = await db.getDatabaseInfo();
        expect(info.isEncrypted, isTrue);
      });

      test('should handle batch operations with XOR encryption', () async {
        final batchData = {
          'user:1': {'name': 'Alice', 'age': 25},
          'user:2': {'name': 'Bob', 'age': 30},
          'user:3': {'name': 'Charlie', 'age': 35},
        };

        await db.putBatch(batchData);

        for (final entry in batchData.entries) {
          final retrieved = await db.get<Map>(entry.key);
          expect(retrieved, equals(entry.value));
        }
      });

      test(
        'should provide encryption info for XOR encrypted database',
        () async {
          final encryptionInfo = db.getEncryptionInfo();

          expect(encryptionInfo['enabled'], isTrue);
          expect(encryptionInfo['type'], equals('xor'));
        },
      );

      test(
        'should handle large data with XOR encryption efficiently',
        () async {
          final largeData = List.generate(10000, (i) => 'item_$i');

          final stopwatch = Stopwatch()..start();
          await db.put('large_encrypted_data', largeData);
          stopwatch.stop();

          // XOR should be fast
          expect(stopwatch.elapsedMilliseconds, lessThan(50));

          final retrieved = await db.get<List>('large_encrypted_data');
          expect(retrieved, equals(largeData));
        },
      );
    });

    group('AES-256 Encryption', () {
      late ReaxDB db;
      final testPath = '${testBasePath}_aes256';
      final encryptionKey = 'secure_aes256_key_for_production_use';

      setUp(() async {
        final dir = Directory(testPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }

        db = await ReaxDB.open(
          'aes256_encryption_db',
          path: testPath,
          config: DatabaseConfig.withAes256Encryption(),
          encryptionKey: encryptionKey,
        );
      });

      tearDown(() async {
        await db.close();
      });

      test('should store and retrieve data with AES-256 encryption', () async {
        await db.put('top_secret', 'classified_information');
        final value = await db.get<String>('top_secret');

        expect(value, equals('classified_information'));

        final info = await db.getDatabaseInfo();
        expect(info.isEncrypted, isTrue);
      });

      test('should handle sensitive data with AES-256 encryption', () async {
        final sensitiveData = {
          'credit_card': '4532-1234-5678-9012',
          'ssn': '123-45-6789',
          'password': 'super_secure_password_123!',
          'api_keys': {
            'stripe': 'sk_test_123456789',
            'aws': 'AKIAIOSFODNN7EXAMPLE',
          },
        };

        await db.put('sensitive_data', sensitiveData);
        final retrieved = await db.get<Map>('sensitive_data');

        expect(retrieved, equals(sensitiveData));
      });

      test(
        'should provide encryption info for AES-256 encrypted database',
        () async {
          final encryptionInfo = db.getEncryptionInfo();

          expect(encryptionInfo['enabled'], isTrue);
          expect(encryptionInfo['type'], equals('aes256'));
        },
      );

      test('should handle batch operations with AES-256 encryption', () async {
        final batchData = <String, dynamic>{};

        // Create batch of encrypted data
        for (int i = 0; i < 20; i++) {
          batchData['secure_record_$i'] = {
            'id': i,
            'secret': 'confidential_data_$i',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
        }

        await db.putBatch(batchData);

        // Verify all data
        for (final entry in batchData.entries) {
          final retrieved = await db.get<Map>(entry.key);
          expect(retrieved, equals(entry.value));
        }
      });

      test('should maintain data integrity with AES-256 encryption', () async {
        // Store data multiple times to test consistency
        const testData = 'integrity_test_data_with_special_chars_!@#\$%^&*()';

        for (int i = 0; i < 10; i++) {
          await db.put('integrity_test', testData);
          final retrieved = await db.get<String>('integrity_test');
          expect(retrieved, equals(testData));
        }
      });
    });

    group('Encryption Performance Comparison', () {
      test('should compare performance across encryption types', () async {
        final testData = List.generate(1000, (i) => 'performance_test_data_$i');
        final results = <String, int>{};

        // Test each encryption type
        for (final configData in [
          {'name': 'none', 'config': DatabaseConfig.defaultConfig()},
          {'name': 'xor', 'config': DatabaseConfig.withXorEncryption()},
          {'name': 'aes256', 'config': DatabaseConfig.withAes256Encryption()},
        ]) {
          final testPath = '${testBasePath}_perf_${configData['name']}';
          final dir = Directory(testPath);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }

          final db = await ReaxDB.open(
            'perf_test_${configData['name']}',
            path: testPath,
            config: configData['config'] as DatabaseConfig,
            encryptionKey:
                configData['name'] != 'none'
                    ? 'test_key_for_performance'
                    : null,
          );

          try {
            final stopwatch = Stopwatch()..start();

            // Perform batch write
            final batchData = <String, dynamic>{};
            for (int i = 0; i < testData.length; i++) {
              batchData['perf_$i'] = testData[i];
            }
            await db.putBatch(batchData);

            // Perform batch read
            final keys = List.generate(testData.length, (i) => 'perf_$i');
            await db.getBatch<String>(keys);

            stopwatch.stop();
            results[configData['name'] as String] =
                stopwatch.elapsedMilliseconds;
          } finally {
            await db.close();
            if (await dir.exists()) {
              await dir.delete(recursive: true);
            }
          }
        }

        // Performance expectations
        expect(
          results['none']!,
          lessThan(results['aes256']!),
        ); // No encryption should be fastest
        expect(
          results['xor']!,
          lessThan(results['aes256']!),
        ); // XOR should be faster than AES-256

        print('Performance Results:');
        print('No Encryption: ${results['none']}ms');
        print('XOR Encryption: ${results['xor']}ms');
        print('AES-256 Encryption: ${results['aes256']}ms');
      });
    });

    group('Encryption Error Handling', () {
      test(
        'should throw error when encryption key is missing for XOR',
        () async {
          final testPath = '${testBasePath}_error_xor';

          expect(
            () async => await ReaxDB.open(
              'error_test_xor',
              path: testPath,
              config: DatabaseConfig.withXorEncryption(),
              // Missing encryptionKey
            ),
            throwsA(isA<ArgumentError>()),
          );
        },
      );

      test(
        'should throw error when encryption key is missing for AES-256',
        () async {
          final testPath = '${testBasePath}_error_aes256';

          expect(
            () async => await ReaxDB.open(
              'error_test_aes256',
              path: testPath,
              config: DatabaseConfig.withAes256Encryption(),
              // Missing encryptionKey
            ),
            throwsA(isA<ArgumentError>()),
          );
        },
      );

      test('should handle empty encryption key', () async {
        final testPath = '${testBasePath}_error_empty';

        expect(
          () async => await ReaxDB.open(
            'error_test_empty',
            path: testPath,
            config: DatabaseConfig.withXorEncryption(),
            encryptionKey: '', // Empty key
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('Encryption Type Information', () {
      test('should provide correct encryption type information', () {
        // Test EncryptionType enum extensions
        expect(EncryptionType.none.displayName, equals('No Encryption'));
        expect(EncryptionType.xor.displayName, equals('XOR (Fast)'));
        expect(EncryptionType.aes256.displayName, equals('AES-256 (Secure)'));

        expect(EncryptionType.none.securityLevel, equals('None'));
        expect(
          EncryptionType.xor.securityLevel,
          equals('Low - Basic obfuscation only'),
        );
        expect(
          EncryptionType.aes256.securityLevel,
          equals('High - Cryptographically secure'),
        );

        expect(EncryptionType.none.requiresKey, isFalse);
        expect(EncryptionType.xor.requiresKey, isTrue);
        expect(EncryptionType.aes256.requiresKey, isTrue);
      });
    });
  });
}
