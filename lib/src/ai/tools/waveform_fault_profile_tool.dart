/// AI tool for the long-term store of user-supplied fault-analysis
/// specifications.
///
/// The tool only forwards profile actions. All file handling is performed by
/// the injected provider; the LLM never reads or writes the JSON file itself.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import 'waveform_fault_tool.dart';

/// Reads, saves or clears the fault-analysis profile.
typedef WaveformFaultProfileProvider =
    Future<Map<String, dynamic>> Function({
      required String action,
      String? channel,
      Map<String, dynamic>? specification,
      String? mode,
    });

/// Registers `manage_fault_analysis_profile` for the Waveform Agent.
Tool<Map<String, dynamic>> createWaveformFaultProfileTool({
  WaveformFaultProfileProvider? manage,
  String agentName = 'unknown',
}) {
  final provider = manage;
  return Tool<Map<String, dynamic>>(
    name: 'manage_fault_analysis_profile',
    description:
        'Reads, saves or clears the long-term store of user-supplied '
        'fault-analysis specifications. The store is a JSON file in the '
        'application data directory and is organized per channel; '
        'measurement_artifacts values are stored globally. Use `read` at the '
        'start of an explicit fault-analysis request to check for existing '
        'data. If stored data exists for the relevant channel, summarize it '
        'and ask the user whether to reuse it before applying it. Use `save` '
        'after the user supplies new reference values, tolerances or limits: '
        '`mode: replace` overwrites the channel block (use when the user '
        'declines reuse), `mode: merge` updates only the supplied tests and '
        'fields (use when the user accepts reuse and adds values). Use `clear` '
        'only when the user explicitly asks to forget stored values. Never '
        'store measured values, analysis results or waveform samples. The '
        'result contains exists/hasData, the per-channel specifications, the '
        'global values, the file path and the saved/cleared status.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'action': {
          'type': 'string',
          'enum': ['read', 'save', 'clear'],
          'description':
              'Profile operation: read the stored values, save the supplied '
              'specification, or clear a channel or the complete profile.',
        },
        'channel': {
          'type': 'string',
          'enum': ['ch1', 'ch2', 'ch3', 'ch4'],
          'description':
              'Channel whose stored specification is read, saved or cleared. '
              'Required for save. Omit it for read to get all channels; omit '
              'it for clear to delete the complete profile.',
        },
        'specification': waveformFaultSpecificationSchema(),
        'mode': {
          'type': 'string',
          'enum': ['replace', 'merge'],
          'description':
              'Save mode. `replace` (default) overwrites the channel block; '
              '`merge` updates only the supplied tests and fields. Ignored for '
              'read and clear.',
        },
      },
      'required': ['action'],
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'manage_fault_analysis_profile',
      );
      final action = _stringArg(args, 'action')?.toLowerCase();
      final specification = args['specification'];
      final result = provider == null
          ? <String, dynamic>{
              'error':
                  'The fault-analysis profile store is not available in this '
                  'context.',
            }
          : action == null
          ? <String, dynamic>{
              'error': 'action is required. Valid actions: read, save, clear.',
            }
          : await provider(
              action: action,
              channel: _stringArg(args, 'channel'),
              specification: specification is Map
                  ? Map<String, dynamic>.from(specification)
                  : null,
              mode: _stringArg(args, 'mode'),
            );
      logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}

String? _stringArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
