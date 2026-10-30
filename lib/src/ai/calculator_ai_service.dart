import 'dart:async';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../calculator/calc_session.dart';
import '../calculator/calculator_service.dart';
import '../core/logger.dart';
import 'agents/calculator_agent.dart';

/// Streaming service for the Engineering Calculator's AI assistant.
///
/// The agent's calculator tool runs on a private scratch session. The user's
/// variables and functions are copied into it for each request, and no
/// calculation changes the live calculator state.
class CalculatorAiService {
  CalculatorAgent? _agent;
  CalculatorService? _calculator;
  CalcSession? _scratch;
  CalculatorAgentContext? _context;
  bool _isDisposed = false;

  static const Duration responseTimeout = Duration(seconds: 120);

  bool get isInitialized => _agent != null;

  CalculatorAgent? get agent => _agent;

  /// The private calculator workspace used by the agent's tools.
  CalculatorService? get calculator => _calculator;

  void configure({
    required String apiKey,
    required String apiToken,
    required String model,
    required CalculatorAgentContext context,
    required void Function(Map<String, dynamic> result) onToolResult,
    int maxToolCalls = CalculatorAgent.defaultMaxToolCalls,
  }) {
    if (_isDisposed) return;
    _agent = null;
    _calculator = null;
    _context = context;

    final scratch = CalcSession.memory();
    _scratch = scratch;
    _resetScratch();
    final calculator = CalculatorService(session: scratch);
    _calculator = calculator;

    Agent.environment[apiKey] = apiToken;
    try {
      _agent = CalculatorAgent(
        model: model,
        context: context,
        calculator: calculator,
        onToolResult: onToolResult,
        maxToolCalls: maxToolCalls,
      );
      AppLogger(
        agentName: 'CalculatorAiService',
        toolName: 'configure',
      ).debug('CalculatorAgent created: model=$model');
    } on Object catch (error) {
      AppLogger(
        agentName: 'CalculatorAiService',
        toolName: 'configure',
      ).error('CalculatorAgent creation failed: $error');
    }
  }

  /// Refreshes the private scratch workspace from the live calculator before
  /// a request. UI variables are authoritative; scratch-only variables from a
  /// previous answer are discarded so stale values cannot leak.
  void syncContext() {
    if (_isDisposed || _scratch == null || _context == null) return;
    _resetScratch();
  }

  void _resetScratch() {
    final scratch = _scratch;
    final context = _context;
    if (scratch == null || context == null) return;
    scratch.engine.settings = context.session.settings;
    scratch.engine.variables
      ..clear()
      ..addAll(context.session.engine.variables);
    scratch.engine.functions
      ..clear()
      ..addAll(context.session.engine.functions);
    scratch.engine.lastAnswer = null;
  }

  /// Sends a prompt and streams the final answer. A timeout is reported as a
  /// stream error so the chat can stop the response and show a message.
  Stream<String> sendMessageStream({required String text}) async* {
    if (_isDisposed) throw StateError('Calculator AI service is disposed');
    final agent = _agent;
    if (agent == null) {
      yield 'Error: AI assistant is not configured. Configure the AI provider, '
          'token and model in SDS-Remote Settings.';
      return;
    }
    syncContext();
    try {
      yield* agent
          .sendStream(text)
          .timeout(
            responseTimeout,
            onTimeout: (sink) {
              sink.addError(
                TimeoutException(
                  'AI request timed out after ${responseTimeout.inSeconds} s',
                ),
              );
              sink.close();
            },
          );
    } on Object catch (error) {
      AppLogger(
        agentName: 'CalculatorAiService',
        toolName: 'sendMessageStream',
      ).error('Calculator AI request failed: $error');
      yield 'Error: AI request failed ($error)';
    }
  }

  void dispose() {
    _isDisposed = true;
    _agent = null;
    _calculator = null;
    _scratch = null;
    _context = null;
  }
}
