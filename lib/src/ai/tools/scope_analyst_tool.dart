/// AI tool exposing the ScopeAnalystAgent sub-agent to the Waveform Agent.
///
/// The ScopeAnalystAgent performs the actual scope measurements and waveform
/// analysis; the Waveform Agent only delegates the request and presents the
/// returned structured JSON result.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';

/// Runs one scope measurement request through the ScopeAnalystAgent.
typedef ScopeAnalysisProvider =
    Future<Map<String, dynamic>> Function({
      required String request,
      bool reportConfirmed,
      bool autonomous,
      String? channel,
      String? focus,
    });

/// Registers `scope_analysis_agent` for the Waveform Agent.
Tool<Map<String, dynamic>> createScopeAnalysisAgentTool({
  ScopeAnalysisProvider? analyze,
  void Function()? onLongRunningStart,
  void Function()? onLongRunningEnd,
  String agentName = 'unknown',
}) {
  final provider = analyze;
  return Tool<Map<String, dynamic>>(
    name: 'scope_analysis_agent',
    description:
        'Delegates a scope measurement and waveform analysis request to the '
        'ScopeAnalystAgent sub-agent. Use it for every value read from the '
        'oscilloscope: time-domain measurements (Vpp, RMS, mean, frequency, '
        'duty cycle, rise/fall time, overshoot), fresh and delayed '
        'acquisitions, FFT/spectrum analysis (fundamental, THD, THD+N, SNR, '
        'SINAD, ENOB, SFDR, noise floor, harmonic and interference peaks), '
        'waveform classification and comparison, waveform features, reference '
        'waveform generation, waveform history, deterministic fault analysis, '
        'the fault-analysis profile store, the PDF measurement report, and '
        'derived calculations with the math and calculator tools. The agent '
        'also has the current date/time tool and can read the application log. '
        'With `autonomous: true` the agent may also change scope settings '
        'through the InstrumentAgent; set it only after the user explicitly '
        'approved the exact change. Without it the agent is read-only and '
        'returns a `requestedAction` when a change is needed. '
        'Do not use it for a logic-level or input-suitability check or for a '
        'measurement at several explicit frequencies; those go to '
        'digital_analysis_agent, planned with digital.frequency_series when '
        'the generator is connected. '
        'The result is JSON and contains `summary`, `measurements` '
        '(each with `name`, `formattedValue`, optional `value`, `unit`, '
        '`channel`, `method` and `notes`), `warnings`, `limitations`, '
        '`toolsUsed`, and `needsInput`, `error`, `partialResults` or `report` '
        'when applicable. Present `summary` and every `formattedValue` '
        'faithfully in the user\'s language; never invent or recalculate them. '
        'If `needsInput` is present, relay it to the user and call the tool '
        'again after the answer. If the result contains `error`, relay it and '
        'do not invent a measurement. Set `reportConfirmed: true` only after '
        'the user explicitly confirmed that a PDF report should be created. '
        'Call it at most twice per user request.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'request': {
          'type': 'string',
          'description':
              'The scope measurement or waveform analysis request in natural '
              'language. Include the quantity, channel(s), timing, reference '
              'values and any known signal conditions.',
        },
        'reportConfirmed': {
          'type': 'boolean',
          'description':
              'True only after the user explicitly confirmed that a PDF '
              'report should be created for the current acquisition. When '
              'false or omitted, the ScopeAnalystAgent must not create a '
              'report.',
        },
        'autonomous': {
          'type': 'boolean',
          'description':
              'True only after the user explicitly approved the exact scope '
              'setting change. It allows the ScopeAnalystAgent to apply the '
              'change through its InstrumentAgent and continue the '
              'measurement. When false or omitted, the agent is read-only and '
              'returns a requestedAction for a needed change.',
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
            'measurement',
            'spectrum',
            'signal_analysis',
            'fault_analysis',
            'report',
          ],
          'description':
              'Measurement block. Set measurement for a direct readout (Vpp, '
              'RMS, mean, frequency, duty cycle, rise/fall time, overshoot), '
              'spectrum for FFT/THD/noise questions, signal_analysis for '
              'classification/comparison/features, fault_analysis for '
              'explicit fault diagnostics, and report for PDF creation. A '
              'focused block registers only the required tools and is much '
              'faster. Use full only for mixed or complex requests.',
        },
      },
      'required': ['request'],
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'scope_analysis_agent',
      );
      final request = _stringArg(args, 'request');
      final reportConfirmed = args['reportConfirmed'] == true;
      final autonomous = args['autonomous'] == true;
      final channel = _stringArg(args, 'channel');
      final focus = _stringArg(args, 'focus');
      final Map<String, dynamic> result;
      if (provider == null) {
        result = <String, dynamic>{
          'error': 'Scope analysis is not available in this context.',
        };
      } else if (request == null) {
        result = <String, dynamic>{
          'error':
              'request is required. Describe the scope measurement the '
              'ScopeAnalystAgent should perform.',
        };
      } else {
        // A fresh acquisition with a delay, a PDF report dialog and a fault
        // analysis can legitimately take longer than the normal response
        // window. Suspend the response timeout for the whole sub-agent run.
        onLongRunningStart?.call();
        try {
          result = await provider(
            request: request,
            reportConfirmed: reportConfirmed,
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
          'reportConfirmed': reportConfirmed,
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
          if (result['report'] != null) 'report': result['report'],
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
