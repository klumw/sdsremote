import 'package:petitparser/petitparser.dart';

import 'macro_ast.dart';
import 'macro_grammar.dart';
import 'macro_lint_error.dart';

/// Runs the macro parser against [source] and returns a list of lint errors.
///
/// Returns an empty list when the source parses successfully with no semantic
/// issues. When parsing fails, a single [MacroLintError] is returned. When
/// parsing succeeds but semantic issues are detected (undefined variables,
/// non-numeric comparisons with >/>=/</<=), one error per issue is returned.
List<MacroLintError> lintMacro(String source) {
  if (source.isEmpty) return [];

  // Pre-scan for unclosed double-quoted string literals.  When petitparser
  // backtracks on a missing closing `"`, the original position is lost and
  // the top-level `end()` reports "end of input expected" at offset 0.
  // Detecting unclosed strings before parsing gives precise line/column info.
  final unclosed = _scanUnclosedStrings(source);
  if (unclosed != null) return [unclosed];

  final parser = MacroGrammarDefinition().build();
  final result = parser.parse(source);

  if (result is Failure) {
    final pos = result.position;
    final end = (pos + 1 < source.length) ? pos + 1 : source.length;
    final line = _lineAtOffset(source, pos);
    return [
      MacroLintError(message: result.message, start: pos, end: end, line: line),
    ];
  }

  final program = result.value as Program;
  return _checkSemantics(source, program);
}

// ── Type tracking for linter ─────────────────────────────────────────────

/// Tracks the statically-inferred type of a variable.
enum _VarType { numeric, string, unknown }

/// Walks the AST statement-by-statement, tracking defined variables and their
/// inferred types, and returns lint errors for:
/// - References to undefined variables
/// - Non-numeric comparisons using `>`, `>=`, `<`, `<=`
List<MacroLintError> _checkSemantics(String source, Program program) {
  final errors = <MacroLintError>[];
  final defined = <String>{};
  final varTypes = <String, _VarType>{};

  // Pre-compute all identifier positions so we can consume them in source
  // order during the walk, giving each reference the correct line number.
  final posMap = _buildPositionMap(source);
  final nextIdx = <String, int>{};

  /// Returns the inferred type of [name], or `unknown` if not tracked.
  _VarType typeOf(String name) => varTypes[name] ?? _VarType.unknown;

  /// True if [op] is a numeric-only comparison operator.
  bool isNumericOp(String? op) =>
      op == '>' || op == '>=' || op == '<' || op == '<=';

  // ── Error reporters ─────────────────────────────────────────────────

  void reportTypeMismatch(String name, String opName, {String? context}) {
    final pos = _nextPos(posMap, nextIdx, name);
    final ctx = context != null ? ' in $context' : '';
    if (pos != null) {
      errors.add(MacroLintError(
        message: 'Variable "$name" holds a string value and cannot be '
            'used with "$opName"$ctx',
        start: pos.$1,
        end: pos.$2,
        line: pos.$3,
      ));
    }
  }

  void reportStringLiteralInCompare(String op) {
    // Use nextIdx to track which comparison operator occurrence we are on
    // so we report the correct line when there are multiple comparisons.
    final opKey = '\$op:$op';
    final opIdx = nextIdx[opKey] ?? 0;
    final pattern = RegExp('\\s${RegExp.escape(op)}\\s');
    final matches = pattern.allMatches(source).toList();
    if (opIdx < matches.length) {
      final m = matches[opIdx];
      final line = _lineAtOffset(source, m.start);
      errors.add(MacroLintError(
        message: 'A string literal cannot be used with "$op" '
            '(only numbers can be compared with $op)',
        start: m.start,
        end: m.end,
        line: line,
      ));
    }
    nextIdx[opKey] = opIdx + 1;
  }

  // ── Reference checker ───────────────────────────────────────────────

  /// Checks whether [name] is defined and consumes its next source
  /// position from [posMap] so that subsequent reports for the same
  /// identifier use the correct later occurrence.
  void checkRef(String name) {
    // Peek at the next position before consuming it, so we can report
    // the error at the correct location.
    final idx = nextIdx[name] ?? 0;
    final list = posMap[name];
    final pos = (list != null && idx < list.length) ? list[idx] : null;

    // Consume the position (advance cursor for this identifier).
    _nextPos(posMap, nextIdx, name);

    if (!defined.contains(name) && pos != null) {
      errors.add(MacroLintError(
        message: 'Variable "$name" is not defined',
        start: pos.$1,
        end: pos.$2,
        line: pos.$3,
      ));
    }
  }

  // ── Expression walkers ──────────────────────────────────────────────

  void walkExpr(Expression expr) {
    switch (expr) {
      case VariableExpr(:final name):
        checkRef(name);
      case QueryExpr(:final variableName):
        if (variableName case final v?) checkRef(v);
      case ScpiExpr(:final variableName):
        if (variableName case final v?) checkRef(v);
    }
  }

  void walkConcat(ConcatString cs) {
    for (final piece in cs.pieces) {
      if (piece case ConcatVarPiece(:final name)) checkRef(name);
    }
  }

  void walkArith(ArithExpr expr) {
    switch (expr) {
      case ArithVariable(:final name):
        checkRef(name);
      case ArithQuery(:final variableName):
        if (variableName case final v?) checkRef(v);
      case ArithBinaryOp(:final left, :final right):
        walkArith(left);
        walkArith(right);
      case ArithNumber():
        break;
    }
  }

  /// Checks a comparison `lhs op rhs` where [op] is `>`, `>=`, `<`, or `<=`.
  /// Reports an error if either side is known to be non-numeric.
  void checkNumericCompare(
    Expression operand,
    String op,
    String rhsValue,
    bool rhsIsVariable,
  ) {
    // Check left-hand side (operand).
    switch (operand) {
      case VariableExpr(:final name):
        switch (typeOf(name)) {
          case _VarType.string:
            reportTypeMismatch(name, op);
          case _VarType.numeric:
          case _VarType.unknown:
            break; // OK or can't determine statically
        }
      case QueryExpr():
        break; // query result is unknown — could be numeric
      case ScpiExpr():
        break; // scpi has no return value, but this case is unlikely
    }

    // Check right-hand side (comparison value).
    if (rhsIsVariable) {
      switch (typeOf(rhsValue)) {
        case _VarType.string:
          reportTypeMismatch(rhsValue, op);
        case _VarType.numeric:
        case _VarType.unknown:
          break;
      }
    } else {
      // RHS is a literal. If it can't be parsed as a number, it's a string
      // literal being used in a numeric comparison.
      if (double.tryParse(rhsValue) == null) {
        reportStringLiteralInCompare(op);
      }
    }
  }

  // ── Statement walkers (mutually recursive) ──────────────────────────

  late final void Function(List<Statement>) walkStmts;
  late final void Function(Statement) walkStmt;

  walkStmts = (List<Statement> stmts) {
    for (final stmt in stmts) {
      walkStmt(stmt);
    }
  };

  walkStmt = (Statement stmt) {
    switch (stmt) {
      case Comment():
      case BreakStmt():
      case ContinueStmt():
        break;

      case ConnectStmt(:final isVariable, :final ip, :final concatString):
        if (concatString != null) {
          walkConcat(concatString);
        } else if (isVariable && ip != null) {
          checkRef(ip);
        }

      case WaitStmt(:final variableName):
        if (variableName case final v?) checkRef(v);

      case ScpiStmt(:final variableName, :final concatString):
        if (concatString != null) {
          walkConcat(concatString);
        } else if (variableName case final v?) {
          checkRef(v);
        }

      case QueryStmt(:final variableName, :final concatString):
        if (concatString != null) {
          walkConcat(concatString);
        } else if (variableName case final v?) {
          checkRef(v);
        }

      case AssignStmt(:final varName, :final arithExpr, :final isVariable,
                       :final isQuery, :final queryOrValue,
                       :final concatString):
        // Check references on the RHS before adding varName to defined.
        if (arithExpr != null) {
          walkArith(arithExpr);
          // Arithmetic results are always numeric.
          varTypes[varName] = _VarType.numeric;
        } else if (isQuery) {
          if (concatString != null) walkConcat(concatString);
          if (isVariable) checkRef(queryOrValue);
          // Query results are unknown at lint time.
          varTypes[varName] = _VarType.unknown;
        } else {
          // Non-query assignment: could be number, string literal, or
          // variable copy. The AST doesn't distinguish these, so we use
          // heuristics.
          if (double.tryParse(queryOrValue) != null) {
            varTypes[varName] = _VarType.numeric;
          } else if (defined.contains(queryOrValue)) {
            // Variable copy — inherit the source variable's type.
            varTypes[varName] = typeOf(queryOrValue);
          } else {
            // Assume string literal.
            varTypes[varName] = _VarType.string;
          }
        }
        if (concatString != null) walkConcat(concatString);
        defined.add(varName);

      case PrintStmt(:final items):
        for (final item in items) {
          switch (item) {
            case VariableItem(:final name):
              checkRef(name);
            case QueryItem(:final variableName, :final concatString):
              if (concatString != null) {
                walkConcat(concatString);
              } else if (variableName case final v?) {
                checkRef(v);
              }
            case TextItem():
              break;
          }
        }

      case AssertStmt(:final operand, :final op, :final expectedValue,
                       :final expectedIsVariable, :final concatText):
        walkExpr(operand);
        if (expectedIsVariable && expectedValue != null) {
          checkRef(expectedValue);
        }
        if (concatText != null) walkConcat(concatText);
        // Type-check numeric comparisons.
        if (isNumericOp(op) && expectedValue != null) {
          checkNumericCompare(operand, op!, expectedValue, expectedIsVariable);
        }

      case LoadProfileStmt(:final concatString):
        if (concatString != null) walkConcat(concatString);

      case IfStmt(:final condition, :final op, :final value,
                   :final valueIsVariable, :final thenBody,
                   :final elseBody):
        walkExpr(condition);
        if (valueIsVariable) checkRef(value);
        // Type-check numeric comparisons.
        if (isNumericOp(op)) {
          checkNumericCompare(condition, op, value, valueIsVariable);
        }
        walkStmts(thenBody);
        if (elseBody != null) walkStmts(elseBody);

      case WhileStmt(:final condition, :final op, :final value,
                      :final valueIsVariable, :final body):
        walkExpr(condition);
        if (valueIsVariable) checkRef(value);
        // Type-check numeric comparisons.
        if (isNumericOp(op)) {
          checkNumericCompare(condition, op, value, valueIsVariable);
        }
        walkStmts(body);
    }
  };

  walkStmts(program.statements);
  return errors;
}

// ── Position tracking ────────────────────────────────────────────────────

typedef _Pos = (int, int, int); // (start, end, line)

/// Builds a map from identifier name to the ordered list of all its
/// occurrences in [source], excluding identifiers inside double-quoted
/// string literals. Each entry is `(start, end, line)`.
Map<String, List<_Pos>> _buildPositionMap(String source) {
  final map = <String, List<_Pos>>{};
  final regex = RegExp(r'\b[a-zA-Z_]\w*\b');

  // Split by `"` — even-indexed segments are outside quotes, odd-indexed
  // segments are inside string literals and should be skipped.
  final segments = source.split('"');
  var offset = 0;
  for (var i = 0; i < segments.length; i++) {
    if (i.isEven) {
      for (final match in regex.allMatches(segments[i])) {
        final name = match.group(0)!;
        final start = offset + match.start;
        final end = offset + match.end;
        final line = _lineAtOffset(source, start);
        (map[name] ??= []).add((start, end, line));
      }
    }
    // Advance past this segment and the closing quote (if not the last).
    offset += segments[i].length + (i < segments.length - 1 ? 1 : 0);
  }
  return map;
}

/// Returns the next occurrence position for [name] from [posMap], advancing
/// the per-name cursor tracked in [nextIdx]. Returns `null` if no more
/// occurrences exist.
_Pos? _nextPos(
    Map<String, List<_Pos>> posMap, Map<String, int> nextIdx, String name) {
  final list = posMap[name];
  if (list == null) return null;
  final idx = nextIdx[name] ?? 0;
  if (idx >= list.length) return null;
  nextIdx[name] = idx + 1;
  return list[idx];
}

/// Returns the 1-based line number for character [offset] in [source].
int _lineAtOffset(String source, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < source.length; i++) {
    if (source[i] == '\n') line++;
  }
  return line;
}

/// Scans [source] line-by-line for an unclosed double-quoted string literal.
///
/// Since macro statements are line-oriented, a line with an odd number of
/// `"` characters has an unclosed string.  The function returns a
/// [MacroLintError] pointing at the first `"` on the first such line, or
/// `null` when every line has balanced quotes.
MacroLintError? _scanUnclosedStrings(String source) {
  final lines = source.split('\n');
  var offset = 0;
  for (var lineNum = 0; lineNum < lines.length; lineNum++) {
    final line = lines[lineNum];
    var quoteCount = 0;
    var firstQuoteCol = -1;
    for (var col = 0; col < line.length; col++) {
      if (line[col] == '"') {
        if (firstQuoteCol < 0) firstQuoteCol = col;
        quoteCount++;
      }
    }
    if (quoteCount.isOdd && firstQuoteCol >= 0) {
      final start = offset + firstQuoteCol;
      final end = (start + 1 < source.length) ? start + 1 : source.length;
      return MacroLintError(
        message: 'Unclosed string literal (missing closing ")',
        start: start,
        end: end,
        line: lineNum + 1,
      );
    }
    offset += line.length + 1; // +1 for the '\n' split delimiter
  }
  return null;
}
