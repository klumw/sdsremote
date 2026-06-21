/// AST (Abstract Syntax Tree) node classes for the macro language.
///
/// Uses Dart's sealed class hierarchy for exhaustive pattern matching in the
/// evaluator and linter.  The expression system follows standard operator
/// precedence:
///
/// ```text
/// 1. Parentheses                  ()
/// 2. Unary operators              !  - (unary minus)
/// 3. Multiplication / Division    *  /
/// 4. Addition / Subtraction       +  -
/// 5. Comparisons                  > >= < <=
/// 6. Equality                     == !=
/// 7. Logical AND                  &&
/// 8. Logical OR                   ||
/// ```
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

/// `<var> = <expr>` — evaluate an expression and store the result.
///
/// The expression may be any [Expr] node: a literal, variable reference,
/// query(), arithmetic, comparison, or logical operation.  All values are
/// stored as strings in the variable table.
class AssignStmt extends Statement {
  final String varName;

  /// The expression whose evaluated result is stored in [varName].
  final Expr value;

  const AssignStmt(this.varName, this.value);
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

// ── Print statement ─────────────────────────────────────────────────────

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

  /// The expression to evaluate.
  ///
  /// When the expression produces a boolean, it is used as a pass/fail check.
  /// When it is a [ScpiExpr], success is determined by whether the command
  /// executes without error.  When it is anything else, truthiness is checked.
  final Expr condition;

  const AssertStmt(
    this.text,
    this.condition, {
    this.concatText,
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

/// `if (<expr>) { ... }` with optional `else { ... }`.
///
/// The condition is any expression.  At evaluation time it is coerced to a
/// boolean: comparison and logical operators naturally produce booleans;
/// other expressions use truthiness rules.
class IfStmt extends Statement {
  final Expr condition;
  final List<Statement> thenBody;
  final List<Statement>? elseBody;

  const IfStmt(this.condition, this.thenBody, {this.elseBody});
}

/// `while (<expr>) { ... }`
class WhileStmt extends Statement {
  final Expr condition;
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

/// `fail("message")` or `fail("prefix" + var + "suffix")` —
/// immediately abort the macro with an error message.
class FailStmt extends Statement {
  /// The error message, or empty when [concatMessage] is used.
  final String message;

  /// When non-null, the argument was a concatenated string expression that
  /// must be resolved at evaluation time. Overrides [message].
  final ConcatString? concatMessage;

  const FailStmt(this.message, {this.concatMessage});
}

// ── Unified expression hierarchy ────────────────────────────────────────

/// One node in the unified expression tree.
///
/// The grammar enforces operator precedence structurally, so the AST shape
/// directly reflects the evaluation order.  For example:
///
/// ```text
/// 2 + 3 * 4
/// ```
///
/// produces:
///
/// ```text
/// BinaryExpr
///  ├─ NumberLiteral(2)
///  ├─ op: "+"
///  └─ BinaryExpr
///      ├─ NumberLiteral(3)
///      ├─ op: "*"
///      └─ NumberLiteral(4)
/// ```
sealed class Expr {
  const Expr();
}

// ── Literals ────────────────────────────────────────────────────────────

/// A numeric literal, e.g. `3.14`.
class NumberLiteral extends Expr {
  final double value;
  const NumberLiteral(this.value);
}

/// A string literal, e.g. `"hello"`.
class StringLiteral extends Expr {
  final String value;
  const StringLiteral(this.value);
}

/// A boolean literal, either `true` or `false`.
class BoolLiteral extends Expr {
  final bool value;
  const BoolLiteral(this.value);
}

// ── Variable ────────────────────────────────────────────────────────────

/// A reference to a previously assigned variable.
///
/// In boolean context the variable's value is checked for truthiness
/// (non-empty, not `"0"`, not `"OFF"`).  In arithmetic context it is
/// parsed as a number.
class Variable extends Expr {
  final String name;
  const Variable(this.name);
}

// ── Inline SCPI operations ──────────────────────────────────────────────

/// An inline SCPI query: `query("CMD")`, `query(varName)`, or
/// `query("prefix" + var + "suffix")`.
///
/// Evaluates to the instrument's response string.  In arithmetic context
/// the response is parsed as a number.
class QueryExpr extends Expr {
  final String command;

  /// When non-null, [command] is a variable name whose value is the actual
  /// SCPI query string, resolved at evaluation time.
  final String? variableName;

  /// When non-null, the argument was a concatenated string expression that
  /// must be resolved at evaluation time. Overrides [command] / [variableName].
  final ConcatString? concatString;

  const QueryExpr(this.command, {this.variableName, this.concatString});
}

/// An inline SCPI command: `scpi("CMD")` or `scpi(varName)`.
///
/// Produces no value; only valid in `assert()` as a success check.
class ScpiExpr extends Expr {
  final String command;

  /// When non-null, [command] is a variable name whose value is the actual
  /// SCPI command string, resolved at evaluation time.
  final String? variableName;

  const ScpiExpr(this.command, {this.variableName});
}

// ── Unary operations ────────────────────────────────────────────────────

/// Unary minus: `-<operand>`.
class UnaryMinusExpr extends Expr {
  final Expr operand;
  const UnaryMinusExpr(this.operand);
}

/// Logical NOT: `!<operand>`.
class NotExpr extends Expr {
  final Expr operand;
  const NotExpr(this.operand);
}

// ── Binary operations ───────────────────────────────────────────────────

/// A binary operation joining two sub-expressions.
///
/// [op] is one of:
/// - Arithmetic: `+`, `-`, `*`, `/`
/// - Relational: `>`, `>=`, `<`, `<=`
/// - Equality: `==`, `!=`
/// - Logical: `&&`, `||`
///
/// Precedence is enforced by the grammar, not the AST.  The evaluator
/// simply dispatches on [op].
class BinaryExpr extends Expr {
  final Expr left;
  final String op;
  final Expr right;

  const BinaryExpr(this.left, this.op, this.right);
}
