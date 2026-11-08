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
        'that captures at least 80 periods (preferably at most 160), the '
        'resulting period count and the exact TDIV value. Use it whenever the '
        'request asks for an FFT, spectrum, spectral peaks, harmonics, THD, '
        'interference or clock feedthrough. Prefer an exact TDIV supplied by '
        'the caller from the acquisition summary field `fftPreparation`; '
        'otherwise determine the measured fundamental frequency first: take '
        'it from the request, or query the frequency measurement documented '
        'in the ACTIVE DEVICE PROFILE and parse the response with '
        'parse_measurement. `frequencyHz` is the measured frequency in hertz, '
        'for example 100.39 for 100.39 Hz. Never pass a timebase (5 ms/div is '
        '0.005 s, not 5 Hz or 5000 Hz), a period, the sample rate or a value '
        'in kHz. Then send `TDIV <timebaseScpi>` through the communication '
        'tool and verify it with TDIV?. Never guess the frequency and never '
        'invent a timebase outside the 1-2-5 grid.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'frequencyHz': {
          'type': 'number',
          'description':
              'Measured signal frequency in hertz (for example 100.39 Hz). '
              'Must be greater than 0. Never pass a timebase, a period, the '
              'sample rate or a frequency in kHz here.',
        },
        'minPeriods': {
          'type': 'integer',
          'minimum': 80,
          'maximum': 1000,
          'description':
              'Minimum number of periods the acquisition must capture. '
              'Defaults to 80.',
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
      } else if (minPeriods < 80 || minPeriods > 1000) {
        result = <String, dynamic>{
          'error': 'minPeriods must be between 80 and 1000.',
        };
      } else {
        final period = 1 / frequency;
        final timebase = timebaseForFftPeriods(period, minPeriods: minPeriods);
        final periods = double.parse(
          (14 * timebase / period).toStringAsFixed(3),
        );
        String? note;
        if (periods < minPeriods) {
          note =
              'The longest timebase still shows only $periods periods; at '
              'least $minPeriods periods are not possible at this frequency.';
        } else if (periods > fftMaxPeriodsOnScreen) {
          note =
              'The 1-2-5 grid leaves no step between $minPeriods and '
              '$fftMaxPeriodsOnScreen periods; the next smaller step would '
              'fall below $minPeriods periods.';
        }
        result = <String, dynamic>{
          'frequencyHz': frequency,
          'periodSeconds': period,
          'timebaseSeconds': timebase,
          'timebaseScpi': formatScpiTimebase(timebase),
          'periodsOnScreen': periods,
          'minPeriods': minPeriods,
          'divisions': 14,
          'method': 'smallest_1_2_5_step_at_or_above_min_periods',
          if (note != null) 'note': note,
          'nextStep':
              'Send "TDIV <timebaseScpi>" through the communication tool and '
              'verify it with TDIV?. The write refreshes the acquisition '
              'automatically; use the returned waveformUpdate.',
        };
      }
      logger.log(
        'FFT timebase: frequencyHz=$frequency, minPeriods=$minPeriods, '
        'TDIV=${result['timebaseScpi'] ?? '-'}, '
        'periodsOnScreen=${result['periodsOnScreen'] ?? '-'}',
      );
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
