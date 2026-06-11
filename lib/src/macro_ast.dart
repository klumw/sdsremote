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

/// `wait(seconds)` or `wait(varName)`
class WaitStmt extends Statement {
  final double seconds;
  final String? variableName;

  /// When [variableName] is non-null, [seconds] is ignored and the actual
  /// duration is resolved from the named variable at evaluation time.
  const WaitStmt(this.seconds, {this.variableName});
}

/// `scpi("CMD")` or `scpi(varName)` — send a raw SCPI command.
class ScpiStmt extends Statement {
  final String command;

  /// When non-null, [command] is a variable name whose value is the actual
  /// SCPI command string, resolved at evaluation time.
  final String? variableName;

  const ScpiStmt(this.command, {this.variableName});
}

/// `query("CMD")` — send a SCPI query and read the response.
class QueryStmt extends Statement {
  final String command;
  const QueryStmt(this.command);
}

/// `<var> = query("CMD")` — store query result in a variable, or
/// `<var> = query(otherVar)` — store query result using a variable as command, or
/// `<var> = "value"` — assign a literal string, or
/// `<var> = otherVar` — copy another variable, or
/// `<var> = <arithExpr>` — evaluate an arithmetic expression.
class AssignStmt extends Statement {
  final String varName;

  /// For [isQuery]: the SCPI query string (or variable name if [isVariable]).
  /// For `!isQuery`: the literal value or other variable name.
  final String queryOrValue;

  /// True if this was `var = query("cmd")`; false for direct assignments.
  final bool isQuery;

  /// True when [queryOrValue] is a variable name that must be resolved at
  /// evaluation time to obtain the actual SCPI command string.
  final bool isVariable;

  /// When non-null, the assignment evaluates an arithmetic expression and
  /// stores the result as a string. Overrides all other fields.
  final ArithExpr? arithExpr;

  const AssignStmt(this.varName, this.queryOrValue, {
    this.isQuery = true,
    this.isVariable = false,
    this.arithExpr,
  });
}

// ── Arithmetic expressions ─────────────────────────────────────────────

/// An arithmetic expression that evaluates to a numeric value.
sealed class ArithExpr {
  const ArithExpr();
}

/// A numeric literal in an arithmetic expression (e.g. `1.0`).
class ArithNumber extends ArithExpr {
  final double value;
  const ArithNumber(this.value);
}

/// A variable reference in an arithmetic expression (e.g. `v`).
class ArithVariable extends ArithExpr {
  final String name;
  const ArithVariable(this.name);
}

/// An inline query in an arithmetic expression, e.g. `query("C1:VDIV?")`
/// or `query(varName)`.
class ArithQuery extends ArithExpr {
  final String command;

  /// When non-null, [command] is a variable name whose value is the actual
  /// SCPI query string, resolved at evaluation time.
  final String? variableName;

  const ArithQuery(this.command, {this.variableName});
}

/// A binary arithmetic operation (`+`, `-`, `*`, `/`).
class ArithBinaryOp extends ArithExpr {
  final ArithExpr left;
  final String op;
  final ArithExpr right;
  const ArithBinaryOp(this.left, this.op, this.right);
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

/// An inline SCPI query `query("CMD")` or `query(varName)`.
class QueryExpr extends Expression {
  final String command;

  /// When non-null, [command] is a variable name whose value is the actual
  /// SCPI query string, resolved at evaluation time.
  final String? variableName;

  const QueryExpr(this.command, {this.variableName});
}

/// An inline SCPI command `scpi("CMD")` or `scpi(varName)` used in `assert`
/// success checks.
class ScpiExpr extends Expression {
  final String command;

  /// When non-null, [command] is a variable name whose value is the actual
  /// SCPI command string, resolved at evaluation time.
  final String? variableName;

  const ScpiExpr(this.command, {this.variableName});
}
