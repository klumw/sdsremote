/// AST (Abstract Syntax Tree) node classes for the macro language.
///
/// All statement and expression types use Dart's sealed class hierarchy
/// for exhaustive pattern matching in the evaluator.
library;

// ── Top-level program ───────────────────────────────────────────────────

/// The root node containing all statements in a macro program.
class Program {
  final List<Statement> statements;
  const Program(this.statements);
}

// ── Statements ──────────────────────────────────────────────────────────

sealed class Statement {
  const Statement();
}

/// A comment line starting with `#`. No runtime effect.
class Comment extends Statement {
  const Comment();
}

/// `connect("ip")` or `connect(usb)` or `connect(varName)`
class ConnectStmt extends Statement {
  /// The IP address string, or `null` for USB mode.
  final String? ip;

  /// True if [ip] is a variable name that should be resolved at eval time.
  final bool isVariable;

  const ConnectStmt(this.ip, {this.isVariable = false});
}

/// `wait(seconds)`
class WaitStmt extends Statement {
  final double seconds;
  const WaitStmt(this.seconds);
}

/// `scpi("CMD")` — send a raw SCPI command.
class ScpiStmt extends Statement {
  final String command;
  const ScpiStmt(this.command);
}

/// `query("CMD")` — send a SCPI query and read the response.
class QueryStmt extends Statement {
  final String command;
  const QueryStmt(this.command);
}

/// `<var> = query("CMD")` — store query result in a variable, or
/// `<var> = "value"` — assign a literal string, or
/// `<var> = otherVar` — copy another variable.
class AssignStmt extends Statement {
  final String varName;

  /// For [isQuery]: the SCPI query string.
  /// For `!isQuery`: the literal value or other variable name.
  final String queryOrValue;

  /// True if this was `var = query("cmd")`; false for direct assignments.
  final bool isQuery;

  const AssignStmt(this.varName, this.queryOrValue, {this.isQuery = true});
}

/// A single item in a `print()` argument list.
sealed class PrintItem {
  const PrintItem();
}

/// A quoted string literal in a print statement, e.g. `"Hello"`.
class TextItem extends PrintItem {
  final String text;
  const TextItem(this.text);
}

/// A variable reference in a print statement, e.g. `myVar`.
class VariableItem extends PrintItem {
  final String name;
  const VariableItem(this.name);
}

/// An inline SCPI query in a print statement, e.g. `query("C1:TRA?")`.
class QueryItem extends PrintItem {
  final String command;
  const QueryItem(this.command);
}

/// `print(<item> + <item> + ...)` — log concatenated text, variables,
/// and query results.
class PrintStmt extends Statement {
  final List<PrintItem> items;
  const PrintStmt(this.items);
}

/// `assert("text", <expr>)` or `assert("text", <expr> <op> <value>)`
class AssertStmt extends Statement {
  /// Human-readable description shown on failure.
  final String text;

  /// The expression to evaluate (variable or inline query/scpi).
  final Expression operand;

  /// Comparison operator (`==`, `!=`, `<`, `<=`, `>`, `>=`), or `null` for
  /// truthiness / scpi-success mode.
  final String? op;

  /// Expected value for comparison, or `null` for truthiness / scpi-success.
  final String? expectedValue;

  const AssertStmt(this.text, this.operand, {this.op, this.expectedValue});
}

/// `loadProfile("path")` — load and send a profile (.lss) file.
class LoadProfileStmt extends Statement {
  final String path;
  const LoadProfileStmt(this.path);
}

/// `if (<expr> <op> <value>) { ... }` with optional `else { ... }`.
class IfStmt extends Statement {
  final Expression condition;
  final String op;
  final String value;
  final List<Statement> thenBody;
  final List<Statement>? elseBody;

  const IfStmt(
    this.condition,
    this.op,
    this.value,
    this.thenBody, {
    this.elseBody,
  });
}

/// `while (<expr> <op> <value>) { ... }`
class WhileStmt extends Statement {
  final Expression condition;
  final String op;
  final String value;
  final List<Statement> body;

  const WhileStmt(this.condition, this.op, this.value, this.body);
}

/// `break` — exit the innermost while loop.
class BreakStmt extends Statement {
  const BreakStmt();
}

/// `continue` — skip to the next while iteration.
class ContinueStmt extends Statement {
  const ContinueStmt();
}

// ── Expressions ─────────────────────────────────────────────────────────

sealed class Expression {
  const Expression();
}

/// A reference to a previously assigned variable.
class VariableExpr extends Expression {
  final String name;
  const VariableExpr(this.name);
}

/// An inline SCPI query `query("CMD")`.
class QueryExpr extends Expression {
  final String command;
  const QueryExpr(this.command);
}

/// An inline SCPI command `scpi("CMD")` used in `assert` success checks.
class ScpiExpr extends Expression {
  final String command;
  const ScpiExpr(this.command);
}
