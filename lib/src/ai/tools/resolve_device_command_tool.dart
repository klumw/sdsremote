import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../../devices/device_agent_context.dart';
import '../../devices/device_profile_models.dart';

/// Provides the currently active device context.
typedef DeviceCommandContextProvider = DeviceAgentContext? Function();

/// Creates the tool that resolves a semantic command against the active device
/// profile.
///
/// The tool only generates and validates a command string; it never sends the
/// command. The agent passes the returned `scpi` value unchanged to the
/// communication tool, which validates it again before transport.
Tool<Map<String, dynamic>> createResolveDeviceCommandTool({
  DeviceCommandContextProvider? contextProvider,
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'resolve_device_command',
    description:
        'Resolve a semantic command against the active device profile and '
        'return the exact validated SCPI string in "scpi". Pass command_id, '
        'the semantic parameters and query=true for a documented query form. '
        'Use the returned string unchanged with the communication tool. Use '
        'this tool for commands whose definition has complete parameter '
        'definitions. Commands whose placeholders have no definitions return '
        'COMMAND_NOT_RESOLVABLE; use the authorized raw pattern for those. '
        'Never invent command ids, parameter names, units or values.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'command_id': {
          'type': 'string',
          'description':
              'Stable command id from the active device profile, for example '
              '"chs", "rst" or "freq".',
        },
        'parameters': {
          'type': 'object',
          'description':
              'Semantic parameters, for example {"n": 1, "value": 1000, '
              '"unit": "HZ"}. Omit it for commands without parameters.',
          'additionalProperties': true,
        },
        'query': {
          'type': 'boolean',
          'description':
              'true builds the documented query form; false (default) builds '
              'the write or action form.',
        },
      },
      'required': ['command_id'],
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'resolve_device_command',
      );
      final context = contextProvider?.call();
      if (context == null) {
        final result = {
          'success': false,
          ...DeviceCommandException(
            DeviceErrorCode.profileNotLoaded,
            'No active device profile is loaded.',
          ).toJson(),
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }

      final commandId = (args['command_id'] as String?)?.trim() ?? '';
      if (commandId.isEmpty) {
        final result = {
          'success': false,
          ...DeviceCommandException(
            DeviceErrorCode.invalidParameterValue,
            'command_id must not be empty.',
            profile: context.profileId,
          ).toJson(),
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }

      final rawParameters = args['parameters'];
      final parameters = <String, Object?>{};
      if (rawParameters is Map) {
        for (final entry in rawParameters.entries) {
          parameters[entry.key.toString()] = entry.value;
        }
      } else if (rawParameters != null) {
        final result = {
          'success': false,
          ...DeviceCommandException(
            DeviceErrorCode.invalidParameterValue,
            'parameters must be an object.',
            profile: context.profileId,
            commandId: commandId,
          ).toJson(),
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }

      final query = args['query'] == true;
      try {
        final resolved = context.profile.registry.resolveCommand(
          commandId,
          parameters,
          query: query,
        );
        final result = {
          'success': true,
          'command_id': resolved.command.commandId,
          'scpi': resolved.scpi,
          'query': resolved.query,
          'parameters': resolved.parameters,
          if (resolved.notes.isNotEmpty) 'notes': resolved.notes,
          if (resolved.waveformResolution != null)
            'waveform_mapping': resolved.waveformResolution!.toJson(),
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      } on DeviceCommandException catch (error) {
        final result = {'success': false, ...error.toJson()};
        await logger.logToolCall(input: args, output: result);
        return result;
      }
    },
  );
}
