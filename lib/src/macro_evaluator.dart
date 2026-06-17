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
      // Extract a snippet of the source around the failure position for context.
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
      case AssignStmt(
        :final varName,
        :final queryOrValue,
        :final isQuery,
        :final isVariable,
        :final arithExpr,
        :final concatString,
      ):
        if (arithExpr != null) {
          final result = await _evalArithExpr(arithExpr);
          _vars[varName] = result.toStringAsFixed(4);
          onLog('Macro variable: $varName=${_vars[varName]}');
        } else if (isQuery) {
          await _ensureDevice();
          await _drainEchoes();
          final command = concatString != null
              ? _resolveConcatString(concatString)
              : isVariable
              ? _resolveVar(queryOrValue)
              : queryOrValue;
          if (concatString == null &&
              isVariable &&
              double.tryParse(command) != null) {
            _error(
              'Variable "$queryOrValue" has value "$command" which is a '
              'number, not a valid SCPI command string',
            );
          }
          onLog('Macro playback: query("$command") -> $varName');
          await instrument!.writeString(command);
          final raw = await instrument!.readString();
          final response = _cleanQueryResponse(raw, command);
          _vars[varName] = response;
          onLog('Macro variable: $varName=$response');
        } else {
          _vars[varName] = queryOrValue;
          onLog('Macro variable: $varName=$queryOrValue');
        }
        await _doDelay();
      case PrintStmt(:final items):
        await _evalPrint(items);
        await _doDelay();
      case AssertStmt(
        :final text,
        :final operand,
        :final op,
        :final expectedValue,
        :final concatText,
        :final expectedIsVariable,
      ):
        final resolvedText = concatText != null
            ? _resolveConcatString(concatText)
            : text;
        await _evalAssert(
          resolvedText,
          operand,
          op,
          expectedValue,
          expectedIsVariable: expectedIsVariable,
        );
        await _doDelay();
      case LoadProfileStmt(:final path, :final concatString):
        await _ensureDevice();
        final resolved = concatString != null
            ? _resolveConcatString(concatString)
            : path;
        await _evalLoadProfile(resolved);
        await _doDelay();
      case IfStmt(
        :final condition,
        :final op,
        :final value,
        :final thenBody,
        :final elseBody,
        :final valueIsVariable,
      ):
        await _evalIf(
          condition,
          op,
          value,
          thenBody,
          elseBody,
          inLoop,
          valueIsVariable: valueIsVariable,
        );
      case WhileStmt(
        :final condition,
        :final op,
        :final value,
        :final body,
        :final valueIsVariable,
      ):
        await _evalWhile(
          condition,
          op,
          value,
          body,
          valueIsVariable: valueIsVariable,
        );
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

  /// Evaluates an arithmetic expression and returns the numeric result.
  Future<double> _evalArithExpr(ArithExpr expr) async {
    switch (expr) {
      case ArithNumber(:final value):
        return value;
      case ArithVariable(:final name):
        final varValue = _vars[name];
        if (varValue == null) _error('Variable "$name" is undefined');
        final parsed = double.tryParse(varValue);
        if (parsed == null) {
          _error(
            'Variable "$name" has value "$varValue" which is not a number',
          );
        }
        return parsed;
      case ArithQuery(:final command, :final variableName, :final concatString):
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
        final parsed = double.tryParse(response);
        if (parsed == null) {
          _error('Query response "$response" is not a valid number');
        }
        return parsed;
      case ArithBinaryOp(:final left, :final op, :final right):
        final l = await _evalArithExpr(left);
        final r = await _evalArithExpr(right);
        return switch (op) {
          '+' => l + r,
          '-' => l - r,
          '*' => l * r,
          '/' =>
            r == 0
                ? _error('Division by zero in arithmetic expression')
                : l / r,
          _ => _error('Unknown arithmetic operator "$op"'),
        };
    }
  }

  Future<void> _evalAssert(
    String text,
    Expression operand,
    String? op,
    String? expectedValue, {
    bool expectedIsVariable = false,
  }) async {
    // Resolve the expected value if it is a variable reference.
    final resolvedExpected = expectedIsVariable && expectedValue != null
        ? _resolveVar(expectedValue)
        : expectedValue;

    switch (operand) {
      case VariableExpr(:final name):
        final varValue = _vars[name];
        if (varValue == null) _error('Variable "$name" is undefined');
        if (op == null || resolvedExpected == null) {
          if (!_isTruthy(varValue)) {
            _error('Assertion failed: $text (got "$varValue")');
          }
          onLog('Macro assert: $text: "$varValue" → True');
        } else {
          final result = _compareValues(varValue, op, resolvedExpected);
          if (result == false) {
            _error('Assertion failed: $text ($varValue $op $resolvedExpected)');
          } else if (result == null) {
            _error(
              'Assertion failed: $text – cannot compare "$varValue" '
              '$op "$resolvedExpected" (non-numeric values with "$op")',
            );
          }
          onLog('Macro assert: $text: $varValue $op $resolvedExpected → True');
        }

      case QueryExpr(:final command, :final variableName, :final concatString):
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
        onLog('Macro assert-query: "$text" query("$resolved")');
        await instrument!.writeString(resolved);
        final raw = await instrument!.readString();
        final response = _cleanQueryResponse(raw, resolved);
        if (op == null || resolvedExpected == null) {
          if (!_isTruthy(response)) {
            _error('Assertion failed: $text (got "$response")');
          }
          onLog('Macro assert: $text: "$response" → True');
        } else {
          final result = _compareValues(response, op, resolvedExpected);
          if (result == false) {
            _error('Assertion failed: $text ($response $op $resolvedExpected)');
          } else if (result == null) {
            _error(
              'Assertion failed: $text – cannot compare "$response" '
              '$op "$resolvedExpected" (non-numeric values with "$op")',
            );
          }
          onLog('Macro assert: $text: $response $op $resolvedExpected → True');
        }

      case ScpiExpr(:final command, :final variableName):
        await _ensureDevice();
        final resolved = variableName != null
            ? _resolveVar(variableName)
            : command;
        if (variableName != null && double.tryParse(resolved) != null) {
          _error(
            'Variable "$variableName" has value "$resolved" which is a '
            'number, not a valid SCPI command string',
          );
        }
        onLog('Macro assert-scpi: "$text" scpi("$resolved")');
        await instrument!.writeString(resolved);
        onLog('Macro assert: $text: scpi("$resolved") → OK');
    }
  }

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
    Expression condition,
    String op,
    String value,
    List<Statement> thenBody,
    List<Statement>? elseBody,
    bool inLoop, {
    bool valueIsVariable = false,
  }) async {
    final resolvedValue = valueIsVariable ? _resolveVar(value) : value;
    final result = await _evalCondition(condition, op, resolvedValue);
    if (result == null) return;

    if (result) {
      await _evalStatements(thenBody, inLoop: inLoop);
    } else if (elseBody != null) {
      await _evalStatements(elseBody, inLoop: inLoop);
    }
  }

  Future<void> _evalWhile(
    Expression condition,
    String op,
    String value,
    List<Statement> body, {
    bool valueIsVariable = false,
  }) async {
    var iterations = 0;

    while (true) {
      if (isCancelled()) throw _MacroStopException();

      final resolvedValue = valueIsVariable ? _resolveVar(value) : value;
      final result = await _evalCondition(condition, op, resolvedValue);
      if (result == null) return;
      if (!result) break;

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

  // ── Condition evaluation ───────────────────────────────────────────

  Future<bool?> _evalCondition(
    Expression condition,
    String op,
    String value,
  ) async {
    switch (condition) {
      case VariableExpr(:final name):
        final varValue = _vars[name];
        if (varValue == null) {
          _error('Variable "$name" is undefined');
        }
        return _compareValues(varValue, op, value);

      case QueryExpr(:final command, :final variableName, :final concatString):
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
        final response = _cleanQueryResponse(raw, resolved);
        return _compareValues(response, op, value);

      case ScpiExpr():
        _error('scpi() cannot be used in a condition (it returns no value)');
    }
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

  static bool? _compareValues(String lhs, String op, String rhs) {
    final lhsNum = double.tryParse(lhs);
    final rhsNum = double.tryParse(rhs);

    switch (op) {
      case '==':
        if (lhsNum != null && rhsNum != null) return lhsNum == rhsNum;
        return lhs == rhs;
      case '!=':
        if (lhsNum != null && rhsNum != null) return lhsNum != rhsNum;
        return lhs != rhs;
      case '<':
      case '<=':
      case '>':
      case '>=':
        if (lhsNum == null || rhsNum == null) return null;
        return switch (op) {
          '<' => lhsNum < rhsNum,
          '<=' => lhsNum <= rhsNum,
          '>' => lhsNum > rhsNum,
          '>=' => lhsNum >= rhsNum,
          _ => null,
        };
    }
    return null;
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
