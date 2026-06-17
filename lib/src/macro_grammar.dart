import 'package:petitparser/petitparser.dart';

import 'macro_ast.dart';

/// Grammar definition for the SDS Remote macro language.
///
/// Uses [GrammarDefinition] from petitparser for recursive descent parsing.
/// Each production returns the corresponding AST node type.
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
    ref0(assignStmt),
    ref0(queryStmt),
    ref0(printStmt),
    ref0(assertStmt),
    ref0(loadProfileStmt),
    ref0(ifStmt),
    ref0(whileStmt),
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

  // ── <var> = query("CMD") | <var> = query(otherVar) ────────────────
  // ── <var> = "value"      | <var> = otherVar     ────────────────────
  // ── <var> = number       | <var> = <arithExpr>  ────────────────────

  Parser<AssignStmt> assignStmt() => [
    // var = arithExpr (e.g. x=v+1, b=v*2+1, x=v+query("C1:VDIV?"))
    // Must come first so that expressions with operators are matched
    // before the simpler query/string/number alternatives.
    (ref0(identifier) & char('=').trim() & ref0(arithExpr)).map(
      (r) => AssignStmt(
        r[0] as String,
        '',
        isQuery: false,
        arithExpr: r[2] as ArithExpr,
      ),
    ),
    // var = * or / only (e.g. x=3.0*2, x=query("C1:VDIV?")*2)
    // Falls through when arithExpr fails (no + or - present).
    (ref0(identifier) & char('=').trim() & ref0(_mulOnlyExpr)).map(
      (r) => AssignStmt(
        r[0] as String,
        '',
        isQuery: false,
        arithExpr: r[2] as ArithExpr,
      ),
    ),
    // var = query("literal cmd" | concatExpr)
    (ref0(identifier) &
            char('=').trim() &
            string('query(').trim() &
            (ref0(concatExpr) |
                ref0(stringLiteral).map((s) => (s, false)) |
                ref0(identifier).map((s) => (s, true))) &
            char(')'))
        .map((r) {
          final arg = r[3];
          if (arg is ConcatString) {
            return AssignStmt(
              r[0] as String,
              '',
              isQuery: true,
              concatString: arg,
            );
          }
          final (argStr, isVar) = arg as (String, bool);
          return AssignStmt(
            r[0] as String,
            argStr,
            isQuery: true,
            isVariable: isVar,
          );
        }),
    // var = "literal string"
    (ref0(identifier) & char('=').trim() & ref0(stringLiteral)).map(
      (r) => AssignStmt(r[0] as String, r[2] as String, isQuery: false),
    ),
    // var = otherVar (variable copy)
    (ref0(identifier) & char('=').trim() & ref0(identifier)).map(
      (r) => AssignStmt(r[0] as String, r[2] as String, isQuery: false),
    ),
    // var = number (e.g. time=2.0)
    (ref0(identifier) & char('=').trim() & ref0(number)).map(
      (r) => AssignStmt(r[0] as String, r[2].toString(), isQuery: false),
    ),
  ].toChoiceParser();

  // ── Arithmetic expressions ──────────────────────────────────────────
  //   arithExpr  → arithMul (('+' | '-') arithMul)+    (requires 1+ op)
  //   arithMul   → arithAtom (('*' | '/') arithAtom)*  (left-associative)
  //   arithAtom  → number | identifier | query("...") | query(var) | '(' expr ')'

  Parser<ArithExpr> arithExpr() =>
      (ref0(arithMul) & (ref0(_addOp) & ref0(arithMul)).plus()).map((r) {
        ArithExpr result = r[0] as ArithExpr;
        for (final item in r[1] as List) {
          result = ArithBinaryOp(
            result,
            item[0] as String,
            item[1] as ArithExpr,
          );
        }
        return result;
      });

  Parser<ArithExpr> arithMul() =>
      (ref0(arithAtom) & (ref0(_mulOp) & ref0(arithAtom)).star()).map((r) {
        ArithExpr result = r[0] as ArithExpr;
        for (final item in r[1] as List) {
          result = ArithBinaryOp(
            result,
            item[0] as String,
            item[1] as ArithExpr,
          );
        }
        return result;
      });

  Parser<ArithExpr> arithAtom() => [
    ref0(number).map((n) => ArithNumber(n)),
    // query("...") must come before identifier so the 'query' keyword
    // isn't consumed as a variable name.
    (string('query(').trim() &
            (ref0(concatExpr) |
                ref0(stringLiteral).map((s) => (s, false)) |
                ref0(identifier).map((s) => (s, true))) &
            char(')'))
        .map((r) {
          final arg = r[1];
          if (arg is ConcatString) return ArithQuery('', concatString: arg);
          final (cmd, isVar) = arg as (String, bool);
          return isVar ? ArithQuery(cmd, variableName: cmd) : ArithQuery(cmd);
        }),
    ref0(identifier).map((name) => ArithVariable(name)),
    (char('(').trim() & ref0(arithExpr) & char(')')).map(
      (r) => r[1] as ArithExpr,
    ),
  ].toChoiceParser();

  Parser<String> _addOp() =>
      (char('+') | char('-')).trim().map((r) => r.toString());
  Parser<String> _mulOp() =>
      (char('*') | char('/')).trim().map((r) => r.toString());

  /// Matches arithmetic expressions with at least one `*` or `/` operator,
  /// e.g. `3.0 * 2`, `v / 2`, `query("C1:VDIV?") * 3`.
  /// Unlike [arithMul] which accepts zero operators, this requires 1+.
  Parser<ArithExpr> _mulOnlyExpr() =>
      (ref0(arithAtom) & (ref0(_mulOp) & ref0(arithAtom)).plus()).map((r) {
        ArithExpr result = r[0] as ArithExpr;
        for (final item in r[1] as List) {
          result = ArithBinaryOp(
            result,
            item[0] as String,
            item[1] as ArithExpr,
          );
        }
        return result;
      });

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
  // ── assert("text", <expr> <op> <value>) ─────────────────────────────
  // ── assert("text", scpi("CMD")) ─────────────────────────────────────

  Parser<AssertStmt> assertStmt() =>
      (string('assert(').trim() &
              (ref0(concatExpr) | ref0(stringLiteral)) &
              char(',').trim() &
              ref0(operand) &
              ref0(_assertTail).optional() &
              char(')').trim())
          .map((r) {
            final exp = r[3] as Expression;
            final tail = r[4] as (String, (String, bool))?;
            final textArg = r[1];
            if (textArg is ConcatString) {
              return AssertStmt(
                '',
                exp,
                op: tail?.$1,
                expectedValue: tail?.$2.$1,
                expectedIsVariable: tail?.$2.$2 ?? false,
                concatText: textArg,
              );
            }
            return AssertStmt(
              textArg as String,
              exp,
              op: tail?.$1,
              expectedValue: tail?.$2.$1,
              expectedIsVariable: tail?.$2.$2 ?? false,
            );
          });

  Parser<(String, (String, bool))> _assertTail() =>
      (ref0(_comparisonOp) & ref0(_comparisonValue)).map(
        (r) => (r[0] as String, r[1] as (String, bool)),
      );

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

  // ── if (<expr> <op> <value>) { ... } ───────────────────────────────
  // ── if (<expr> <op> <value>) then { ... } ──────────────────────────

  Parser<IfStmt> ifStmt() =>
      (string('if').trim() &
              char('(').trim() &
              ref0(operand) &
              ref0(_comparisonOp) &
              ref0(_comparisonValue) &
              char(')').trim() &
              string('then').trim().optional() &
              char('{').trim() &
              ref0(statement).star() &
              char('}').trim() &
              ref0(_elseBlock).optional())
          .map((r) {
            final compVal = r[4] as (String, bool);
            return IfStmt(
              r[2] as Expression,
              r[3] as String,
              compVal.$1,
              (r[8] as List).cast<Statement>(),
              elseBody: (r[10] as List<Statement>?),
              valueIsVariable: compVal.$2,
            );
          });

  Parser<List<Statement>> _elseBlock() =>
      (string('else').trim() &
              char('{').trim() &
              ref0(statement).star() &
              char('}'))
          .map((r) => (r[2] as List).cast<Statement>());

  // ── while (<expr> <op> <value>) { ... } ────────────────────────────

  Parser<WhileStmt> whileStmt() =>
      (string('while').trim() &
              char('(').trim() &
              ref0(operand) &
              ref0(_comparisonOp) &
              ref0(_comparisonValue) &
              char(')').trim() &
              char('{').trim() &
              ref0(statement).star() &
              char('}'))
          .map((r) {
            final compVal = r[4] as (String, bool);
            return WhileStmt(
              r[2] as Expression,
              r[3] as String,
              compVal.$1,
              (r[7] as List).cast<Statement>(),
              valueIsVariable: compVal.$2,
            );
          });

  // ── break / continue ───────────────────────────────────────────────

  Parser<BreakStmt> breakStmt() =>
      string('break').map((_) => const BreakStmt());
  Parser<ContinueStmt> continueStmt() =>
      string('continue').map((_) => const ContinueStmt());

  // ── Expressions ─────────────────────────────────────────────────────

  Parser<Expression> operand() =>
      [ref0(queryExpr), ref0(scpiExpr), ref0(variableExpr)].toChoiceParser();

  Parser<QueryExpr> queryExpr() =>
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

  Parser<ScpiExpr> scpiExpr() =>
      (string('scpi(').trim() &
              (ref0(stringLiteral).map((s) => (s, false)) |
                  ref0(identifier).map((s) => (s, true))) &
              char(')'))
          .map((r) {
            final (arg, isVar) = r[1] as (String, bool);
            return isVar ? ScpiExpr(arg, variableName: arg) : ScpiExpr(arg);
          });

  Parser<VariableExpr> variableExpr() =>
      ref0(identifier).map((name) => VariableExpr(name));

  // ── Common parsers ──────────────────────────────────────────────────

  Parser<String> _comparisonOp() => [
    string('<='),
    string('>='),
    string('=='),
    string('!='),
    char('<'),
    char('>'),
  ].toChoiceParser().trim().map((r) => r.toString());

  Parser<(String, bool)> _comparisonValue() => [
    ref0(number).map((n) => (n.toString(), false)),
    ref0(stringLiteral).map((s) => (s, false)),
    ref0(identifier).map((s) => (s, true)),
  ].toChoiceParser();

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
