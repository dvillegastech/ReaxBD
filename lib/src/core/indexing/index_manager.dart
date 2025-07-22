import 'dart:io';

import 'secondary_index.dart';
import '../storage/hybrid_storage_engine.dart';

// Index manager
class IndexManager {
  final String _basePath;
  final HybridStorageEngine _storageEngine;
  final Map<String, SecondaryIndex> _indexes = {};

  IndexManager({
    required String basePath,
    required HybridStorageEngine storageEngine,
  }) : _basePath = basePath,
       _storageEngine = storageEngine;

  // Creates index
  Future<void> createIndex(String collection, String fieldName) async {
    final indexKey = '$collection.$fieldName';

    if (_indexes.containsKey(indexKey)) {
      throw StateError('Index already exists for $indexKey');
    }

    final indexDir = Directory('$_basePath/indexes');
    if (!await indexDir.exists()) {
      await indexDir.create(recursive: true);
    }

    final index = await SecondaryIndex.create(
      collection: collection,
      fieldName: fieldName,
      basePath: _basePath,
      storageEngine: _storageEngine,
    );

    _indexes[indexKey] = index;

    await _rebuildIndex(collection, fieldName, index);
  }

  // Drops index
  Future<void> dropIndex(String collection, String fieldName) async {
    final indexKey = '$collection.$fieldName';
    final index = _indexes[indexKey];

    if (index == null) {
      throw StateError('Index does not exist for $indexKey');
    }

    await index.close();
    _indexes.remove(indexKey);

    final indexPath = '$_basePath/indexes/${collection}_$fieldName';
    final indexDir = Directory(indexPath);
    if (await indexDir.exists()) {
      await indexDir.delete(recursive: true);
    }
  }

  // Gets index
  SecondaryIndex? getIndex(String collection, String fieldName) {
    return _indexes['$collection.$fieldName'];
  }

  // Lists indexes
  List<String> listIndexes() {
    return _indexes.keys.toList();
  }

  // Updates indexes on insert
  Future<void> onDocumentInsert(
    String collection,
    String documentId,
    Map<String, dynamic> document,
  ) async {
    for (final entry in _indexes.entries) {
      if (entry.key.startsWith('$collection.')) {
        final fieldName = entry.key.split('.')[1];
        final fieldValue = document[fieldName];

        if (fieldValue != null) {
          await entry.value.addEntry(fieldValue, documentId);
        }
      }
    }
  }

  // Updates indexes on update
  Future<void> onDocumentUpdate(
    String collection,
    String documentId,
    Map<String, dynamic> oldDocument,
    Map<String, dynamic> newDocument,
  ) async {
    for (final entry in _indexes.entries) {
      if (entry.key.startsWith('$collection.')) {
        final fieldName = entry.key.split('.')[1];
        final oldValue = oldDocument[fieldName];
        final newValue = newDocument[fieldName];

        await entry.value.updateEntry(oldValue, newValue, documentId);
      }
    }
  }

  // Updates indexes on delete
  Future<void> onDocumentDelete(
    String collection,
    String documentId,
    Map<String, dynamic> document,
  ) async {
    for (final entry in _indexes.entries) {
      if (entry.key.startsWith('$collection.')) {
        final fieldName = entry.key.split('.')[1];
        final fieldValue = document[fieldName];

        if (fieldValue != null) {
          await entry.value.removeEntry(fieldValue, documentId);
        }
      }
    }
  }

  // Loads indexes
  Future<void> loadIndexes() async {
    final indexDir = Directory('$_basePath/indexes');
    if (!await indexDir.exists()) {
      return;
    }

    await for (final entity in indexDir.list()) {
      if (entity is Directory) {
        final dirName = entity.path.split('/').last;
        final parts = dirName.split('_');

        if (parts.length >= 2) {
          final collection = parts[0];
          final fieldName = parts.sublist(1).join('_');

          try {
            final index = await SecondaryIndex.create(
              collection: collection,
              fieldName: fieldName,
              basePath: _basePath,
              storageEngine: _storageEngine,
            );

            _indexes['$collection.$fieldName'] = index;
          } catch (e) {
            print('Failed to load index $collection.$fieldName: $e');
          }
        }
      }
    }
  }

  // Closes indexes
  Future<void> close() async {
    for (final index in _indexes.values) {
      await index.close();
    }
    _indexes.clear();
  }

  Future<void> _rebuildIndex(
    String collection,
    String fieldName,
    SecondaryIndex index,
  ) async {
    try {
      print('Rebuilding index for $collection.$fieldName...');

      print('Index rebuild skipped');
    } catch (e) {
      print('Failed to rebuild index for $collection.$fieldName: $e');
    }
  }
}
