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

  Parser<Comment> comment() => (char('#') &
          any().starLazy(newline() | endOfInput()).flatten() &
          (newline() | endOfInput()))
      .map((_) => const Comment());

  // ── connect("ip") | connect(usb) ────────────────────────────────────

  Parser<ConnectStmt> connectStmt() => (string('connect(').trim() &
          (ref0(stringLiteral) | string('usb')) &
          char(')'))
      .map((r) {
    final arg = r[1] as String;
    if (arg == 'usb') return const ConnectStmt(null);
    return ConnectStmt(arg);
  });

  // ── wait(seconds) ───────────────────────────────────────────────────

  Parser<WaitStmt> waitStmt() =>
      (string('wait(').trim() & ref0(number) & char(')'))
          .map((r) => WaitStmt(r[1] as double));

  // ── scpi("CMD") ─────────────────────────────────────────────────────

  Parser<ScpiStmt> scpiStmt() =>
      (string('scpi(').trim() & ref0(stringLiteral) & char(')'))
          .map((r) => ScpiStmt(r[1] as String));

  // ── query("CMD") ────────────────────────────────────────────────────

  Parser<QueryStmt> queryStmt() =>
      (string('query(').trim() & ref0(stringLiteral) & char(')'))
          .map((r) => QueryStmt(r[1] as String));

  // ── <var> = query("CMD") ───────────────────────────────────────────

  Parser<AssignStmt> assignStmt() => (ref0(identifier) &
          char('=').trim() &
          string('query(').trim() &
          ref0(stringLiteral) &
          char(')'))
      .map((r) => AssignStmt(r[0] as String, r[3] as String));

  // ── print(item + item + ...) ────────────────────────────────────────

  Parser<PrintStmt> printStmt() =>
      (string('print(').trim() & ref0(printItem) & ref0(_printTail).star() & char(')'))
          .map((r) {
        final first = r[1] as PrintItem;
        final rest = (r[2] as List).cast<PrintItem>();
        return PrintStmt([first, ...rest]);
      });

  Parser<PrintItem> printItem() => [
        ref0(_textItem),
        ref0(_queryItem),
        ref0(_variableItem),
      ].toChoiceParser();

  Parser<PrintItem> _textItem() => ref0(stringLiteral)
      .map((s) => TextItem(s as String));

  Parser<PrintItem> _queryItem() =>
      (string('query(').trim() & ref0(stringLiteral) & char(')'))
          .map((r) => QueryItem(r[1] as String));

  Parser<PrintItem> _variableItem() => ref0(identifier)
      .map((s) => VariableItem(s as String));

  Parser<PrintItem> _printTail() =>
      (char('+').trim() & ref0(printItem))
          .map((r) => r[1] as PrintItem);

  // ── assert("text", <expr>) ──────────────────────────────────────────
  // ── assert("text", <expr> <op> <value>) ─────────────────────────────
  // ── assert("text", scpi("CMD")) ─────────────────────────────────────

  Parser<AssertStmt> assertStmt() => (string('assert(').trim() &
          ref0(stringLiteral) &
          char(',').trim() &
          ref0(operand) &
          ref0(_assertTail).optional() &
          char(')').trim())
      .map((r) {
    final exp = r[3] as Expression;
    final tail = r[4] as (String, String)?;
    return AssertStmt(
      r[1] as String,
      exp,
      op: tail?.$1,
      expectedValue: tail?.$2,
    );
  });

  Parser<(String, String)> _assertTail() =>
      (ref0(_comparisonOp) & ref0(_comparisonValue))
          .map((r) => (r[0] as String, r[1] as String));

  // ── loadProfile("path") ─────────────────────────────────────────────

  Parser<LoadProfileStmt> loadProfileStmt() =>
      (string('loadProfile(').trim() & ref0(stringLiteral) & char(')'))
          .map((r) => LoadProfileStmt(r[1] as String));

  // ── if (<expr> <op> <value>) { ... } ───────────────────────────────
  // ── if (<expr> <op> <value>) then { ... } ──────────────────────────

  Parser<IfStmt> ifStmt() => (string('if').trim() &
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
      .map((r) => IfStmt(
            r[2] as Expression,
            r[3] as String,
            r[4] as String,
            (r[8] as List).cast<Statement>(),
            elseBody: (r[10] as List<Statement>?),
          ));

  Parser<List<Statement>> _elseBlock() =>
      (string('else').trim() & char('{').trim() & ref0(statement).star() & char('}'))
          .map((r) => (r[2] as List).cast<Statement>());

  // ── while (<expr> <op> <value>) { ... } ────────────────────────────

  Parser<WhileStmt> whileStmt() => (string('while').trim() &
          char('(').trim() &
          ref0(operand) &
          ref0(_comparisonOp) &
          ref0(_comparisonValue) &
          char(')').trim() &
          char('{').trim() &
          ref0(statement).star() &
          char('}'))
      .map((r) => WhileStmt(
            r[2] as Expression,
            r[3] as String,
            r[4] as String,
            (r[7] as List).cast<Statement>(),
          ));

  // ── break / continue ───────────────────────────────────────────────

  Parser<BreakStmt> breakStmt() => string('break').map((_) => const BreakStmt());
  Parser<ContinueStmt> continueStmt() =>
      string('continue').map((_) => const ContinueStmt());

  // ── Expressions ─────────────────────────────────────────────────────

  Parser<Expression> operand() => [
        ref0(queryExpr),
        ref0(scpiExpr),
        ref0(variableExpr),
      ].toChoiceParser();

  Parser<QueryExpr> queryExpr() =>
      (string('query(').trim() & ref0(stringLiteral) & char(')'))
          .map((r) => QueryExpr(r[1] as String));

  Parser<ScpiExpr> scpiExpr() =>
      (string('scpi(').trim() & ref0(stringLiteral) & char(')'))
          .map((r) => ScpiExpr(r[1] as String));

  Parser<VariableExpr> variableExpr() =>
      ref0(identifier).map((name) => VariableExpr(name as String));

  // ── Common parsers ──────────────────────────────────────────────────

  Parser<String> _comparisonOp() => [
        string('<='),
        string('>='),
        string('=='),
        string('!='),
        char('<'),
        char('>'),
      ].toChoiceParser().trim().map((r) => r.toString());

  Parser<String> _comparisonValue() => ref0(identifier);

  // ── Lexical primitives ──────────────────────────────────────────────

  Parser<String> stringLiteral() =>
      (char('"') & any().starLazy(char('"')).flatten() & char('"'))
          .map((r) => r[1] as String);

  Parser<double> number() =>
      (digit().plus() &
              (char('.') & digit().plus()).optional())
          .flatten()
          .map((s) => double.parse(s));

  Parser<String> identifier() =>
      (letter() & word().star()).flatten();
}
