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
///     -> cmd '(' ... ')'
///     -> connect '(' ... ')'
///     -> Variable
///     -> '(' Expression ')'
/// ```
class MacroGrammarDefinition extends GrammarDefinition {
  /// Optional callback invoked for every parsed statement with its start and
  /// stop offsets in the source.
  ///
  /// The evaluator uses it to map AST statements to source lines, which the
  /// Macro Editor debugger needs for breakpoints and current-line
  /// highlighting.
  final void Function(Statement statement, int start, int stop)? onStatement;

  const MacroGrammarDefinition({this.onStatement});

  @override
  Parser<Program> start() => ref0(program).end();

  // ── Program ─────────────────────────────────────────────────────────

  Parser<Program> program() =>
      ref0(statement).star().map((list) => Program(list.cast<Statement>()));

  // ── Statement dispatcher ────────────────────────────────────────────

  Parser<Statement> statement() {
    final parser = [
      ref0(comment),
      ref0(connectStmt),
      ref0(waitStmt),
      ref0(cmdStmt),
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

    final onStatement = this.onStatement;
    if (onStatement == null) return parser;

    return parser.token().map((token) {
      onStatement(token.value, token.start, token.stop);
      return token.value;
    });
  }

  // ── Comment ─────────────────────────────────────────────────────────

  Parser<Comment> comment() =>
      (char('#') &
              any().starLazy(newline() | endOfInput()).flatten() &
              (newline() | endOfInput()))
          // A fresh instance per comment keeps the statement→line map
          // accurate; const constructor calls would share one instance.
          .map((_) => Comment());

  // ── Device selector ─────────────────────────────────────────────────
  //
  // `SIG` addresses the signal generator configured in the settings; any
  // other identifier names a variable that holds a device handle opened by
  // `myscope = connect("192.168.1.100")`. Commands without a selector keep
  // addressing the default oscilloscope connection:
  //
  //   connect(SIG, usb)   cmd(SIG, "…")   cmd(myscope, "…")
  //
  // The selector is only recognized together with its trailing comma, so a
  // variable named `sig` still works in the one-argument forms.

  /// Matches the `SIG` selector (case-insensitive) and its trailing comma.
  Parser<String> _siggenSelector() =>
      (_ciKeyword(macroSignalGeneratorDevice) & char(',').trim()).map(
        (_) => macroSignalGeneratorDevice,
      );

  /// Matches a device selector and its trailing comma.
  ///
  /// `SIG` (any capitalization) selects the signal generator; every other
  /// identifier is a variable holding a device handle.
  Parser<String> deviceSelector() => (ref0(identifier) & char(',').trim()).map(
    (r) => _normalizeDeviceSelector(r[0] as String),
  );

  /// Maps the case-insensitive `SIG` keyword to the canonical selector.
  String _normalizeDeviceSelector(String selector) =>
      selector.toUpperCase() == macroSignalGeneratorDevice
      ? macroSignalGeneratorDevice
      : selector;

  /// Adds an optional device selector to [target].
  ///
  /// [selector] overrides the default selector grammar; `connect()` uses it
  /// to accept only the `SIG` keyword as its first argument.
  Parser<_DeviceArg> _withDeviceSelector(
    Parser<_DeviceArg> target, {
    Parser<String>? selector,
  }) => [
    ((selector ?? ref0(deviceSelector)) & target).map(
      (r) => (r[1] as _DeviceArg).withDevice(r[0] as String),
    ),
    target,
  ].toChoiceParser();

  // ── connect("ip") | connect(usb) | connect(SIG, usb) ───────────────

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
              ref0(_connectArgs) &
              char(')'))
          .map((r) {
            final arg = r[2] as _DeviceArg;
            if (arg.concatString != null) {
              return ConnectStmt(
                null,
                device: arg.device,
                concatString: arg.concatString,
              );
            }
            if (arg.text == null) {
              return ConnectStmt(null, device: arg.device); // usb
            }
            return ConnectStmt(
              arg.text,
              device: arg.device,
              isVariable: arg.isVariable,
            );
          });

  Parser<_DeviceArg> _connectArgs() => _withDeviceSelector(
    ref0(_connectTarget),
    selector: ref0(_siggenSelector),
  );

  Parser<_DeviceArg> _connectTarget() => [
    ref0(concatExpr).map((c) => _DeviceArg(concatString: c)),
    ref0(stringLiteral).map((s) => _DeviceArg(text: s)),
    string('usb').map((_) => const _DeviceArg()),
    ref0(identifier).map((s) => _DeviceArg(text: s, isVariable: true)),
  ].toChoiceParser();

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

  // ── cmd("CMD") | cmd(varName) | cmd("str" + var + "str") ─────────
  // ── cmd(SIG, <same argument forms>) ───────────────────────────────

  Parser<ScpiStmt> cmdStmt() =>
      (string('cmd(').trim() & ref0(_textArgs) & char(')')).map((r) {
        final arg = r[1] as _DeviceArg;
        if (arg.concatString != null) {
          return ScpiStmt(
            '',
            device: arg.device,
            concatString: arg.concatString,
          );
        }
        final text = arg.text!;
        return arg.isVariable
            ? ScpiStmt(text, device: arg.device, variableName: text)
            : ScpiStmt(text, device: arg.device);
      });

  /// A text argument with an optional `SIG` selector.
  Parser<_DeviceArg> _textArgs() => _withDeviceSelector(ref0(_textTarget));

  Parser<_DeviceArg> _textTarget() => [
    ref0(concatExpr).map((c) => _DeviceArg(concatString: c)),
    ref0(stringLiteral).map((s) => _DeviceArg(text: s)),
    ref0(identifier).map((s) => _DeviceArg(text: s, isVariable: true)),
  ].toChoiceParser();

  // ── query("CMD") | query(varName) | query("str" + var + "str") ─────
  // ── query(SIG, <same argument forms>) ─────────────────────────────

  Parser<QueryStmt> queryStmt() =>
      (string('query(').trim() & ref0(_textArgs) & char(')')).map((r) {
        final arg = r[1] as _DeviceArg;
        if (arg.concatString != null) {
          return QueryStmt(
            '',
            device: arg.device,
            concatString: arg.concatString,
          );
        }
        final text = arg.text!;
        return arg.isVariable
            ? QueryStmt(text, device: arg.device, variableName: text)
            : QueryStmt(text, device: arg.device);
      });

  // ── <var> = <expr> ──────────────────────────────────────────────────
  //
  // With the unified expression grammar, any expression is valid on the
  // RHS: literal, variable, query(), arithmetic, comparison, or logical.

  Parser<AssignStmt> assignStmt() =>
      (ref0(identifier) & char('=').trim() & ref0(expression)).map(
        (r) => AssignStmt(r[0] as String, r[2] as Expr),
      );

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
      (string('query(').trim() & ref0(_textArgs) & char(')')).map((r) {
        final arg = r[1] as _DeviceArg;
        if (arg.concatString != null) {
          return QueryItem(
            '',
            device: arg.device,
            concatString: arg.concatString,
          );
        }
        final text = arg.text!;
        return arg.isVariable
            ? QueryItem(text, device: arg.device, variableName: text)
            : QueryItem(text, device: arg.device);
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
            return WhileStmt(r[2] as Expr, (r[5] as List).cast<Statement>());
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
      (ref0(andExpression) & (ref0(_orOp) & ref0(andExpression)).star()).map(
        (r) => _buildBinaryChain(r[0] as Expr, r[1] as List),
      );

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
      (ref0(unaryExpression) & (ref0(_mulOp) & ref0(unaryExpression)).star())
          .map((r) => _buildBinaryChain(r[0] as Expr, r[1] as List));

  // ── Level 2: Unary (! -) ────────────────────────────────────────────
  //
  // The NOT operand excludes another NOT to reject `!!` at parse time.
  // Unary minus can be chained (`--5` is allowed).

  Parser<Expr> unaryExpression() => [
    (char('!').trim() & ref0(unaryNotOperand)).map(
      (r) => NotExpr(r[1] as Expr),
    ),
    (char('-').trim() & ref0(unaryExpression)).map(
      (r) => UnaryMinusExpr(r[1] as Expr),
    ),
    ref0(primaryExpression),
  ].toChoiceParser();

  /// Operand of `!` — excludes another `!` to prevent double negation.
  Parser<Expr> unaryNotOperand() => [
    (char('-').trim() & ref0(unaryExpression)).map(
      (r) => UnaryMinusExpr(r[1] as Expr),
    ),
    ref0(primaryExpression),
  ].toChoiceParser();

  // ── Level 1: Primary ────────────────────────────────────────────────

  Parser<Expr> primaryExpression() => [
    ref0(boolLiteral),
    ref0(number).map((n) => NumberLiteral(n)),
    ref0(stringLiteral).map((s) => StringLiteral(s)),
    ref0(_queryExpr),
    ref0(_cmdExpr),
    ref0(_connectExpr),
    ref0(identifier).map((name) => Variable(name)),
    (char('(').trim() & ref0(expression) & char(')').trim()).map(
      (r) => r[1] as Expr,
    ),
  ].toChoiceParser();

  // ── Inline query(), cmd() and connect() in expression context ───────

  Parser<Expr> _queryExpr() =>
      (string('query(').trim() & ref0(_textArgs) & char(')')).map((r) {
        final arg = r[1] as _DeviceArg;
        if (arg.concatString != null) {
          return QueryExpr(
            '',
            device: arg.device,
            concatString: arg.concatString,
          );
        }
        final text = arg.text!;
        return arg.isVariable
            ? QueryExpr(text, device: arg.device, variableName: text)
            : QueryExpr(text, device: arg.device);
      });

  Parser<Expr> _cmdExpr() =>
      (string('cmd(').trim() & ref0(_plainArgs) & char(')')).map((r) {
        final arg = r[1] as _DeviceArg;
        final text = arg.text!;
        return arg.isVariable
            ? ScpiExpr(text, device: arg.device, variableName: text)
            : ScpiExpr(text, device: arg.device);
      });

  /// `myscope = connect("192.168.1.100")` — opens a named device handle.
  ///
  /// The handle can be used as the selector of `cmd()` and `query()`.
  Parser<Expr> _connectExpr() =>
      (_ciKeyword('connect').trim() &
              char('(').trim() &
              ref0(_connectArgs) &
              char(')'))
          .map((r) {
            final arg = r[2] as _DeviceArg;
            if (arg.concatString != null) {
              return ConnectExpr(
                null,
                device: arg.device,
                concatString: arg.concatString,
              );
            }
            return ConnectExpr(
              arg.text,
              device: arg.device,
              isVariable: arg.isVariable,
            );
          });

  /// A literal/variable argument with an optional `SIG` selector.
  Parser<_DeviceArg> _plainArgs() => _withDeviceSelector(ref0(_plainTarget));

  Parser<_DeviceArg> _plainTarget() => [
    ref0(stringLiteral).map((s) => _DeviceArg(text: s)),
    ref0(identifier).map((s) => _DeviceArg(text: s, isVariable: true)),
  ].toChoiceParser();

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

/// One command argument plus its optional device selector.
class _DeviceArg {
  const _DeviceArg({
    this.device,
    this.text,
    this.isVariable = false,
    this.concatString,
  });

  /// Device selector (`SIG` or a handle variable name), or `null` for the
  /// default oscilloscope connection.
  final String? device;

  /// Literal text or variable name; `null` for the bare `usb` keyword.
  final String? text;

  final bool isVariable;
  final ConcatString? concatString;

  _DeviceArg withDevice(String value) => _DeviceArg(
    device: value,
    text: text,
    isVariable: isVariable,
    concatString: concatString,
  );
}

/// Builds a left-associative binary expression chain from the initial
/// left operand and a list of `(operator, rightOperand)` pairs.
Expr _buildBinaryChain(Expr left, List pairs) {
  Expr result = left;
  for (final item in pairs) {
    result = BinaryExpr(result, item[0] as String, item[1] as Expr);
  }
  return result;
}
