import 'package:dartantic_ai/dartantic_ai.dart';

import '../dart_vxi11.dart';
import '../logger.dart';

/// Default IP address of the VXI-11 instrument.
const String defaultVxi11Host = '192.168.178.95';

/// Creates a VXI-11 tool that allows the AI agent to send SCPI commands
/// and queries to a remote instrument.
///
/// The tool provides two operations:
/// - `write`: Send a SCPI command (no response expected)
/// - `query`: Send a SCPI query and read the response
///
/// Usage by the AI agent:
/// - "Send the command C1:TRA OFF to the device"
/// - "Query the device identification with *IDN?"
Tool<Map<String, dynamic>> createVxi11Tool({
  String host = defaultVxi11Host,
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'vxi11',
    description:
        'Send SCPI commands and queries to a VXI-11 instrument. '
        'Use "write" to send a command (no response), '
        'or "query" to send a query and get a response. '
        'The default device IP is $defaultVxi11Host.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'operation': {
          'type': 'string',
          'enum': ['write', 'query'],
          'description':
              '"write" sends a command without expecting a response. '
              '"query" sends a command and reads the response.',
        },
        'command': {
          'type': 'string',
          'description':
              'The SCPI command or query to send, e.g. "C1:TRA OFF" or "*IDN?"',
        },
        'host': {
          'type': 'string',
          'description':
              'The IP address of the instrument. Defaults to $defaultVxi11Host.',
        },
      },
      'required': ['operation', 'command'],
    }),
    onCall: (args) async {
      final operation = args['operation'] as String;
      final command = args['command'] as String;
      final host = (args['host'] as String?) ?? defaultVxi11Host;

      final logger = AppLogger(
        agentName: agentName,
        toolName: 'vxi11',
      );

      final instrument = Vxi11Instrument(host, sourceLabel: 'AI-tool($agentName)');

      try {
        await instrument.open(timeoutSeconds: 10.0);

        Map<String, dynamic> result;
        switch (operation) {
          case 'write':
            await instrument.writeString(command);
            result = {
              'success': true,
              'operation': 'write',
              'command': command,
              'response': null,
              'host': host,
            };

          case 'query':
            await instrument.writeString(command);
            final response = await instrument.readString(maxLen: 4096);
            result = {
              'success': true,
              'operation': 'query',
              'command': command,
              'response': response,
              'host': host,
            };

          default:
            throw ArgumentError('Unknown operation: $operation');
        }

        logger.logToolCall(input: args, output: result);
        return result;
      } catch (e) {
        final errorResult = {
          'success': false,
          'operation': operation,
          'command': command,
          'error': e.toString(),
          'host': host,
        };
        logger.logToolCall(input: args, output: errorResult);
        return errorResult;
      } finally {
        await instrument.close();
      }
    },
  );
}
