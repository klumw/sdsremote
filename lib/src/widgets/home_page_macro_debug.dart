part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeMacroDebug on _OsciHomePageState {
  /// Starts a paused debug session for the current editor content.
  ///
  /// Returns the session once it is paused before its first executable
  /// statement, or null when the macro is empty, failed to parse, or contains
  /// no statements to execute.
  Future<_MacroDebugSession?> _startMacroDebugSession() async {
    final source = _currentMacroContent;
    if (source.trim().isEmpty) {
      _showMacroError('Macro is empty');
      return null;
    }

    await _stopMacroDebugSession(status: 'Stopped');

    _macroHadPlaybackError = false;
    _macroStatus = null;
    _macroStatusMessage = null;
    _macroDebugCurrentLine = null;
    _macroDebugVariables = <String, String>{};
    _macroPrintController.clear();
    _macroDebugStatus = 'Preparing…';
    if (mounted) _setState(() {});

    late final _MacroDebugSession session;
    final evaluator = MacroEvaluator(
      onError: _showMacroError,
      isCancelled: () => session.cancelled,
      delay: (duration) => Future.any([
        Future<void>.delayed(duration),
        session.cancelSignal.future,
      ]),
      onPrint: _macroPrintController.add,
      onBeforeStatement: (statement) =>
          _onDebugBeforeStatement(session, statement),
      siggenConnector: _connectMacroSignalGenerator,
    );
    session = _MacroDebugSession(evaluator);

    final program = evaluator.parseSource(source);
    if (program == null) {
      _macroHadPlaybackError = true;
      _macroStatus = 0;
      _macroDebugStatus = 'Error (parse)';
      if (mounted) _setState(() {});
      return null;
    }

    _macroDebugSession = session;
    session.runFuture = _runMacroDebugSession(session, program);

    // Wait until the evaluator pauses before the first statement. A macro
    // without executable statements finishes immediately and marks the
    // session as finished instead.
    await session.armed.future;
    if (session.finished || session.cancelled) {
      if (identical(_macroDebugSession, session)) {
        _macroDebugSession = null;
      }
      if (session.finished && !session.cancelled) {
        _macroDebugStatus = 'Finished';
      }
      if (mounted) _setState(() {});
      return null;
    }
    return session;
  }

  Future<void> _runMacroDebugSession(
    _MacroDebugSession session,
    Program program,
  ) async {
    try {
      final success = await session.evaluator.evaluate(program);
      if (!session.cancelled) {
        _macroDebugStatus = _macroHadPlaybackError
            ? 'Error'
            : success
            ? 'Finished'
            : 'Stopped';
      }
    } finally {
      final isCurrentSession = identical(_macroDebugSession, session);
      session.finished = true;
      session.markArmed();
      if (isCurrentSession) {
        // Capture values assigned by the last statement, which has no
        // following gate to read them.
        session.variables = session.evaluator.variables;
        _macroDebugVariables = session.variables;
      }
      try {
        await session.evaluator.close();
      } catch (_) {}
      if (isCurrentSession) {
        _macroDebugSession = null;
      }
      if (mounted) _setState(() {});
    }
  }

  /// Gate called by the evaluator before each non-comment statement.
  Future<void> _onDebugBeforeStatement(
    _MacroDebugSession session,
    Statement statement,
  ) async {
    if (session.cancelled) return;

    session.step++;
    session.statement = describeMacroStatement(statement);
    session.currentLine = session.evaluator.lineForStatement(statement);
    session.variables = session.evaluator.variables;
    _macroDebugCurrentLine = session.currentLine;
    _macroDebugVariables = session.variables;

    final line = session.currentLine;
    final hitBreakpoint = isMacroBreakpointActive(
      line: line,
      breakpoints: _macroBreakpoints,
      inactiveBreakpoints: _macroInactiveBreakpoints,
    );

    // Continue mode: skip statements until the next breakpoint. The current
    // line is still updated so the editor highlights what is executing.
    if (session.runToBreakpoint && !hitBreakpoint) {
      _macroDebugStatus =
          !hasActiveMacroBreakpoint(
            breakpoints: _macroBreakpoints,
            inactiveBreakpoints: _macroInactiveBreakpoints,
          )
          ? 'Running to end…'
          : line == null
          ? 'Running…'
          : 'Running to breakpoint · line $line';
      if (mounted && identical(_macroDebugSession, session)) {
        _setState(() {});
      }
      return;
    }
    session.runToBreakpoint = false;

    session.paused = true;
    final gate = Completer<void>();
    session.gate = gate;
    session.markArmed();
    final prefix = hitBreakpoint ? 'Paused at breakpoint' : 'Paused';
    _macroDebugStatus = '$prefix · Step ${session.step}: ${session.statement}';
    if (mounted && identical(_macroDebugSession, session)) {
      _setState(() {});
    }

    await gate.future;

    session.gate = null;
    session.paused = false;
    if (session.cancelled) return;
    _macroDebugStatus = 'Running step ${session.step}…';
    if (mounted && identical(_macroDebugSession, session)) {
      _setState(() {});
    }
  }

  void _onMacroEditorStep() {
    unawaited(_stepMacroDebugSession());
  }

  Future<void> _stepMacroDebugSession() async {
    if (_macroDebugStepPending || _isMacroPlaying) return;
    _macroDebugStepPending = true;

    try {
      var session = _macroDebugSession;
      if (session == null) {
        session = await _startMacroDebugSession();
        if (session == null || !mounted) return;
      }

      final gate = session.gate;
      if (gate == null || gate.isCompleted) return;

      _macroDebugStatus = 'Running step ${session.step}…';
      if (mounted) _setState(() {});
      gate.complete();
    } finally {
      _macroDebugStepPending = false;
    }
  }

  void _onMacroEditorContinue() {
    final session = _macroDebugSession;
    if (session == null || !session.paused) return;

    final gate = session.gate;
    if (gate == null || gate.isCompleted) return;

    session.runToBreakpoint = true;
    _macroDebugStatus = 'Continuing…';
    if (mounted) _setState(() {});
    gate.complete();
  }

  void _onMacroEditorPlay() {
    final session = _macroDebugSession;
    if (session != null && session.paused) {
      // Play from a breakpoint continues the run. Restarting here would hit
      // the same breakpoint again immediately (especially when it sits on the
      // first executable statement), which looks like Play did nothing.
      _onMacroEditorContinue();
      return;
    }
    unawaited(_runMacroDebugFromEditor());
  }

  /// Starts a fresh debug run from the beginning and lets it execute until
  /// the first breakpoint (or the end). Continue and Play on a paused session
  /// resume it; Stop followed by Play restarts from the beginning.
  Future<void> _runMacroDebugFromEditor() async {
    if (_macroDebugStepPending || _isMacroPlaying) return;
    _macroDebugStepPending = true;

    try {
      // Starting a session stops any previous paused run.
      final session = await _startMacroDebugSession();
      if (session == null || !mounted) return;

      // The first gate is paused before statement 1. If it sits on an active
      // breakpoint, stop there instead of executing it.
      final line = session.currentLine;
      if (isMacroBreakpointActive(
        line: line,
        breakpoints: _macroBreakpoints,
        inactiveBreakpoints: _macroInactiveBreakpoints,
      )) {
        _macroDebugStatus =
            'Paused at breakpoint · Step ${session.step}: '
            '${session.statement}';
        if (mounted) _setState(() {});
        return;
      }

      final gate = session.gate;
      if (gate == null || gate.isCompleted) return;

      session.runToBreakpoint = true;
      _macroDebugStatus = 'Running…';
      if (mounted) _setState(() {});
      gate.complete();
    } finally {
      _macroDebugStepPending = false;
    }
  }

  /// Cancels a running debug session and closes its instrument connection.
  Future<void> _stopMacroDebugSession({String status = 'Stopped'}) async {
    final session = _macroDebugSession;
    if (session == null) return;

    session.cancel();
    _macroDebugStatus = status;
    if (mounted) _setState(() {});

    final runFuture = session.runFuture;
    if (runFuture != null) {
      // Do not block forever on an in-flight device operation. The run's
      // finally closes the instrument and clears the session.
      await runFuture.timeout(const Duration(seconds: 2), onTimeout: () {});
    }

    if (identical(_macroDebugSession, session)) {
      _macroDebugSession = null;
    }
    if (mounted) _setState(() {});
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
