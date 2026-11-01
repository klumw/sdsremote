/// AI tools exposing the waveform classification and comparison engine.
///
/// The tools are thin wrappers: all measurements and similarity values are
/// produced by `WaveformAnalysisService` on the captured data. The providers
/// are injected by the Acquire Waveform page, so the agent always sees the
/// current acquisition.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';

/// Classifies a captured channel and returns the complete classification map.
///
/// `channel` may be omitted to analyse the first available channel.
/// `referenceTypes` restricts the candidate set (all ten types by default).
typedef WaveformClassificationProvider =
    Future<Map<String, dynamic>> Function({
      String? channel,
      List<String>? referenceTypes,
    });

/// Compares a captured channel against selected reference types.
typedef WaveformReferenceComparisonProvider =
    Future<Map<String, dynamic>> Function({
      String? channel,
      List<String>? referenceTypes,
    });

/// Returns the complete feature set of a captured channel.
typedef WaveformFeaturesProvider =
    Future<Map<String, dynamic>> Function({String? channel});

/// Compares two captured channels with each other.
typedef WaveformPairComparisonProvider =
    Future<Map<String, dynamic>> Function({
      required String channelA,
      required String channelB,
    });

/// Generates a reference waveform with optional parameters.
typedef ReferenceGenerationProvider =
    Future<Map<String, dynamic>> Function({
      required String referenceType,
      Map<String, dynamic>? parameters,
    });

const List<String> _referenceTypeIds = [
  'sine',
  'square',
  'triangle',
  'sawtooth',
  'pulse',
  'exponential_decay',
  'damped_oscillation',
  'clipped_sine',
  'noisy_sine',
  'pwm',
];

Schema _referenceComparisonSchema() => Schema.fromMap({
  'type': 'object',
  'properties': {
    'channel': {
      'type': 'string',
      'enum': ['ch1', 'ch2', 'ch3', 'ch4'],
      'description':
          'Acquired channel to analyse. Omit it to use the first channel '
          'that has waveform data.',
    },
    'referenceTypes': {
      'type': 'array',
      'items': {'type': 'string', 'enum': _referenceTypeIds},
      'description':
          'Optional subset of reference types. Omit it to compare against '
          'all ten types.',
    },
  },
});

/// Registers `classify_waveform` for the Waveform Agent.
Tool<Map<String, dynamic>> createClassifyWaveformTool({
  WaveformClassificationProvider? classify,
  String agentName = 'unknown',
}) {
  final provider = classify;
  return Tool<Map<String, dynamic>>(
    name: 'classify_waveform',
    description:
        'Classifies the captured waveform against the ten reference signal '
        'types (sine, square, triangle, sawtooth, pulse, exponential decay, '
        'damped oscillation, clipped sine, noisy sine and PWM). Returns the '
        'primary classification, similarity percentage, confidence band, the '
        'top three candidates, all candidate scores with their comparison '
        'breakdowns, the complete extracted features, detected anomalies, '
        'secondary characteristics and a written explanation. Use it whenever '
        'the user asks what kind of waveform this is, which reference matches '
        'best, why a signal is distorted, or whether it looks like a specific '
        'signal type. Quote the returned percentages and measured values; '
        'never invent similarity scores or measurements. Similarity is a '
        'descriptive match score, not a calibrated probability. Follow the '
        'returned `mentionAlternatives` flag: when it is false, name only the '
        'primary classification; when it is true, name the closest '
        'alternatives as well. Optional arguments: channel (ch1-ch4) and '
        'referenceTypes (subset).',
    inputSchema: _referenceComparisonSchema(),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'classify_waveform',
      );
      final result = provider == null
          ? <String, dynamic>{
              'error':
                  'Waveform classification is not available in this context.',
            }
          : await provider(
              channel: _stringArg(args, 'channel'),
              referenceTypes: _stringListArg(args, 'referenceTypes'),
            );
      logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}

/// Registers `compare_waveform_to_references` for the Waveform Agent.
Tool<Map<String, dynamic>> createCompareWaveformToReferencesTool({
  WaveformReferenceComparisonProvider? compare,
  String agentName = 'unknown',
}) {
  final provider = compare;
  return Tool<Map<String, dynamic>>(
    name: 'compare_waveform_to_references',
    description:
        'Compares the captured waveform against all or selected reference '
        'types and returns the individual similarity scores, the ranking, the '
        'best matching reference and the detailed shape-correlation, DTW, '
        'feature and frequency-domain breakdown. Use it when the user asks '
        '"compare this signal with a sine wave", "which reference matches '
        'best" or wants the score of a specific reference type. Optional '
        'arguments: channel (ch1-ch4) and referenceTypes (subset). Quote only '
        'the returned values; similarity is not a calibrated probability.',
    inputSchema: _referenceComparisonSchema(),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'compare_waveform_to_references',
      );
      final result = provider == null
          ? <String, dynamic>{
              'error':
                  'Waveform reference comparison is not available in this '
                  'context.',
            }
          : await provider(
              channel: _stringArg(args, 'channel'),
              referenceTypes: _stringListArg(args, 'referenceTypes'),
            );
      logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}

/// Registers `get_waveform_features` for the Waveform Agent.
Tool<Map<String, dynamic>> createGetWaveformFeaturesTool({
  WaveformFeaturesProvider? readFeatures,
  String agentName = 'unknown',
}) {
  final provider = readFeatures;
  return Tool<Map<String, dynamic>>(
    name: 'get_waveform_features',
    description:
        'Returns the complete feature set extracted from the captured '
        'waveform: voltage statistics, frequency and period, duty cycle, rise '
        'and fall times, slopes, symmetry, peak and zero-crossing counts, '
        'harmonic amplitudes, THD, SNR, spectral centroid, shape correlations, '
        'ramp linearity, exponential fit quality and time constant, envelope '
        'decay rate, clipping ratio and duty-cycle variation. Use it when the '
        'user asks for a specific measured property or for the data behind a '
        'classification. Optional argument: channel (ch1-ch4). Never invent '
        'or recalculate a value that the tool returns.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'channel': {
          'type': 'string',
          'enum': ['ch1', 'ch2', 'ch3', 'ch4'],
          'description':
              'Acquired channel to analyse. Omit it to use the first channel '
              'that has waveform data.',
        },
      },
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'get_waveform_features',
      );
      final result = provider == null
          ? <String, dynamic>{
              'error': 'Waveform features are not available in this context.',
            }
          : await provider(channel: _stringArg(args, 'channel'));
      logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}

/// Registers `compare_waveforms` for the Waveform Agent.
Tool<Map<String, dynamic>> createCompareWaveformsTool({
  WaveformPairComparisonProvider? compare,
  String agentName = 'unknown',
}) {
  final provider = compare;
  return Tool<Map<String, dynamic>>(
    name: 'compare_waveforms',
    description:
        'Compares two captured channels with each other and returns the shape '
        'similarity, correlation coefficient with relative delay, DTW '
        'distance and similarity, frequency-domain similarity, amplitude '
        'difference, timing differences and a written summary. Use it when the '
        'user asks how similar two channels are or whether two captures show '
        'the same signal. Both channel arguments are required (ch1-ch4). '
        'Quote the returned values only.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'channelA': {
          'type': 'string',
          'enum': ['ch1', 'ch2', 'ch3', 'ch4'],
          'description': 'First acquired channel.',
        },
        'channelB': {
          'type': 'string',
          'enum': ['ch1', 'ch2', 'ch3', 'ch4'],
          'description': 'Second acquired channel.',
        },
      },
      'required': ['channelA', 'channelB'],
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'compare_waveforms',
      );
      final channelA = _stringArg(args, 'channelA');
      final channelB = _stringArg(args, 'channelB');
      final result = provider == null
          ? <String, dynamic>{
              'error': 'Waveform comparison is not available in this context.',
            }
          : channelA == null || channelB == null
          ? <String, dynamic>{
              'error': 'Both channelA and channelB are required.',
            }
          : await provider(channelA: channelA, channelB: channelB);
      logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}

/// Registers `generate_reference_waveform` for the Waveform Agent.
Tool<Map<String, dynamic>> createGenerateReferenceWaveformTool({
  ReferenceGenerationProvider? generate,
  String agentName = 'unknown',
}) {
  final provider = generate;
  return Tool<Map<String, dynamic>>(
    name: 'generate_reference_waveform',
    description:
        'Generates a mathematical reference waveform of one of the ten signal '
        'types with configurable frequency, amplitude, offset, phase, sample '
        'rate, duration, duty cycle, noise level, damping, exponential time '
        'constant, clipping levels and rectangular edge width. Returns the '
        'parameters and a downsampled preview of the reference values, not the '
        'complete waveform. Use it when the user asks what an ideal or '
        'non-ideal reference of a type looks like or wants a reference with '
        'specific parameters. This tool does not classify a capture; use '
        'classify_waveform for that.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'referenceType': {
          'type': 'string',
          'enum': _referenceTypeIds,
          'description': 'Reference type to generate.',
        },
        'parameters': {
          'type': 'object',
          'description': 'Optional waveform parameters.',
          'properties': {
            'frequencyHz': {'type': 'number'},
            'amplitudeVolts': {'type': 'number'},
            'offsetVolts': {'type': 'number'},
            'phaseRadians': {'type': 'number'},
            'sampleRateHz': {'type': 'number'},
            'durationSeconds': {'type': 'number'},
            'dutyCycle': {'type': 'number'},
            'noiseLevelPercent': {'type': 'number'},
            'dampingPerSecond': {'type': 'number'},
            'timeConstantSeconds': {'type': 'number'},
            'clippingLevel': {'type': 'number'},
            'lowerClipLevel': {'type': 'number'},
            'upperClipLevel': {'type': 'number'},
            'rectangularEdgeFraction': {'type': 'number'},
            'directionIsRising': {'type': 'boolean'},
            'seed': {'type': 'integer'},
          },
        },
      },
      'required': ['referenceType'],
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'generate_reference_waveform',
      );
      final referenceType = _stringArg(args, 'referenceType');
      final parameters = args['parameters'];
      final result = provider == null
          ? <String, dynamic>{
              'error':
                  'Reference waveform generation is not available in this '
                  'context.',
            }
          : referenceType == null
          ? <String, dynamic>{'error': 'referenceType is required.'}
          : await provider(
              referenceType: referenceType,
              parameters: parameters is Map
                  ? Map<String, dynamic>.from(parameters)
                  : null,
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
