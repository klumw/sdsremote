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

  // Pre-scan for double negation (`!!`).  The grammar rejects nested NOT
  // expressions, but we provide a specific diagnostic message instead of a
  // generic petitparser failure.
  final doubleNeg = _scanDoubleNegation(source);
  if (doubleNeg != null) return [doubleNeg];

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
/// - Suspicious mixed operator expressions
/// - Redundant parentheses
/// - Chained comparisons
/// - Mixed equality and relational operators
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

  /// True if [op] is a relational operator (>, >=, <, <=).
  bool isRelationalOp(String op) =>
      op == '>' || op == '>=' || op == '<' || op == '<=';

  /// True if [op] is an equality operator (==, !=).
  bool isEqualityOp(String op) => op == '==' || op == '!=';

  /// True if [op] is a logical operator (&&, ||, &, |).
  bool isLogicalOp(String op) =>
      op == '&&' || op == '||' || op == '&' || op == '|';

  /// True if [op] is an arithmetic operator (+, -, *, /).
  bool isArithmeticOp(String op) =>
      op == '+' || op == '-' || op == '*' || op == '/';

  // ── Error reporters ─────────────────────────────────────────────────

  void reportTypeMismatch(String name, String opName, {String? context}) {
    final pos = _nextPos(posMap, nextIdx, name);
    final ctx = context != null ? ' in $context' : '';
    if (pos != null) {
      errors.add(
        MacroLintError(
          message:
              'Variable "$name" holds a string value and cannot be '
              'used with "$opName"$ctx',
          start: pos.$1,
          end: pos.$2,
          line: pos.$3,
        ),
      );
    }
  }

  void reportStringLiteralInCompare(String op) {
    final opKey = '\$op:$op';
    final opIdx = nextIdx[opKey] ?? 0;
    final pattern = RegExp('\\s${RegExp.escape(op)}\\s');
    final matches = pattern.allMatches(source).toList();
    if (opIdx < matches.length) {
      final m = matches[opIdx];
      final line = _lineAtOffset(source, m.start);
      errors.add(
        MacroLintError(
          message:
              'A string literal cannot be used with "$op" '
              '(only numbers can be compared with $op)',
          start: m.start,
          end: m.end,
          line: line,
        ),
      );
    }
    nextIdx[opKey] = opIdx + 1;
  }

  void reportErrorAt(String message, String posKey) {
    final pos = _nextPos(posMap, nextIdx, posKey);
    if (pos != null) {
      errors.add(
        MacroLintError(
          message: message,
          start: pos.$1,
          end: pos.$2,
          line: pos.$3,
        ),
      );
    }
  }

  /// Reports a lint error at a binary operator position, using the
  /// operator length as the end offset.
  void reportAtOp(String message, int opStart, String op) {
    errors.add(
      MacroLintError(
        message: message,
        start: opStart,
        end: opStart + op.length,
        line: _lineAtOffset(source, opStart),
      ),
    );
  }

  // ── Reference checker ───────────────────────────────────────────────

  void checkRef(String name) {
    final idx = nextIdx[name] ?? 0;
    final list = posMap[name];
    final pos = (list != null && idx < list.length) ? list[idx] : null;

    // Consume the position (advance cursor for this identifier).
    _nextPos(posMap, nextIdx, name);

    if (!defined.contains(name) && pos != null) {
      errors.add(
        MacroLintError(
          message: 'Variable "$name" is not defined',
          start: pos.$1,
          end: pos.$2,
          line: pos.$3,
        ),
      );
    }
  }

  // ── String concatenation walker ───────────────────────────────────

  void walkConcat(ConcatString cs) {
    for (final piece in cs.pieces) {
      if (piece case ConcatVarPiece(:final name)) checkRef(name);
    }
  }

  // ── NOT operand check ─────────────────────────────────────────────

  void checkNotOperand(Expr operand) {
    switch (operand) {
      case NumberLiteral():
        final notIdx = (nextIdx['!'] ?? 0);
        final pos = _findNotOperatorPos(source, notIdx);
        if (pos != null) {
          nextIdx['!'] = notIdx + 1;
          errors.add(MacroLintError(
            message:
                "The '!' operator can only be applied to boolean expressions.",
            start: pos.$1,
            end: pos.$2,
            line: pos.$3,
          ));
        }
      case StringLiteral():
        final notIdx = (nextIdx['!'] ?? 0);
        final pos = _findNotOperatorPos(source, notIdx);
        if (pos != null) {
          nextIdx['!'] = notIdx + 1;
          errors.add(MacroLintError(
            message:
                "The '!' operator can only be applied to boolean expressions.",
            start: pos.$1,
            end: pos.$2,
            line: pos.$3,
          ));
        }
      case Variable(:final name):
        if (typeOf(name) == _VarType.numeric) {
          final pos = _nextPos(posMap, nextIdx, name);
          if (pos != null) {
            errors.add(MacroLintError(
              message:
                  "The '!' operator can only be applied to boolean expressions.",
              start: pos.$1,
              end: pos.$2,
              line: pos.$3,
            ));
          }
        }
      case BoolLiteral():
        break;
      case QueryExpr():
      case ScpiExpr():
      case UnaryMinusExpr():
      case NotExpr():
      case BinaryExpr():
        break;
    }
  }

  // ── Numeric comparison check ─────────────────────────────────────

  void checkNumericCompare(Expr lhs, String op, Expr rhs) {
    switch (lhs) {
      case Variable(:final name):
        if (typeOf(name) == _VarType.string) {
          reportTypeMismatch(name, op);
        }
      case StringLiteral():
        reportStringLiteralInCompare(op);
      case QueryExpr():
      case NumberLiteral():
      case BoolLiteral():
      case ScpiExpr():
      case UnaryMinusExpr():
      case NotExpr():
      case BinaryExpr():
        break;
    }

    switch (rhs) {
      case Variable(:final name):
        if (typeOf(name) == _VarType.string) {
          reportTypeMismatch(name, op);
        }
      case StringLiteral():
        reportStringLiteralInCompare(op);
      case NumberLiteral():
      case BoolLiteral():
      case QueryExpr():
      case ScpiExpr():
      case UnaryMinusExpr():
      case NotExpr():
      case BinaryExpr():
        break;
    }
  }

  // ── New lint rule: ComparisonChain ────────────────────────────────

  void checkComparisonChain(BinaryExpr expr) {
    if (!isRelationalOp(expr.op) && !isEqualityOp(expr.op)) return;

    if (expr.left is BinaryExpr) {
      final leftBin = expr.left as BinaryExpr;
      if (isRelationalOp(leftBin.op) || isEqualityOp(leftBin.op)) {
        final pos = _findBinaryOpPos(source, expr.op, nextIdx);
        reportAtOp(
          'Chained comparisons are not supported. '
          'Use explicit logical operators instead '
          '(e.g. "a ${leftBin.op} b && b ${expr.op} c").',
          pos,
          expr.op,
        );
        return;
      }
    }

    if (expr.right is BinaryExpr) {
      final rightBin = expr.right as BinaryExpr;
      if (isRelationalOp(rightBin.op) || isEqualityOp(rightBin.op)) {
        final pos = _findBinaryOpPos(source, expr.op, nextIdx);
        reportAtOp(
          'Chained comparisons are not supported. '
          'Use explicit logical operators instead.',
          pos,
          expr.op,
        );
      }
    }
  }

  // ── New lint rule: MixedEqualityAndRelational ────────────────────

  void checkMixedEqualityRelational(BinaryExpr expr) {
    if (!isEqualityOp(expr.op)) return;

    final hasRelationalChild =
        (expr.left is BinaryExpr &&
            isRelationalOp((expr.left as BinaryExpr).op)) ||
        (expr.right is BinaryExpr &&
            isRelationalOp((expr.right as BinaryExpr).op));

    if (hasRelationalChild) {
      final pos = _findBinaryOpPos(source, expr.op, nextIdx);
      reportAtOp(
        'Mixed equality and relational operators without parentheses '
        'may be confusing.  The expression is evaluated as '
        '"(left ${expr.op} right)" with relational operators binding '
        'first.  Add parentheses to clarify intent.',
        pos,
        expr.op,
      );
    }
  }

  // ── New lint rule: SuspiciousMixedOperators ───────────────────────

  bool hasMixedOps(Expr expr) {
    if (expr is! BinaryExpr) return false;

    final op = expr.op;
    var hasArith = isArithmeticOp(op);
    var hasRel = isRelationalOp(op);
    var hasEq = isEqualityOp(op);

    if (expr.left is BinaryExpr) {
      final child = expr.left as BinaryExpr;
      hasArith = hasArith || isArithmeticOp(child.op);
      hasRel = hasRel || isRelationalOp(child.op);
      hasEq = hasEq || isEqualityOp(child.op);
    }
    if (expr.right is BinaryExpr) {
      final child = expr.right as BinaryExpr;
      hasArith = hasArith || isArithmeticOp(child.op);
      hasRel = hasRel || isRelationalOp(child.op);
      hasEq = hasEq || isEqualityOp(child.op);
    }

    final categories =
        (hasArith ? 1 : 0) + (hasRel ? 1 : 0) + (hasEq ? 1 : 0);
    return categories >= 2;
  }

  void checkSuspiciousMixedOps(BinaryExpr expr) {
    if (!isLogicalOp(expr.op)) return;

    if (hasMixedOps(expr.left) || hasMixedOps(expr.right)) {
      final pos = _findBinaryOpPos(source, expr.op, nextIdx);
      reportAtOp(
        'Suspicious mix of arithmetic, comparison, and logical operators '
        'without clarifying parentheses.  Consider adding parentheses to '
        'make the evaluation order explicit.',
        pos,
        expr.op,
      );
    }
  }

  // ── Expression walker (declared late — uses helpers above) ─────────

  late final void Function(Expr, {required bool allowTruthy}) walkExpr;

  walkExpr = (Expr expr, {required bool allowTruthy}) {
    switch (expr) {
      case NumberLiteral():
      case StringLiteral():
      case BoolLiteral():
        break;

      case Variable(:final name):
        if (!allowTruthy) {
          reportErrorAt(
            'Bare expression "$name" cannot be used as a boolean '
            'condition in if/while — use a comparison like '
            '"$name == value"',
            name,
          );
        }
        checkRef(name);

      case QueryExpr(:final variableName):
        if (!allowTruthy) {
          final displayName = variableName ?? 'query';
          reportErrorAt(
            'Bare expression "query(...)" cannot be used as a boolean '
            'condition in if/while — use a comparison like '
            '"query(...) > value"',
            displayName,
          );
        }
        if (variableName case final v?) checkRef(v);

      case ScpiExpr(:final variableName):
        if (variableName case final v?) checkRef(v);

      case UnaryMinusExpr(:final operand):
        walkExpr(operand, allowTruthy: allowTruthy);

      case NotExpr(:final operand):
        walkExpr(operand, allowTruthy: true);
        checkNotOperand(operand);

      case BinaryExpr(:final left, :final op, :final right):
        // Children of any binary operator are in expression context —
        // the operator itself determines whether the result is boolean.
        walkExpr(left, allowTruthy: true);

        if (isNumericOp(op)) {
          checkNumericCompare(left, op, right);
        }

        walkExpr(right, allowTruthy: true);

        checkComparisonChain(expr);
        checkMixedEqualityRelational(expr);
        checkSuspiciousMixedOps(expr);
    }
  };

  // ── Statement walkers ──────────────────────────────────────────────

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

      case FailStmt(:final concatMessage):
        if (concatMessage != null) walkConcat(concatMessage);

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

      case AssignStmt(:final varName, :final value):
        // Walk the expression RHS for references before adding varName.
        walkExpr(value, allowTruthy: true);

        // Infer the type of the assigned variable.
        if (value is NumberLiteral || value is UnaryMinusExpr) {
          varTypes[varName] = _VarType.numeric;
        } else if (value is StringLiteral) {
          // Quoted number strings like "3.0" are treated as numeric.
          if (double.tryParse(value.value) != null) {
            varTypes[varName] = _VarType.numeric;
          } else {
            varTypes[varName] = _VarType.string;
          }
        } else if (value is BoolLiteral) {
          varTypes[varName] = _VarType.string; // bools stored as strings
        } else if (value is Variable) {
          // Variable copy — inherit the source variable's type.
          varTypes[varName] = typeOf(value.name);
        } else if (value is QueryExpr) {
          // Query results are unknown at lint time.
          varTypes[varName] = _VarType.unknown;
        } else if (value is BinaryExpr) {
          // Arithmetic ops produce numbers; comparison/logical produce
          // boolean strings.
          if (isArithmeticOp(value.op)) {
            varTypes[varName] = _VarType.numeric;
          } else {
            varTypes[varName] = _VarType.string;
          }
        } else {
          varTypes[varName] = _VarType.unknown;
        }
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

      case AssertStmt(:final concatText, :final condition):
        walkExpr(condition, allowTruthy: true);
        if (concatText != null) walkConcat(concatText);

      case LoadProfileStmt(:final concatString):
        if (concatString != null) walkConcat(concatString);

      case IfStmt(:final condition, :final thenBody, :final elseBody):
        walkExpr(condition, allowTruthy: false);
        walkStmts(thenBody);
        if (elseBody != null) walkStmts(elseBody);

      case WhileStmt(:final condition, :final body):
        walkExpr(condition, allowTruthy: false);
        walkStmts(body);
    }
  };

  walkStmts(program.statements);

  // ── RedundantParentheses scan (source-level, not AST) ──────────

  _checkRedundantParentheses(source, errors);

  return errors;
}

// ── New lint rule: RedundantParentheses ──────────────────────────────────

/// Scans [source] for redundant parentheses patterns and adds diagnostics
/// to [errors].
///
/// Detects patterns like `((a))` where double-wrapping is unnecessary.
/// Since the AST flattens parentheses, this check operates on the source
/// text directly using a simple brace-matching scan.
void _checkRedundantParentheses(
    String source, List<MacroLintError> errors) {
  // Find patterns of the form ((...)) where the inner content is a simple
  // expression (single identifier, number, or already-wrapped expr).
  final pattern = RegExp(r'\(\(\s*([a-zA-Z_]\w*|\d+(?:\.\d+)?)\s*\)\)');
  for (final match in pattern.allMatches(source)) {
    // Skip matches inside string literals.
    if (_isInsideString(source, match.start)) continue;

    final line = _lineAtOffset(source, match.start);
    errors.add(
      MacroLintError(
        message:
            'Redundant parentheses detected. Consider writing '
            '"${match.group(1)}" instead of "${match.group(0)}".',
        start: match.start,
        end: match.end,
        line: line,
      ),
    );
  }
}

/// Returns `true` if [offset] falls inside a double-quoted string literal
/// in [source].
bool _isInsideString(String source, int offset) {
  var inString = false;
  for (var i = 0; i < offset && i < source.length; i++) {
    if (source[i] == '"') inString = !inString;
  }
  return inString;
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
  Map<String, List<_Pos>> posMap,
  Map<String, int> nextIdx,
  String name,
) {
  final list = posMap[name];
  if (list == null) return null;
  final idx = nextIdx[name] ?? 0;
  if (idx >= list.length) return null;
  nextIdx[name] = idx + 1;
  return list[idx];
}

/// Finds the position of a binary operator in [source] for error reporting.
///
/// Uses [nextIdx] to track which occurrence of the operator we are on.
/// Handles multi-character operator ambiguity (e.g., `>` must not match
/// inside `>=`, `<` must not match inside `<=`).
int _findBinaryOpPos(
    String source, String op, Map<String, int> nextIdx) {
  final key = '\$binop:$op';
  final idx = nextIdx[key] ?? 0;

  // Build a regex that matches [op] as a standalone operator, not as
  // a prefix of a longer operator.  For example, `>` matches `>` but
  // not the `>` inside `>=`.  Also skip matches inside string literals.
  final escaped = RegExp.escape(op);
  final String regexStr = switch (op) {
    '>' => '$escaped(?!=)',
    '<' => '$escaped(?!=)',
    '!' => '$escaped(?!=)',
    '=' => '$escaped(?!=)',
    '&' => '$escaped(?!&)',
    '|' => r'$escaped(?!\|)', // will be interpolated below
    _ => escaped,
  };
  // Manually handle the | case to avoid raw string interpolation issues.
  final effectiveRegex = op == '|' ? '\\|(?!\\|)' : regexStr;

  final pattern = RegExp(effectiveRegex);
  final allMatches = pattern.allMatches(source).toList();

  // Filter out matches inside string literals.
  final validMatches = allMatches
      .where((m) => !_isInsideString(source, m.start))
      .toList();

  if (idx < validMatches.length) {
    final m = validMatches[idx];
    nextIdx[key] = idx + 1;
    return m.start;
  }
  nextIdx[key] = (nextIdx[key] ?? 0) + 1;
  return 0;
}

/// Returns the 1-based line number for character [offset] in [source].
int _lineAtOffset(String source, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < source.length; i++) {
    if (source[i] == '\n') line++;
  }
  return line;
}

// ── Pre-scanners ─────────────────────────────────────────────────────────

/// Scans [source] line-by-line for an unclosed double-quoted string literal.
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

/// Scans [source] for `!!` (double negation) patterns and returns a
/// [MacroLintError] with a specific diagnostic message. Returns `null`
/// when no double negation is found.
MacroLintError? _scanDoubleNegation(String source) {
  final pattern = RegExp(r'!!+');
  final match = pattern.firstMatch(source);
  if (match == null) return null;
  final line = _lineAtOffset(source, match.start);
  return MacroLintError(
    message: "Double negation is not supported. Remove the extra '!' operator.",
    start: match.start,
    end: match.end,
    line: line,
  );
}

/// Returns the position of the [occurrence]-th `!` character in [source]
/// (0-based), or `null` if fewer than [occurrence] + 1 exist.
_Pos? _findNotOperatorPos(String source, int occurrence) {
  var idx = -1;
  for (var i = 0; i <= occurrence; i++) {
    idx = source.indexOf('!', idx + 1);
    if (idx < 0) return null;
  }
  final line = _lineAtOffset(source, idx);
  return (idx, idx + 1, line);
}
