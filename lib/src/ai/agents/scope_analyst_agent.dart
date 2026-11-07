import 'dart:async';
import 'dart:convert';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../cancellation.dart';
import '../tools/acquire_waveform_tool.dart';
import '../tools/calculator_tool.dart';
import '../tools/date_time_tool.dart';
import '../tools/log_tool.dart';
import '../tools/math_tool.dart';
import '../tools/spectrum_summary_tool.dart';
import '../tools/waveform_analysis_tools.dart';
import '../tools/waveform_fault_profile_tool.dart';
import '../tools/waveform_fault_tool.dart';
import '../tools/waveform_history_tool.dart';
import '../tools/waveform_report_tool.dart';
import '../tools/waveform_summary_tool.dart';
import 'systemprompts.dart';

/// Scope measurement specialist and sub-agent of the Waveform Agent.
///
/// The agent reads the current acquisition or acquires a fresh one through the
/// injected providers, runs the deterministic waveform, spectrum, classification
/// and fault-analysis tools, performs derived calculations with the math and
/// calculator tools, and returns one structured JSON result through
/// `submit_scope_analysis`. The Waveform Agent presents that result to the user.
///
/// The agent keeps no conversation between calls: every request starts with a
/// fresh system prompt. It does not access the oscilloscope through SCPI and
/// cannot change instrument settings; live queries and instrument changes stay
/// with the Waveform Agent's InstrumentAgent.
class ScopeAnalystAgent {
  static const String defaultModel = 'deepseek:deepseek-v4-flash';

  /// Enough budget for summary, acquisition, spectrum, classification,
  /// features, fault-profile read, fault analysis, calculations and the final
  /// submission.
  static const int defaultMaxToolCalls = 24;

  final String _model;
  final int _maxToolCalls;
  final WaveformSummaryProvider? _readWaveformSummary;
  late final List<Tool> _tools;
  Map<String, dynamic>? _lastSubmission;
  Map<String, dynamic>? _lastReportResult;
  final List<Map<String, dynamic>> _partialResults = <Map<String, dynamic>>[];
  CancellationToken? _activeCancelToken;
  void Function()? _onSubmissionReceived;
  bool _analysisCancelled = false;
  bool _reportConfirmed = false;

  /// Tools registered with the agent, exposed for diagnostics and tests.
  List<String> get toolNames => _tools.map((tool) => tool.name).toList();

  /// Tools available for one focus, exposed for diagnostics and tests.
  List<String> toolNamesForFocus(String? focus) {
    final names = _toolNamesForFocus(focus);
    return [
      for (final tool in _tools)
        if (names.contains(tool.name)) tool.name,
    ];
  }

  ScopeAnalystAgent({
    String model = defaultModel,
    WaveformSummaryProvider? readWaveformSummary,
    SpectrumSummaryProvider? readSpectrumSummary,
    WaveformAcquisitionProvider? acquireWaveform,
    WaveformHistoryProvider? readWaveformHistory,
    WaveformClassificationProvider? classifyWaveform,
    WaveformReferenceComparisonProvider? compareWaveformToReferences,
    WaveformFeaturesProvider? readWaveformFeatures,
    WaveformPairComparisonProvider? compareWaveforms,
    ReferenceGenerationProvider? generateReferenceWaveform,
    WaveformFaultAnalysisProvider? analyzeWaveformFaults,
    WaveformFaultProfileProvider? manageFaultProfile,
    WaveformReportProvider? createWaveformReport,
    LogReader? readLog,
    int maxToolCalls = defaultMaxToolCalls,
  }) : _model = model,
       _maxToolCalls = maxToolCalls,
       _readWaveformSummary = readWaveformSummary {
    final reportTool = createWaveformReportTool(
      createReport: createWaveformReport,
      agentName: 'ScopeAnalystAgent',
    );
    final scopeTools = <Tool<Map<String, dynamic>>>[
      createWaveformSummaryTool(
        readSummary: readWaveformSummary,
        agentName: 'ScopeAnalystAgent',
      ),
      createSpectrumSummaryTool(
        readSummary: readSpectrumSummary,
        agentName: 'ScopeAnalystAgent',
      ),
      createAcquireWaveformTool(
        acquire: acquireWaveform,
        agentName: 'ScopeAnalystAgent',
      ),
      createWaveformHistoryTool(
        readHistory: readWaveformHistory,
        agentName: 'ScopeAnalystAgent',
      ),
      _capturingReportTool(reportTool),
      createClassifyWaveformTool(
        classify: classifyWaveform,
        agentName: 'ScopeAnalystAgent',
      ),
      createCompareWaveformToReferencesTool(
        compare: compareWaveformToReferences,
        agentName: 'ScopeAnalystAgent',
      ),
      createCompareWaveformsTool(
        compare: compareWaveforms,
        agentName: 'ScopeAnalystAgent',
      ),
      createGetWaveformFeaturesTool(
        readFeatures: readWaveformFeatures,
        agentName: 'ScopeAnalystAgent',
      ),
      createGenerateReferenceWaveformTool(
        generate: generateReferenceWaveform,
        agentName: 'ScopeAnalystAgent',
      ),
      createWaveformFaultAnalysisTool(
        analyze: analyzeWaveformFaults,
        agentName: 'ScopeAnalystAgent',
      ),
      createWaveformFaultProfileTool(
        manage: manageFaultProfile,
        agentName: 'ScopeAnalystAgent',
      ),
      createMathTool(agentName: 'ScopeAnalystAgent'),
      createCalculatorTool(agentName: 'ScopeAnalystAgent'),
      createDateTimeTool(agentName: 'ScopeAnalystAgent'),
      createLogFileTool(
        readLog: readLog,
        agentName: 'ScopeAnalystAgent',
        description:
            'Return the most recent lines of the SDS-Remote application log '
            '(sds.log in the application temp directory). Call this when a '
            'waveform acquisition, a spectrum calculation or an analysis tool '
            'fails and the log can explain why: search for the failing '
            'command or error with "contains", quote the matching lines and '
            'report the limitation. By default only warning and error lines '
            'are returned; set errors_only to false to include all recent '
            'lines for context. Never invent a log entry.',
      ),
    ];
    _tools = [
      for (final tool in scopeTools) _recordingTool(tool),
      _guardedTool(_submissionTool()),
    ];
  }

  /// Builds a fresh agent with only the tools needed for [focus].
  ///
  /// A simple measurement must not carry the schemas of the classification,
  /// fault-analysis and math tools: every tool schema is sent to the model on
  /// every turn, and the large schemas dominate the latency of simple
  /// requests. The full set is used for `full` or an unknown focus.
  Agent _buildAgent(String? focus) {
    final names = _toolNamesForFocus(focus);
    return Agent(
      _model,
      displayName: 'ScopeAnalystAgent',
      maxToolCalls: _maxToolCalls,
      tools: [
        for (final tool in _tools)
          if (names.contains(tool.name)) tool,
      ],
    );
  }

  Set<String> _toolNamesForFocus(String? focus) {
    switch (focus) {
      case 'measurement':
        return const {
          'read_waveform_summary',
          'acquire_waveform',
          'submit_scope_analysis',
        };
      case 'spectrum':
        return const {
          'read_waveform_summary',
          'read_spectrum_summary',
          'math_tool',
          'calculator_tool',
          'submit_scope_analysis',
        };
      case 'signal_analysis':
        return const {
          'read_waveform_summary',
          'classify_waveform',
          'compare_waveform_to_references',
          'compare_waveforms',
          'get_waveform_features',
          'generate_reference_waveform',
          'math_tool',
          'calculator_tool',
          'submit_scope_analysis',
        };
      case 'fault_analysis':
        return const {
          'read_waveform_summary',
          'read_spectrum_summary',
          'analyze_waveform_faults',
          'manage_fault_analysis_profile',
          'math_tool',
          'calculator_tool',
          'submit_scope_analysis',
        };
      case 'report':
        return const {
          'read_waveform_summary',
          'read_spectrum_summary',
          'create_waveform_report',
          'submit_scope_analysis',
        };
      case 'full':
      default:
        return {for (final tool in _tools) tool.name};
    }
  }

  /// Compact context from the current acquisition, read before the model
  /// starts. This removes one model/tool round-trip for simple measurements.
  String _contextSummary() {
    try {
      final summary = _readWaveformSummary?.call();
      if (summary == null) {
        return 'No acquisition is currently available.';
      }
      return jsonEncode(summary);
    } on Object catch (error) {
      return 'The current acquisition could not be read ($error).';
    }
  }

  /// Runs one scope measurement request and returns the structured JSON
  /// result.
  ///
  /// [reportConfirmed] is true only after the Waveform Agent obtained the
  /// user's explicit confirmation for a PDF report. The agent then may call
  /// `create_waveform_report`; otherwise it must not.
  Future<Map<String, dynamic>> analyze({
    required String request,
    bool reportConfirmed = false,
    String? channel,
    String? focus,
    CancellationToken? cancelToken,
  }) async {
    _analysisCancelled = cancelToken?.isCancelled == true;
    if (_analysisCancelled) {
      return <String, dynamic>{
        'cancelled': true,
        'error': 'The scope analysis was cancelled.',
      };
    }
    final trimmed = request.trim();
    if (trimmed.isEmpty) {
      return <String, dynamic>{'error': 'The scope analysis request is empty.'};
    }

    final requestedChannel = channel?.trim();
    final requestedFocus = focus?.trim();
    final prompt = StringBuffer()
      ..writeln('SCOPE MEASUREMENT REQUEST FROM THE WAVEFORM AGENT:')
      ..writeln(trimmed)
      ..writeln()
      ..writeln('REPORT_CONFIRMED: ${reportConfirmed ? 'true' : 'false'}')
      ..writeln(
        'REQUESTED_CHANNEL: '
        '${requestedChannel == null || requestedChannel.isEmpty ? 'not specified' : requestedChannel}',
      )
      ..writeln(
        'FOCUS: ${requestedFocus == null || requestedFocus.isEmpty ? 'full' : requestedFocus}',
      )
      ..writeln()
      ..writeln('CURRENT ACQUISITION CONTEXT (read before this request):')
      ..writeln(_contextSummary())
      ..writeln()
      ..writeln(
        'Use the context values directly when they answer the request. Call '
        'read_waveform_summary only if a needed value is missing. If the '
        'request asks for a fresh or delayed acquisition, call '
        'acquire_waveform and use its returned measurements. Use only the '
        'provided tools. Call submit_scope_analysis exactly once with the '
        'structured JSON result. Put every measured value into a measurement '
        'entry and return it in human-readable form with its unit in '
        'formattedValue. Write the summary in the language of the request.',
      );

    _lastSubmission = null;
    _lastReportResult = null;
    _partialResults.clear();
    _reportConfirmed = reportConfirmed;
    _activeCancelToken = cancelToken;
    final logger = AppLogger(
      agentName: 'ScopeAnalystAgent',
      toolName: 'analyze',
    );
    logger.log(
      'Scope analysis started '
      '(channel=${requestedChannel ?? 'auto'}, '
      'focus=${requestedFocus ?? 'full'}, reportConfirmed=$reportConfirmed, '
      'chars=${trimmed.length})',
    );

    final agent = _buildAgent(requestedFocus);
    String response = '';
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
        done.completeError(const _ScopeAnalysisCancelled());
      }
    }

    // Stop the model stream as soon as the structured result has arrived.
    // Continuing after the submission would cost one more full model turn
    // that cannot change the result.
    _onSubmissionReceived = () {
      if (!done.isCompleted) done.complete();
    };

    try {
      subscription = agent
          .sendStream(
            prompt.toString(),
            history: [ChatMessage.system(scopeAnalystSystemPrompt)],
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
    } on _ScopeAnalysisCancelled {
      logger.log('Scope analysis cancelled');
      return <String, dynamic>{
        'cancelled': true,
        'error': 'The scope analysis was cancelled.',
      };
    } on Object catch (error) {
      if (_lastSubmission != null) {
        // The submission arrived and the model stream was stopped early; the
        // resulting cancellation error is expected and must not discard the
        // structured result.
        logger.log('Scope analysis submission received; stream stopped early');
      } else {
        logger.error('Scope analysis failed: $error');
        final partial = _partialResults.length > 12
            ? _partialResults.sublist(_partialResults.length - 12)
            : List<Map<String, dynamic>>.of(_partialResults);
        if (partial.isEmpty) {
          return <String, dynamic>{
            'error': 'The ScopeAnalystAgent request failed ($error).',
          };
        }
        return <String, dynamic>{
          'ok': false,
          'error':
              'The ScopeAnalystAgent could not encode its structured result '
              '($error).',
          'partialResults': partial,
          'limitations': const [
            'The structured submission failed; the values below come from the '
                'completed tool calls and were not re-measured.',
          ],
          'needsInput':
              'Present the completed measurements from partialResults and ask '
              'whether the remaining analysis should be continued.',
        };
      }
    } finally {
      _onSubmissionReceived = null;
      cancelToken?.removeListener(cancelAnalysis);
      final current = subscription;
      if (current != null) unawaited(current.cancel());
      if (identical(_activeCancelToken, cancelToken)) {
        _activeCancelToken = null;
      }
    }

    final submission = _lastSubmission;
    if (submission == null) {
      final partial = _partialResults.length > 12
          ? _partialResults.sublist(_partialResults.length - 12)
          : List<Map<String, dynamic>>.of(_partialResults);
      logger.error(
        'ScopeAnalystAgent did not submit a structured result '
        '(partial tool results=${_partialResults.length}).',
      );
      return <String, dynamic>{
        'ok': false,
        'error': 'The ScopeAnalystAgent did not submit a structured result.',
        if (response.isNotEmpty) 'detail': response,
        if (partial.isNotEmpty) 'partialResults': partial,
        'needsInput': partial.isEmpty
            ? 'The scope analysis could not be completed. Should I split it '
                  'into focused blocks?'
            : 'Some measurements completed. Should I continue with the '
                  'remaining blocks?',
        'limitations': const [
          'The ScopeAnalystAgent reached its measurement limit before '
              'submitting a structured result.',
        ],
      };
    }

    final measurementCount = submission['measurements'] is List
        ? (submission['measurements'] as List).length
        : 0;
    logger.log(
      'Scope analysis completed '
      '(measurements=$measurementCount, reportConfirmed=$reportConfirmed)',
    );
    return <String, dynamic>{
      'ok': submission['error'] == null,
      ...submission,
      if (response.isNotEmpty) 'response': response,
      if (_lastReportResult != null) 'report': _lastReportResult,
      'reportConfirmed': reportConfirmed,
      if (requestedChannel != null && requestedChannel.isNotEmpty)
        'requestedChannel': requestedChannel,
    };
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

  /// Captures the report result so the Waveform Agent can verify that a PDF
  /// report was actually saved.
  Tool<Map<String, dynamic>> _capturingReportTool(
    Tool<Map<String, dynamic>> tool,
  ) {
    return Tool<Map<String, dynamic>>(
      name: tool.name,
      description: tool.description,
      inputSchema: tool.inputSchema,
      onCall: (args) async {
        if (!_reportConfirmed) {
          return <String, dynamic>{
            'error':
                'A PDF report requires the user\'s explicit confirmation. '
                'Return needsInput asking whether a report should be created.',
          };
        }
        final result = await tool.onCall(args);
        if (result is Map<String, dynamic>) {
          _lastReportResult = Map<String, dynamic>.from(result);
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
    'error': 'The scope analysis was cancelled.',
    'error_code': 'CANCELLED',
  };

  Tool<Map<String, dynamic>> _submissionTool() {
    return Tool<Map<String, dynamic>>(
      name: 'submit_scope_analysis',
      description:
          'Submits the final structured JSON result to the Waveform Agent. '
          'Call it exactly once after all measurements are complete. Include '
          'one measurement entry per reported metric; put the human-readable '
          'value with its unit into formattedValue (for example "1.003 kHz", '
          '"2.45 Vpp" or "45.6 ns"). Use only values returned by the tools. '
          'Report only the quantities the delegation request asks for; if it '
          'asks for one value, do not add other measurements or device '
          'parameters. Do not dump raw tool output. Keep every string short '
          'and free of quotation marks, apostrophes and line breaks so the '
          'JSON encoding stays valid. If the request cannot be completed, '
          'set `error` or `needsInput` and explain the limitation. The '
          'summary must be in the language of the request.',
      inputSchema: _submissionSchema(),
      onCall: (args) async {
        _lastSubmission = Map<String, dynamic>.from(args);
        final measurements = args['measurements'];
        final warnings = args['warnings'];
        _onSubmissionReceived?.call();
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
          'the measured result; include only the measurements the delegation '
          'request asks for and do not repeat the full tool output. Use '
          'human-readable values with units.',
    },
    'measurements': {
      'type': 'array',
      'description':
          'One entry per measured metric. Omit metrics that could not be '
          'measured and explain them in warnings or limitations instead.',
      'items': {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description':
                'Metric name, for example vppVolts, rmsVolts, frequencyHz, '
                'dutyPercent, riseTimeSeconds, thdPercent or snrDb.',
          },
          'formattedValue': {
            'type': 'string',
            'description':
                'Human-readable value with its unit, exactly as the Waveform '
                'Agent should quote it. Examples: "1.003 kHz", "2.45 Vpp", '
                '"12.3 %", "45.6 ns", "-3.2 dB".',
          },
          'value': {
            'type': 'number',
            'description': 'Optional raw numeric value of the measurement.',
          },
          'unit': {
            'type': 'string',
            'description':
                'Unit, for example V, Vpp, Vrms, Hz, s, %, dB, dBFS.',
          },
          'channel': {
            'type': 'string',
            'description': 'Channel the value belongs to (ch1-ch4), if any.',
          },
          'method': {
            'type': 'string',
            'description':
                'Measurement method or tool, for example '
                'read_waveform_summary, acquire_waveform, get_waveform_features '
                'or analyze_waveform_faults.',
          },
          'notes': {
            'type': 'string',
            'description': 'Short caveat or measurement limitation.',
          },
        },
        'required': ['name', 'formattedValue'],
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
          'ADC, FFT resolution or probe loading.',
    },
    'toolsUsed': {
      'type': 'array',
      'items': {'type': 'string'},
      'description':
          'Scope measurement and analysis tools used for this result.',
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

/// Thrown internally when the chat request cancels the scope analysis.
class _ScopeAnalysisCancelled implements Exception {
  const _ScopeAnalysisCancelled();
}
