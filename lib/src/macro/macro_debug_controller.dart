import 'dart:async';

import 'package:flutter/foundation.dart';

import 'macro_ast.dart';
import 'macro_debug.dart';
import 'macro_evaluator.dart';
import 'macro_siggen.dart';

/// Owns the Macro Editor's step-by-step debug session.
///
/// The controller keeps the session state machine, the breakpoints, and the
/// debug cursor. Listeners are notified whenever that state changes; the home
/// page forwards the notification to `setState`.
class MacroDebugController extends ChangeNotifier {
  MacroDebugController({
    required this.readSource,
    required this.beforeStart,
    required this.markPlaybackError,
    required this.hasPlaybackError,
    required this.onError,
    required this.onPrint,
    required this.connectSignalGenerator,
    required this.isMacroPlaying,
  });

  /// Returns the macro source currently shown in the editor.
  final String Function() readSource;

  /// Resets playback-side state before a session starts.
  final void Function() beforeStart;

  /// Marks the surrounding playback state as failed (parse error).
  final void Function() markPlaybackError;

  /// Whether the last playback or debug run reported an error.
  final bool Function() hasPlaybackError;

  /// Reports an evaluator error to the user.
  final void Function(String message) onError;

  /// Receives `print()` output from the evaluator.
  final void Function(String message) onPrint;

  /// Opens the signal generator for `connect(SIG, usb)`.
  final Future<MacroSiggenSession> Function() connectSignalGenerator;

  /// Whether a macro playback is currently running.
  final bool Function() isMacroPlaying;

  _MacroDebugSession? _session;
  String? _status;
  bool _stepPending = false;
  int? _currentLine;
  Map<String, String> _variables = <String, String>{};
  Set<int> _breakpoints = <int>{};
  Set<int> _inactiveBreakpoints = <int>{};
  bool _disposed = false;

  /// Status text shown in the Macro Editor's debug bar.
  String? get status => _status;

  /// Source line of the statement currently highlighted in the editor.
  int? get currentLine => _currentLine;

  /// Variables shown in the debug watch panel.
  Map<String, String> get variables => _variables;

  /// Breakpoints set in the Macro Editor (1-based source lines).
  Set<int> get breakpoints => _breakpoints;

  /// Breakpoints that are currently disabled.
  Set<int> get inactiveBreakpoints => _inactiveBreakpoints;

  /// Whether a debug session is active.
  bool get hasSession => _session != null;

  /// Whether the active session is paused at a statement.
  bool get isPaused => _session?.paused ?? false;

  /// Whether the active session is running.
  bool get isRunning => _session != null && !(_session?.paused ?? false);

  /// Clears the debug status, cursor, and variables (e.g. before playback).
  void clearStatus() {
    _status = null;
    _currentLine = null;
    _variables = <String, String>{};
    _notify();
  }

  /// Clears the editor cursor after the source changed.
  void clearCursor() {
    if (_currentLine == null && _variables.isEmpty) return;
    _currentLine = null;
    _variables = <String, String>{};
    _notify();
  }

  /// Clears everything, including breakpoints (new or loaded macro).
  void reset() {
    _status = null;
    _currentLine = null;
    _variables = <String, String>{};
    _breakpoints = <int>{};
    _inactiveBreakpoints = <int>{};
    _notify();
  }

  /// Marks the active session as failed.
  void markError() {
    if (_session == null) return;
    _status = 'Error';
    _notify();
  }

  void updateBreakpoints(Set<int> breakpoints) {
    final added = breakpoints.difference(_breakpoints);
    _breakpoints = breakpoints;
    // A newly created breakpoint is always active; removed lines no longer
    // belong to the inactive set.
    _inactiveBreakpoints.removeAll(added);
    _inactiveBreakpoints.removeWhere((line) => !breakpoints.contains(line));
    _notify();
  }

  void deleteBreakpoint(int line) {
    _breakpoints.remove(line);
    _inactiveBreakpoints.remove(line);
    _notify();
  }

  void setBreakpointEnabled(int line, bool enabled) {
    if (enabled) {
      _inactiveBreakpoints.remove(line);
    } else {
      _inactiveBreakpoints.add(line);
    }
    _notify();
  }

  void setAllBreakpointsEnabled(bool enabled) {
    if (enabled) {
      _inactiveBreakpoints.clear();
    } else {
      _inactiveBreakpoints = Set<int>.of(_breakpoints);
    }
    _notify();
  }

  void deleteAllBreakpoints() {
    _breakpoints.clear();
    _inactiveBreakpoints.clear();
    _notify();
  }

  void onStep() {
    unawaited(step());
  }

  Future<void> step() async {
    if (_stepPending || isMacroPlaying()) return;
    _stepPending = true;

    try {
      var session = _session;
      if (session == null) {
        session = await _startSession();
        if (session == null || _disposed) return;
      }

      final gate = session.gate;
      if (gate == null || gate.isCompleted) return;

      _status = 'Running step ${session.step}…';
      _notify();
      gate.complete();
    } finally {
      _stepPending = false;
    }
  }

  void onContinue() {
    final session = _session;
    if (session == null || !session.paused) return;

    final gate = session.gate;
    if (gate == null || gate.isCompleted) return;

    session.runToBreakpoint = true;
    _status = 'Continuing…';
    _notify();
    gate.complete();
  }

  void onPlay() {
    final session = _session;
    if (session != null && session.paused) {
      // Play from a breakpoint continues the run. Restarting here would hit
      // the same breakpoint again immediately (especially when it sits on the
      // first executable statement), which looks like Play did nothing.
      onContinue();
      return;
    }
    unawaited(runFromEditor());
  }

  /// Starts a fresh debug run and lets it execute until the first breakpoint
  /// (or the end). Stop followed by Play restarts from the beginning.
  Future<void> runFromEditor() async {
    if (_stepPending || isMacroPlaying()) return;
    _stepPending = true;

    try {
      // Starting a session stops any previous paused run.
      final session = await _startSession();
      if (session == null || _disposed) return;

      // The first gate is paused before statement 1. If it sits on an active
      // breakpoint, stop there instead of executing it.
      final line = session.currentLine;
      if (isMacroBreakpointActive(
        line: line,
        breakpoints: _breakpoints,
        inactiveBreakpoints: _inactiveBreakpoints,
      )) {
        _status =
            'Paused at breakpoint · Step ${session.step}: '
            '${session.statement}';
        _notify();
        return;
      }

      final gate = session.gate;
      if (gate == null || gate.isCompleted) return;

      session.runToBreakpoint = true;
      _status = 'Running…';
      _notify();
      gate.complete();
    } finally {
      _stepPending = false;
    }
  }

  /// Cancels a running debug session and closes its instrument connection.
  Future<void> stop({String status = 'Stopped'}) async {
    final session = _session;
    if (session == null) return;

    session.cancel();
    _status = status;
    _notify();

    final runFuture = session.runFuture;
    if (runFuture != null) {
      // Do not block forever on an in-flight device operation. The run's
      // finally closes the instrument and clears the session.
      await runFuture.timeout(const Duration(seconds: 2), onTimeout: () {});
    }

    if (identical(_session, session)) {
      _session = null;
    }
    _notify();
  }

  /// Starts a paused session for the current editor content.
  ///
  /// Returns the session once it is paused before its first executable
  /// statement, or null when the macro is empty, failed to parse, or contains
  /// no statements to execute.
  Future<_MacroDebugSession?> _startSession() async {
    final source = readSource();
    if (source.trim().isEmpty) {
      onError('Macro is empty');
      return null;
    }

    await stop(status: 'Stopped');

    beforeStart();
    _currentLine = null;
    _variables = <String, String>{};
    _status = 'Preparing…';
    _notify();

    late final _MacroDebugSession session;
    final evaluator = MacroEvaluator(
      onError: onError,
      isCancelled: () => session.cancelled,
      delay: (duration) => Future.any([
        Future<void>.delayed(duration),
        session.cancelSignal.future,
      ]),
      onPrint: onPrint,
      onBeforeStatement: (statement) => _onBeforeStatement(session, statement),
      siggenConnector: connectSignalGenerator,
    );
    session = _MacroDebugSession(evaluator);

    final program = evaluator.parseSource(source);
    if (program == null) {
      markPlaybackError();
      _status = 'Error (parse)';
      _notify();
      return null;
    }

    _session = session;
    session.runFuture = _runSession(session, program);

    // Wait until the evaluator pauses before the first statement. A macro
    // without executable statements finishes immediately and marks the
    // session as finished instead.
    await session.armed.future;
    if (session.finished || session.cancelled) {
      if (identical(_session, session)) {
        _session = null;
      }
      if (session.finished && !session.cancelled) {
        _status = 'Finished';
      }
      _notify();
      return null;
    }
    return session;
  }

  Future<void> _runSession(_MacroDebugSession session, Program program) async {
    try {
      final success = await session.evaluator.evaluate(program);
      if (!session.cancelled) {
        _status = hasPlaybackError()
            ? 'Error'
            : success
            ? 'Finished'
            : 'Stopped';
      }
    } finally {
      final isCurrentSession = identical(_session, session);
      session.finished = true;
      session.markArmed();
      if (isCurrentSession) {
        // Capture values assigned by the last statement, which has no
        // following gate to read them.
        session.variables = session.evaluator.variables;
        _variables = session.variables;
      }
      try {
        await session.evaluator.close();
      } catch (_) {}
      if (isCurrentSession) {
        _session = null;
      }
      _notify();
    }
  }

  /// Gate called by the evaluator before each non-comment statement.
  Future<void> _onBeforeStatement(
    _MacroDebugSession session,
    Statement statement,
  ) async {
    if (session.cancelled) return;

    session.step++;
    session.statement = describeMacroStatement(statement);
    session.currentLine = session.evaluator.lineForStatement(statement);
    session.variables = session.evaluator.variables;
    _currentLine = session.currentLine;
    _variables = session.variables;

    final line = session.currentLine;
    final hitBreakpoint = isMacroBreakpointActive(
      line: line,
      breakpoints: _breakpoints,
      inactiveBreakpoints: _inactiveBreakpoints,
    );

    // Continue mode: skip statements until the next breakpoint. The current
    // line is still updated so the editor highlights what is executing.
    if (session.runToBreakpoint && !hitBreakpoint) {
      _status =
          !hasActiveMacroBreakpoint(
            breakpoints: _breakpoints,
            inactiveBreakpoints: _inactiveBreakpoints,
          )
          ? 'Running to end…'
          : line == null
          ? 'Running…'
          : 'Running to breakpoint · line $line';
      if (identical(_session, session)) {
        _notify();
      }
      return;
    }
    session.runToBreakpoint = false;

    session.paused = true;
    final gate = Completer<void>();
    session.gate = gate;
    session.markArmed();
    final prefix = hitBreakpoint ? 'Paused at breakpoint' : 'Paused';
    _status = '$prefix · Step ${session.step}: ${session.statement}';
    if (identical(_session, session)) {
      _notify();
    }

    await gate.future;

    session.gate = null;
    session.paused = false;
    if (session.cancelled) return;
    _status = 'Running step ${session.step}…';
    if (identical(_session, session)) {
      _notify();
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final session = _session;
    _session = null;
    session?.cancel();
    super.dispose();
  }
}

/// One step-by-step debugging run of the macro in the editor.
///
/// The evaluator runs in the background and pauses before every statement at
/// [gate]. Releasing the gate executes that statement; [cancel] interrupts a
/// paused gate and any in-flight `wait()` delay.
class _MacroDebugSession {
  final MacroEvaluator evaluator;

  /// Completed when the first statement gate is reached, or when the run
  /// ends without reaching one (empty or comment-only macro).
  final Completer<void> armed = Completer<void>();

  /// Completed when the session is cancelled. Races against `wait()` delays
  /// so Stop takes effect immediately.
  final Completer<void> cancelSignal = Completer<void>();

  bool cancelled = false;
  bool paused = false;
  bool finished = false;
  int step = 0;
  String statement = '';
  bool runToBreakpoint = false;
  int? currentLine;
  Map<String, String> variables = <String, String>{};
  Completer<void>? gate;
  Future<void>? runFuture;

  _MacroDebugSession(this.evaluator);

  void markArmed() {
    if (!armed.isCompleted) armed.complete();
  }

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    if (!cancelSignal.isCompleted) cancelSignal.complete();
    final pendingGate = gate;
    if (pendingGate != null && !pendingGate.isCompleted) {
      pendingGate.complete();
    }
    paused = false;
  }
}
