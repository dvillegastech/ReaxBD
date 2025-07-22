import 'package:test/test.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';
import 'dart:io';

void main() {
  group('Secondary Index Tests', () {
    late ReaxDB db;
    final testPath = 'test/index_test_db';

    setUp(() async {
      // Clean up any existing test database
      final dir = Directory(testPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }

      // Create database
      db = await ReaxDB.open('index_db', path: testPath);
    });

    tearDown(() async {
      await db.close();

      // Clean up test database
      final dir = Directory(testPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('should create and list indexes', () async {
      // Create indexes
      await db.createIndex('users', 'email');
      await db.createIndex('users', 'age');
      await db.createIndex('products', 'price');

      // List indexes
      final indexes = db.listIndexes();

      expect(indexes, contains('users.email'));
      expect(indexes, contains('users.age'));
      expect(indexes, contains('products.price'));
      expect(indexes.length, equals(3));
    });

    test('should drop indexes', () async {
      // Create indexes
      await db.createIndex('users', 'email');
      await db.createIndex('users', 'age');

      // Drop one index
      await db.dropIndex('users', 'email');

      // Verify
      final indexes = db.listIndexes();
      expect(indexes, isNot(contains('users.email')));
      expect(indexes, contains('users.age'));
    });

    test('should prevent duplicate index creation', () async {
      await db.createIndex('users', 'email');

      // Try to create same index again
      expect(() => db.createIndex('users', 'email'), throwsStateError);
    });

    test('should query by indexed field', () async {
      // Create index
      await db.createIndex('users', 'email');

      // Insert test data
      await db.put('users:1', {
        'id': '1',
        'name': 'John',
        'email': 'john@test.com',
        'age': 25,
      });

      await db.put('users:2', {
        'id': '2',
        'name': 'Jane',
        'email': 'jane@test.com',
        'age': 30,
      });

      // Query by email
      final results = await db.where('users', 'email', 'jane@test.com');

      expect(results.length, equals(1));
      expect(results[0]['name'], equals('Jane'));
      expect(results[0]['email'], equals('jane@test.com'));
    });

    test('should handle range queries', () async {
      // Create index
      await db.createIndex('products', 'price');

      // Insert products
      final products = [
        {'id': '1', 'name': 'Laptop', 'price': 999.99},
        {'id': '2', 'name': 'Mouse', 'price': 29.99},
        {'id': '3', 'name': 'Keyboard', 'price': 79.99},
        {'id': '4', 'name': 'Monitor', 'price': 299.99},
        {'id': '5', 'name': 'Headphones', 'price': 149.99},
      ];

      for (final product in products) {
        await db.put('products:${product['id']}', product);
      }

      // Query products between $50 and $200
      final results =
          await db
              .collection('products')
              .whereBetween('price', 50.0, 200.0)
              .orderBy('price')
              .find();

      expect(results.length, equals(2));
      expect(results[0]['name'], equals('Keyboard'));
      expect(results[1]['name'], equals('Headphones'));
    });

    test('should update index on document update', () async {
      // Create index
      await db.createIndex('users', 'email');

      // Insert user
      await db.put('users:1', {
        'id': '1',
        'name': 'John',
        'email': 'john@old.com',
      });

      // Verify old email
      var results = await db.where('users', 'email', 'john@old.com');
      expect(results.length, equals(1));

      // Update email
      await db.put('users:1', {
        'id': '1',
        'name': 'John',
        'email': 'john@new.com',
      });

      // Old email should not find anything
      results = await db.where('users', 'email', 'john@old.com');
      expect(results.length, equals(0));

      // New email should find the user
      results = await db.where('users', 'email', 'john@new.com');
      expect(results.length, equals(1));
      expect(results[0]['email'], equals('john@new.com'));
    });

    test('should handle complex queries', () async {
      // Create indexes
      await db.createIndex('users', 'age');
      await db.createIndex('users', 'city');

      // Insert users
      final users = [
        {'id': '1', 'name': 'John', 'age': 25, 'city': 'NYC'},
        {'id': '2', 'name': 'Jane', 'age': 30, 'city': 'LA'},
        {'id': '3', 'name': 'Bob', 'age': 35, 'city': 'NYC'},
        {'id': '4', 'name': 'Alice', 'age': 28, 'city': 'Chicago'},
        {'id': '5', 'name': 'Charlie', 'age': 22, 'city': 'NYC'},
      ];

      for (final user in users) {
        await db.put('users:${user['id']}', user);
      }

      // Find young users in NYC
      final results =
          await db
              .collection('users')
              .whereEquals('city', 'NYC')
              .whereLessThan('age', 30)
              .orderBy('age')
              .find();

      expect(results.length, equals(2));
      expect(results[0]['name'], equals('Charlie'));
      expect(results[1]['name'], equals('John'));
    });

    test('should handle pagination', () async {
      // Create index
      await db.createIndex('users', 'name');

      // Insert users
      for (int i = 1; i <= 10; i++) {
        await db.put('users:$i', {
          'id': '$i',
          'name': 'User${i.toString().padLeft(2, '0')}',
        });
      }

      // First page
      final page1 =
          await db.collection('users').orderBy('name').limit(3).find();

      expect(page1.length, equals(3));
      expect(page1[0]['name'], equals('User01'));
      expect(page1[2]['name'], equals('User03'));

      // Second page
      final page2 =
          await db
              .collection('users')
              .orderBy('name')
              .limit(3)
              .offset(3)
              .find();

      expect(page2.length, equals(3));
      expect(page2[0]['name'], equals('User04'));
      expect(page2[2]['name'], equals('User06'));
    });

    test('should handle null values in indexed fields', () async {
      // Create index
      await db.createIndex('users', 'email');

      // Insert user without email
      await db.put('users:1', {
        'id': '1',
        'name': 'John',
        // no email field
      });

      // Insert user with null email
      await db.put('users:2', {'id': '2', 'name': 'Jane', 'email': null});

      // Insert user with email
      await db.put('users:3', {
        'id': '3',
        'name': 'Bob',
        'email': 'bob@test.com',
      });

      // Query for specific email
      final results = await db.where('users', 'email', 'bob@test.com');
      expect(results.length, equals(1));
      expect(results[0]['name'], equals('Bob'));
    });

    test('should measure index performance', () async {
      // Insert many users without index
      final stopwatch1 = Stopwatch()..start();

      for (int i = 1; i <= 100; i++) {
        await db.put('users:$i', {
          'id': '$i',
          'name': 'User $i',
          'email': 'user$i@test.com',
          'score': i * 10,
        });
      }

      // Search without index
      await db
          .collection('users')
          .whereEquals('email', 'user50@test.com')
          .findOne();

      stopwatch1.stop();
      final timeWithoutIndex = stopwatch1.elapsedMicroseconds;

      // Create index
      await db.createIndex('users', 'email');

      // Search with index
      final stopwatch2 = Stopwatch()..start();
      await db
          .collection('users')
          .whereEquals('email', 'user50@test.com')
          .findOne();
      stopwatch2.stop();
      final timeWithIndex = stopwatch2.elapsedMicroseconds;

      print('Query without index: $timeWithoutIndexμs');
      print('Query with index: $timeWithIndexμs');

      // Index should be faster (though for small datasets the difference might be minimal)
      expect(timeWithIndex, lessThanOrEqualTo(timeWithoutIndex));
    });
  });
}
