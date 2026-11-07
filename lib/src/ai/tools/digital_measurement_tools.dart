/// Dedicated deterministic digital measurements for the DigitalAgent.
///
/// The tools are thin wrappers around the host's digital measurement provider.
/// The provider supplies the current acquisition and returns the measured
/// values; these tools only validate arguments, log the call and forward it.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';

/// Digital measurement kinds exposed as individual tools.
enum DigitalMeasurementType {
  riseFallTime('measure_rise_fall_time'),
  pulseWidth('measure_pulse_width'),
  edgeStatistics('measure_edge_statistics'),
  jitter('measure_jitter'),
  clockStability('measure_clock_stability'),
  setupHold('measure_setup_hold'),
  skew('measure_skew'),
  glitches('measure_glitches'),
  overshootUndershoot('measure_overshoot_undershoot');

  const DigitalMeasurementType(this.toolName);

  final String toolName;
}

/// One request to the host's digital measurement provider.
class DigitalMeasurementRequest {
  const DigitalMeasurementRequest({
    required this.type,
    this.channel,
    this.channelB,
    this.edge = 'rising',
    this.clockEdge = 'rising',
    this.maxPulseWidthSeconds,
    this.nominalFrequencyHz,
    this.thresholdVolts,
  });

  final DigitalMeasurementType type;

  /// Single channel, or channel A for skew, or clock channel for setup/hold.
  final String? channel;

  /// Data channel for setup/hold or channel B for skew.
  final String? channelB;

  final String edge;
  final String clockEdge;
  final double? maxPulseWidthSeconds;
  final double? nominalFrequencyHz;
  final double? thresholdVolts;
}

/// Runs one digital measurement and returns its result map.
typedef DigitalMeasurementProvider =
    Future<Map<String, dynamic>> Function(DigitalMeasurementRequest request);

/// Creates the nine dedicated digital measurement tools.
List<Tool<Map<String, dynamic>>> createDigitalMeasurementTools({
  DigitalMeasurementProvider? provider,
  String agentName = 'unknown',
}) {
  return [
    _measurementTool(
      name: DigitalMeasurementType.riseFallTime.toolName,
      description:
          'Returns the mean 10–90 % rise and fall times of the specified '
          'channel, the edge counts and the edge slopes. Use it when the user '
          'asks for rise time, fall time or edge speed.',
      properties: {
        'channel': _channelProperty(
          'Channel to measure. Omit it to use the first acquired channel.',
        ),
      },
      request: (args) => DigitalMeasurementRequest(
        type: DigitalMeasurementType.riseFallTime,
        channel: _stringArg(args, 'channel'),
      ),
      provider: provider,
      agentName: agentName,
    ),
    _measurementTool(
      name: DigitalMeasurementType.pulseWidth.toolName,
      description:
          'Returns the mean, minimum and maximum high and low pulse widths, '
          'the duty cycle and the mean period of the specified channel. Use '
          'it for pulse-width, duty-cycle or timing questions.',
      properties: {
        'channel': _channelProperty(
          'Channel to measure. Omit it to use the first acquired channel.',
        ),
      },
      request: (args) => DigitalMeasurementRequest(
        type: DigitalMeasurementType.pulseWidth,
        channel: _stringArg(args, 'channel'),
      ),
      provider: provider,
      agentName: agentName,
    ),
    _measurementTool(
      name: DigitalMeasurementType.edgeStatistics.toolName,
      description:
          'Returns the rising and falling edge counts and the interval '
          'distribution (mean, minimum, maximum and standard deviation) '
          'between consecutive edges of the selected polarity. Use it when '
          'the user asks for edge spacing, period distribution or timing '
          'spread.',
      properties: {
        'channel': _channelProperty(
          'Channel to measure. Omit it to use the first acquired channel.',
        ),
        'edge': _enumProperty('Edge polarity to analyse.', const [
          'rising',
          'falling',
          'both',
        ]),
      },
      request: (args) => DigitalMeasurementRequest(
        type: DigitalMeasurementType.edgeStatistics,
        channel: _stringArg(args, 'channel'),
        edge: _stringArg(args, 'edge') ?? 'both',
      ),
      provider: provider,
      agentName: agentName,
    ),
    _measurementTool(
      name: DigitalMeasurementType.jitter.toolName,
      description:
          'Returns the RMS and peak-to-peak period jitter and the '
          'cycle-to-cycle jitter from the rising edges of the specified '
          'channel. Use it for clock or data jitter questions.',
      properties: {
        'channel': _channelProperty(
          'Channel to measure. Omit it to use the first acquired channel.',
        ),
      },
      request: (args) => DigitalMeasurementRequest(
        type: DigitalMeasurementType.jitter,
        channel: _stringArg(args, 'channel'),
      ),
      provider: provider,
      agentName: agentName,
    ),
    _measurementTool(
      name: DigitalMeasurementType.clockStability.toolName,
      description:
          'Returns the mean, minimum and maximum frequency, the frequency '
          'stability in ppm and the linear drift in ppm from the rising '
          'edges. Pass nominalFrequencyHz to also receive the frequency error '
          'in ppm.',
      properties: {
        'channel': _channelProperty(
          'Channel to measure. Omit it to use the first acquired channel.',
        ),
        'nominalFrequencyHz': _numberProperty(
          'Nominal clock frequency for the frequency-error calculation.',
          minimum: 0,
        ),
      },
      request: (args) => DigitalMeasurementRequest(
        type: DigitalMeasurementType.clockStability,
        channel: _stringArg(args, 'channel'),
        nominalFrequencyHz: _numberArg(args, 'nominalFrequencyHz'),
      ),
      provider: provider,
      agentName: agentName,
    ),
    _measurementTool(
      name: DigitalMeasurementType.setupHold.toolName,
      description:
          'Returns the setup and hold time distribution between a clock '
          'channel and a data channel. Setup is the time from the last data '
          'transition before the selected clock edge to that edge; hold is '
          'the time from the clock edge to the next data transition.',
      properties: {
        'clockChannel': _channelProperty('Channel carrying the clock signal.'),
        'dataChannel': _channelProperty('Channel carrying the data signal.'),
        'clockEdge': _enumProperty('Clock edge used for the analysis.', const [
          'rising',
          'falling',
        ]),
        'thresholdVolts': _numberProperty(
          'Optional logic threshold in volts for both channels. Omit it to '
          'use the mid-level of each channel.',
        ),
      },
      required: const ['clockChannel', 'dataChannel'],
      request: (args) => DigitalMeasurementRequest(
        type: DigitalMeasurementType.setupHold,
        channel: _stringArg(args, 'clockChannel'),
        channelB: _stringArg(args, 'dataChannel'),
        clockEdge: _stringArg(args, 'clockEdge') ?? 'rising',
        thresholdVolts: _numberArg(args, 'thresholdVolts'),
      ),
      provider: provider,
      agentName: agentName,
    ),
    _measurementTool(
      name: DigitalMeasurementType.skew.toolName,
      description:
          'Returns the time offset between corresponding edges of two '
          'channels (channel A minus channel B) with mean, minimum, maximum '
          'and standard deviation. Use it for skew, lane-to-lane or '
          'clock-to-data offset questions.',
      properties: {
        'channelA': _channelProperty('First channel (A).'),
        'channelB': _channelProperty('Second channel (B).'),
        'edge': _enumProperty('Edge polarity used for the pairing.', const [
          'rising',
          'falling',
        ]),
        'thresholdVolts': _numberProperty(
          'Optional logic threshold in volts for both channels. Omit it to '
          'use the mid-level of each channel.',
        ),
      },
      required: const ['channelA', 'channelB'],
      request: (args) => DigitalMeasurementRequest(
        type: DigitalMeasurementType.skew,
        channel: _stringArg(args, 'channelA'),
        channelB: _stringArg(args, 'channelB'),
        edge: _stringArg(args, 'edge') ?? 'rising',
        thresholdVolts: _numberArg(args, 'thresholdVolts'),
      ),
      provider: provider,
      agentName: agentName,
    ),
    _measurementTool(
      name: DigitalMeasurementType.glitches.toolName,
      description:
          'Returns pulses narrower than maxPulseWidthSeconds (default: 25 % '
          'of the median high pulse width), including their start time, width '
          'and polarity. Use it for glitch and runt-pulse searches.',
      properties: {
        'channel': _channelProperty(
          'Channel to measure. Omit it to use the first acquired channel.',
        ),
        'maxPulseWidthSeconds': _numberProperty(
          'Maximum pulse width treated as a glitch. Omit it to use 25 % of '
          'the median high pulse width.',
          minimum: 0,
        ),
        'thresholdVolts': _numberProperty(
          'Optional logic threshold in volts. Omit it to use the mid-level.',
        ),
      },
      request: (args) => DigitalMeasurementRequest(
        type: DigitalMeasurementType.glitches,
        channel: _stringArg(args, 'channel'),
        maxPulseWidthSeconds: _numberArg(args, 'maxPulseWidthSeconds'),
        thresholdVolts: _numberArg(args, 'thresholdVolts'),
      ),
      provider: provider,
      agentName: agentName,
    ),
    _measurementTool(
      name: DigitalMeasurementType.overshootUndershoot.toolName,
      description:
          'Returns the maximum overshoot and undershoot in volts and as a '
          'percentage of the top-base amplitude, together with the top, base, '
          'maximum and minimum levels. Use it for signal-integrity checks.',
      properties: {
        'channel': _channelProperty(
          'Channel to measure. Omit it to use the first acquired channel.',
        ),
      },
      request: (args) => DigitalMeasurementRequest(
        type: DigitalMeasurementType.overshootUndershoot,
        channel: _stringArg(args, 'channel'),
      ),
      provider: provider,
      agentName: agentName,
    ),
  ];
}

Tool<Map<String, dynamic>> _measurementTool({
  required String name,
  required String description,
  required Map<String, dynamic> properties,
  List<String> required = const [],
  required DigitalMeasurementRequest Function(Map<String, dynamic>) request,
  required DigitalMeasurementProvider? provider,
  required String agentName,
}) {
  return Tool<Map<String, dynamic>>(
    name: name,
    description: description,
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
    }),
    onCall: (args) async {
      final logger = AppLogger(agentName: agentName, toolName: name);
      Map<String, dynamic> result;
      if (provider == null) {
        result = <String, dynamic>{
          'error': 'Digital measurements are not available in this context.',
        };
      } else {
        try {
          result = await provider(request(args));
        } on Object catch (error) {
          result = <String, dynamic>{'error': '$name failed: $error'};
        }
      }
      // Logging is best-effort and must not delay the measurement result:
      // the pretty-printed JSON can queue behind a large DEBUG backlog.
      logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}

Map<String, dynamic> _channelProperty(String description) => {
  'type': 'string',
  'enum': const ['ch1', 'ch2', 'ch3', 'ch4'],
  'description': description,
};

Map<String, dynamic> _numberProperty(String description, {double? minimum}) => {
  'type': 'number',
  'description': description,
  'minimum': ?minimum,
};

Map<String, dynamic> _enumProperty(String description, List<String> values) => {
  'type': 'string',
  'enum': values,
  'description': description,
};

String? _stringArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double? _numberArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}
