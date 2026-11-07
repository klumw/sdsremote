import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../../devices/device_agent_context.dart';
import '../../instrument/dart_vxi11.dart';

/// Callback invoked whenever a SCPI command is sent to the device via the
/// vxi11 tool. Receives the command string and the operation type
/// (`"write"` or `"query"`).
typedef ScpiCommandCallback = void Function(String command, String operation);

/// Refreshes the waveform acquisition after a successful scope write.
///
/// Returns a JSON-safe update that is attached to the tool result under
/// `waveformUpdate`. The write itself stays successful when the refresh fails.
typedef ScopeWriteHandler =
    Future<Map<String, dynamic>> Function(String command);

/// Builds the VXI-11 transport. Overridable in tests.
typedef Vxi11InstrumentBuilder = Vxi11Instrument Function(String host);

/// A static callback that is invoked for every SCPI command sent through
/// the vxi11 tool. Set this from the macro recorder to capture AI-driven
/// SCPI commands into the recorded macro.
ScpiCommandCallback? onScpiCommandSent;

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
  required String host,
  String agentName = 'unknown',
  ScpiCommandCallback? onCommandSent,
  DeviceCommandGate? commandGate,
  ScopeWriteHandler? afterWrite,
  Vxi11InstrumentBuilder? instrumentBuilder,
}) {
  return Tool<Map<String, dynamic>>(
    name: 'vxi11',
    description:
        'Send SCPI commands and queries to a VXI-11 instrument. '
        'Use "write" to send a command (no response), '
        'or "query" to send a query and get a response. '
        'Every command is validated against the active device profile before '
        'it is sent; a rejected command returns success=false and an '
        'error_code. After a successful write (a scope setting change) the '
        'tool automatically refreshes the waveform acquisition and returns '
        'the result as waveformUpdate; a failed refresh does not undo the '
        'write. '
        'The configured device IP is $host.',
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
          'description': 'The IP address of the instrument. Defaults to $host.',
        },
      },
      'required': ['operation', 'command'],
    }),
    onCall: (args) async {
      final operation = args['operation'] as String;
      final command = args['command'] as String;
      final effectiveHost = (args['host'] as String?) ?? host;

      final logger = AppLogger(agentName: agentName, toolName: 'vxi11');

      // Validate before any callback or transport work: a blocked command must
      // not be recorded into a macro and must never reach the device.
      final validation = commandGate?.validate(
        command,
        isQuery: operation == 'query',
      );
      if (validation != null && !validation.isValid) {
        final rejection = {
          'success': false,
          'operation': operation,
          'command': command,
          ...validation.error!.toJson(),
          'host': effectiveHost,
        };
        logger.warning(
          'SCPI $operation rejected by the device profile: ${validation.error}',
        );
        logger.logToolCall(input: args, output: rejection);
        return rejection;
      }

      // Notify the macro recorder (if any) that a SCPI command is being sent.
      onScpiCommandSent?.call(command, operation);
      // Notify the owning feature (for example the Control Panel's screen
      // refresh) without disturbing the global recorder callback.
      onCommandSent?.call(command, operation);

      final instrument =
          instrumentBuilder?.call(effectiveHost) ??
          Vxi11Instrument(effectiveHost, sourceLabel: 'AI-tool($agentName)');

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
              if (validation != null && validation.warnings.isNotEmpty)
                'warnings': validation.warnings,
              'host': effectiveHost,
            };

          case 'query':
            await instrument.writeString(command);
            final response = await instrument.readString(maxLen: 4096);
            result = {
              'success': true,
              'operation': 'query',
              'command': command,
              'response': response,
              if (validation != null && validation.warnings.isNotEmpty)
                'warnings': validation.warnings,
              'host': effectiveHost,
            };

          default:
            throw ArgumentError('Unknown operation: $operation');
        }

        // A successful write is an active scope setting change. Refresh the
        // waveform acquisition so every agent works with the new state. A
        // failed refresh must not turn the successful write into an error.
        if (operation == 'write' &&
            afterWrite != null &&
            _changesScopeState(command)) {
          try {
            final update = await afterWrite(command);
            result = <String, dynamic>{...result, 'waveformUpdate': update};
          } on Object catch (error) {
            result = <String, dynamic>{
              ...result,
              'waveformUpdate': <String, dynamic>{
                'error': 'The waveform refresh failed ($error).',
              },
            };
          }
        }

        logger.logToolCall(input: args, output: result);
        return result;
      } catch (e) {
        final errorResult = {
          'success': false,
          'operation': operation,
          'command': command,
          'error': e.toString(),
          'host': effectiveHost,
        };
        // Keep failures visible at the default log level: the agent's
        // read_log_file tool can then analyze what went wrong, and the log
        // still shows the cause after the chat is closed.
        logger.warning(
          'SCPI $operation failed: $command - $e (host: $effectiveHost)',
        );
        logger.logToolCall(input: args, output: errorResult);
        return errorResult;
      } finally {
        await instrument.close();
      }
    },
  );
}

/// Whether [command] changes a scope setting or state.
///
/// Status and synchronization commands do not change a setting, so they need
/// no waveform refresh.
bool _changesScopeState(String command) {
  final normalized = command.trim().toUpperCase();
  if (normalized.isEmpty) return false;
  return normalized != '*CLS' && normalized != '*OPC' && normalized != '*WAI';
}
