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
      final snippet = source.substring(start, end)
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
      case ConnectStmt(:final ip, :final isVariable):
        await _evalConnect(ip, isVariable: isVariable);
        await _doDelay();
      case WaitStmt(:final seconds):
        onLog('Macro playback: wait($seconds s)');
        await delay(seconds.toInt().clamp(0, 3600));
      case ScpiStmt(:final command):
        await _ensureDevice();
        onLog('Macro playback: scpi("$command")');
        await instrument!.writeString(command);
        await _doDelay();
      case QueryStmt(:final command):
        await _ensureDevice();
        await _drainEchoes();
        onLog('Macro playback: query("$command")');
        await instrument!.writeString(command);
        final raw = await instrument!.readString();
        final response = _cleanQueryResponse(raw, command);
        onLog('Macro query response: $response');
        await _doDelay();
      case AssignStmt(:final varName, :final queryOrValue, :final isQuery):
        if (isQuery) {
          await _ensureDevice();
          await _drainEchoes();
          onLog('Macro playback: query("$queryOrValue") -> $varName');
          await instrument!.writeString(queryOrValue);
          final raw = await instrument!.readString();
          final response = _cleanQueryResponse(raw, queryOrValue);
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
      case AssertStmt(:final text, :final operand, :final op, :final expectedValue):
        await _evalAssert(text, operand, op, expectedValue);
        await _doDelay();
      case LoadProfileStmt(:final path):
        await _ensureDevice();
        await _evalLoadProfile(path);
        await _doDelay();
      case IfStmt(:final condition, :final op, :final value, :final thenBody, :final elseBody):
        await _evalIf(condition, op, value, thenBody, elseBody, inLoop);
      case WhileStmt(:final condition, :final op, :final value, :final body):
        await _evalWhile(condition, op, value, body);
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
    return value!;
  }

  Future<void> _evalAssert(
    String text,
    Expression operand,
    String? op,
    String? expectedValue,
  ) async {
    switch (operand) {
      case VariableExpr(:final name):
        final varValue = _vars[name];
        if (varValue == null) _error('Variable "$name" is undefined');
        if (op == null || expectedValue == null) {
          if (!_isTruthy(varValue!)) {
            _error('Assertion failed: $text (got "$varValue")');
          }
          onLog('Macro assert: $text: "$varValue" → True');
        } else {
          final result = _compareValues(varValue!, op, expectedValue);
          if (result == false) {
            _error('Assertion failed: $text ($varValue $op $expectedValue)');
          } else if (result == null) {
            return;
          }
          onLog('Macro assert: $text: $varValue $op $expectedValue → True');
        }

      case QueryExpr(:final command):
        await _ensureDevice();
        await _drainEchoes();
        onLog('Macro assert-query: "$text" query("$command")');
        await instrument!.writeString(command);
        final raw = await instrument!.readString();
        final response = _cleanQueryResponse(raw, command);
        if (op == null || expectedValue == null) {
          if (!_isTruthy(response)) {
            _error('Assertion failed: $text (got "$response")');
          }
          onLog('Macro assert: $text: "$response" → True');
        } else {
          final result = _compareValues(response, op, expectedValue);
          if (result == false) {
            _error('Assertion failed: $text ($response $op $expectedValue)');
          } else if (result == null) {
            return;
          }
          onLog('Macro assert: $text: $response $op $expectedValue → True');
        }

      case ScpiExpr(:final command):
        await _ensureDevice();
        onLog('Macro assert-scpi: "$text" scpi("$command")');
        await instrument!.writeString(command);
        onLog('Macro assert: $text: scpi("$command") → OK');
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
        return _vars[name] ?? '<undefined>';
      case QueryItem(:final command):
        await _ensureDevice();
        await _drainEchoes();
        await instrument!.writeString(command);
        final raw = await instrument!.readString();
        return _cleanQueryResponse(raw, command);
    }
  }

  Future<void> _evalIf(
    Expression condition,
    String op,
    String value,
    List<Statement> thenBody,
    List<Statement>? elseBody,
    bool inLoop,
  ) async {
    final result = await _evalCondition(condition, op, value);
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
    List<Statement> body,
  ) async {
    var iterations = 0;

    while (true) {
      if (isCancelled()) throw _MacroStopException();

      final result = await _evalCondition(condition, op, value);
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
          return null;
        }
        return _compareValues(varValue, op, value);

      case QueryExpr(:final command):
        await _ensureDevice();
        await _drainEchoes();
        await instrument!.writeString(command);
        final raw = await instrument!.readString();
        final response = _cleanQueryResponse(raw, command);
        return _compareValues(response, op, value);

      case ScpiExpr():
        _error('scpi() cannot be used in a condition (it returns no value)');
        return null;
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
