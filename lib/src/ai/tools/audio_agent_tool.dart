/// AI tool exposing the AudioAgent sub-agent to the Waveform Agent.
///
/// The AudioAgent performs the actual audio measurements; the Waveform Agent
/// only delegates the request and presents the returned structured result.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';

/// Runs one audio analysis request through the AudioAgent.
typedef AudioAnalysisProvider =
    Future<Map<String, dynamic>> Function({
      required String request,
      bool autonomous,
      String? channel,
      String? focus,
    });

/// Registers `audio_analysis_agent` for the Waveform Agent.
Tool<Map<String, dynamic>> createAudioAnalysisAgentTool({
  AudioAnalysisProvider? analyze,
  void Function()? onLongRunningStart,
  void Function()? onLongRunningEnd,
  String agentName = 'unknown',
}) {
  final provider = analyze;
  return Tool<Map<String, dynamic>>(
    name: 'audio_analysis_agent',
    description:
        'Delegates an audio measurement or analysis request to the '
        'AudioAgent sub-agent. Use it for audio-specific work: level, '
        'RMS/peak, clipping, DC offset, THD, THD+N, SINAD, harmonics, '
        'intermodulation, distortion, SNR, noise floor, crest factor, hum, '
        'interference, spectral peaks, bandwidth, rise/fall time, phase, '
        'delay, transients, dropout, stability, crosstalk, dynamic range, '
        'gain, frequency response, phase response, group delay, sweeps and '
        'coherence. The AudioAgent can use all audio tools, call the '
        'InstrumentAgent for live queries and signal changes, and run a Bode '
        'sweep when needed. Before the first call, ask the user once whether '
        'the audio measurements may run autonomously, including the necessary '
        'oscilloscope/generator changes and sweeps. Pass `autonomous: true` '
        'only after that permission. The result contains `summary`, '
        '`measurements`, `warnings`, `limitations`, `toolsUsed`, '
        '`requestedAction` and `needsInput`. Present the summary and '
        'measurement values faithfully in the user\'s language; never invent '
        'or recalculate them. If `requestedAction` or `needsInput` is '
        'present, relay it to the user and call the tool again after the '
        'answer. If the result contains `error`, relay it and do not invent a '
        'measurement. Call it at most twice per user request.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'request': {
          'type': 'string',
          'description':
              'The audio measurement or analysis request in natural '
              'language. Include the quantities, channel(s), frequency range '
              'and any known signal conditions.',
        },
        'autonomous': {
          'type': 'boolean',
          'description':
              'True only after the user granted the one-time permission for '
              'autonomous audio measurements, including necessary '
              'scope/generator changes and sweeps.',
        },
        'channel': {
          'type': 'string',
          'enum': ['ch1', 'ch2', 'ch3', 'ch4'],
          'description':
              'Optional primary channel. Omit it when the request names the '
              'channel or the first acquired channel should be used.',
        },
        'focus': {
          'type': 'string',
          'enum': [
            'full',
            'level_distortion',
            'time_domain',
            'frequency_response',
          ],
          'description':
              'Optional measurement block. Use a focused block after a broad '
              'request ran out of budget: level_distortion, time_domain or '
              'frequency_response. full is the default.',
        },
      },
      'required': ['request'],
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'audio_analysis_agent',
      );
      final request = _stringArg(args, 'request');
      final autonomous = args['autonomous'] == true;
      final channel = _stringArg(args, 'channel');
      final focus = _stringArg(args, 'focus');
      final Map<String, dynamic> result;
      if (provider == null) {
        result = <String, dynamic>{
          'error': 'Audio analysis is not available in this context.',
        };
      } else if (request == null) {
        result = <String, dynamic>{
          'error':
              'request is required. Describe the audio measurement the '
              'AudioAgent should perform.',
        };
      } else {
        // An audio analysis can run Bode sweeps and many measurement tools,
        // which legitimately take several minutes. Suspend the response
        // timeout for its duration; the service counts nested suspensions
        // such as an acquire_waveform delay.
        onLongRunningStart?.call();
        try {
          result = await provider(
            request: request,
            autonomous: autonomous,
            channel: channel,
            focus: focus,
          );
        } finally {
          onLongRunningEnd?.call();
        }
      }
      logger.logToolCall(
        input: {
          'requestCharacters': request?.length ?? 0,
          'autonomous': autonomous,
          if (channel != null) 'channel': channel,
          if (focus != null) 'focus': focus,
        },
        output: {
          if (result['ok'] != null) 'ok': result['ok'],
          if (result['error'] != null) 'error': result['error'],
          if (result['needsInput'] != null) 'needsInput': result['needsInput'],
          if (result['requestedAction'] != null)
            'requestedAction': result['requestedAction'],
          if (result['measurements'] is List)
            'measurementCount': (result['measurements'] as List).length,
        },
      );
      return result;
    },
  );
}

String? _stringArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
