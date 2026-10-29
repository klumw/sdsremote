import 'dart:io';

import 'package:petitparser/petitparser.dart';

import '../core/logger.dart';
import '../instrument/dart_vxi11.dart';
import 'macro_ast.dart';
import 'macro_grammar.dart';
import 'macro_print_formatter.dart';
import 'macro_siggen.dart';

/// Creates the VXI-11 instrument behind `connect("IP")` and the device
/// handles opened by `myscope = connect("192.168.1.100")`.
///
/// The application keeps the default factory; tests inject a fake.
typedef MacroInstrumentFactory = Vxi11Instrument Function(String host);

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
  final Future<void> Function(Duration duration) delay;
  final void Function(String message) onLog;

  /// Creates the instruments for `connect("IP")` and for device handles.
  final MacroInstrumentFactory _createInstrument;

  /// Device handles bound by `myscope = connect("IP")`, keyed by variable
  /// name.
  final Map<String, _MacroDeviceHandle> _handles = {};

  /// Opens the signal generator addressed by `connect(SIG, usb)`.
  ///
  /// The host application injects the connector; without one the `SIG`
  /// commands report that signal generator support is unavailable.
  final MacroSiggenConnector _siggenConnector;

  /// Signal-generator session opened by `connect(SIG, usb)`.
  MacroSiggenSession? _siggen;

  /// Called with the formatted output of each executed `print()` statement.
  ///
  /// Unlike [onLog], this receives only the print text, without the
  /// `Macro print: ` prefix, so it can be shown verbatim in the Macro
  /// Editor's print panel.
  final void Function(String message)? onPrint;

  /// Called before each non-comment statement. The returned future is awaited
  /// before the statement executes.
  ///
  /// The Macro Editor's step-by-step debugger uses this to pause between
  /// statements: the future completes when the user presses Step. Comments
  /// are skipped and do not consume a step.
  final Future<void> Function(Statement statement)? onBeforeStatement;

  final Map<String, String> _vars = {};

  /// Display unit (`Hz` or `V`) of variables assigned from a recognized SCPI
  /// measurement query. Used by `print()` to show readable values.
  final Map<String, String> _varUnits = <String, String>{};

  /// 1-based source line of each parsed statement, used by the debugger for
  /// breakpoints and current-line highlighting.
  final Map<Statement, int> _statementLines = {};

  /// The variable values of the current (or most recent) evaluation.
  ///
  /// The debugger shows this map after every step.
  Map<String, String> get variables => Map<String, String>.unmodifiable(_vars);

  /// The 1-based source line of [statement], or null when it is unknown.
  int? lineForStatement(Statement statement) => _statementLines[statement];

  bool _echoesDrained = false;
  bool _breakRequested = false;
  bool _continueRequested = false;

  MacroEvaluator({
    this.instrument,
    required this.onError,
    required this.isCancelled,
    this.delay = _defaultDelay,
    this.onLog = _defaultLog,
    this.onPrint,
    this.onBeforeStatement,
    MacroSiggenConnector? siggenConnector,
    MacroInstrumentFactory? instrumentFactory,
  }) : _siggenConnector = siggenConnector ?? unavailableMacroSiggenConnector,
       _createInstrument = instrumentFactory ?? _defaultInstrumentFactory;

  static Vxi11Instrument _defaultInstrumentFactory(String host) =>
      Vxi11Instrument(host, sourceLabel: 'macroPlay');

  static Future<void> _defaultDelay(Duration duration) =>
      Future.delayed(duration);

  static void _defaultLog(String message) => AppLogger().log(message);

  /// Parse [source] into a [Program], or return null after reporting a parse
  /// error through [onError].
  ///
  /// Splitting parsing from evaluation lets the step debugger prepare a
  /// program and then drive it statement by statement.
  Program? parseSource(String source) {
    _statementLines.clear();
    final parser = MacroGrammarDefinition(
      onStatement: (statement, start, stop) {
        _statementLines[statement] = _lineColumn(source, start).$1;
      },
    ).build();
    final result = parser.parse(source);
    if (result is Failure) {
      _statementLines.clear();
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
      return null;
    }
    return result.value as Program;
  }

  /// Parse [source] and evaluate the resulting program.
  ///
  /// Returns `true` if the macro completed successfully, `false` if an
  /// error occurred or playback was cancelled.
  Future<bool> evaluateSource(String source) async {
    final program = parseSource(source);
    if (program == null) return false;
    return evaluate(program);
  }

  /// Evaluate a previously parsed [Program].
  Future<bool> evaluate(Program program) async {
    await _closeHandles();
    _vars.clear();
    _varUnits.clear();
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

  /// Close the oscilloscope and signal-generator connections and every
  /// device handle opened by `myscope = connect("IP")`.
  Future<void> close() async {
    await instrument?.close();
    instrument = null;
    await _closeSiggen();
    await _closeHandles();
  }

  /// Closes the device handle bound to [varName], if any.
  Future<void> _releaseHandle(String varName) async {
    final handle = _handles.remove(varName);
    if (handle == null) return;
    try {
      await handle.instrument.close();
    } catch (e) {
      onLog('Macro playback: closing device handle $varName failed: $e');
    }
  }

  /// Closes every device handle opened by `myscope = connect("IP")`.
  Future<void> _closeHandles() async {
    for (final name in _handles.keys.toList()) {
      await _releaseHandle(name);
    }
  }

  /// Closes the signal-generator session without failing the macro.
  Future<void> _closeSiggen() async {
    final session = _siggen;
    _siggen = null;
    if (session == null) return;
    try {
      await session.close();
    } catch (e) {
      onLog('Macro playback: closing the signal generator failed: $e');
    }
  }

  // ── Statement evaluation ───────────────────────────────────────────

  Future<void> _evalStatements(
    List<Statement> stmts, {
    required bool inLoop,
  }) async {
    for (final stmt in stmts) {
      if (isCancelled()) throw _MacroStopException();
      if (stmt is! Comment) {
        await onBeforeStatement?.call(stmt);
        // The gate may have been released by a stop request.
        if (isCancelled()) throw _MacroStopException();
      }
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
      case ConnectStmt(
        :final ip,
        :final isVariable,
        :final concatString,
        :final device,
      ):
        if (concatString != null) {
          await _evalConnect(device, _resolveConcatString(concatString));
        } else {
          await _evalConnect(device, ip, isVariable: isVariable);
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
        final clamped = duration.clamp(0.0, 3600.0);
        await delay(Duration(milliseconds: (clamped * 1000).round()));
      case ScpiStmt(
        :final command,
        :final variableName,
        :final concatString,
        :final device,
      ):
        // Resolve first so a handle used as command text is reported as
        // such, even when no default device is connected.
        final resolved = _resolveScpiText(
          command: command,
          variableName: variableName,
          concatString: concatString,
          kind: 'command',
        );
        if (_isSiggen(device)) {
          final session = _requireSiggen();
          onLog('Macro playback: cmd(${_devicePrefix(device)}"$resolved")');
          final response = await session.execute(resolved);
          if (response != null) {
            onLog('Macro query response: $response');
          }
        } else {
          final target = _requireVxiDevice(device);
          onLog('Macro playback: cmd(${_devicePrefix(device)}"$resolved")');
          await target.instrument.writeString(resolved);
        }
        await _doDelay();
      case QueryStmt(
        :final command,
        :final variableName,
        :final concatString,
        :final device,
      ):
        final resolved = _resolveScpiText(
          command: command,
          variableName: variableName,
          concatString: concatString,
          kind: 'query',
        );
        if (_isSiggen(device)) {
          final session = _requireSiggen();
          onLog('Macro playback: query(${_devicePrefix(device)}"$resolved")');
          final response = await session.execute(resolved);
          if (response == null) {
            _error(
              'query(SIG, "$resolved") returned no response; '
              'use cmd(SIG, ...) for set commands',
            );
          }
          onLog('Macro query response: $response');
        } else {
          final target = _requireVxiDevice(device);
          onLog('Macro playback: query(${_devicePrefix(device)}"$resolved")');
          final response = await _queryVxi(target, resolved);
          onLog('Macro query response: $response');
        }
        await _doDelay();
      case AssignStmt(:final varName, :final value):
        if (value is ConnectExpr) {
          await _assignDeviceConnection(varName, value);
        } else {
          // Resolve the unit before the assignment overwrites the variable; a
          // query may use the target variable as its command.
          final unit = _unitForAssignment(value);
          final result = await _evalExpr(value);
          final stored = switch (result) {
            double d => d.toStringAsFixed(4),
            int i => i.toStringAsFixed(4),
            _ => result.toString(),
          };
          // Reassigning a handle variable to a value closes its connection.
          await _releaseHandle(varName);
          _vars[varName] = stored;
          if (unit != null) {
            _varUnits[varName] = unit;
          } else {
            _varUnits.remove(varName);
          }
          onLog('Macro variable: $varName=$stored');
        }
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
        _ensureDevice();
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

  Future<void> _evalConnect(
    String? device,
    String? ip, {
    bool isVariable = false,
  }) async {
    if (device == macroSignalGeneratorDevice) {
      if (ip != null) {
        _error('connect(SIG, ...) only supports usb: use connect(SIG, usb)');
      }
      await _connectSignalGenerator();
      return;
    }
    if (ip == null && _handles.isNotEmpty) {
      _error(
        'connect(usb) cannot be combined with device handles. '
        'Use connect("IP") for the oscilloscope instead.',
      );
    }
    await instrument?.close();
    instrument = null;
    // A new default connection needs its own echo drain.
    _echoesDrained = false;
    if (ip == null) {
      onLog('Macro playback: connect via USB (USBTMC)');
      Vxi11Instrument.isUsbMode = true;
      instrument = _createInstrument('usb');
      await instrument!.open(timeoutSeconds: 5.0);
      return;
    }
    final resolved = isVariable ? _resolveVar(ip) : ip;
    onLog('Macro playback: connect to $resolved');
    Vxi11Instrument.isUsbMode = false;
    instrument = _createInstrument(resolved);
    await instrument!.open(timeoutSeconds: 5.0);
  }

  /// Opens the signal generator configured in the settings.
  Future<void> _connectSignalGenerator() async {
    onLog('Macro playback: connect(SIG, usb)');
    await _closeSiggen();
    try {
      _siggen = await _siggenConnector();
    } on MacroSiggenException {
      rethrow;
    } catch (e) {
      throw MacroSiggenException('Signal generator connection failed: $e');
    }
  }

  /// Opens the VXI-11 connection of `name = connect("IP")` and binds its
  /// handle to [varName].
  ///
  /// Assigning the same address to the same variable again reuses the open
  /// connection; a different address closes the old one first. Only IP
  /// addresses produce a handle — `connect(usb)` and `connect(SIG, usb)`
  /// remain statements.
  Future<void> _assignDeviceConnection(String varName, ConnectExpr expr) async {
    if (expr.device == macroSignalGeneratorDevice) {
      _error(
        'connect(SIG, ...) does not return a device handle. '
        'Use connect("IP") to open an addressable device.',
      );
    }
    if (instrument != null && Vxi11Instrument.isUsbMode) {
      _error(
        'Device handles are network connections and cannot be combined '
        'with connect(usb). Connect the oscilloscope with connect("IP") '
        'instead.',
      );
    }
    final String host;
    if (expr.concatString != null) {
      host = _resolveConcatString(expr.concatString!);
    } else if (expr.isVariable) {
      host = _resolveVar(expr.address!);
    } else if (expr.address != null) {
      host = expr.address!;
    } else {
      _error(
        'connect(usb) does not return a device handle. '
        'Use connect("IP") with the device address.',
      );
    }

    final existing = _handles[varName];
    if (existing != null && existing.host == host) {
      _vars[varName] = host;
      onLog('Macro playback: reusing connection to $host (handle $varName)');
      return;
    }
    await _releaseHandle(varName);

    onLog('Macro playback: connect to $host (handle $varName)');
    // A handle is a VXI-11 connection, like connect("IP").
    Vxi11Instrument.isUsbMode = false;
    final device = _createInstrument(host);
    try {
      await device.open(timeoutSeconds: 5.0);
    } catch (_) {
      try {
        await device.close();
      } catch (_) {
        // The failed open already cleaned up.
      }
      rethrow;
    }
    _handles[varName] = _MacroDeviceHandle(
      name: varName,
      host: host,
      instrument: device,
    );
    _vars[varName] = host;
    _varUnits.remove(varName);
  }

  /// Resolves the device selector of `cmd()` / `query()`.
  ///
  /// Without a selector the default oscilloscope connection is used. A
  /// selector names a variable bound by `myscope = connect("IP")`.
  _MacroVxiTarget _requireVxiDevice(String? device) {
    if (device == null) {
      _ensureDevice();
      return (instrument: instrument!, handle: null);
    }
    final handle = _handles[device];
    if (handle != null) {
      return (instrument: handle.instrument, handle: handle);
    }
    _error(
      _vars.containsKey(device)
          ? 'Variable "$device" does not hold a device handle. '
                'Assign it from connect("IP") first, e.g. '
                '$device = connect("192.168.1.100").'
          : 'Variable "$device" is undefined. Open the device first with '
                '$device = connect("192.168.1.100").',
    );
  }

  /// Sends [command] as a query to [target] and returns the cleaned response.
  ///
  /// The first query on each connection drains the command echoes that the
  /// oscilloscope sends back for every received command.
  Future<String> _queryVxi(_MacroVxiTarget target, String command) async {
    final handle = target.handle;
    final drained = handle?.echoesDrained ?? _echoesDrained;
    if (!drained) {
      if (handle != null) {
        handle.echoesDrained = true;
      } else {
        _echoesDrained = true;
      }
      await _drainEchoes(target.instrument);
    }
    await target.instrument.writeString(command);
    final raw = await target.instrument.readString();
    return _cleanQueryResponse(raw, command);
  }

  /// Whether [device] is the signal-generator selector.
  static bool _isSiggen(String? device) => device == macroSignalGeneratorDevice;

  /// Comma-separated device selector for log messages, or an empty string.
  static String _devicePrefix(String? device) =>
      device == null ? '' : '$device, ';

  /// Returns the signal-generator session, or stops the macro if
  /// `connect(SIG, usb)` has not run yet.
  MacroSiggenSession _requireSiggen() {
    final session = _siggen;
    if (session == null) {
      _error(
        'No signal generator connected. '
        'Add connect(SIG, usb) at the start of the macro.',
      );
    }
    return session;
  }

  /// Resolves a `cmd()` / `query()` argument and rejects numeric variables
  /// and device handles, which are never valid SCPI text.
  String _resolveScpiText({
    required String command,
    required String? variableName,
    required ConcatString? concatString,
    required String kind,
  }) {
    final resolved = concatString != null
        ? _resolveConcatString(concatString)
        : variableName != null
        ? _resolveVar(variableName)
        : command;
    if (concatString == null && variableName != null) {
      if (_handles.containsKey(variableName)) {
        final call = kind == 'query' ? 'query' : 'cmd';
        _error(
          'Variable "$variableName" holds a device handle, not a SCPI '
          '$kind string. Use $call($variableName, "...") to address the '
          'device.',
        );
      }
      if (double.tryParse(resolved) != null) {
        _error(
          'Variable "$variableName" has value "$resolved" which is a '
          'number, not a valid SCPI $kind string',
        );
      }
    }
    return resolved;
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
      case QueryExpr(
        :final command,
        :final variableName,
        :final concatString,
        :final device,
      ):
        final cmd = _resolveScpiText(
          command: command,
          variableName: variableName,
          concatString: concatString,
          kind: 'query',
        );
        if (_isSiggen(device)) {
          final session = _requireSiggen();
          final response = await session.execute(cmd);
          if (response == null) {
            _error(
              'query(SIG, "$cmd") returned no response; '
              'use cmd(SIG, ...) for set commands',
            );
          }
          return response;
        }
        final target = _requireVxiDevice(device);
        return _queryVxi(target, cmd);

      // ── Scpi ──────────────────────────────────────────────────────
      case ScpiExpr():
        _error(
          'cmd() cannot be used as an expression value '
          '(it returns no value)',
        );

      // ── Connect ───────────────────────────────────────────────────
      case ConnectExpr():
        _error(
          'connect() opens a device handle and can only be assigned '
          'directly: name = connect("192.168.1.100")',
        );

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
          '/' =>
            r == 0
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
    if (value is _MacroDeviceHandle) return 'the device handle "$value.name"';
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

  /// Handle `assert("text", cmd("CMD"))` — success if the command
  /// executes without error.
  Future<void> _evalAssertScpi(String text, ScpiExpr scpi) async {
    final label = _devicePrefix(scpi.device);
    final resolved = _resolveScpiText(
      command: scpi.command,
      variableName: scpi.variableName,
      concatString: null,
      kind: 'command',
    );
    if (_isSiggen(scpi.device)) {
      final session = _requireSiggen();
      onLog('Macro assert-cmd: "$text" cmd($label"$resolved")');
      await session.execute(resolved);
      onLog('Macro assert: $text: cmd($label"$resolved") → OK');
      return;
    }
    final target = _requireVxiDevice(scpi.device);
    onLog('Macro assert-cmd: "$text" cmd($label"$resolved")');
    await target.instrument.writeString(resolved);
    onLog('Macro assert: $text: cmd($label"$resolved") → OK');
  }

  // ── Print evaluation ──────────────────────────────────────────────

  Future<void> _evalLoadProfile(String path) async {
    onLog('Macro playback: loadProfile("$path")');
    final file = File(path);
    if (!await file.exists()) {
      _error('loadProfile("$path"): file not found');
    }
    _ensureDevice();
    final xml = await file.readAsString();
    // The upload itself is acknowledged immediately, but the instrument then
    // stops answering SCPI queries while it applies the profile. VXI-11
    // reports error 15 and is retried; USB uses one long read instead, because
    // a retried Bulk-IN request has a new bTag and a late response would fail
    // with "bTag mismatch".
    const profileTimeout = Duration(seconds: 30);
    await instrument!.writeProfileData(xml, timeout: profileTimeout);
    await instrument!.awaitProfileApplied();
    if (Vxi11Instrument.isUsbMode) {
      // Applying a profile resets the instrument's USB interface, which
      // invalidates the shared connection. Reopen it so the statements after
      // loadProfile() in the same macro keep working.
      await instrument!.open(timeoutSeconds: 5);
    }
  }

  Future<void> _evalPrint(List<PrintItem> items) async {
    final buf = StringBuffer();
    for (final item in items) {
      buf.write(await _resolvePrintItem(item));
    }
    // Normalize units, value labels and any remaining scientific notation.
    final text = prettyPrintMacroText(buf.toString());
    onPrint?.call(text);
    onLog('Macro print: $text');
  }

  Future<String> _resolvePrintItem(PrintItem item) async {
    switch (item) {
      case TextItem(:final text):
        return text;
      case VariableItem(:final name):
        final value = _vars[name];
        if (value == null) _error('Variable "$name" is undefined in print()');
        return prettyPrintMacroValue(value, unit: _varUnits[name]);
      case QueryItem(
        :final command,
        :final variableName,
        :final concatString,
        :final device,
      ):
        final resolved = _resolveScpiText(
          command: command,
          variableName: variableName,
          concatString: concatString,
          kind: 'query',
        );
        if (_isSiggen(device)) {
          final session = _requireSiggen();
          final response = await session.execute(resolved);
          if (response == null) {
            _error(
              'query(SIG, "$resolved") returned no response; '
              'use cmd(SIG, ...) for set commands',
            );
          }
          return prettyPrintMacroValue(
            response,
            unit: inferMacroUnit(resolved),
          );
        }
        final target = _requireVxiDevice(device);
        final response = await _queryVxi(target, resolved);
        return prettyPrintMacroValue(response, unit: inferMacroUnit(resolved));
    }
  }

  /// Returns the display unit of [expr] when it is a measurement query with a
  /// recognizable unit, or copies a variable that has one.
  String? _unitForAssignment(Expr expr) {
    if (expr is Variable) return _varUnits[expr.name];
    if (expr is! QueryExpr) return null;

    final String command;
    if (expr.concatString != null) {
      command = _resolveConcatString(expr.concatString!);
    } else if (expr.variableName != null) {
      command = _resolveVar(expr.variableName!);
    } else {
      command = expr.command;
    }
    return inferMacroUnit(command);
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

  void _ensureDevice() {
    if (instrument == null) {
      _error(
        'No device connected. Add connect("IP") at the start of the macro.',
      );
    }
  }

  /// Small settle pause after a statement.
  ///
  /// This used to be a full second per statement, which dominated playback
  /// time on macros with many commands. Longer settling is best expressed
  /// explicitly with the `wait()` statement.
  Future<void> _doDelay() => delay(const Duration(milliseconds: 50));

  /// Drains the command echoes a VXI-11 device sends back for received
  /// commands, so they do not pollute the next query response.
  Future<void> _drainEchoes(Vxi11Instrument target) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        final data = await target.readString();
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

/// A VXI-11 target resolved from a `cmd()` / `query()` device selector.
///
/// [handle] is null for the default oscilloscope connection.
typedef _MacroVxiTarget = ({
  Vxi11Instrument instrument,
  _MacroDeviceHandle? handle,
});

/// Runtime binding of `name = connect("IP")`.
class _MacroDeviceHandle {
  _MacroDeviceHandle({
    required this.name,
    required this.host,
    required this.instrument,
  });

  /// Variable name the handle is bound to.
  final String name;

  /// Device address the connection was opened to.
  final String host;

  final Vxi11Instrument instrument;

  /// Whether the first query already drained the command echoes.
  bool echoesDrained = false;

  @override
  String toString() => host;
}
