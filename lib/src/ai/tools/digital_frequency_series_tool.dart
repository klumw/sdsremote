/// Host-managed digital frequency series for the DigitalAgent.
///
/// The tool is a thin wrapper around a host provider. The provider steps the
/// connected signal generator through an explicit frequency list while
/// preserving its waveform, amplitude and offset, reads the digital levels and
/// timing from the oscilloscope, restores the device state and turns the
/// generator outputs off. The DigitalAgent interprets the returned values.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../cancellation.dart';

/// Scope quantities returned by the host for every frequency.
const List<String> digitalFrequencySeriesQuantities = <String>[
  'pkpk',
  'top',
  'base',
  'max',
  'min',
  'rise',
  'fall',
  'freq',
  'duty',
];

/// Units of [digitalFrequencySeriesQuantities].
const Map<String, String> digitalFrequencySeriesUnits = <String, String>{
  'pkpk': 'V',
  'top': 'V',
  'base': 'V',
  'max': 'V',
  'min': 'V',
  'rise': 's',
  'fall': 's',
  'freq': 'Hz',
  'duty': '%',
};

/// One request to the host's digital frequency-series provider.
class DigitalFrequencySeriesRequest {
  const DigitalFrequencySeriesRequest({
    required this.frequenciesHz,
    required this.channel,
    this.generatorChannel = 1,
    this.settlingMs = 1000,
    this.useCurrentSettings = false,
    this.waveform = 'sine',
    this.amplitudeVpp,
    this.offsetV,
    this.cancelToken,
  });

  /// Frequencies in measurement order.
  final List<double> frequenciesHz;

  /// Scope channel label, for example `ch1`.
  final String channel;

  /// Generator channel, 1 or 2.
  final int generatorChannel;

  /// Settling time after each frequency change in milliseconds.
  final int settlingMs;

  /// Whether the current generator waveform, amplitude and offset stay.
  final bool useCurrentSettings;

  /// Generator waveform when [useCurrentSettings] is false.
  final String waveform;

  /// Generator amplitude when [useCurrentSettings] is false.
  final double? amplitudeVpp;

  /// Generator offset when [useCurrentSettings] is false.
  final double? offsetV;

  final CancellationToken? cancelToken;
}

/// One measured point of a digital frequency series.
class DigitalFrequencySeriesPoint {
  const DigitalFrequencySeriesPoint({
    required this.frequencyHz,
    required this.values,
    this.valid = true,
    this.note,
  });

  final double frequencyHz;

  /// Measured values by quantity name. A quantity that could not be read is
  /// `null`; the other quantities of the same point remain usable.
  final Map<String, double?> values;

  final bool valid;
  final String? note;
}

/// Result of a host-managed digital frequency series.
class DigitalFrequencySeriesData {
  const DigitalFrequencySeriesData({
    required this.points,
    this.source = 'frequency_series',
    this.configSummary,
  });

  final List<DigitalFrequencySeriesPoint> points;
  final String source;
  final String? configSummary;
}

/// Reports why a host-managed digital frequency series could not run.
class DigitalFrequencySeriesException implements Exception {
  const DigitalFrequencySeriesException(
    this.message, {
    this.code = 'SERIES_FAILED',
    this.hint,
  });

  final String message;
  final String code;
  final String? hint;

  @override
  String toString() => message;
}

/// Runs one digital frequency series and returns its measured points.
typedef DigitalFrequencySeriesProvider =
    Future<DigitalFrequencySeriesData?> Function(
      DigitalFrequencySeriesRequest request,
    );

/// Creates the `measure_digital_frequency_series` tool.
Tool<Map<String, dynamic>> createDigitalFrequencySeriesTool({
  DigitalFrequencySeriesProvider? provider,
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'measure_digital_frequency_series',
    description:
        'Measures the digital signal quality on one scope channel at an '
        'explicit list of frequencies. The host keeps the connected signal '
        'generator waveform, amplitude and offset, sets each frequency, '
        'adjusts the scope timebase and vertical scale, reads peak-to-peak, '
        'top, base, maximum, minimum, rise time, fall time, frequency and duty '
        'cycle, restores the device state and turns the generator outputs off. '
        'Use it ONCE for an input-suitability or logic-level check at several '
        'discrete frequencies. Do not step the generator through individual '
        'frequency commands and do not call it for a continuous sweep.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'frequenciesHz': {
          'type': 'array',
          'minItems': 1,
          'maxItems': 50,
          'items': {'type': 'number', 'minimum': 0.001},
          'description': 'Frequencies in Hz, in measurement order.',
        },
        'channel': {
          'type': 'string',
          'enum': const ['ch1', 'ch2', 'ch3', 'ch4'],
          'description':
              'Scope channel that carries the digital signal. Use ch1 when '
              'the request does not name another channel.',
        },
        'generatorChannel': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 2,
          'description': 'Generator channel (1 or 2).',
        },
        'settlingMs': {
          'type': 'integer',
          'minimum': 100,
          'maximum': 10000,
          'description':
              'Settling time after each frequency change in milliseconds.',
        },
        'useCurrentSettings': {
          'type': 'boolean',
          'description':
              'Keep the current generator waveform, amplitude and offset and '
              'only step the frequency.',
        },
        'waveform': {
          'type': 'string',
          'enum': const ['sine', 'square', 'triangle', 'ramp', 'pulse'],
          'description': 'Generator waveform when useCurrentSettings is false.',
        },
        'amplitudeVpp': {
          'type': 'number',
          'minimum': 0.001,
          'description':
              'Generator amplitude when useCurrentSettings is false.',
        },
        'offsetV': {
          'type': 'number',
          'description': 'Generator offset when useCurrentSettings is false.',
        },
      },
      'required': const ['frequenciesHz'],
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'measure_digital_frequency_series',
      );
      Map<String, dynamic> result;
      try {
        result = await _handle(args, provider);
      } on DigitalFrequencySeriesException catch (error) {
        result = <String, dynamic>{
          'error_code': error.code,
          'error': error.message,
          if (error.hint != null) 'hint': error.hint,
        };
      } on Object catch (error) {
        result = <String, dynamic>{
          'error': 'measure_digital_frequency_series failed: $error',
        };
      }
      await logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}

Future<Map<String, dynamic>> _handle(
  Map<String, dynamic> args,
  DigitalFrequencySeriesProvider? provider,
) async {
  if (provider == null) {
    return <String, dynamic>{
      'error_code': 'SERIES_PROVIDER_MISSING',
      'error':
          'No frequency-series provider is available in this context. The '
          'measurement needs a connected signal generator and oscilloscope.',
    };
  }

  final frequencies = <double>[];
  final raw = args['frequenciesHz'];
  if (raw is Iterable) {
    for (final entry in raw) {
      if (entry is num && entry.isFinite && entry > 0) {
        frequencies.add(entry.toDouble());
      }
    }
  }
  if (frequencies.isEmpty) {
    return <String, dynamic>{
      'error': 'Enter at least one positive frequency in Hz.',
    };
  }
  if (frequencies.length > 50) {
    return <String, dynamic>{'error': 'At most 50 frequencies are supported.'};
  }

  final channel = _stringArg(args, 'channel') ?? 'ch1';
  if (!const <String>['ch1', 'ch2', 'ch3', 'ch4'].contains(channel)) {
    return <String, dynamic>{
      'error': 'channel must be one of ch1, ch2, ch3 or ch4.',
    };
  }
  final generatorChannel = _intArg(args, 'generatorChannel') ?? 1;
  if (generatorChannel != 1 && generatorChannel != 2) {
    return <String, dynamic>{'error': 'generatorChannel must be 1 or 2.'};
  }
  final settlingMs = _intArg(args, 'settlingMs') ?? 1000;
  if (settlingMs < 100 || settlingMs > 10000) {
    return <String, dynamic>{
      'error': 'settlingMs must be between 100 and 10000.',
    };
  }
  final useCurrentSettings = args['useCurrentSettings'] == true;
  final amplitude = _numberArg(args, 'amplitudeVpp');
  if (!useCurrentSettings &&
      (amplitude == null || !amplitude.isFinite || amplitude <= 0)) {
    return <String, dynamic>{
      'error': 'amplitudeVpp is required unless useCurrentSettings is true.',
    };
  }
  final waveform = _stringArg(args, 'waveform') ?? 'sine';
  final offset = _numberArg(args, 'offsetV');

  final data = await provider(
    DigitalFrequencySeriesRequest(
      frequenciesHz: frequencies,
      channel: channel,
      generatorChannel: generatorChannel,
      settlingMs: settlingMs,
      useCurrentSettings: useCurrentSettings,
      waveform: waveform,
      amplitudeVpp: amplitude,
      offsetV: offset,
    ),
  );
  if (data == null) {
    return <String, dynamic>{
      'error_code': 'SERIES_PROVIDER_MISSING',
      'error':
          'The frequency-series provider returned no data. The measurement '
          'needs a connected signal generator and oscilloscope.',
    };
  }

  final validPointCount = data.points
      .where(
        (point) =>
            point.valid &&
            point.values.values.any((value) => value != null && value.isFinite),
      )
      .length;
  return <String, dynamic>{
    'source': data.source,
    'configSummary': data.configSummary,
    'quantities': digitalFrequencySeriesQuantities,
    'unitByQuantity': digitalFrequencySeriesUnits,
    'pointCount': data.points.length,
    'validPointCount': validPointCount,
    'points': <Map<String, dynamic>>[
      for (final point in data.points)
        <String, dynamic>{
          'frequencyHz': point.frequencyHz,
          'values': point.values,
          'valid': point.valid,
          'note': point.note,
        },
    ],
    'method': 'host_digital_frequency_series',
  };
}

String? _stringArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _intArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? _numberArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}
