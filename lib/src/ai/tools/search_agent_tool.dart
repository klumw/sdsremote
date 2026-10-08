import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../agents/search_agent.dart';

/// Creates the tool that wraps the knowledgebase search agent.
///
/// The [searchAgent] is captured in the closure so the tool can delegate
/// knowledgebase queries to the search agent.
Tool<Map<String, dynamic>> createSearchAgentTool(
  SearchAgent searchAgent, {
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'search_agent',
    description:
        'Search the oscilloscope knowledgebase for information about '
        'commands, settings, troubleshooting, or device specifications. '
        'Use this tool when you need to answer questions about how to use '
        'the oscilloscope, what SCPI commands are available, how to '
        'configure channels or triggers, or how to troubleshoot issues. '
        'The knowledgebase contains documentation about the oscilloscope '
        'device including channel setup, timebase, measurements, '
        'troubleshooting, and specifications.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description':
              'The question about the oscilloscope device, e.g. '
              '"How do I set the trigger level?" or '
              '"What is the C1:TRA command?" or '
              '"What are the specifications of the SDS1202X-E?"',
        },
      },
      'required': ['query'],
    }),
    onCall: (args) async {
      final query = args['query'] as String;
      final logger = AppLogger(agentName: agentName, toolName: 'search_agent');
      final response = await searchAgent.send(query);
      logger.logToolCall(input: args, output: {'response': response});
      return {'response': response};
    },
  );
}
