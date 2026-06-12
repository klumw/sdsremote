import 'package:petitparser/petitparser.dart';

import 'macro_grammar.dart';
import 'macro_lint_error.dart';

/// Runs the macro parser against [source] and returns a list of lint errors.
///
/// Returns an empty list when the source parses successfully. When parsing
/// fails, a single [MacroLintError] is returned whose range spans a single
/// character at the failure position (extended by one so the highlight is
/// visible).
List<MacroLintError> lintMacro(String source) {
  if (source.isEmpty) return [];

  final parser = MacroGrammarDefinition().build();
  final result = parser.parse(source);

  if (result is Failure) {
    final pos = result.position;
    // Clamp end to at least pos+1 so the wavy underline has a pixel span,
    // and no further than text.length.
    final end = (pos + 1 < source.length) ? pos + 1 : source.length;
    // Compute 1-based line number from the character offset.
    final line = _lineAtOffset(source, pos);
    return [
      MacroLintError(message: result.message, start: pos, end: end, line: line),
    ];
  }

  return const [];
}

/// Returns the 1-based line number for character [offset] in [source].
int _lineAtOffset(String source, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < source.length; i++) {
    if (source[i] == '\n') line++;
  }
  return line;
}
