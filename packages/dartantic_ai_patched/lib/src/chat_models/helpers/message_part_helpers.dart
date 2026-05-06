import 'dart:convert';

/// Static helper methods for handling tool results of any type.
class ToolResultHelpers {
  /// Serializes the result to a string representation.
  ///
  /// If the result is already a String, returns it as-is.
  /// Otherwise, encodes it as JSON.
  static String serialize(dynamic result) =>
      result is String ? result : json.encode(result);

  /// Ensures the result is wrapped in a Map&lt;String, dynamic&gt;.
  ///
  /// If the result is already a Map&lt;String, dynamic&gt;, returns it as-is.
  /// Otherwise, wraps it in a map with key 'result'.
  static Map<String, dynamic> ensureMap(dynamic result) {
    // Only return as-is if it's already Map<String, dynamic>
    if (result is Map<String, dynamic>) {
      return result;
    }
    return <String, dynamic>{'result': result};
  }
}
