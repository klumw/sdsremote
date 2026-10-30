import 'package:dartantic_ai/dartantic_ai.dart';

import '../../calculator/calc_format.dart';
import '../../calculator/calc_session.dart';
import '../../calculator/calculator_service.dart';
import '../tools/calculator_context_tool.dart';
import '../tools/calculator_tool.dart';
import '../tools/math_tool.dart';
import 'systemprompts.dart';

/// Live calculator state exposed to the Calculator Agent.
///
/// The callbacks are evaluated on every tool call, so the assistant always
/// sees the current expression, program, variables and functions.
class CalculatorAgentContext {
  const CalculatorAgentContext({
    required this.session,
    required this.readExpression,
    required this.readProgram,
    required this.readVariables,
    required this.readFunctions,
    required this.readSettings,
  });

  final CalcSession session;
  final String Function() readExpression;
  final String Function() readProgram;
  final Map<String, String> Function() readVariables;
  final Map<String, String> Function() readFunctions;
  final CalcFormatSettings Function() readSettings;

  Map<String, dynamic> toToolMap() {
    final settings = readSettings();
    return {
      'expression': readExpression(),
      'program': readProgram(),
      'variables': readVariables(),
      'functions': readFunctions(),
      'angle_mode': settings.angleMode.name,
      'number_format': settings.format.name,
      'number_base': settings.numberBase.name,
    };
  }
}

/// Technical calculation assistant of the Engineering Calculator.
class CalculatorAgent {
  static const int defaultMaxToolCalls = 8;
  static const int _maxHistoryMessages = 12;

  final Agent _agent;
  List<ChatMessage> _history;

  CalculatorAgent({
    String model = 'deepseek:deepseek-v4-flash',
    required CalculatorAgentContext context,
    required CalculatorService calculator,
    int? Function(Map<String, dynamic> result)? onToolResult,
    int maxToolCalls = defaultMaxToolCalls,
  }) : _agent = Agent(
         model,
         displayName: 'CalculatorAgent',
         maxToolCalls: maxToolCalls,
         tools: [
           createCalculatorTool(
             agentName: 'CalculatorAgent',
             service: calculator,
             onResult: onToolResult,
           ),
           createMathTool(agentName: 'CalculatorAgent'),
           createCalculatorContextTool(
             agentName: 'CalculatorAgent',
             readContext: context.toToolMap,
           ),
         ],
       ),
       _history = [ChatMessage.system(calculatorAgentSystemPrompt)];

  String get displayName => _agent.displayName;

  String get model => _agent.model;

  /// Streams the final answer, suppressing intermediate "thinking aloud" text
  /// that precedes tool calls (same buffering policy as the macro agent).
  Stream<String> sendStream(String prompt) async* {
    final textBuffer = <String>[];
    final allChunks = <String>[];
    var hasSeenToolCall = false;
    var hasFlushedAfterTools = false;

    await for (final chunk in _agent.sendStream(prompt, history: _history)) {
      final hasToolCalls = chunk.messages.any(
        (message) => message.hasToolCalls,
      );
      if (hasToolCalls) {
        textBuffer.clear();
        hasSeenToolCall = true;
        hasFlushedAfterTools = false;
      }
      final hasToolResults = chunk.messages.any(
        (message) => message.hasToolResults,
      );
      if (hasToolResults) hasFlushedAfterTools = false;

      if (chunk.output.isNotEmpty) {
        if (!hasSeenToolCall || !hasFlushedAfterTools) {
          textBuffer.add(chunk.output);
        } else {
          allChunks.add(chunk.output);
          yield chunk.output;
        }
      }

      if (hasSeenToolCall &&
          !hasFlushedAfterTools &&
          chunk.output.isNotEmpty &&
          !hasToolCalls &&
          !hasToolResults) {
        hasFlushedAfterTools = true;
        for (final buffered in textBuffer) {
          allChunks.add(buffered);
          yield buffered;
        }
        textBuffer.clear();
      }
    }

    if (textBuffer.isNotEmpty) {
      for (final buffered in textBuffer) {
        allChunks.add(buffered);
        yield buffered;
      }
    }

    final output = allChunks.join();
    if (output.isNotEmpty) {
      _history.addAll([ChatMessage.user(prompt), ChatMessage.model(output)]);
      if (_history.length > _maxHistoryMessages + 1) {
        _history = [
          _history.first,
          ..._history.sublist(_history.length - _maxHistoryMessages),
        ];
      }
    }
  }

  void clearHistory() {
    _history = [ChatMessage.system(calculatorAgentSystemPrompt)];
  }
}
