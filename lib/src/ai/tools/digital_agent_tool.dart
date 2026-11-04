/// AI tool exposing the DigitalAgent sub-agent to the Waveform Agent.
///
/// The DigitalAgent performs digital circuit measurements and signal-integrity
/// analysis; the Waveform Agent only delegates the request and presents the
/// returned structured result.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';

/// Runs one digital measurement request through the DigitalAgent.
typedef DigitalAnalysisProvider =
    Future<Map<String, dynamic>> Function({
      required String request,
      bool autonomous,
      String? channel,
      String? focus,
    });

/// Registers `digital_analysis_agent` for the Waveform Agent.
Tool<Map<String, dynamic>> createDigitalAnalysisAgentTool({
  DigitalAnalysisProvider? analyze,
  void Function()? onLongRunningStart,
  void Function()? onLongRunningEnd,
  String agentName = 'unknown',
}) {
  final provider = analyze;
  return Tool<Map<String, dynamic>>(
    name: 'digital_analysis_agent',
    description:
        'Delegates digital circuit measurement and signal-integrity analysis '
        'to the DigitalAgent sub-agent. Use it for logic levels and '
        'thresholds (VIL/VIH/VOL/VOH), logic families, edge/rise/fall times, '
        'duty and timing, clock jitter, overshoot, ringing, reflections, '
        'glitches, protocol signal integrity and digital fault analysis. The '
        'DigitalAgent can read the current acquisition, query the logic-level '
        'reference table, run deterministic fault diagnostics, change scope or '
        'generator settings when autonomous permission is granted, and acquire '
        'a fresh waveform. Before the first call, ask the user once whether '
        'the digital measurements may run autonomously, including the '
        'necessary oscilloscope/generator changes. Pass `autonomous: true` '
        'only after that permission. The result contains `summary`, '
        '`measurements`, `warnings`, `limitations`, `toolsUsed`, '
        '`requestedAction` and `needsInput`. Present the summary and '
        'measurement values faithfully in the user\'s language; never invent '
        'or recalculate them. If `requestedAction` or `needsInput` is present, '
        'relay it to the user and call the tool again after the answer. If the '
        'result contains `error`, relay it and do not invent a measurement. '
        'Call it at most twice per user request.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'request': {
          'type': 'string',
          'description':
              'The digital measurement or analysis request in natural '
              'language. Include the signal type, logic standard or family, '
              'supply voltage, channel(s), threshold direction (input or '
              'output) and any known signal conditions.',
        },
        'autonomous': {
          'type': 'boolean',
          'description':
              'True only after the user granted the one-time permission for '
              'autonomous digital measurements, including necessary '
              'scope/generator changes.',
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
            'logic_levels',
            'timing',
            'signal_integrity',
            'fault_analysis',
          ],
          'description':
              'Optional measurement block. Use a focused block after a broad '
              'request ran out of budget.',
        },
      },
      'required': ['request'],
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'digital_analysis_agent',
      );
      final request = _stringArg(args, 'request');
      final autonomous = args['autonomous'] == true;
      final channel = _stringArg(args, 'channel');
      final focus = _stringArg(args, 'focus');
      final Map<String, dynamic> result;
      if (provider == null) {
        result = <String, dynamic>{
          'error': 'Digital analysis is not available in this context.',
        };
      } else if (request == null) {
        result = <String, dynamic>{
          'error':
              'request is required. Describe the digital measurement the '
              'DigitalAgent should perform.',
        };
      } else {
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
          'channel': ?channel,
          'focus': ?focus,
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
