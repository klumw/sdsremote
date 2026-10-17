/// Transport seam for the JDS6600.
///
/// This file deliberately imports neither Flutter nor libserialport so unit
/// tests can use a fake transport without loading the native library.
library;

/// Narrow transport interface.
abstract class Jds6600Transport {
  Future<void> open();

  Future<void> close();

  bool get isOpen;

  /// Sends one command and waits for [count] matching response lines.
  ///
  /// [accept] may discard stale lines (for example a late reply from a
  /// previous transaction) until a matching line arrives or the timeout
  /// expires.
  Future<List<String>> transactMany(
    String command, {
    required int count,
    Duration timeout = const Duration(milliseconds: 1000),
    bool Function(String line)? accept,
  });

  /// Convenience wrapper for single-line transactions.
  Future<String> transact(
    String command, {
    Duration timeout = const Duration(milliseconds: 1000),
    bool Function(String line)? accept,
  }) async {
    final lines = await transactMany(
      command,
      count: 1,
      timeout: timeout,
      accept: accept,
    );
    return lines.single;
  }
}
