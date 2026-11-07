/// Strict JSON helpers for the planner data contracts.
///
/// The planner does not use generated serialization code. Every model parses
/// its wire representation explicitly so malformed model or session input
/// fails with a deterministic, testable error instead of a silent default.
library;

/// Thrown when a planner JSON payload does not match its contract.
class PlannerFormatException implements Exception {
  const PlannerFormatException(this.field, this.expected, this.actual);

  /// JSON path of the offending value, for example `safetyHints.coupling`.
  final String field;

  /// Human-readable description of the accepted shape.
  final String expected;

  /// The rejected value.
  final Object? actual;

  @override
  String toString() =>
      'PlannerFormatException($field): expected $expected, got $actual';
}

/// Reads a required JSON object.
///
/// A [Map] with non-string keys is rejected so a malformed payload cannot
/// silently lose or rename an entry.
Map<String, dynamic> requireJsonMap(Object? value, String field) {
  if (value is! Map) {
    throw PlannerFormatException(field, 'object', value);
  }
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw PlannerFormatException('$field.<key>', 'string keys', key);
    }
    result[key] = entry.value;
  }
  return result;
}

/// Reads an optional JSON object.
Map<String, dynamic>? optionalJsonMap(Object? value, String field) {
  if (value == null) return null;
  return requireJsonMap(value, field);
}

/// Reads a required JSON string.
String requireJsonString(Object? value, String field) {
  if (value is String) return value;
  throw PlannerFormatException(field, 'string', value);
}

/// Reads an optional JSON string.
String? optionalJsonString(Object? value, String field) {
  if (value == null) return null;
  if (value is String) return value;
  throw PlannerFormatException(field, 'string', value);
}

/// Reads an optional JSON number.
double? optionalJsonDouble(Object? value, String field) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw PlannerFormatException(field, 'number', value);
}

/// Reads a required JSON number.
double requireJsonDouble(Object? value, String field) {
  final number = optionalJsonDouble(value, field);
  if (number == null) {
    throw PlannerFormatException(field, 'number', value);
  }
  return number;
}

/// Reads an optional JSON integer.
int? optionalJsonInt(Object? value, String field) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double && value == value.roundToDouble()) return value.toInt();
  throw PlannerFormatException(field, 'integer', value);
}

/// Reads an optional JSON boolean.
bool? optionalJsonBool(Object? value, String field) {
  if (value == null) return null;
  if (value is bool) return value;
  throw PlannerFormatException(field, 'boolean', value);
}

/// Reads an optional JSON array.
List<Object?>? optionalJsonList(Object? value, String field) {
  if (value == null) return null;
  if (value is List) return List<Object?>.of(value);
  throw PlannerFormatException(field, 'array', value);
}

/// Reads a required JSON array.
List<Object?> requireJsonList(Object? value, String field) {
  final list = optionalJsonList(value, field);
  if (list == null) {
    throw PlannerFormatException(field, 'array', value);
  }
  return list;
}

/// Reads an optional array of strings.
List<String>? optionalJsonStringList(Object? value, String field) {
  final list = optionalJsonList(value, field);
  if (list == null) return null;
  final result = <String>[];
  for (var index = 0; index < list.length; index++) {
    final entry = list[index];
    if (entry is! String) {
      throw PlannerFormatException('$field[$index]', 'string', entry);
    }
    result.add(entry);
  }
  return result;
}

/// Reads a required array of strings.
List<String> requireJsonStringList(Object? value, String field) {
  final list = optionalJsonStringList(value, field);
  if (list == null || list.isEmpty) {
    throw PlannerFormatException(field, 'non-empty array of strings', value);
  }
  return list;
}

/// Reads an optional map with JSON-safe values.
Map<String, Object?>? optionalJsonValueMap(Object? value, String field) {
  final map = optionalJsonMap(value, field);
  if (map == null) return null;
  return map.map((key, entry) => MapEntry(key, jsonSafe(entry, '$field.$key')));
}

/// Converts [value] into a JSON-safe tree.
///
/// Rejects values that `jsonEncode` would drop or transform silently.
Object? jsonSafe(Object? value, String field) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw PlannerFormatException('$field.<key>', 'string keys', key);
      }
      result[key] = jsonSafe(entry.value, '$field.$key');
    }
    return result;
  }
  if (value is Iterable) {
    final result = <Object?>[];
    var index = 0;
    for (final entry in value) {
      result.add(jsonSafe(entry, '$field[${index++}]'));
    }
    return result;
  }
  throw PlannerFormatException(field, 'JSON value', value);
}
