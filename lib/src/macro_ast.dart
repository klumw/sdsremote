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

/// `connect("ip")` or `connect(usb)` or `connect(varName)` or
/// `connect("ip" + var + "suffix")`.
class ConnectStmt extends Statement {
  /// The IP address string, or `null` for USB mode.
  final String? ip;

  /// True if [ip] is a variable name that should be resolved at eval time.
  final bool isVariable;

  /// When non-null, the argument was a concatenated string expression that
  /// must be resolved at evaluation time. Overrides [ip] / [isVariable].
  final ConcatString? concatString;

  const ConnectStmt(this.ip, {this.isVariable = false, this.concatString});
}

/// `wait(seconds)` or `wait(varName)`
class WaitStmt extends Statement {
  final double seconds;
  final String? variableName;

  /// When [variableName] is non-null, [seconds] is ignored and the actual
  /// duration is resolved from the named variable at evaluation time.
  const WaitStmt(this.seconds, {this.variableName});
}

/// `scpi("CMD")` or `scpi(varName)` or `scpi("prefix" + var + "suffix")` —
/// send a raw SCPI command.
class ScpiStmt extends Statement {
  final String command;

  /// When non-null, [command] is a variable name whose value is the actual
  /// SCPI command string, resolved at evaluation time.
  final String? variableName;

  /// When non-null, the argument was a concatenated string expression that
  /// must be resolved at evaluation time. Overrides [command] / [variableName].
  final ConcatString? concatString;

  const ScpiStmt(this.command, {this.variableName, this.concatString});
}

/// `query("CMD")` or `query(varName)` or `query("prefix" + var + "suffix")` —
/// send a SCPI query and read the response.
class QueryStmt extends Statement {
  final String command;

  /// When non-null, [command] is a variable name whose value is the actual
  /// SCPI query string, resolved at evaluation time.
  final String? variableName;

  /// When non-null, the argument was a concatenated string expression that
  /// must be resolved at evaluation time. Overrides [command] / [variableName].
  final ConcatString? concatString;

  const QueryStmt(this.command, {this.variableName, this.concatString});
}

/// `<var> = query("CMD")` — store query result in a variable, or
/// `<var> = query(otherVar)` — store query result using a variable as command, or
/// `<var> = query("prefix" + var + "suffix")` — use a concatenated query, or
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

  /// When non-null, the query argument was a concatenated string expression
  /// that must be resolved at evaluation time. Only valid when [isQuery] is
  /// true. Overrides [queryOrValue] / [isVariable].
  final ConcatString? concatString;

  const AssignStmt(
    this.varName,
    this.queryOrValue, {
    this.isQuery = true,
    this.isVariable = false,
    this.arithExpr,
    this.concatString,
  });
}

// ── String concatenation ───────────────────────────────────────────────

/// A piece of a concatenated string expression.
sealed class ConcatPiece {
  const ConcatPiece();
}

/// A literal string piece in a concatenation, e.g. `"C1:VDIV "`.
class ConcatTextPiece extends ConcatPiece {
  final String text;
  const ConcatTextPiece(this.text);
}

/// A variable reference piece in a concatenation, e.g. `val`.
class ConcatVarPiece extends ConcatPiece {
  final String name;
  const ConcatVarPiece(this.name);
}

/// A concatenated string expression with 2+ pieces joined by `+`,
/// e.g. `"C1:VDIV " + val + "V"`.
class ConcatString {
  /// At least two pieces — a single piece would be parsed as a literal or
  /// variable directly.
  final List<ConcatPiece> pieces;
  const ConcatString(this.pieces);
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
/// or `query(varName)` or `query("pre" + var + "suf")`.
class ArithQuery extends ArithExpr {
  final String command;

  /// When non-null, [command] is a variable name whose value is the actual
  /// SCPI query string, resolved at evaluation time.
  final String? variableName;

  /// When non-null, the argument was a concatenated string expression that
  /// must be resolved at evaluation time. Overrides [command] / [variableName].
  final ConcatString? concatString;

  const ArithQuery(this.command, {this.variableName, this.concatString});
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

/// An inline SCPI query in a print statement, e.g. `query("C1:TRA?")`,
/// `query(varName)`, or `query("prefix" + var + "suffix")`.
class QueryItem extends PrintItem {
  final String command;

  /// When non-null, [command] is a variable name whose value is the actual
  /// SCPI query string, resolved at evaluation time.
  final String? variableName;

  /// When non-null, the argument was a concatenated string expression that
  /// must be resolved at evaluation time. Overrides [command] / [variableName].
  final ConcatString? concatString;

  const QueryItem(this.command, {this.variableName, this.concatString});
}

/// `print(<item> + <item> + ...)` — log concatenated text, variables,
/// and query results.
class PrintStmt extends Statement {
  final List<PrintItem> items;
  const PrintStmt(this.items);
}

/// `assert("text", <expr>)` or `assert("text" + var + "suffix", <expr>)`
/// or `assert("text", <expr> <op> <value>)`
/// or `assert("text", <boolExpr>)`.
class AssertStmt extends Statement {
  /// Human-readable description shown on failure.
  final String text;

  /// When non-null, the description was a concatenated string expression that
  /// must be resolved at evaluation time. Overrides [text] for display.
  final ConcatString? concatText;

  /// The expression for scpi-success or bare truthiness mode.
  /// When non-null, [condition] is null.
  final Expression? operand;

  /// The boolean expression for the comparison / combined mode.
  /// When non-null, [operand] is null.
  final BoolExpr? condition;

  const AssertStmt(
    this.text,
    this.operand, {
    this.concatText,
    this.condition,
  });
}

/// `loadProfile("path")` or `loadProfile("prefix" + var + "suffix")` —
/// load and send a profile (.lss) file.
class LoadProfileStmt extends Statement {
  final String path;

  /// When non-null, the argument was a concatenated string expression that
  /// must be resolved at evaluation time. Overrides [path].
  final ConcatString? concatString;

  const LoadProfileStmt(this.path, {this.concatString});
}

/// `if (<boolExpr>) { ... }` with optional `else { ... }`.
class IfStmt extends Statement {
  final BoolExpr condition;
  final List<Statement> thenBody;
  final List<Statement>? elseBody;

  const IfStmt(this.condition, this.thenBody, {this.elseBody});
}

/// `while (<boolExpr>) { ... }`
class WhileStmt extends Statement {
  final BoolExpr condition;
  final List<Statement> body;

  const WhileStmt(this.condition, this.body);
}

/// `break` — exit the innermost while loop.
class BreakStmt extends Statement {
  const BreakStmt();
}

/// `continue` — skip to the next while iteration.
class ContinueStmt extends Statement {
  const ContinueStmt();
}

// ── Boolean expressions ──────────────────────────────────────────────────

/// A boolean expression that evaluates to `true`, `false`, or `null` (error).
sealed class BoolExpr {
  const BoolExpr();
}

/// A single comparison: `<operand> <op> <value>`.
///
/// [op] is one of `==`, `!=`, `<`, `<=`, `>`, `>=`.
/// [value] is either a literal or a variable name (when [valueIsVariable]).
class ComparisonExpr extends BoolExpr {
  final Expression operand;
  final String op;
  final String value;
  final bool valueIsVariable;

  const ComparisonExpr(
    this.operand,
    this.op,
    this.value, {
    this.valueIsVariable = false,
  });
}

/// Two boolean expressions joined by a boolean operator (`&`, `&&`, `|`, `||`).
class BoolBinaryExpr extends BoolExpr {
  final BoolExpr left;
  final String boolOp;
  final BoolExpr right;

  const BoolBinaryExpr(this.left, this.boolOp, this.right);
}

/// A bare expression used as a truthiness check (no comparison operator).
///
/// Only valid inside `assert()`; the linter rejects it in `if` / `while`.
class TruthyExpr extends BoolExpr {
  final Expression operand;
  const TruthyExpr(this.operand);
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

/// An inline SCPI query `query("CMD")` or `query(varName)` or
/// `query("prefix" + var + "suffix")`.
class QueryExpr extends Expression {
  final String command;

  /// When non-null, [command] is a variable name whose value is the actual
  /// SCPI query string, resolved at evaluation time.
  final String? variableName;

  /// When non-null, the argument was a concatenated string expression that
  /// must be resolved at evaluation time. Overrides [command] / [variableName].
  final ConcatString? concatString;

  const QueryExpr(this.command, {this.variableName, this.concatString});
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
