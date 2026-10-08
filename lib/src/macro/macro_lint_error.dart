/// Represents a single syntax error found by the macro linter.
///
/// [start] and [end] are zero-based character offsets into the source text,
/// defining the range that should be visually highlighted. [line] is the
/// 1-based line number for gutter highlighting.
class MacroLintError {
  /// A human-readable description of what went wrong.
  final String message;

  /// Zero-based starting character index of the error location.
  final int start;

  /// Zero-based ending character index (exclusive).
  final int end;

  /// 1-based line number of the error.
  final int line;

  const MacroLintError({
    required this.message,
    required this.start,
    required this.end,
    required this.line,
  });

  @override
  bool operator ==(Object other) =>
      other is MacroLintError &&
      other.message == message &&
      other.start == start &&
      other.end == end &&
      other.line == line;

  @override
  int get hashCode => Object.hash(message, start, end, line);

  @override
  String toString() =>
      'MacroLintError(line: $line, message: "$message", start: $start, end: $end)';
}
