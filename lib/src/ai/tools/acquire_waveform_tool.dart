import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';

/// Maximum delay accepted by the `acquire_waveform` tool.
const int maxAcquireDelaySeconds = 600;

/// Performs a new waveform acquisition for the AI tool.
///
/// The provider waits for [delaySeconds] and then runs the acquisition on the
/// UI isolate, because the acquisition updates the displayed chart and the
/// measurement state.
typedef WaveformAcquisitionProvider =
    Future<Map<String, dynamic>> Function({int delaySeconds});

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
        'Acquire Waveform view. Pass `delaySeconds` to wait before the '
        'acquisition starts: 0 (default) acquires immediately, n waits n '
        'seconds first. Use it when the user asks for a fresh capture, a '
        'delayed capture, or a measurement after a capture (for example '
        '"acquire in 10 seconds and then measure Vpp on CH2"). The call '
        'blocks until the acquisition has completed and returns `acquired` '
        'and the new measurement summary in `measurements`; '
        '`measurements.channels.<ch>` contains vppVolts, rmsVolts, meanVolts, '
        'frequency, duty cycle and edge times. Answer the requested '
        'measurement from that result. It is a measurement action: '
        'it temporarily stops the trigger and restores the previous trigger '
        'mode, but it does not change persistent instrument settings, so it '
        'does not need confirmation. Call it at most once per user request.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'delaySeconds': {
          'type': 'integer',
          'minimum': 0,
          'maximum': maxAcquireDelaySeconds,
          'description':
              'Seconds to wait before starting the acquisition. Use 0 to '
              'acquire immediately. Maximum $maxAcquireDelaySeconds.',
        },
      },
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'acquire_waveform',
      );
      final delaySeconds = _intArg(args, 'delaySeconds', 0);
      if (delaySeconds < 0 || delaySeconds > maxAcquireDelaySeconds) {
        final result = <String, dynamic>{
          'error':
              'delaySeconds must be between 0 and $maxAcquireDelaySeconds.',
        };
        await logger.logToolCall(
          input: {'delaySeconds': delaySeconds},
          output: {'error': result['error']},
        );
        return result;
      }
      final result = provider == null
          ? <String, dynamic>{
              'error': 'Waveform acquisition is not available in this context.',
            }
          : await provider(delaySeconds: delaySeconds);
      await logger.logToolCall(
        input: {'delaySeconds': delaySeconds},
        output: {
          if (result['acquired'] != null) 'acquired': result['acquired'],
          if (result['cancelled'] != null) 'cancelled': result['cancelled'],
          if (result['error'] != null) 'error': result['error'],
        },
      );
      return result;
    },
  );
}

int _intArg(Map<String, dynamic> args, String key, int fallback) {
  final value = args[key];
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}
