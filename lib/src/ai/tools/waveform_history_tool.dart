import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';

/// Supplies the recent waveform acquisitions for the AI tool.
///
/// The list is ordered newest first and contains at most four entries.
typedef WaveformHistoryProvider = List<Map<String, dynamic>> Function();

/// Creates the `read_waveform_history` tool for the Waveform Agent.
Tool<Map<String, dynamic>> createWaveformHistoryTool({
  WaveformHistoryProvider? readHistory,
  String agentName = 'unknown',
}) {
  final provider = readHistory;
  return Tool<Map<String, dynamic>>(
    name: 'read_waveform_history',
    description:
        'Returns the most recent waveform acquisitions (newest first, up to '
        'four). Each '
        'entry contains a sequence number, the capture timestamp, the device '
        'settings and the automatic time-domain measurements per channel. '
        'Use it to compare recent measurements or when the user refers '
        'to an earlier acquisition. Spectrum metrics are not stored per '
        'acquisition; use read_spectrum_summary for the current acquisition. '
        'Returns an error if no acquisition has been recorded yet.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': <String, dynamic>{},
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'read_waveform_history',
      );
      final history = provider?.call() ?? const <Map<String, dynamic>>[];
      final result = history.isEmpty
          ? <String, dynamic>{
              'error':
                  'No waveform acquisition has been recorded yet. Acquire a '
                  'waveform first.',
            }
          : <String, dynamic>{'count': history.length, 'measurements': history};
      logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}
