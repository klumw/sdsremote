/// AI tool exposing the deterministic waveform fault analyzer.
///
/// The tool only forwards a test selection and a specification. All
/// measurements and verdicts are produced by the analyzer on the complete raw
/// capture; the LLM never computes or invents a fault value.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../../waveform/analysis/waveform_fault_models.dart';

/// Runs fault tests on the current acquisition.
typedef WaveformFaultAnalysisProvider =
    Future<Map<String, dynamic>> Function({
      required List<String> tests,
      String? channel,
      String? channelB,
      Map<String, dynamic>? specification,
    });

/// Registers `analyze_waveform_faults` for the Waveform Agent.
Tool<Map<String, dynamic>> createWaveformFaultAnalysisTool({
  WaveformFaultAnalysisProvider? analyze,
  String agentName = 'unknown',
}) {
  final provider = analyze;
  return Tool<Map<String, dynamic>>(
    name: 'analyze_waveform_faults',
    description:
        'Runs deterministic fault diagnostics on every raw sample of the '
        'current acquisition (no display decimation). Use this tool ONLY when '
        'the user explicitly asks for fault analysis, error diagnosis or '
        'troubleshooting of the waveform; do not call it for normal '
        'measurement, classification or comparison questions. Select only the '
        'tests relevant to the symptom and put them in `tests`: '
        '${WaveformFaultTest.values.map((test) => test.id).join(', ')}. Omit '
        '`tests` only when the user asks for a comprehensive check. Before the '
        'call, ask the user for the reference value, tolerance or limit each '
        'selected test needs and pass it in `specification`; without a '
        'specification a test reports measurements and clear anomalies but '
        'cannot claim a confirmed violation. For phase_delay and crosstalk '
        'pass `channelB`; both channels must be acquired. The result contains '
        'per-test status (pass, fail, warning, informational, inconclusive, '
        'not_applicable), measured values, expected limits, deviations, '
        'affected events and measurement limitations. Quote only the returned '
        'values and event times; never invent thresholds or diagnose a fault '
        'that the tool did not report. If `missingInputs` is returned, ask the '
        'user for those values and repeat only the affected tests.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'tests': {
          'type': 'array',
          'items': {
            'type': 'string',
            'enum': [for (final test in WaveformFaultTest.values) test.id],
          },
          'description':
              'Fault tests to run. Select only the tests that match the '
              'reported symptom. Omit the field to run all twenty tests.',
        },
        'channel': {
          'type': 'string',
          'enum': ['ch1', 'ch2', 'ch3', 'ch4'],
          'description':
              'Acquired channel carrying the suspected faulty signal. Omit it '
              'to use the first channel that has waveform data.',
        },
        'channelB': {
          'type': 'string',
          'enum': ['ch1', 'ch2', 'ch3', 'ch4'],
          'description':
              'Second acquired channel. Required for phase_delay and '
              'crosstalk; both channels must have been acquired together.',
        },
        'specification': waveformFaultSpecificationSchema(),
      },
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'analyze_waveform_faults',
      );
      final tests = _stringListArg(args, 'tests') ?? const <String>[];
      final specification = args['specification'];
      final result = provider == null
          ? <String, dynamic>{
              'error':
                  'Waveform fault analysis is not available in this context.',
            }
          : await provider(
              tests: tests,
              channel: _stringArg(args, 'channel'),
              channelB: _stringArg(args, 'channelB'),
              specification: specification is Map
                  ? Map<String, dynamic>.from(specification)
                  : null,
            );
      logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}

Map<String, dynamic> waveformFaultSpecificationSchema() => {
  'type': 'object',
  'description':
      'Per-test reference values and tolerances. The key is the test id; only '
      'the fields required by the selected tests are needed. Values are in '
      'volts, seconds, hertz, percent, decibels or degrees as named. Ask the '
      'user for a value before calling when it is not already known.',
  'properties': {
    'amplitude': _object({
      'expectedVppVolts': _number('Expected peak-to-peak voltage in volts.'),
      'expectedVmaxVolts': _number('Expected maximum voltage in volts.'),
      'expectedVminVolts': _number('Expected minimum voltage in volts.'),
      'minVppVolts': _number('Minimum allowed Vpp in volts.'),
      'maxVppVolts': _number('Maximum allowed Vpp in volts.'),
      'toleranceVolts': _number('Allowed absolute deviation in volts.'),
      'tolerancePercent': _number(
        'Allowed deviation as a percentage of the reference.',
      ),
    }),
    'signal_loss': _object({
      'minRmsVolts': _number('Minimum allowed RMS voltage in volts.'),
      'minVppVolts': _number('Minimum allowed Vpp in volts.'),
      'maxDropoutFraction': _number(
        'Maximum allowed fraction of windows with a dropout (0 to 1).',
      ),
      'dropoutFraction': _number(
        'Window Vpp below this fraction of the median counts as a dropout '
        '(default 0.2).',
      ),
      'windowSeconds': _number(
        'Window length for the dropout scan in seconds.',
      ),
    }),
    'transients': _object({
      'spikeThresholdVolts': _number(
        'Minimum spike amplitude above the local baseline in volts.',
      ),
      'maxSpikeDurationSeconds': _number(
        'Maximum width of a transient in seconds.',
      ),
      'maxSpikeCount': _integer('Maximum allowed number of transients.'),
    }),
    'clipping': _object({
      'allowedMaxVolts': _number('Maximum allowed signal voltage in volts.'),
      'allowedMinVolts': _number('Minimum allowed signal voltage in volts.'),
      'maxClippingPercent': _number(
        'Maximum allowed percentage of clipped samples.',
      ),
      'toleranceVolts': _number(
        'Tolerance for allowedMaxVolts/allowedMinVolts in volts.',
      ),
    }),
    'frequency_error': _object({
      'expectedFrequencyHz': _number('Expected frequency in hertz.'),
      'toleranceHz': _number('Allowed absolute frequency deviation in hertz.'),
      'tolerancePercent': _number(
        'Allowed frequency deviation as a percentage.',
      ),
      'maxDriftHz': _number('Maximum frequency drift across the record in Hz.'),
      'maxDriftPercent': _number(
        'Maximum frequency drift across the record in percent.',
      ),
    }),
    'noise': _object({
      'maxNoiseRmsVolts': _number('Maximum allowed RMS noise in volts.'),
      'minSnrDb': _number('Minimum allowed signal-to-noise ratio in dB.'),
      'maxNoiseFloorVolts': _number(
        'Maximum allowed spectral noise floor in volts.',
      ),
    }),
    'ringing': _object({
      'ringingThresholdVolts': _number('Minimum ringing amplitude in volts.'),
      'maxRingingDurationSeconds': _number(
        'Maximum allowed ringing duration in seconds.',
      ),
      'minRingingFrequencyHz': _number(
        'Minimum expected ringing frequency in hertz.',
      ),
      'maxRingingFrequencyHz': _number(
        'Maximum expected ringing frequency in hertz.',
      ),
    }),
    'duty_cycle': _object({
      'expectedDutyPercent': _number('Expected duty cycle in percent.'),
      'tolerancePercent': _number(
        'Allowed absolute duty-cycle deviation in percentage points.',
      ),
    }),
    'glitches': _object({
      'minPulseWidthSeconds': _number(
        'Pulses shorter than this are glitches, in seconds.',
      ),
      'maxGlitchCount': _integer('Maximum allowed number of glitches.'),
      'expectedPulseCount': _integer(
        'Expected number of high pulses in the record.',
      ),
    }),
    'jitter': _object({
      'maxJitterSeconds': _number(
        'Maximum allowed RMS period jitter in seconds.',
      ),
      'maxJitterPicoseconds': _number(
        'Maximum allowed RMS period jitter in picoseconds.',
      ),
      'maxJitterPercent': _number('Maximum allowed RMS jitter in percent.'),
      'maxCycleToCycleSeconds': _number(
        'Maximum allowed cycle-to-cycle period deviation in seconds.',
      ),
    }),
    'dc_offset': _object({
      'expectedMeanVolts': _number('Expected mean voltage in volts.'),
      'expectedBaselineVolts': _number(
        'Expected baseline (mid-level) voltage in volts.',
      ),
      'toleranceVolts': _number('Allowed absolute DC deviation in volts.'),
      'maxDriftVolts': _number(
        'Maximum allowed DC drift across the record in volts.',
      ),
    }),
    'distortion': _object({
      'maxThdPercent': _number(
        'Maximum allowed total harmonic distortion in percent.',
      ),
      'maxHarmonicPercent': _number(
        'Maximum allowed single harmonic as a percentage of the fundamental.',
      ),
      'maxSymmetryErrorPercent': _number(
        'Maximum allowed positive/negative half-wave asymmetry in percent.',
      ),
    }),
    'spurious_frequencies': _object({
      'expectedFundamentalHz': _number(
        'Known fundamental frequency in hertz; improves the harmonic '
        'exclusion.',
      ),
      'minSpuriousLevelDbc': _number(
        'Any non-harmonic component above this level in dBc is a violation; '
        'use a negative value such as -60.',
      ),
      'minSpuriousAmplitudeVolts': _number(
        'Any non-harmonic component above this amplitude in volts is a '
        'violation.',
      ),
      'harmonicCount': _integer(
        'Number of harmonics to exclude from the spurious search.',
      ),
    }),
    'edge_times': _object({
      'maxRiseTimeSeconds': _number(
        'Maximum allowed 10-90 % rise time in seconds.',
      ),
      'maxFallTimeSeconds': _number(
        'Maximum allowed 90-10 % fall time in seconds.',
      ),
      'maxAsymmetryPercent': _number(
        'Maximum allowed rise/fall asymmetry in percent.',
      ),
    }),
    'amplitude_stability': _object({
      'maxAmplitudeVariationPercent': _number(
        'Maximum allowed Vpp range across the record in percent.',
      ),
      'windowSeconds': _number(
        'Window length for the amplitude scan in seconds.',
      ),
    }),
    'settling': _object({
      'maxSettlingTimeSeconds': _number(
        'Maximum allowed settling time in seconds.',
      ),
      'settlingBandPercent': _number(
        'Settling band as a percentage of the step (default 2 %).',
      ),
      'maxOvershootPercent': _number('Maximum allowed overshoot in percent.'),
      'edgeTimeSeconds': _number(
        'Time of the step edge in seconds; omit to use the largest edge.',
      ),
    }),
    'phase_delay': _object({
      'expectedDelaySeconds': _number('Expected propagation delay in seconds.'),
      'expectedDelayMicroseconds': _number(
        'Expected propagation delay in microseconds.',
      ),
      'toleranceDelaySeconds': _number('Allowed delay deviation in seconds.'),
      'toleranceDelayMicroseconds': _number(
        'Allowed delay deviation in microseconds.',
      ),
      'expectedPhaseDegrees': _number(
        'Expected phase shift in degrees (wrapped to -180..180).',
      ),
      'tolerancePhaseDegrees': _number('Allowed phase deviation in degrees.'),
    }),
    'crosstalk': _object({
      'maxCrosstalkDb': _number(
        'Maximum allowed coupling at the aggressor edges in dB.',
      ),
      'maxCrosstalkPercent': _number(
        'Maximum allowed active/quiet RMS ratio in percent.',
      ),
    }),
    'intermittent': _object({
      'maxEventCount': _integer(
        'Maximum allowed number of intermittent events in the record.',
      ),
      'maxEventsPerMillionPeriods': _number(
        'Maximum allowed event rate per million periods.',
      ),
      'observationSeconds': _number(
        'Observation length the user expects the rate to be valid for.',
      ),
    }),
    'measurement_artifacts': _object({
      'probeAttenuation': _number(
        'Probe attenuation factor (for example 10 for a 10:1 probe).',
      ),
      'adcBits': _integer('ADC resolution in bits; the scope uses 8.'),
      'triggerLevelVolts': _number('Trigger level in volts, when known.'),
    }),
  },
};

Map<String, dynamic> _object(Map<String, dynamic> properties) => {
  'type': 'object',
  'properties': properties,
};

Map<String, dynamic> _number(String description) => {
  'type': 'number',
  'description': description,
};

Map<String, dynamic> _integer(String description) => {
  'type': 'integer',
  'description': description,
};

String? _stringArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

List<String>? _stringListArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is List) {
    final result = [
      for (final entry in value)
        if (entry != null && entry.toString().trim().isNotEmpty)
          entry.toString().trim(),
    ];
    return result.isEmpty ? null : result;
  }
  if (value is String && value.trim().isNotEmpty) {
    return value
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }
  return null;
}
