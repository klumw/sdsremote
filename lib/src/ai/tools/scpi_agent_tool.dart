import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../agents/instrument_agent.dart';

/// Creates the tool that wraps the VXI-11 instrument agent.
///
/// The [vxiAgent] is captured in the closure so the tool can delegate
/// prompts to the instrument agent.
Tool<Map<String, dynamic>> createScpiAgentTool(
  InstrumentAgent vxiAgent, {
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'scpi_instrument_agent',
    description:
        'Send SCPI commands and queries to the connected instrument or the '
        'separate signal generator. Use this tool when you need to interact '
        'with an instrument. Describe what you want to do in natural language; '
        'the instrument agent selects the device, validates the command '
        'against the active device profile and handles the communication.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'prompt': {
          'type': 'string',
          'description':
              'Describe what you want to do with the instrument in natural '
              'language, e.g. "Send the command C1:TRA OFF" or '
              '"Query the device identification with *IDN?"',
        },
      },
      'required': ['prompt'],
    }),
    onCall: (args) async {
      final prompt = args['prompt'] as String;
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'scpi_instrument_agent',
      );
      final response = await vxiAgent.send(prompt);
      logger.logToolCall(input: args, output: {'response': response});
      return {'response': response};
    },
  );
}
