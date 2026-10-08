import 'package:petitparser/petitparser.dart';

import 'macro_ast.dart';

/// Grammar definition for the SDS Remote macro language.
///
/// Uses [GrammarDefinition] from petitparser for recursive descent parsing.
/// Each production returns the corresponding AST node type.
///
/// ## Operator Precedence (highest to lowest)
///
/// 1. Parentheses                  `()`
/// 2. Unary operators              `!`  `-` (unary minus)
/// 3. Multiplication / Division    `*`  `/`
/// 4. Addition / Subtraction       `+`  `-`
/// 5. Comparisons                  `>`  `>=`  `<`  `<=`
/// 6. Equality                     `==`  `!=`
/// 7. Logical AND                  `&&`
/// 8. Logical OR                   `||`
///
/// Operators on the same level are left-associative.
///
/// ## Expression Grammar
///
/// ```text
/// Expression
///     -> OrExpression
///
/// OrExpression
///     -> AndExpression (('||' | '|') AndExpression)*
///
/// AndExpression
///     -> EqualityExpression (('&&' | '&') EqualityExpression)*
///
/// EqualityExpression
///     -> RelationalExpression (('==' | '!=') RelationalExpression)*
///
/// RelationalExpression
///     -> AdditiveExpression (('>' | '>=' | '<' | '<=') AdditiveExpression)*
///
/// AdditiveExpression
///     -> MultiplicativeExpression (('+' | '-') MultiplicativeExpression)*
///
/// MultiplicativeExpression
///     -> UnaryExpression (('*' | '/') UnaryExpression)*
///
/// UnaryExpression
///     -> '!' UnaryNotOperand
///     -> '-' UnaryExpression
///     -> PrimaryExpression
///
/// UnaryNotOperand
///     -> '-' UnaryExpression
///     -> PrimaryExpression
///
/// PrimaryExpression
///     -> NumberLiteral
///     -> StringLiteral
///     -> BoolLiteral
///     -> query '(' ... ')'
///     -> scpi '(' ... ')'
///     -> Variable
///     -> '(' Expression ')'
/// ```
class MacroGrammarDefinition extends GrammarDefinition {
  const MacroGrammarDefinition();

  @override
  Parser<Program> start() => ref0(program).end();

  // ── Program ─────────────────────────────────────────────────────────

  Parser<Program> program() =>
      ref0(statement).star().map((list) => Program(list.cast<Statement>()));

  // ── Statement dispatcher ────────────────────────────────────────────

  Parser<Statement> statement() => [
    ref0(comment),
    ref0(connectStmt),
    ref0(waitStmt),
    ref0(scpiStmt),
    ref0(queryStmt),
    ref0(assignStmt),
    ref0(printStmt),
    ref0(assertStmt),
    ref0(loadProfileStmt),
    ref0(ifStmt),
    ref0(whileStmt),
    ref0(failStmt),
    ref0(breakStmt),
    ref0(continueStmt),
  ].toChoiceParser().trim();

  // ── Comment ─────────────────────────────────────────────────────────

  Parser<Comment> comment() =>
      (char('#') &
              any().starLazy(newline() | endOfInput()).flatten() &
              (newline() | endOfInput()))
          .map((_) => const Comment());

  // ── connect("ip") | connect(usb) ────────────────────────────────────

  /// Builds a case-insensitive parser for [word].
  Parser<String> _ciKeyword(String word) {
    final chars = word.split('');
    Parser<dynamic> result = _ciChar(chars.first);
    for (var i = 1; i < chars.length; i++) {
      result = result.seq(_ciChar(chars[i]));
    }
    return result.flatten();
  }

  /// Matches a single character case-insensitively.
  Parser<String> _ciChar(String c) {
    final lo = c.toLowerCase();
    final up = c.toUpperCase();
    if (lo == up) return char(c);
    return (char(lo) | char(up)).cast<String>();
  }

  Parser<ConnectStmt> connectStmt() =>
      (_ciKeyword('connect').trim() &
              char('(').trim() &
              (ref0(concatExpr) |
                  ref0(stringLiteral).map((s) => (s, false)) |
                  string('usb').map((_) => (null, false)) |
                  ref0(identifier).map((s) => (s, true))) &
              char(')'))
          .map((r) {
            final arg = r[2];
            if (arg is ConcatString) {
              return ConnectStmt(null, concatString: arg);
            }
            final (argStr, isVar) = arg as (String?, bool);
            if (argStr == null && !isVar) return const ConnectStmt(null); // usb
            return ConnectStmt(argStr, isVariable: isVar);
          });

  // ── wait(seconds) | wait(varName) ──────────────────────────────────

  Parser<WaitStmt> waitStmt() =>
      (string('wait(').trim() & (ref0(number) | ref0(identifier)) & char(')'))
          .map((r) {
            final arg = r[1];
            if (arg is double) {
              return WaitStmt(arg);
            }
            return WaitStmt(0.0, variableName: arg as String);
          });

  // ── scpi("CMD") | scpi(varName) | scpi("str" + var + "str") ───────

  Parser<ScpiStmt> scpiStmt() =>
      (string('scpi(').trim() &
              (ref0(concatExpr) |
                  ref0(stringLiteral).map((s) => (s, false)) |
                  ref0(identifier).map((s) => (s, true))) &
              char(')'))
          .map((r) {
            final arg = r[1];
            if (arg is ConcatString) return ScpiStmt('', concatString: arg);
            final (argStr, isVar) = arg as (String, bool);
            return isVar
                ? ScpiStmt(argStr, variableName: argStr)
                : ScpiStmt(argStr);
          });

  // ── query("CMD") | query(varName) | query("str" + var + "str") ─────

  Parser<QueryStmt> queryStmt() =>
      (string('query(').trim() &
              (ref0(concatExpr) |
                  ref0(stringLiteral).map((s) => (s, false)) |
                  ref0(identifier).map((s) => (s, true))) &
              char(')'))
          .map((r) {
            final arg = r[1];
            if (arg is ConcatString) return QueryStmt('', concatString: arg);
            final (argStr, isVar) = arg as (String, bool);
            return isVar
                ? QueryStmt(argStr, variableName: argStr)
                : QueryStmt(argStr);
          });

  // ── <var> = <expr> ──────────────────────────────────────────────────
  //
  // With the unified expression grammar, any expression is valid on the
  // RHS: literal, variable, query(), arithmetic, comparison, or logical.

  Parser<AssignStmt> assignStmt() =>
      (ref0(identifier) & char('=').trim() & ref0(expression))
          .map((r) => AssignStmt(r[0] as String, r[2] as Expr));

  // ── print(item + item + ...) ────────────────────────────────────────

  Parser<PrintStmt> printStmt() =>
      (string('print(').trim() &
              ref0(printItem) &
              ref0(_printTail).star() &
              char(')').trim())
          .map((r) {
            final first = r[1] as PrintItem;
            final rest = (r[2] as List).cast<PrintItem>();
            return PrintStmt([first, ...rest]);
          });

  Parser<PrintItem> printItem() =>
      [ref0(_textItem), ref0(_queryItem), ref0(_variableItem)].toChoiceParser();

  Parser<PrintItem> _textItem() => ref0(stringLiteral).map((s) => TextItem(s));

  Parser<PrintItem> _queryItem() =>
      (string('query(').trim() &
              (ref0(concatExpr) |
                  ref0(stringLiteral).map((s) => (s, false)) |
                  ref0(identifier).map((s) => (s, true))) &
              char(')'))
          .map((r) {
            final arg = r[1];
            if (arg is ConcatString) return QueryItem('', concatString: arg);
            final (argStr, isVar) = arg as (String, bool);
            return isVar
                ? QueryItem(argStr, variableName: argStr)
                : QueryItem(argStr);
          });

  Parser<PrintItem> _variableItem() =>
      ref0(identifier).map((s) => VariableItem(s));

  Parser<PrintItem> _printTail() =>
      (char('+').trim() & ref0(printItem)).map((r) => r[1] as PrintItem);

  // ── assert("text", <expr>) ──────────────────────────────────────────
  //
  // The second argument is any expression.  The evaluator treats [ScpiExpr]
  // as a success check and everything else as a boolean/truthiness check.

  Parser<AssertStmt> assertStmt() =>
      (string('assert(').trim() &
              (ref0(concatExpr) | ref0(stringLiteral)) &
              char(',').trim() &
              ref0(expression) &
              char(')').trim())
          .map((r) {
            final textArg = r[1];
            if (textArg is ConcatString) {
              return AssertStmt('', r[3] as Expr, concatText: textArg);
            }
            return AssertStmt(textArg as String, r[3] as Expr);
          });

  // ── loadProfile("path") | loadProfile("str" + var + "str") ─────────

  Parser<LoadProfileStmt> loadProfileStmt() =>
      (string('loadProfile(').trim() &
              (ref0(concatExpr) | ref0(stringLiteral)) &
              char(')'))
          .map((r) {
            final arg = r[1];
            if (arg is ConcatString) {
              return LoadProfileStmt('', concatString: arg);
            }
            return LoadProfileStmt(arg as String);
          });

  // ── if (<expr>) { ... } ────────────────────────────────────────────
  // ── if (<expr>) then { ... } ───────────────────────────────────────

  Parser<IfStmt> ifStmt() =>
      (string('if').trim() &
              char('(').trim() &
              ref0(expression) &
              char(')').trim() &
              string('then').trim().optional() &
              char('{').trim() &
              ref0(statement).star() &
              char('}').trim() &
              ref0(_elseBlock).optional())
          .map((r) {
            return IfStmt(
              r[2] as Expr,
              (r[6] as List).cast<Statement>(),
              elseBody: (r[8] as List<Statement>?),
            );
          });

  Parser<List<Statement>> _elseBlock() =>
      (string('else').trim() &
              char('{').trim() &
              ref0(statement).star() &
              char('}'))
          .map((r) => (r[2] as List).cast<Statement>());

  // ── while (<expr>) { ... } ─────────────────────────────────────────

  Parser<WhileStmt> whileStmt() =>
      (string('while').trim() &
              char('(').trim() &
              ref0(expression) &
              char(')').trim() &
              char('{').trim() &
              ref0(statement).star() &
              char('}'))
          .map((r) {
            return WhileStmt(
              r[2] as Expr,
              (r[5] as List).cast<Statement>(),
            );
          });

  // ── break / continue ───────────────────────────────────────────────

  Parser<BreakStmt> breakStmt() =>
      string('break').map((_) => const BreakStmt());
  Parser<ContinueStmt> continueStmt() =>
      string('continue').map((_) => const ContinueStmt());

  // ── fail("message") | fail("str" + var + "str") ────────────────────

  Parser<FailStmt> failStmt() =>
      (string('fail(').trim() &
              (ref0(concatExpr) | ref0(stringLiteral)) &
              char(')'))
          .map((r) {
            final arg = r[1];
            if (arg is ConcatString) {
              return FailStmt('', concatMessage: arg);
            }
            return FailStmt(arg as String);
          });

  // ══════════════════════════════════════════════════════════════════════
  // Unified expression grammar — precedence climbing
  // ══════════════════════════════════════════════════════════════════════

  /// Top-level entry point for expressions.
  Parser<Expr> expression() => ref0(orExpression);

  // ── Level 8: Logical OR (lowest precedence) ─────────────────────────

  Parser<Expr> orExpression() =>
      (ref0(andExpression) & (ref0(_orOp) & ref0(andExpression)).star())
          .map((r) => _buildBinaryChain(r[0] as Expr, r[1] as List));

  // ── Level 7: Logical AND ────────────────────────────────────────────

  Parser<Expr> andExpression() =>
      (ref0(equalityExpression) &
              (ref0(_andOp) & ref0(equalityExpression)).star())
          .map((r) => _buildBinaryChain(r[0] as Expr, r[1] as List));

  // ── Level 6: Equality ───────────────────────────────────────────────

  Parser<Expr> equalityExpression() =>
      (ref0(relationalExpression) &
              (ref0(_equalityOp) & ref0(relationalExpression)).star())
          .map((r) => _buildBinaryChain(r[0] as Expr, r[1] as List));

  // ── Level 5: Relational ─────────────────────────────────────────────

  Parser<Expr> relationalExpression() =>
      (ref0(additiveExpression) &
              (ref0(_relationalOp) & ref0(additiveExpression)).star())
          .map((r) => _buildBinaryChain(r[0] as Expr, r[1] as List));

  // ── Level 4: Additive (+ -) ─────────────────────────────────────────

  Parser<Expr> additiveExpression() =>
      (ref0(multiplicativeExpression) &
              (ref0(_addOp) & ref0(multiplicativeExpression)).star())
          .map((r) => _buildBinaryChain(r[0] as Expr, r[1] as List));

  // ── Level 3: Multiplicative (* /) ───────────────────────────────────

  Parser<Expr> multiplicativeExpression() =>
      (ref0(unaryExpression) &
              (ref0(_mulOp) & ref0(unaryExpression)).star())
          .map((r) => _buildBinaryChain(r[0] as Expr, r[1] as List));

  // ── Level 2: Unary (! -) ────────────────────────────────────────────
  //
  // The NOT operand excludes another NOT to reject `!!` at parse time.
  // Unary minus can be chained (`--5` is allowed).

  Parser<Expr> unaryExpression() => [
    (char('!').trim() & ref0(unaryNotOperand))
        .map((r) => NotExpr(r[1] as Expr)),
    (char('-').trim() & ref0(unaryExpression))
        .map((r) => UnaryMinusExpr(r[1] as Expr)),
    ref0(primaryExpression),
  ].toChoiceParser();

  /// Operand of `!` — excludes another `!` to prevent double negation.
  Parser<Expr> unaryNotOperand() => [
    (char('-').trim() & ref0(unaryExpression))
        .map((r) => UnaryMinusExpr(r[1] as Expr)),
    ref0(primaryExpression),
  ].toChoiceParser();

  // ── Level 1: Primary ────────────────────────────────────────────────

  Parser<Expr> primaryExpression() => [
    ref0(boolLiteral),
    ref0(number).map((n) => NumberLiteral(n)),
    ref0(stringLiteral).map((s) => StringLiteral(s)),
    ref0(_queryExpr),
    ref0(_scpiExpr),
    ref0(identifier).map((name) => Variable(name)),
    (char('(').trim() & ref0(expression) & char(')').trim())
        .map((r) => r[1] as Expr),
  ].toChoiceParser();

  // ── Inline query() and scpi() in expression context ─────────────────

  Parser<Expr> _queryExpr() =>
      (string('query(').trim() &
              (ref0(concatExpr) |
                  ref0(stringLiteral).map((s) => (s, false)) |
                  ref0(identifier).map((s) => (s, true))) &
              char(')'))
          .map((r) {
            final arg = r[1];
            if (arg is ConcatString) return QueryExpr('', concatString: arg);
            final (argStr, isVar) = arg as (String, bool);
            return isVar
                ? QueryExpr(argStr, variableName: argStr)
                : QueryExpr(argStr);
          });

  Parser<Expr> _scpiExpr() =>
      (string('scpi(').trim() &
              (ref0(stringLiteral).map((s) => (s, false)) |
                  ref0(identifier).map((s) => (s, true))) &
              char(')'))
          .map((r) {
            final (arg, isVar) = r[1] as (String, bool);
            return isVar ? ScpiExpr(arg, variableName: arg) : ScpiExpr(arg);
          });

  // ── Boolean literals ────────────────────────────────────────────────

  Parser<Expr> boolLiteral() => [
    string('true').map((_) => const BoolLiteral(true)),
    string('false').map((_) => const BoolLiteral(false)),
  ].toChoiceParser();

  // ── Operator parsers ────────────────────────────────────────────────

  Parser<String> _orOp() =>
      (string('||') | char('|')).trim().map((r) => r.toString());

  Parser<String> _andOp() =>
      (string('&&') | char('&')).trim().map((r) => r.toString());

  Parser<String> _equalityOp() => [
    string('=='),
    string('!='),
  ].toChoiceParser().trim().map((r) => r.toString());

  Parser<String> _relationalOp() => [
    string('<='),
    string('>='),
    char('<'),
    char('>'),
  ].toChoiceParser().trim().map((r) => r.toString());

  Parser<String> _addOp() =>
      (char('+') | char('-')).trim().map((r) => r.toString());

  Parser<String> _mulOp() =>
      (char('*') | char('/')).trim().map((r) => r.toString());

  // ── String concatenation ────────────────────────────────────────────

  /// A concatenated string expression: `"str" + var + "str"` with 2+ pieces.
  Parser<ConcatString> concatExpr() =>
      (ref0(_concatPiece) & (char('+').trim() & ref0(_concatPiece)).plus()).map(
        (r) {
          final first = r[0] as ConcatPiece;
          final rest = (r[1] as List).map((e) => e[1] as ConcatPiece);
          return ConcatString([first, ...rest]);
        },
      );

  Parser<ConcatPiece> _concatPiece() => [
    ref0(stringLiteral).map((s) => ConcatTextPiece(s)),
    ref0(identifier).map((s) => ConcatVarPiece(s)),
  ].toChoiceParser();

  // ── Lexical primitives ──────────────────────────────────────────────

  Parser<String> stringLiteral() =>
      (char('"') & any().starLazy(char('"')).flatten() & char('"')).map(
        (r) => r[1] as String,
      );

  Parser<double> number() =>
      (digit().plus() & (char('.') & digit().plus()).optional()).flatten().map(
        (s) => double.parse(s),
      );

  Parser<String> identifier() => (letter() & word().star()).flatten();
}

// ── Helper ───────────────────────────────────────────────────────────────

/// Builds a left-associative binary expression chain from the initial
/// left operand and a list of `(operator, rightOperand)` pairs.
Expr _buildBinaryChain(Expr left, List pairs) {
  Expr result = left;
  for (final item in pairs) {
    result = BinaryExpr(result, item[0] as String, item[1] as Expr);
  }
  return result;
}
