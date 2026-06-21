import 'dart:io';

import 'package:petitparser/petitparser.dart';

import '../dart_vxi11.dart';
import '../logger.dart';
import 'macro_ast.dart';
import 'macro_grammar.dart';

/// Evaluates a macro [Program] by walking its AST and executing commands
/// against a VXI-11 instrument.
///
/// The [instrument] field is mutable — `connect()` updates it during
/// evaluation. Call [close] when done to clean up.
class MacroEvaluator {
  /// The active instrument connection. May be updated by `connect()` during
  /// evaluation.
  Vxi11Instrument? instrument;

  final void Function(String message) onError;
  final bool Function() isCancelled;
  final Future<void> Function(int seconds) delay;
  final void Function(String message) onLog;

  final Map<String, String> _vars = {};
  bool _echoesDrained = false;
  bool _breakRequested = false;
  bool _continueRequested = false;

  MacroEvaluator({
    this.instrument,
    required this.onError,
    required this.isCancelled,
    this.delay = _defaultDelay,
    this.onLog = _defaultLog,
  });

  static Future<void> _defaultDelay(int seconds) =>
      Future.delayed(Duration(seconds: seconds));

  static void _defaultLog(String message) => AppLogger().log(message);

  /// Parse [source] and evaluate the resulting program.
  ///
  /// Returns `true` if the macro completed successfully, `false` if an
  /// error occurred or playback was cancelled.
  Future<bool> evaluateSource(String source) async {
    final parser = MacroGrammarDefinition().build();
    final result = parser.parse(source);
    if (result is Failure) {
      final pos = result.position;
      final start = pos > 30 ? pos - 30 : 0;
      final end = pos + 40 < source.length ? pos + 40 : source.length;
      final snippet = source
          .substring(start, end)
          .replaceAll('\n', '\\n')
          .replaceAll('\r', '\\r');
      final lineCol = _lineColumn(source, pos);
      onError(
        'Parse error at line ${lineCol.$1}, col ${lineCol.$2}: '
        '${result.message}\n'
        'Near: "$snippet"',
      );
      return false;
    }
    final program = result.value as Program;
    return evaluate(program);
  }

  /// Evaluate a previously parsed [Program].
  Future<bool> evaluate(Program program) async {
    _vars.clear();
    _echoesDrained = false;
    _breakRequested = false;
    _continueRequested = false;

    try {
      await _evalStatements(program.statements, inLoop: false);
    } on _MacroStopException {
      return false;
    } catch (e) {
      onError('$e');
      return false;
    }

    return true;
  }

  /// Close the instrument connection.
  Future<void> close() async {
    await instrument?.close();
    instrument = null;
  }

  // ── Statement evaluation ───────────────────────────────────────────

  Future<void> _evalStatements(
    List<Statement> stmts, {
    required bool inLoop,
  }) async {
    for (final stmt in stmts) {
      if (isCancelled()) throw _MacroStopException();
      await _evalStmt(stmt, inLoop: inLoop);
      if (_breakRequested) break;
      if (_continueRequested) break;
      if (isCancelled()) throw _MacroStopException();
    }
  }

  Future<void> _evalStmt(Statement stmt, {required bool inLoop}) async {
    switch (stmt) {
      case Comment():
        break;
      case BreakStmt():
        if (!inLoop) _error('break outside of while loop');
        _breakRequested = true;
      case ContinueStmt():
        if (!inLoop) _error('continue outside of while loop');
        _continueRequested = true;
      case FailStmt(:final message, :final concatMessage):
        final resolved = concatMessage != null
            ? _resolveConcatString(concatMessage)
            : message;
        _error(resolved);
      case ConnectStmt(:final ip, :final isVariable, :final concatString):
        if (concatString != null) {
          final resolved = _resolveConcatString(concatString);
          await _evalConnect(resolved);
        } else {
          await _evalConnect(ip, isVariable: isVariable);
        }
        await _doDelay();
      case WaitStmt(:final seconds, :final variableName):
        final duration = () {
          if (variableName case final name?) {
            final resolved = _resolveVar(name);
            final parsed = double.tryParse(resolved);
            if (parsed == null) {
              _error(
                'Variable "$name" has value "$resolved" '
                'which is not a valid number',
              );
            }
            return parsed;
          }
          return seconds;
        }();
        onLog('Macro playback: wait(${variableName ?? duration} s)');
        await delay(duration.toInt().clamp(0, 3600));
      case ScpiStmt(:final command, :final variableName, :final concatString):
        await _ensureDevice();
        final resolved = concatString != null
            ? _resolveConcatString(concatString)
            : variableName != null
            ? _resolveVar(variableName)
            : command;
        if (concatString == null &&
            variableName != null &&
            double.tryParse(resolved) != null) {
          _error(
            'Variable "$variableName" has value "$resolved" which is a '
            'number, not a valid SCPI command string',
          );
        }
        onLog('Macro playback: scpi("$resolved")');
        await instrument!.writeString(resolved);
        await _doDelay();
      case QueryStmt(:final command, :final variableName, :final concatString):
        await _ensureDevice();
        await _drainEchoes();
        final resolved = concatString != null
            ? _resolveConcatString(concatString)
            : variableName != null
            ? _resolveVar(variableName)
            : command;
        if (concatString == null &&
            variableName != null &&
            double.tryParse(resolved) != null) {
          _error(
            'Variable "$variableName" has value "$resolved" which is a '
            'number, not a valid SCPI query string',
          );
        }
        onLog('Macro playback: query("$resolved")');
        await instrument!.writeString(resolved);
        final raw = await instrument!.readString();
        final response = _cleanQueryResponse(raw, resolved);
        onLog('Macro query response: $response');
        await _doDelay();
      case AssignStmt(:final varName, :final value):
        final result = await _evalExpr(value);
        final stored = switch (result) {
          double d => d.toStringAsFixed(4),
          int i => i.toStringAsFixed(4),
          _ => result.toString(),
        };
        _vars[varName] = stored;
        onLog('Macro variable: $varName=$stored');
        await _doDelay();
      case PrintStmt(:final items):
        await _evalPrint(items);
        await _doDelay();
      case AssertStmt(:final text, :final concatText, :final condition):
        final resolvedText = concatText != null
            ? _resolveConcatString(concatText)
            : text;
        await _evalAssert(resolvedText, condition);
        await _doDelay();
      case LoadProfileStmt(:final path, :final concatString):
        await _ensureDevice();
        final resolved = concatString != null
            ? _resolveConcatString(concatString)
            : path;
        await _evalLoadProfile(resolved);
        await _doDelay();
      case IfStmt(:final condition, :final thenBody, :final elseBody):
        await _evalIf(condition, thenBody, elseBody, inLoop);
      case WhileStmt(:final condition, :final body):
        await _evalWhile(condition, body);
    }
  }

  // ── Command implementations ────────────────────────────────────────

  Future<void> _evalConnect(String? ip, {bool isVariable = false}) async {
    await instrument?.close();
    if (ip == null) {
      onLog('Macro playback: connect via USB (USBTMC)');
      Vxi11Instrument.isUsbMode = true;
      instrument = Vxi11Instrument('usb', sourceLabel: 'macroPlay');
      await instrument!.open(timeoutSeconds: 5.0);
      return;
    }
    final resolved = isVariable ? _resolveVar(ip) : ip;
    onLog('Macro playback: connect to $resolved');
    Vxi11Instrument.isUsbMode = false;
    instrument = Vxi11Instrument(resolved, sourceLabel: 'macroPlay');
    await instrument!.open(timeoutSeconds: 5.0);
  }

  String _resolveVar(String name) {
    final value = _vars[name];
    if (value == null) {
      _error('Variable "$name" is undefined');
    }
    return value;
  }

  /// Resolve a [ConcatString] into a single string by concatenating all
  /// pieces — resolving variable references at evaluation time.
  String _resolveConcatString(ConcatString cs) {
    final buf = StringBuffer();
    for (final piece in cs.pieces) {
      switch (piece) {
        case ConcatTextPiece(:final text):
          buf.write(text);
        case ConcatVarPiece(:final name):
          buf.write(_resolveVar(name));
      }
    }
    return buf.toString();
  }

  /// Evaluates a unified expression and returns the result.
  ///
  /// The result type depends on the expression:
  /// - [NumberLiteral] → `double`
  /// - [StringLiteral] → `String`
  /// - [BoolLiteral] → `bool`
  /// - [Variable] → resolved value (String, parsed double if arithmetic ctx)
  /// - [QueryExpr] → query response string
  /// - [BinaryExpr] with arithmetic op → `double`
  /// - [BinaryExpr] with comparison/logical op → `bool`
  /// - [NotExpr] → `bool`
  /// - [UnaryMinusExpr] → `double`
  ///
  /// If the expression cannot be evaluated (e.g. string used with `>`),
  /// an error is reported and [_MacroStopException] is thrown.
  Future<Object> _evalExpr(Expr expr) async {
    switch (expr) {
      // ── Literals ──────────────────────────────────────────────────
      case NumberLiteral(:final value):
        return value;

      case StringLiteral(:final value):
        return value;

      case BoolLiteral(:final value):
        return value;

      // ── Variable ──────────────────────────────────────────────────
      case Variable(:final name):
        final varValue = _vars[name];
        if (varValue == null) _error('Variable "$name" is undefined');
        return varValue;

      // ── Query ─────────────────────────────────────────────────────
      case QueryExpr(:final command, :final variableName, :final concatString):
        await _ensureDevice();
        await _drainEchoes();
        final cmd = concatString != null
            ? _resolveConcatString(concatString)
            : variableName != null
            ? _resolveVar(variableName)
            : command;
        if (concatString == null &&
            variableName != null &&
            double.tryParse(cmd) != null) {
          _error(
            'Variable "$variableName" has value "$cmd" which is a '
            'number, not a valid SCPI query string',
          );
        }
        await instrument!.writeString(cmd);
        final raw = await instrument!.readString();
        final response = _cleanQueryResponse(raw, cmd);
        return response;

      // ── Scpi ──────────────────────────────────────────────────────
      case ScpiExpr():
        _error('scpi() cannot be used as an expression value '
            '(it returns no value)');

      // ── Unary minus ───────────────────────────────────────────────
      case UnaryMinusExpr(:final operand):
        final val = await _evalExpr(operand);
        final num = _asNumber(val, 'unary minus (-)');
        return -num;

      // ── Logical NOT ───────────────────────────────────────────────
      case NotExpr(:final operand):
        final val = await _evalExpr(operand);
        final b = _asBool(val, "the '!' operator");
        return !b;

      // ── Binary expression ─────────────────────────────────────────
      case BinaryExpr(:final left, :final op, :final right):
        return await _evalBinaryExpr(left, op, right);
    }
  }

  /// Evaluates a binary expression, dispatching on the operator type.
  Future<Object> _evalBinaryExpr(Expr left, String op, Expr right) async {
    return switch (op) {
      // ── Logical operators (short-circuit) ─────────────────────────
      '&&' || '&' => () async {
        final l = _asBool(await _evalExpr(left), op);
        if (!l) return false; // short-circuit
        final r = _asBool(await _evalExpr(right), op);
        return l && r;
      }(),

      '||' || '|' => () async {
        final l = _asBool(await _evalExpr(left), op);
        if (l) return true; // short-circuit
        final r = _asBool(await _evalExpr(right), op);
        return l || r;
      }(),

      // ── Equality ─────────────────────────────────────────────────
      '==' || '!=' => () async {
        final l = await _evalExpr(left);
        final r = await _evalExpr(right);
        return _compareEquality(l, r, op);
      }(),

      // ── Relational ───────────────────────────────────────────────
      '>' || '>=' || '<' || '<=' => () async {
        final l = _asNumber(await _evalExpr(left), op);
        final r = _asNumber(await _evalExpr(right), op);
        return switch (op) {
          '>' => l > r,
          '>=' => l >= r,
          '<' => l < r,
          '<=' => l <= r,
          _ => _error('Unknown relational operator "$op"'),
        };
      }(),

      // ── Arithmetic ───────────────────────────────────────────────
      '+' || '-' || '*' || '/' => () async {
        final l = _asNumber(await _evalExpr(left), op);
        final r = _asNumber(await _evalExpr(right), op);
        return switch (op) {
          '+' => l + r,
          '-' => l - r,
          '*' => l * r,
          '/' => r == 0
              ? _error('Division by zero in arithmetic expression')
              : l / r,
          _ => _error('Unknown arithmetic operator "$op"'),
        };
      }(),

      _ => _error('Unknown operator "$op"'),
    };
  }

  // ── Type coercion helpers ─────────────────────────────────────────

  /// Coerces [value] to a [double].  Strings are parsed; bools and other
  /// types cause an error referencing [context].
  double _asNumber(Object value, String context) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    _error(
      'Cannot use ${_describeValue(value)} with $context '
      '(a number is required)',
    );
  }

  /// Coerces [value] to a [bool].  Numbers and strings use truthiness
  /// rules; bools pass through.
  bool _asBool(Object value, String context) {
    if (value is bool) return value;
    if (value is String) return _isTruthy(value);
    if (value is num) return value != 0;
    _error(
      'Cannot use ${_describeValue(value)} with $context '
      '(a boolean is required)',
    );
  }

  /// Human-readable description of a runtime value for error messages.
  String _describeValue(Object value) {
    if (value is String) return '"$value"';
    if (value is bool) return '$value';
    if (value is num) return '$value';
    return '${value.runtimeType}';
  }

  // ── Equality comparison ───────────────────────────────────────────

  /// Compares two values for equality / inequality.
  ///
  /// When both sides parse as numbers, numeric comparison is used.
  /// Otherwise, string comparison is used.
  bool _compareEquality(Object lhs, Object rhs, String op) {
    final lhsStr = lhs.toString();
    final rhsStr = rhs.toString();
    final lhsNum = double.tryParse(lhsStr);
    final rhsNum = double.tryParse(rhsStr);

    final equal = (lhsNum != null && rhsNum != null)
        ? lhsNum == rhsNum
        : lhsStr == rhsStr;

    return op == '==' ? equal : !equal;
  }

  // ── Assert evaluation ─────────────────────────────────────────────

  /// Evaluate an assert statement with a unified expression condition.
  Future<void> _evalAssert(String text, Expr condition) async {
    // Special case: ScpiExpr in assert means "SCPI command success".
    if (condition is ScpiExpr) {
      await _evalAssertScpi(text, condition);
      return;
    }

    final result = await _evalExpr(condition);
    final passed = _asBool(result, 'assert() condition');

    if (!passed) {
      _error('Assertion failed: $text');
    }
    onLog('Macro assert: $text → $passed');
  }

  /// Handle `assert("text", scpi("CMD"))` — success if the command
  /// executes without error.
  Future<void> _evalAssertScpi(String text, ScpiExpr scpi) async {
    await _ensureDevice();
    final resolved = scpi.variableName != null
        ? _resolveVar(scpi.variableName!)
        : scpi.command;
    if (scpi.variableName != null && double.tryParse(resolved) != null) {
      _error(
        'Variable "${scpi.variableName}" has value "$resolved" which is a '
        'number, not a valid SCPI command string',
      );
    }
    onLog('Macro assert-scpi: "$text" scpi("$resolved")');
    await instrument!.writeString(resolved);
    onLog('Macro assert: $text: scpi("$resolved") → OK');
  }

  // ── Print evaluation ──────────────────────────────────────────────

  Future<void> _evalLoadProfile(String path) async {
    onLog('Macro playback: loadProfile("$path")');
    final file = File(path);
    if (!await file.exists()) {
      _error('loadProfile("$path"): file not found');
    }
    final xml = await file.readAsString();
    await instrument!.writeProfileData(
      xml,
      timeout: const Duration(seconds: 15),
    );
    await instrument!.writeString('*OPC?');
    await instrument!.readString();
  }

  Future<void> _evalPrint(List<PrintItem> items) async {
    final buf = StringBuffer();
    for (final item in items) {
      buf.write(await _resolvePrintItem(item));
    }
    onLog('Macro print: ${buf.toString()}');
  }

  Future<String> _resolvePrintItem(PrintItem item) async {
    switch (item) {
      case TextItem(:final text):
        return text;
      case VariableItem(:final name):
        final value = _vars[name];
        if (value == null) _error('Variable "$name" is undefined in print()');
        return value;
      case QueryItem(:final command, :final variableName, :final concatString):
        await _ensureDevice();
        await _drainEchoes();
        final resolved = concatString != null
            ? _resolveConcatString(concatString)
            : variableName != null
            ? _resolveVar(variableName)
            : command;
        if (concatString == null &&
            variableName != null &&
            double.tryParse(resolved) != null) {
          _error(
            'Variable "$variableName" has value "$resolved" which is a '
            'number, not a valid SCPI query string',
          );
        }
        await instrument!.writeString(resolved);
        final raw = await instrument!.readString();
        return _cleanQueryResponse(raw, resolved);
    }
  }

  Future<void> _evalIf(
    Expr condition,
    List<Statement> thenBody,
    List<Statement>? elseBody,
    bool inLoop,
  ) async {
    final result = await _evalExpr(condition);
    final cond = _asBool(result, 'if() condition');

    if (cond) {
      await _evalStatements(thenBody, inLoop: inLoop);
    } else if (elseBody != null) {
      await _evalStatements(elseBody, inLoop: inLoop);
    }
  }

  Future<void> _evalWhile(Expr condition, List<Statement> body) async {
    var iterations = 0;

    while (true) {
      if (isCancelled()) throw _MacroStopException();

      final result = await _evalExpr(condition);
      final cond = _asBool(result, 'while() condition');
      if (!cond) break;

      if (iterations >= 100) {
        _error('while loop exceeded maximum of 100 iterations');
      }

      _breakRequested = false;
      _continueRequested = false;
      await _evalStatements(body, inLoop: true);

      if (_breakRequested) break;
      // continue falls through — next iteration
      iterations++;
    }
    _breakRequested = false;
    _continueRequested = false;
  }

  // ── Helpers ────────────────────────────────────────────────────────

  Future<void> _ensureDevice() async {
    if (instrument == null) {
      _error(
        'No device connected. Add connect("IP") at the start of the macro.',
      );
    }
  }

  Future<void> _doDelay() => delay(1);

  Future<void> _drainEchoes() async {
    if (_echoesDrained || instrument == null) return;
    _echoesDrained = true;
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        final data = await instrument!.readString();
        if (data.isEmpty) break;
      } catch (_) {
        break;
      }
    }
  }

  Never _error(String message) {
    onError(message);
    throw _MacroStopException();
  }

  // ── Static utility methods ─────────────────────────────────────────

  /// Returns the (line, column) 1-based coordinates for [offset] in [source].
  static (int, int) _lineColumn(String source, int offset) {
    var line = 1;
    var col = 1;
    for (var i = 0; i < offset && i < source.length; i++) {
      if (source[i] == '\n') {
        line++;
        col = 1;
      } else {
        col++;
      }
    }
    return (line, col);
  }

  static bool _isTruthy(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed == '0') return false;
    if (trimmed.toUpperCase() == 'OFF') return false;
    return true;
  }

  static String _cleanQueryResponse(String raw, String cmd) {
    var response = raw.trim();

    if (response.startsWith(cmd)) {
      response = response.substring(cmd.length);
    } else {
      final cmdNoQuery = cmd.replaceAll('?', '');
      if (response.startsWith(cmdNoQuery)) {
        response = response.substring(cmdNoQuery.length);
      }
    }

    response = response.trim();
    if (response.startsWith(',')) {
      response = response.substring(1).trim();
    }

    response = response.replaceFirst(RegExp(r'(?<=\d)[a-zA-Z%]+$'), '');
    return response;
  }
}

class _MacroStopException implements Exception {}
