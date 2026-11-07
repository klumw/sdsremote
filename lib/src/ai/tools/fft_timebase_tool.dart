import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../../waveform/clock_detection.dart';

/// Registers the deterministic `fft_timebase` tool for the InstrumentAgent.
///
/// The tool only calculates the timebase for a spectral analysis. It never
/// talks to the instrument; the returned SCPI value is sent through the
/// validated communication tool.
Tool<Map<String, dynamic>> createFftTimebaseTool({
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'fft_timebase',
    description:
        'Computes the oscilloscope timebase for a spectral analysis (FFT) '
        'from the signal frequency. The graticule spans 14 horizontal '
        'divisions. The tool returns the smallest standard 1-2-5 timebase '
        'that captures at least 50 periods (preferably at most 100), the '
        'resulting period count and the exact TDIV value. Use it whenever the '
        'request asks for an FFT, spectrum, spectral peaks, harmonics, THD, '
        'interference or clock feedthrough. Determine the signal frequency '
        'first: take it from the request, or query the frequency measurement '
        'documented in the ACTIVE DEVICE PROFILE and parse the response with '
        'parse_measurement. Then send `TDIV <timebaseScpi>` through the '
        'communication tool and verify it with TDIV?. Never guess the '
        'frequency and never invent a timebase outside the 1-2-5 grid.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'frequencyHz': {
          'type': 'number',
          'description': 'Signal frequency in Hz. Must be greater than 0.',
        },
        'minPeriods': {
          'type': 'integer',
          'minimum': 5,
          'maximum': 1000,
          'description':
              'Minimum number of periods the acquisition must capture. '
              'Defaults to 50.',
        },
      },
      'required': ['frequencyHz'],
    }),
    onCall: (args) async {
      final logger = AppLogger(agentName: agentName, toolName: 'fft_timebase');
      final frequency = _numberArg(args, 'frequencyHz');
      final minPeriods = _intArg(args, 'minPeriods', fftTargetPeriodsOnScreen);

      Map<String, dynamic> result;
      if (frequency == null || frequency <= 0) {
        result = <String, dynamic>{
          'error': 'frequencyHz must be a positive number.',
        };
      } else if (minPeriods < 5 || minPeriods > 1000) {
        result = <String, dynamic>{
          'error': 'minPeriods must be between 5 and 1000.',
        };
      } else {
        final period = 1 / frequency;
        final timebase = timebaseForFftPeriods(period, minPeriods: minPeriods);
        final periods = double.parse(
          (14 * timebase / period).toStringAsFixed(3),
        );
        result = <String, dynamic>{
          'frequencyHz': frequency,
          'periodSeconds': period,
          'timebaseSeconds': timebase,
          'timebaseScpi': formatScpiTimebase(timebase),
          'periodsOnScreen': periods,
          'minPeriods': minPeriods,
          'divisions': 14,
          'method': 'smallest_1_2_5_step_at_or_above_min_periods',
          if (periods > fftMaxPeriodsOnScreen)
            'note':
                'The 1-2-5 grid leaves no step between $minPeriods and '
                '$fftMaxPeriodsOnScreen periods; the next smaller step would '
                'fall below $minPeriods periods.',
          'nextStep':
              'Send "TDIV <timebaseScpi>" through the communication tool and '
              'verify it with TDIV?. The write refreshes the acquisition '
              'automatically; use the returned waveformUpdate.',
        };
      }
      logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}

double? _numberArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is num) {
    final number = value.toDouble();
    return number.isFinite ? number : null;
  }
  if (value is String) {
    final number = double.tryParse(value.trim());
    return number != null && number.isFinite ? number : null;
  }
  return null;
}

int _intArg(Map<String, dynamic> args, String key, int fallback) {
  final value = args[key];
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}
