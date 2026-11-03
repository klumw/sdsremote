import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';

/// Loads authorized command definitions and knowledge for a device profile.
///
/// The provider is supplied by the application: it reads the loaded profiles
/// from the device-profile store and returns only documentation, never a live
/// device action.
typedef DeviceCommandReferenceReader =
    Future<Map<String, dynamic>> Function({
      String? profileId,
      String? commandId,
      String? query,
    });

/// Creates the tool that exposes the device-profile command registry to an
/// agent.
///
/// This replaces static, per-device SCPI references in agent prompts. The
/// agent asks for the profile (or omits it to discover the configured devices)
/// and receives the authorized patterns, parameters and knowledge sections.
Tool<Map<String, dynamic>> createDeviceCommandReferenceTool({
  DeviceCommandReferenceReader? readReference,
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'device_command_reference',
    description:
        'Return the authorized SCPI command definitions and device knowledge '
        'for a device profile. Use profile_id "sds1000xe" for the '
        'oscilloscope and "fy6900" or "jds6600" for the configured signal '
        'generator. Omit profile_id to list the available profiles and the '
        'configured signal generator. Pass command_id for one command or '
        'query to search commands and knowledge. Use only the returned '
        'patterns; never invent a command, parameter, unit or query form.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'profile_id': {
          'type': 'string',
          'enum': ['sds1000xe', 'fy6900', 'jds6600'],
          'description':
              'Device profile id. Omit it to discover the available profiles '
              'and the configured signal generator.',
        },
        'command_id': {
          'type': 'string',
          'description':
              'Optional stable command id, for example "freq" or "tra".',
        },
        'query': {
          'type': 'string',
          'description':
              'Optional search text for a command name, description or '
              'knowledge section.',
        },
      },
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'device_command_reference',
      );
      if (readReference == null) {
        const result = {
          'error': 'Device command reference is not available in this context.',
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }

      final profileId = (args['profile_id'] as String?)?.trim();
      final commandId = (args['command_id'] as String?)?.trim();
      final query = (args['query'] as String?)?.trim();
      try {
        final result = await readReference(
          profileId: profileId == null || profileId.isEmpty ? null : profileId,
          commandId: commandId == null || commandId.isEmpty ? null : commandId,
          query: query == null || query.isEmpty ? null : query,
        );
        await logger.logToolCall(input: args, output: result);
        return result;
      } catch (error) {
        final result = {
          'error_code': 'COMMAND_REFERENCE_FAILED',
          'error': 'Device command reference failed: $error',
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }
    },
  );
}
