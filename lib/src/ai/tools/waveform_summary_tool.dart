import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';

/// Supplies the waveform summary data for the AI tool.
///
/// Returns `null` when no waveform is currently displayed.
typedef WaveformSummaryProvider = Map<String, dynamic>? Function();

/// Creates the deterministic `read_waveform_summary` tool.
///
/// The tool performs no AI/LLM work itself: the provider hands over the
/// already computed measurements, device parameters and reference/mask state
/// so the assistant can explain them. Without a displayed waveform it returns
/// a structured error instead of inventing values.
Tool<Map<String, dynamic>> createWaveformSummaryTool({
  WaveformSummaryProvider? readSummary,
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'read_waveform_summary',
    description:
        'Returns the automatic time-domain measurements of the waveform '
        'currently displayed in the main window: active channels with Vpp, '
        'RMS, frequency, duty, rise/fall, overshoot and notes, the device '
        'parameters (timebase, sample rate, V/div and offset), and the '
        'reference comparison and mask-test result when available. Use it '
        'when the user asks why a signal looks the way it does or asks for '
        'measurement values. Returns an error if no waveform is displayed.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': <String, dynamic>{},
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'read_waveform_summary',
      );
      final summary = readSummary?.call();
      final result =
          summary ??
          <String, dynamic>{
            'error':
                'No waveform measurements available. Acquire a waveform '
                'first.',
          };
      logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}
