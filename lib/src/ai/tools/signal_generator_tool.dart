import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../../signal_generator/models.dart';

/// Returns the live signal-generator settings and connection status.
typedef SignalGeneratorStatusProvider = Future<Map<String, dynamic>> Function();

/// Applies one change request to the connected signal generator.
typedef SignalGeneratorApplyProvider =
    Future<Map<String, dynamic>> Function(SignalGeneratorSettings settings);

/// Executes a signal-generator action that is not a channel setting.
///
/// Supported operations: `reset_safe_state` and `stop_action`.
typedef SignalGeneratorActionProvider =
    Future<Map<String, dynamic>> Function(String operation);

/// Whether the current user request contains the signal-generator keyword.
typedef SignalGeneratorIntentCheck = bool Function();

/// A change request for one channel of the connected signal generator.
class SignalGeneratorSettings {
  const SignalGeneratorSettings({
    required this.channel,
    this.frequencyHz,
    this.amplitudeVpp,
    this.offsetV,
    this.waveform,
    this.requestedWaveform,
    this.dutyPercent,
    this.phaseDeg,
    this.output,
  });

  final int channel;
  final double? frequencyHz;
  final double? amplitudeVpp;
  final double? offsetV;

  /// Resolved waveform enum used by the transport.
  final Jds6600Waveform? waveform;

  /// Waveform name exactly as requested by the agent.
  ///
  /// The provider validates this name against the active device profile and
  /// reports the requested and resolved names when they differ.
  final String? requestedWaveform;

  final double? dutyPercent;
  final double? phaseDeg;
  final bool? output;

  /// Whether the request changes at least one setting.
  bool get hasSettings =>
      frequencyHz != null ||
      amplitudeVpp != null ||
      offsetV != null ||
      waveform != null ||
      dutyPercent != null ||
      phaseDeg != null ||
      output != null;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'channel': channel,
    if (frequencyHz != null) 'frequency_hz': frequencyHz,
    if (amplitudeVpp != null) 'amplitude_vpp': amplitudeVpp,
    if (offsetV != null) 'offset_v': offsetV,
    if (waveform != null) 'waveform': waveform!.scpiMnemonic,
    if (requestedWaveform != null) 'requested_waveform': requestedWaveform,
    if (dutyPercent != null) 'duty_percent': dutyPercent,
    if (phaseDeg != null) 'phase_deg': phaseDeg,
    if (output != null) 'output': output,
  };
}

/// Error returned when a signal-generator tool is used without a keyword.
const String signalGeneratorKeywordError =
    'Signal generator control requires a signal-generator keyword such as '
    '"Signalgenerator", "Funktionsgenerator" or "Function Generator" in the '
    'user request, for example "Signalgenerator Frequenz Kanal 1 10 kHz". '
    'If the user is confirming a previously proposed generator change, ask '
    'them to repeat the request with a signal-generator keyword.';

/// Words and phrases that explicitly address the signal generator.
///
/// The comparison uses normalized whole words, so a phrase only matches when
/// it appears as a complete word or phrase. This keeps words such as
/// "microwave generator" from matching "WaveGen".
const List<String> signalGeneratorKeywords = [
  'signalgenerator',
  'signal generator',
  'signalgeber',
  'funktionsgenerator',
  'frequenzgenerator',
  'testsignalgenerator',
  'test signal generator',
  'pruefsignalgenerator',
  'signalquelle',
  'signal source',
  'function generator',
  'frequency generator',
  'waveform generator',
  'signal synthesizer',
  'signalgen',
  'siggen',
  'wavegen',
];

String _normalizeWords(String text) {
  var value = text.toLowerCase().trim();
  value = value
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss');
  value = value.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Whether [text] explicitly addresses the signal generator.
///
/// The user must include one of [signalGeneratorKeywords] before a command,
/// for example "Signalgenerator", "Signalgeber", "Funktionsgenerator",
/// "Signalquelle", "Function Generator" or "WaveGen". Without a keyword, a
/// request such as "set frequency channel 1" keeps referring to the
/// oscilloscope waveform.
///
/// When [includeGenericGenerator] is true, the bare word "Generator" also
/// counts. The AI Chat orchestrator enables this alias; the Waveform
/// assistant deliberately keeps the explicit keywords so a generic mention
/// such as "clock generator" does not enable generator control.
bool hasSignalGeneratorKeyword(
  String text, {
  bool includeGenericGenerator = false,
}) {
  final padded = ' ${_normalizeWords(text)} ';
  for (final keyword in signalGeneratorKeywords) {
    if (padded.contains(' $keyword ')) return true;
  }
  if (includeGenericGenerator && padded.contains(' generator ')) return true;
  return false;
}

/// Creates the tool that reports the signal generator's live status.
Tool<Map<String, dynamic>> createReadSignalGeneratorStatusTool({
  SignalGeneratorStatusProvider? readStatus,
  SignalGeneratorIntentCheck? isEnabled,
  String agentName = 'unknown',
  String? description,
}) {
  return Tool<Map<String, dynamic>>(
    name: 'read_signal_generator_status',
    description:
        description ??
        'Return the status of the separate JDS6600/FY6900 signal generator: '
            'the configured device, whether it is detected and connected, the '
            'serial port, model, cached per-channel settings (waveform, frequency, '
            'amplitude, offset, duty cycle, phase), the output states and the '
            'device limits. Only use this tool when the user\'s request contains '
            'a signal-generator keyword such as Signalgenerator, Generator (AI Chat only), Signalgeber,'
            'Funktionsgenerator, Signalquelle, Function Generator or WaveGen.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': <String, dynamic>{},
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'read_signal_generator_status',
      );
      if (isEnabled != null && !isEnabled()) {
        await logger.logToolCall(
          input: args,
          output: {'error': signalGeneratorKeywordError},
        );
        return {'error': signalGeneratorKeywordError};
      }
      if (readStatus == null) {
        const result = {
          'error': 'Signal generator status is not available in this context.',
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }
      final result = await readStatus();
      await logger.logToolCall(
        input: args,
        output: {
          'configured_device': result['configured_device'],
          'connected': result['connected'],
          if (result['error'] != null) 'error': result['error'],
        },
      );
      return result;
    },
  );
}

/// Creates the tool that changes settings on the connected signal generator.
Tool<Map<String, dynamic>> createSetSignalGeneratorTool({
  SignalGeneratorApplyProvider? apply,
  SignalGeneratorIntentCheck? isEnabled,
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'set_signal_generator',
    description:
        'Change the separate JDS6600/FY6900 signal generator. Set the output '
        'channel and any of frequencyHz, amplitudeVpp, offsetV, waveform, '
        'dutyPercent, phaseDeg and output. Convert kHz/MHz to hertz and mV/V '
        'to volts before calling. The tool applies the waveform first, then '
        'frequency, amplitude, offset, duty, phase and output, because the '
        'device limits depend on the waveform and the frequency. Only use '
        'this tool when the user\'s request contains a signal-generator '
        'keyword such as Signalgenerator, Signalgeber, Funktionsgenerator, '
        'Signalquelle, Generator (AI Chat only), Function Generator or '
        'WaveGen, for example '
        '"Signalgenerator Frequenz Kanal 1 10 kHz". Never change the '
        'generator without such a keyword.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'channel': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 2,
          'description': 'Generator output channel (1 or 2). Required.',
        },
        'frequencyHz': {
          'type': 'number',
          'minimum': 0,
          'description':
              'Output frequency in hertz. Convert kHz or MHz to Hz, for '
              'example 10 kHz = 10000.',
        },
        'amplitudeVpp': {
          'type': 'number',
          'minimum': 0,
          'description': 'Output amplitude in volts peak-to-peak (Vpp).',
        },
        'offsetV': {'type': 'number', 'description': 'DC offset in volts.'},
        'waveform': {
          'type': 'string',
          'description':
              'Waveform name accepted by the configured device profile. '
              'Common values: sine, square, triangle, pulse, ramp, noise; '
              'device mnemonics such as SIN, SQU, TRI, PULS and NOIS are also '
              'accepted. The tool validates the name against the active '
              'profile and returns UNSUPPORTED_WAVEFORM instead of guessing.',
        },
        'dutyPercent': {
          'type': 'number',
          'minimum': 0,
          'maximum': 100,
          'description':
              'Duty cycle in percent. Applies to square and pulse waveforms.',
        },
        'phaseDeg': {
          'type': 'number',
          'minimum': 0,
          'maximum': 360,
          'description': 'Channel phase in degrees (0 to 360).',
        },
        'output': {
          'type': 'boolean',
          'description': 'true switches the channel output on, false off.',
        },
      },
      'required': ['channel'],
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'set_signal_generator',
      );
      if (isEnabled != null && !isEnabled()) {
        await logger.logToolCall(
          input: args,
          output: {'error': signalGeneratorKeywordError},
        );
        return {'error': signalGeneratorKeywordError};
      }

      final channel = _intArg(args, 'channel', 1);
      if (channel != 1 && channel != 2) {
        const result = {'error': 'channel must be 1 or 2.'};
        await logger.logToolCall(input: args, output: result);
        return result;
      }

      final waveformText = args['waveform'] as String?;
      final waveform = waveformText == null
          ? null
          : _resolveWaveform(waveformText);
      if (waveformText != null && waveform == null) {
        final result = {
          'error_code': 'UNSUPPORTED_WAVEFORM',
          'error':
              'Unknown waveform "$waveformText". Use a waveform name from the '
              'configured signal-generator profile or a common name such as '
              'sine, square, triangle, pulse, ramp or noise.',
          'requested_value': waveformText,
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }

      final settings = SignalGeneratorSettings(
        channel: channel,
        frequencyHz: _doubleArg(args, 'frequencyHz'),
        amplitudeVpp: _doubleArg(args, 'amplitudeVpp'),
        offsetV: _doubleArg(args, 'offsetV'),
        waveform: waveform,
        requestedWaveform: waveformText,
        dutyPercent: _doubleArg(args, 'dutyPercent'),
        phaseDeg: _doubleArg(args, 'phaseDeg'),
        output: args['output'] is bool ? args['output'] as bool : null,
      );
      if (!settings.hasSettings) {
        const result = {
          'error':
              'No setting was provided. Pass at least one of frequencyHz, '
              'amplitudeVpp, offsetV, waveform, dutyPercent, phaseDeg or '
              'output.',
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }

      final result = apply == null
          ? const {
              'error':
                  'Signal generator control is not available in this context.',
            }
          : await apply(settings);
      await logger.logToolCall(
        input: settings.toMap(),
        output: {
          if (result['success'] != null) 'success': result['success'],
          if (result['error'] != null) 'error': result['error'],
        },
      );
      return result;
    },
  );
}

/// Creates the tool for resetting or stopping the signal generator.
Tool<Map<String, dynamic>> createSignalGeneratorActionTool({
  SignalGeneratorActionProvider? control,
  SignalGeneratorIntentCheck? isEnabled,
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'signal_generator_action',
    description:
        'Execute a signal-generator action that is not a channel setting. '
        'operation "reset_safe_state" resets both channels to sine, 1 kHz, '
        '1 Vpp, 0 V offset and switches both outputs off. operation '
        '"stop_action" cancels a running modulation or sweep. Only use this '
        'tool when the user\'s request contains a signal-generator keyword '
        'such as Signalgenerator, Signalgeber, Generator (AI Chat only), '
        'Funktionsgenerator, Signalquelle, Function Generator or WaveGen.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'operation': {
          'type': 'string',
          'enum': ['reset_safe_state', 'stop_action'],
          'description':
              'reset_safe_state returns both channels to safe defaults; '
              'stop_action cancels a running modulation or sweep.',
        },
      },
      'required': ['operation'],
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'signal_generator_action',
      );
      if (isEnabled != null && !isEnabled()) {
        await logger.logToolCall(
          input: args,
          output: {'error': signalGeneratorKeywordError},
        );
        return {'error': signalGeneratorKeywordError};
      }
      final operation = (args['operation'] as String?)?.trim() ?? '';
      if (operation != 'reset_safe_state' && operation != 'stop_action') {
        const result = {
          'error': 'operation must be "reset_safe_state" or "stop_action".',
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }
      final result = control == null
          ? const {
              'error':
                  'Signal generator control is not available in this context.',
            }
          : await control(operation);
      await logger.logToolCall(
        input: args,
        output: {
          if (result['success'] != null) 'success': result['success'],
          if (result['error'] != null) 'error': result['error'],
        },
      );
      return result;
    },
  );
}

String _normalizeName(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

Jds6600Waveform? _resolveWaveform(String value) {
  final normalized = _normalizeName(value);
  switch (normalized) {
    case 'sinus':
      return Jds6600Waveform.sine;
    case 'rechteck':
      return Jds6600Waveform.square;
    case 'dreieck':
      return Jds6600Waveform.triangle;
    case 'saegezahn':
    case 'sagezahn':
      return Jds6600Waveform.ramp;
    case 'rauschen':
      return Jds6600Waveform.noise;
  }
  for (final waveform in Jds6600Waveform.values) {
    if (_normalizeName(waveform.scpiMnemonic) == normalized ||
        _normalizeName(waveform.displayName) == normalized ||
        _normalizeName(waveform.fy6900Name ?? '') == normalized) {
      return waveform;
    }
  }
  return Jds6600Waveform.fromScpi(value);
}

int _intArg(Map<String, dynamic> args, String key, int fallback) {
  final value = args[key];
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}

double? _doubleArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}
