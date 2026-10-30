import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';

/// Reads the calculator context for the Calculator Agent.
///
/// The callback is supplied by the calculator window and returns the live
/// expression, program and variable/function state.
typedef CalculatorContextReader = Map<String, dynamic> Function();

/// Creates the read-only `read_calculator_context` tool.
Tool<Map<String, dynamic>> createCalculatorContextTool({
  required CalculatorContextReader readContext,
  String agentName = 'CalculatorAgent',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'read_calculator_context',
    description:
        'Read the live Engineering Calculator context: current expression, '
        'program editor content, variables, user functions and display '
        'settings (angle mode, number format and number base). Use it whenever '
        'a request depends on the current program or stored values. This tool '
        'never changes the calculator.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': const <String, dynamic>{},
    }),
    onCall: (_) async {
      Map<String, dynamic> context;
      try {
        context = readContext();
      } on Object catch (error) {
        context = {'error': 'Could not read the calculator context: $error'};
      }
      AppLogger(
        agentName: agentName,
        toolName: 'read_calculator_context',
      ).logToolCall(
        input: const {},
        output: {
          'variables': (context['variables'] as Map?)?.length ?? 0,
          'program_chars': '${context['program'] ?? ''}'.length,
        },
      );
      return {'ok': true, ...context};
    },
  );
}
