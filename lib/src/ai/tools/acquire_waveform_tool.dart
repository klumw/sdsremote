import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';

/// Performs a new waveform acquisition for the AI tool.
///
/// The provider must return a structured result map. It runs on the UI
/// isolate because the acquisition updates the displayed chart and the
/// measurement state.
typedef WaveformAcquisitionProvider = Future<Map<String, dynamic>> Function();

/// Creates the `acquire_waveform` tool for the Waveform Agent.
Tool<Map<String, dynamic>> createAcquireWaveformTool({
  WaveformAcquisitionProvider? acquire,
  String agentName = 'unknown',
}) {
  final provider = acquire;
  return Tool<Map<String, dynamic>>(
    name: 'acquire_waveform',
    description:
        'Acquire a new waveform from the oscilloscope into the SDS-Remote '
        'Acquire Waveform view. The acquisition updates the displayed chart '
        'and the automatic time-domain measurements and returns the new '
        'measurement summary. It is a measurement action: it temporarily '
        'stops the trigger and restores the previous trigger mode, but it '
        'does not change persistent instrument settings, so it does not need '
        'confirmation. Use it when the user asks for a fresh capture or after '
        'a confirmed setting change. Call it at most once per user request.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': <String, dynamic>{},
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'acquire_waveform',
      );
      final result = provider == null
          ? <String, dynamic>{
              'error': 'Waveform acquisition is not available in this context.',
            }
          : await provider();
      logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}
