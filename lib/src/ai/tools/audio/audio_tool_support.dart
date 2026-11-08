/// Shared plumbing for the audio analysis tools.
///
/// Every tool is a thin wrapper around the pure functions in this folder. The
/// helpers here provide consistent schemas, logging, error handling and
/// JSON-safe results.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../../core/logger.dart';
import 'audio_analysis_context.dart';

const List<String> audioChannelIds = ['ch1', 'ch2', 'ch3', 'ch4'];

/// Creates a tool with consistent logging and exception handling.
Tool<Map<String, dynamic>> createAudioTool({
  required String name,
  required String description,
  required Map<String, dynamic> properties,
  List<String> required = const [],
  required Future<Map<String, dynamic>> Function(Map<String, dynamic> args)
  handler,
  String agentName = 'unknown',
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
      logger.log('$name started');
      try {
        result = audioResult(await handler(args));
      } on AudioSweepException catch (error) {
        result = audioResult(audioSweepFailure(error));
      } on AudioFrequencySeriesException catch (error) {
        result = audioResult(audioSeriesFailure(error));
      } on Object catch (error) {
        result = audioResult({'error': '$name failed: $error'});
      }
      await logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}

/// Converts non-finite doubles and nested collections into JSON-safe values.
Map<String, dynamic> audioResult(Map<String, dynamic> values) {
  final result = <String, dynamic>{};
  for (final entry in values.entries) {
    result[entry.key] = _finiteValue(entry.value);
  }
  return result;
}

Object? _finiteValue(Object? value) {
  if (value is double) return value.isFinite ? value : null;
  if (value is num || value is bool || value is String || value == null) {
    return value;
  }
  if (value is List) {
    return [for (final item in value) _finiteValue(item)];
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _finiteValue(entry.value),
    };
  }
  return value.toString();
}

Map<String, dynamic> audioContextError() => {
  'error': 'No audio analysis context is available. Acquire a waveform first.',
};

Map<String, dynamic> audioChannelError(String? channel) => {
  'error':
      'No usable waveform data for '
      '${channel?.trim().isNotEmpty == true ? channel!.trim() : 'the first acquired channel'}. '
      'Enable the channel on the oscilloscope and acquire a new waveform, or '
      'choose a channel that was captured.',
  'hint':
      'A channel that is switched off or has too few samples is not part of '
      'the audio context.',
};

Map<String, dynamic> audioSweepError() => {
  'error_code': 'SWEEP_PROVIDER_MISSING',
  'error':
      'No Bode/frequency sweep provider is available in this context. The '
      'sweep tools need a connected signal generator and oscilloscope.',
};

/// Structured result for a sweep that failed after the provider was called.
Map<String, dynamic> audioSweepFailure(AudioSweepException error) => {
  'error_code': error.code,
  'error': error.message,
  if (error.hint != null) 'hint': error.hint,
};

/// Structured error for a missing frequency-series provider.
Map<String, dynamic> audioSeriesError() => {
  'error_code': 'SERIES_PROVIDER_MISSING',
  'error':
      'No frequency-series provider is available in this context. The '
      'measurement needs a connected signal generator and oscilloscope.',
};

/// Structured result for a frequency series that failed after the provider
/// was called.
Map<String, dynamic> audioSeriesFailure(AudioFrequencySeriesException error) =>
    {
      'error_code': error.code,
      'error': error.message,
      if (error.hint != null) 'hint': error.hint,
    };

AudioAnalysisContext? audioContext(AudioAnalysisContextProvider? provider) =>
    provider?.call();

AudioChannelData? audioChannel(
  AudioAnalysisContext? context,
  String? channel,
) => context?.channel(channel);

Map<String, dynamic> audioChannelProperty(String description) => {
  'type': 'string',
  'enum': audioChannelIds,
  'description': description,
};

Map<String, dynamic> audioNumberProperty(
  String description, {
  double? minimum,
  double? maximum,
}) => {
  'type': 'number',
  'description': description,
  'minimum': ?minimum,
  'maximum': ?maximum,
};

Map<String, dynamic> audioIntegerProperty(
  String description, {
  int? minimum,
  int? maximum,
}) => {
  'type': 'integer',
  'description': description,
  'minimum': ?minimum,
  'maximum': ?maximum,
};

Map<String, dynamic> audioBooleanProperty(String description) => {
  'type': 'boolean',
  'description': description,
};

Map<String, dynamic> audioEnumProperty(
  String description,
  List<String> values,
) => {'type': 'string', 'enum': values, 'description': description};

String? audioStringArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double? audioNumberArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

int? audioIntArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

bool audioBoolArg(
  Map<String, dynamic> args,
  String key, {
  bool fallback = false,
}) {
  final value = args[key];
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
  }
  return fallback;
}

double audioDoubleOr(Map<String, dynamic> args, String key, double fallback) =>
    audioNumberArg(args, key) ?? fallback;

int audioIntOr(Map<String, dynamic> args, String key, int fallback) =>
    audioIntArg(args, key) ?? fallback;

String audioStringOr(Map<String, dynamic> args, String key, String fallback) =>
    audioStringArg(args, key) ?? fallback;
