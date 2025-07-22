import '../indexing/index_manager.dart';
import '../indexing/secondary_index.dart';
import '../../reaxdb.dart';

/// Operators available for database queries.
enum QueryOperator {
  equals,
  notEquals,
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  between,
  inList,
  contains,
}

/// Represents a single condition in a database query.
class QueryCondition {
  final String field;
  final QueryOperator operator;
  final dynamic value;

  QueryCondition({
    required this.field,
    required this.operator,
    required this.value,
  });
}

/// Fluent interface for building and executing database queries.
///
/// Provides methods for filtering, sorting, and limiting query results.
/// Automatically uses secondary indexes when available for optimal performance.
class QueryBuilder {
  final String collection;
  final ReaxDB _db;
  final IndexManager _indexManager;
  final List<QueryCondition> _conditions = [];
  int? _limitValue;
  int? _offsetValue;
  String? _orderByField;
  bool _orderDescending = false;

  /// Creates a new query builder for the specified collection.
  QueryBuilder({
    required this.collection,
    required ReaxDB db,
    required IndexManager indexManager,
  }) : _db = db,
       _indexManager = indexManager;

  /// Adds a condition to the query.
  ///
  /// [field] is the document field to filter on.
  /// [operator] specifies the comparison operation.
  /// [value] is the value to compare against.
  QueryBuilder where(String field, QueryOperator operator, dynamic value) {
    _conditions.add(
      QueryCondition(field: field, operator: operator, value: value),
    );
    return this;
  }

  /// Adds an equality condition to the query.
  QueryBuilder whereEquals(String field, dynamic value) {
    return where(field, QueryOperator.equals, value);
  }

  // Where greater than
  QueryBuilder whereGreaterThan(String field, dynamic value) {
    return where(field, QueryOperator.greaterThan, value);
  }

  // Where less than
  QueryBuilder whereLessThan(String field, dynamic value) {
    return where(field, QueryOperator.lessThan, value);
  }

  // Where between
  QueryBuilder whereBetween(String field, dynamic start, dynamic end) {
    return where(field, QueryOperator.between, [start, end]);
  }

  // Where in
  QueryBuilder whereIn(String field, List<dynamic> values) {
    return where(field, QueryOperator.inList, values);
  }

  /// Specifies the field to sort results by.
  ///
  /// [field] is the field name to sort on.
  /// [descending] determines sort order (default is ascending).
  QueryBuilder orderBy(String field, {bool descending = false}) {
    _orderByField = field;
    _orderDescending = descending;
    return this;
  }

  /// Limits the number of results returned.
  QueryBuilder limit(int count) {
    _limitValue = count;
    return this;
  }

  /// Skips the specified number of results.
  QueryBuilder offset(int count) {
    _offsetValue = count;
    return this;
  }

  /// Executes the query and returns all matching documents.
  Future<List<Map<String, dynamic>>> find() async {
    Set<String> candidateIds = {};
    bool hasIndexedQuery = false;

    for (final condition in _conditions) {
      final index = _indexManager.getIndex(collection, condition.field);

      if (index != null && _canUseIndex(condition)) {
        hasIndexedQuery = true;
        final indexResults = await _queryIndex(index, condition);

        if (candidateIds.isEmpty) {
          candidateIds = indexResults.toSet();
        } else {
          candidateIds = candidateIds.intersection(indexResults.toSet());
        }

        if (candidateIds.isEmpty) {
          return [];
        }
      }
    }

    if (!hasIndexedQuery) {
      if (_orderByField != null &&
          _indexManager.getIndex(collection, _orderByField!) != null) {
        final index = _indexManager.getIndex(collection, _orderByField!)!;

        candidateIds = (await index.findRange(null, null)).toSet();
      } else {
        print('Query without index not implemented');
        return [];
      }
    }

    final results = <Map<String, dynamic>>[];

    for (final docId in candidateIds) {
      final doc = await _loadDocument(docId);

      if (doc != null && _matchesAllConditions(doc)) {
        results.add(doc);
      }
    }

    if (_orderByField != null) {
      _sortResults(results);
    }

    final start = _offsetValue ?? 0;
    final end = _limitValue != null ? start + _limitValue! : results.length;

    return results.sublist(
      start.clamp(0, results.length),
      end.clamp(0, results.length),
    );
  }

  /// Executes the query and returns the first matching document.
  Future<Map<String, dynamic>?> findOne() async {
    final results = await limit(1).find();
    return results.isEmpty ? null : results.first;
  }

  /// Counts the number of documents matching the query.
  Future<int> count() async {
    final results = await find();
    return results.length;
  }

  bool _canUseIndex(QueryCondition condition) {
    switch (condition.operator) {
      case QueryOperator.equals:
      case QueryOperator.greaterThan:
      case QueryOperator.greaterThanOrEqual:
      case QueryOperator.lessThan:
      case QueryOperator.lessThanOrEqual:
      case QueryOperator.between:
        return true;
      default:
        return false;
    }
  }

  Future<List<String>> _queryIndex(
    SecondaryIndex index,
    QueryCondition condition,
  ) async {
    switch (condition.operator) {
      case QueryOperator.equals:
        return index.findEquals(condition.value);

      case QueryOperator.greaterThan:
      case QueryOperator.greaterThanOrEqual:
        return index.findRange(
          condition.value,
          null,
          includeStart: condition.operator == QueryOperator.greaterThanOrEqual,
        );

      case QueryOperator.lessThan:
      case QueryOperator.lessThanOrEqual:
        return index.findRange(
          null,
          condition.value,
          includeEnd: condition.operator == QueryOperator.lessThanOrEqual,
        );

      case QueryOperator.between:
        if (condition.value is List && condition.value.length == 2) {
          return index.findRange(
            condition.value[0],
            condition.value[1],
            includeStart: true,
            includeEnd: true,
          );
        }
        return [];

      default:
        return [];
    }
  }

  Future<Map<String, dynamic>?> _loadDocument(String docId) async {
    final key = '$collection:$docId';
    return await _db.get<Map<String, dynamic>>(key);
  }

  bool _matchesAllConditions(Map<String, dynamic> doc) {
    for (final condition in _conditions) {
      if (!_matchesCondition(doc, condition)) {
        return false;
      }
    }
    return true;
  }

  bool _matchesCondition(Map<String, dynamic> doc, QueryCondition condition) {
    final fieldValue = doc[condition.field];

    switch (condition.operator) {
      case QueryOperator.equals:
        return fieldValue == condition.value;

      case QueryOperator.notEquals:
        return fieldValue != condition.value;

      case QueryOperator.greaterThan:
        return _compare(fieldValue, condition.value) > 0;

      case QueryOperator.greaterThanOrEqual:
        return _compare(fieldValue, condition.value) >= 0;

      case QueryOperator.lessThan:
        return _compare(fieldValue, condition.value) < 0;

      case QueryOperator.lessThanOrEqual:
        return _compare(fieldValue, condition.value) <= 0;

      case QueryOperator.between:
        if (condition.value is List && condition.value.length == 2) {
          return _compare(fieldValue, condition.value[0]) >= 0 &&
              _compare(fieldValue, condition.value[1]) <= 0;
        }
        return false;

      case QueryOperator.inList:
        return (condition.value as List).contains(fieldValue);

      case QueryOperator.contains:
        if (fieldValue is String && condition.value is String) {
          return fieldValue.contains(condition.value);
        }
        return false;
    }
  }

  int _compare(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;

    if (a is num && b is num) {
      return a.compareTo(b);
    }

    return a.toString().compareTo(b.toString());
  }

  void _sortResults(List<Map<String, dynamic>> results) {
    results.sort((a, b) {
      final aValue = a[_orderByField!];
      final bValue = b[_orderByField!];

      final comparison = _compare(aValue, bValue);
      return _orderDescending ? -comparison : comparison;
    });
  }
}
