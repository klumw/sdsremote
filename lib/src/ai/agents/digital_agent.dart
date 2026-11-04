import 'dart:async';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../cancellation.dart';
import '../tools/acquire_waveform_tool.dart';
import '../tools/calculator_tool.dart';
import '../tools/logic_level_reference_tool.dart';
import '../tools/math_tool.dart';
import '../tools/scpi_agent_tool.dart';
import '../tools/spectrum_summary_tool.dart';
import '../tools/waveform_analysis_tools.dart';
import '../tools/waveform_fault_profile_tool.dart';
import '../tools/waveform_fault_tool.dart';
import '../tools/waveform_summary_tool.dart';
import 'instrument_agent.dart';
import 'systemprompts.dart';

/// Digital circuit measurement specialist and sub-agent of the Waveform Agent.
///
/// The agent receives the current acquisition through injected providers, runs
/// the deterministic digital measurement and fault-analysis tools, and may use
/// the InstrumentAgent for live scope/generator changes when the Waveform
/// Agent granted autonomous permission. It returns one structured result
/// through `submit_digital_analysis`; the Waveform Agent presents it to the
/// user.
class DigitalAgent {
  static const String defaultModel = 'deepseek:deepseek-v4-flash';

  /// Enough budget for summary, features, spectrum, classification, logic
  /// reference, fault-profile read, fault analysis, an optional acquisition
  /// and the final submission.
  static const int defaultMaxToolCalls = 26;

  final WaveformSummaryProvider? _readWaveformSummary;
  final InstrumentAgent? _instrumentAgent;
  final bool _faultAnalysisAvailable;
  final bool _instrumentAvailable;
  final bool _acquireAvailable;
  late final List<Tool> _tools;
  late final Agent _agent;
  Map<String, dynamic>? _lastSubmission;
  final List<Map<String, dynamic>> _partialResults = <Map<String, dynamic>>[];
  CancellationToken? _activeCancelToken;
  bool _analysisCancelled = false;

  /// Tools registered with the agent, exposed for diagnostics and tests.
  List<String> get toolNames => _tools.map((tool) => tool.name).toList();

  DigitalAgent({
    String model = defaultModel,
    WaveformSummaryProvider? readWaveformSummary,
    SpectrumSummaryProvider? readSpectrumSummary,
    WaveformFeaturesProvider? readWaveformFeatures,
    WaveformClassificationProvider? classifyWaveform,
    WaveformFaultAnalysisProvider? analyzeWaveformFaults,
    WaveformFaultProfileProvider? manageFaultProfile,
    WaveformAcquisitionProvider? acquireWaveform,
    InstrumentAgent? instrumentAgent,
    int maxToolCalls = defaultMaxToolCalls,
  }) : _readWaveformSummary = readWaveformSummary,
       _instrumentAgent = instrumentAgent,
       _faultAnalysisAvailable = analyzeWaveformFaults != null,
       _instrumentAvailable = instrumentAgent != null,
       _acquireAvailable = acquireWaveform != null {
    final digitalTools = <Tool<Map<String, dynamic>>>[
      createWaveformSummaryTool(
        readSummary: readWaveformSummary,
        agentName: 'DigitalAgent',
      ),
      createSpectrumSummaryTool(
        readSummary: readSpectrumSummary,
        agentName: 'DigitalAgent',
      ),
      createGetWaveformFeaturesTool(
        readFeatures: readWaveformFeatures,
        agentName: 'DigitalAgent',
      ),
      createClassifyWaveformTool(
        classify: classifyWaveform,
        agentName: 'DigitalAgent',
      ),
      createLogicLevelReferenceTool(agentName: 'DigitalAgent'),
      createWaveformFaultAnalysisTool(
        analyze: analyzeWaveformFaults,
        agentName: 'DigitalAgent',
      ),
      createWaveformFaultProfileTool(
        manage: manageFaultProfile,
        agentName: 'DigitalAgent',
      ),
      createMathTool(agentName: 'DigitalAgent'),
      createCalculatorTool(agentName: 'DigitalAgent'),
    ];
    _tools = [
      for (final tool in digitalTools) _recordingTool(tool),
      _guardedTool(
        createAcquireWaveformTool(
          acquire: acquireWaveform,
          agentName: 'DigitalAgent',
        ),
      ),
      if (instrumentAgent != null)
        _guardedTool(
          createScpiAgentTool(instrumentAgent, agentName: 'DigitalAgent'),
        ),
      _guardedTool(_submissionTool()),
    ];
    _agent = Agent(
      model,
      displayName: 'DigitalAgent',
      maxToolCalls: maxToolCalls,
      tools: _tools,
    );
  }

  /// Runs one digital measurement request and returns the structured result.
  ///
  /// [autonomous] is true only after the Waveform Agent obtained the user's
  /// one-time permission for the digital task. It allows the agent to change
  /// scope/generator settings and acquire fresh waveforms as needed.
  Future<Map<String, dynamic>> analyze({
    required String request,
    bool autonomous = false,
    String? channel,
    String? focus,
    CancellationToken? cancelToken,
  }) async {
    _analysisCancelled = cancelToken?.isCancelled == true;
    if (_analysisCancelled) {
      return <String, dynamic>{
        'cancelled': true,
        'error': 'The digital analysis was cancelled.',
      };
    }
    final trimmed = request.trim();
    if (trimmed.isEmpty) {
      return <String, dynamic>{'error': 'The digital request is empty.'};
    }

    Map<String, dynamic>? summary;
    try {
      summary = _readWaveformSummary?.call();
    } on Object catch (error) {
      return <String, dynamic>{
        'error': 'The current acquisition could not be read ($error).',
      };
    }
    if (summary == null) {
      return <String, dynamic>{
        'error':
            'No usable waveform acquisition is available. Acquire a waveform '
            'first.',
      };
    }

    final requestedChannel = channel?.trim();
    final prompt = StringBuffer()
      ..writeln('DIGITAL REQUEST FROM THE WAVEFORM AGENT:')
      ..writeln(trimmed)
      ..writeln()
      ..writeln(
        'AUTONOMOUS_PERMISSION: '
        '${autonomous ? 'granted' : 'not granted'}',
      )
      ..writeln(
        'REQUESTED_CHANNEL: '
        '${requestedChannel == null || requestedChannel.isEmpty ? 'not specified' : requestedChannel}',
      )
      ..writeln(
        'FOCUS: ${focus?.trim().isNotEmpty == true ? focus!.trim() : 'full'}',
      )
      ..writeln()
      ..writeln('CURRENT ACQUISITION CONTEXT:')
      ..writeln(_contextSummary(summary))
      ..writeln(
        'Run all measurements needed for this request. If autonomous '
        'permission is granted, you may change the oscilloscope or signal '
        'generator through scpi_instrument_agent and acquire a fresh waveform. '
        'Call submit_digital_analysis exactly once with the structured '
        'result. Write the summary in the language of the request.',
      );

    _lastSubmission = null;
    _partialResults.clear();
    _activeCancelToken = cancelToken;
    final logger = AppLogger(agentName: 'DigitalAgent', toolName: 'analyze');
    logger.log(
      'Digital analysis started '
      '(autonomous=$autonomous, channel=${requestedChannel ?? 'auto'}, '
      'chars=${trimmed.length})',
    );

    String response;
    StreamSubscription<ChatResult<String>>? subscription;
    final done = Completer<void>();
    final chunks = <String>[];
    void cancelAnalysis() {
      _analysisCancelled = true;
      final current = subscription;
      if (current != null) {
        unawaited(current.cancel());
      }
      if (!done.isCompleted) {
        done.completeError(const _DigitalAnalysisCancelled());
      }
    }

    // One-time autonomous permission covers the scope and generator changes
    // this analysis needs, so the generator tools are enabled for its
    // duration. The regular keyword gate applies again afterwards.
    _instrumentAgent?.setAutonomousGeneratorAccess(autonomous);
    try {
      subscription = _agent
          .sendStream(
            prompt.toString(),
            history: [ChatMessage.system(digitalAgentSystemPrompt)],
          )
          .listen(
            (result) => chunks.add(result.output),
            onError: (Object error, StackTrace stackTrace) {
              if (!done.isCompleted) done.completeError(error, stackTrace);
            },
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            cancelOnError: true,
          );
      cancelToken?.addListener(cancelAnalysis);
      await done.future;
      response = chunks.join().trim();
    } on _DigitalAnalysisCancelled {
      logger.log('Digital analysis cancelled');
      return <String, dynamic>{
        'cancelled': true,
        'error': 'The digital analysis was cancelled.',
      };
    } on Object catch (error) {
      logger.error('Digital analysis failed: $error');
      return <String, dynamic>{
        'error': 'The DigitalAgent request failed ($error).',
      };
    } finally {
      cancelToken?.removeListener(cancelAnalysis);
      final current = subscription;
      if (current != null) unawaited(current.cancel());
      if (identical(_activeCancelToken, cancelToken)) {
        _activeCancelToken = null;
      }
      _instrumentAgent?.setAutonomousGeneratorAccess(false);
    }

    final submission = _lastSubmission;
    if (submission == null) {
      final partial = _partialResults.length > 12
          ? _partialResults.sublist(_partialResults.length - 12)
          : List<Map<String, dynamic>>.of(_partialResults);
      logger.error(
        'DigitalAgent did not submit a structured result '
        '(partial tool results=${_partialResults.length}).',
      );
      return <String, dynamic>{
        'ok': false,
        'error': 'The DigitalAgent did not submit a structured result.',
        if (response.isNotEmpty) 'detail': response,
        if (partial.isNotEmpty) 'partialResults': partial,
        'needsInput': partial.isEmpty
            ? 'The digital analysis could not be completed. Should I split it '
                  'into focused blocks?'
            : 'Some measurements completed. Should I continue with the '
                  'remaining blocks?',
        'limitations': const [
          'The DigitalAgent reached its measurement limit before submitting a '
              'structured result.',
        ],
      };
    }

    final measurementCount = submission['measurements'] is List
        ? (submission['measurements'] as List).length
        : 0;
    logger.log(
      'Digital analysis completed '
      '(measurements=$measurementCount, autonomous=$autonomous)',
    );
    return <String, dynamic>{
      'ok': submission['error'] == null,
      ...submission,
      if (response.isNotEmpty) 'response': response,
      'autonomous': autonomous,
      if (requestedChannel != null && requestedChannel.isNotEmpty)
        'requestedChannel': requestedChannel,
    };
  }

  String _contextSummary(Map<String, dynamic> summary) {
    final buffer = StringBuffer();
    final channels = summary['channels'];
    final channelNames = channels is Map
        ? channels.keys.map((key) => key.toString()).toList(growable: false)
        : const <String>[];
    buffer.writeln(
      'Acquisition available: true; channels: '
      '${channelNames.isEmpty ? 'unknown' : channelNames.join(', ')}',
    );
    final device = summary['device'];
    if (device is Map) {
      buffer
        ..writeln('Timebase: ${device['timebaseSecondsPerDiv'] ?? 'unknown'}')
        ..writeln(
          'Sample rate: ${device['sampleRatePerSecond'] ?? 'unknown'} Sa/s',
        )
        ..writeln(
          'Trigger delay: ${device['triggerDelaySeconds'] ?? 'unknown'} s',
        );
    }
    buffer
      ..writeln('Logic-level reference available: true')
      ..writeln('Fault analysis available: $_faultAnalysisAvailable')
      ..writeln('Instrument agent available: $_instrumentAvailable')
      ..writeln('Acquire waveform available: $_acquireAvailable');
    return buffer.toString();
  }

  Tool<Map<String, dynamic>> _recordingTool(Tool<Map<String, dynamic>> tool) {
    return Tool<Map<String, dynamic>>(
      name: tool.name,
      description: tool.description,
      inputSchema: tool.inputSchema,
      onCall: (args) async {
        if (_analysisCancelled) return _cancelledToolResult();
        final result = await tool.onCall(args);
        if (result is Map<String, dynamic>) {
          _partialResults.add({'tool': tool.name, 'result': result});
        }
        return result;
      },
    );
  }

  /// Blocks a tool call after the analysis has been cancelled.
  Tool<Map<String, dynamic>> _guardedTool(Tool<Map<String, dynamic>> tool) {
    return Tool<Map<String, dynamic>>(
      name: tool.name,
      description: tool.description,
      inputSchema: tool.inputSchema,
      onCall: (args) async {
        if (_analysisCancelled) return _cancelledToolResult();
        return tool.onCall(args);
      },
    );
  }

  Map<String, dynamic> _cancelledToolResult() => <String, dynamic>{
    'error': 'The digital analysis was cancelled.',
    'error_code': 'CANCELLED',
  };

  Tool<Map<String, dynamic>> _submissionTool() {
    return Tool<Map<String, dynamic>>(
      name: 'submit_digital_analysis',
      description:
          'Submits the final structured digital analysis to the Waveform '
          'Agent. Call it exactly once after all measurements are complete. '
          'Include one measurement entry per reported metric with its unit, '
          'channel and method. Do not dump raw tool output. If the request '
          'cannot be completed, set `error` or `needsInput` and explain the '
          'limitation. The summary must be in the language of the digital '
          'request.',
      inputSchema: _submissionSchema(),
      onCall: (args) async {
        _lastSubmission = Map<String, dynamic>.from(args);
        final measurements = args['measurements'];
        final warnings = args['warnings'];
        return <String, dynamic>{
          'accepted': true,
          'measurementCount': measurements is List ? measurements.length : 0,
          'warningCount': warnings is List ? warnings.length : 0,
        };
      },
    );
  }
}

Schema _submissionSchema() => Schema.fromMap({
  'type': 'object',
  'properties': {
    'summary': {
      'type': 'string',
      'description':
          'Concise result summary in the language of the request. Lead with '
          'the measured result; do not repeat the full tool output.',
    },
    'measurements': {
      'type': 'array',
      'description':
          'One entry per measured metric. Omit metrics that could not be '
          'measured and explain them in warnings instead.',
      'items': {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description':
                'Metric name, for example vilMaxVolts, vihMinVolts, '
                'volMaxVolts, vohMinVolts, riseTimeSeconds, dutyPercent, '
                'periodJitterSeconds, overshootPercent, glitchCount.',
          },
          'value': {'type': 'number', 'description': 'Measured numeric value.'},
          'unit': {
            'type': 'string',
            'description': 'Unit, for example V, s, %, Hz, dB.',
          },
          'channel': {
            'type': 'string',
            'description': 'Channel the value belongs to (ch1-ch4), if any.',
          },
          'method': {
            'type': 'string',
            'description':
                'Measurement method or tool, for example '
                'read_waveform_summary, get_waveform_features or '
                'analyze_waveform_faults.',
          },
          'notes': {
            'type': 'string',
            'description': 'Short caveat or measurement limitation.',
          },
        },
        'required': ['name', 'value'],
      },
    },
    'warnings': {
      'type': 'array',
      'items': {'type': 'string'},
      'description': 'Measurement warnings and limitations.',
    },
    'limitations': {
      'type': 'array',
      'items': {'type': 'string'},
      'description':
          'Known limits such as sample rate, bandwidth, record length, 8-bit '
          'ADC or probe loading.',
    },
    'toolsUsed': {
      'type': 'array',
      'items': {'type': 'string'},
      'description': 'Digital and instrument tools used for this result.',
    },
    'requestedAction': {
      'type': 'object',
      'description':
          'A change or extra step that requires the Waveform Agent or user. '
          'Use it when autonomous permission is not granted or the action '
          'needs a decision.',
      'properties': {
        'type': {
          'type': 'string',
          'enum': [
            'instrument_change',
            'generator_change',
            'acquire',
            'user_input',
          ],
        },
        'description': {'type': 'string'},
        'channel': {'type': 'string'},
        'parameter': {'type': 'string'},
        'value': {'type': 'string'},
        'unit': {'type': 'string'},
        'reason': {'type': 'string'},
      },
      'required': ['type', 'description'],
    },
    'needsInput': {
      'type': 'string',
      'description':
          'One specific question for the user when the measurement cannot '
          'continue without information.',
    },
    'error': {
      'type': 'string',
      'description':
          'Set when the request cannot be fulfilled at all. Explain why.',
    },
  },
  'required': ['summary'],
});

/// Thrown internally when the chat request cancels the digital analysis.
class _DigitalAnalysisCancelled implements Exception {
  const _DigitalAnalysisCancelled();
}
