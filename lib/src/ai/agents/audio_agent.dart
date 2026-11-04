import 'dart:async';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../cancellation.dart';
import '../tools/acquire_waveform_tool.dart';
import '../tools/audio/audio_tools.dart';
import '../tools/scpi_agent_tool.dart';
import 'instrument_agent.dart';
import 'systemprompts.dart';

/// Audio measurement specialist and sub-agent of the Waveform Agent.
///
/// The agent receives the current acquisition through injected providers,
/// runs the deterministic audio tools, and may use the InstrumentAgent for
/// live scope/generator changes when the Waveform Agent granted autonomous
/// permission. It returns one structured result through
/// `submit_audio_analysis`; the Waveform Agent presents it to the user.
///
/// The agent keeps no conversation between calls: every request starts with a
/// fresh system prompt. It caches one Bode sweep per user request so several
/// sweep tools share a single hardware run; the Waveform Agent clears the
/// cache at the start of every request.
class AudioAgent {
  static const String defaultModel = 'deepseek:deepseek-v4-flash';

  /// Enough budget for several audio tools, instrument queries, an optional
  /// acquisition and the final submission.
  static const int defaultMaxToolCalls = 22;

  final AudioAnalysisContextProvider _contextProvider;
  final AudioSweepProvider? _sweepProvider;
  final InstrumentAgent? _instrumentAgent;
  final bool _sweepAvailable;
  final bool _instrumentAvailable;
  final bool _acquireAvailable;
  late final List<Tool> _tools;
  late final Agent _agent;
  Map<String, dynamic>? _lastSubmission;
  final List<Map<String, dynamic>> _partialResults = <Map<String, dynamic>>[];
  AudioSweepData? _cachedSweep;
  String? _cachedSweepKey;
  CancellationToken? _activeCancelToken;
  bool _analysisCancelled = false;

  /// Tools registered with the agent, exposed for diagnostics and tests.
  List<String> get toolNames => _tools.map((tool) => tool.name).toList();

  AudioAgent({
    String model = defaultModel,
    required AudioAnalysisContextProvider contextProvider,
    AudioSweepProvider? sweepProvider,
    WaveformAcquisitionProvider? acquireWaveform,
    InstrumentAgent? instrumentAgent,
    int maxToolCalls = defaultMaxToolCalls,
  }) : _contextProvider = contextProvider,
       _sweepProvider = sweepProvider,
       _instrumentAgent = instrumentAgent,
       _sweepAvailable = sweepProvider != null,
       _instrumentAvailable = instrumentAgent != null,
       _acquireAvailable = acquireWaveform != null {
    final audioTools = createAudioTools(
      context: contextProvider,
      sweep: _sweepProvider == null ? null : _cachedSweepProvider,
      agentName: 'AudioAgent',
    );
    _tools = [
      for (final tool in audioTools) _recordingTool(tool),
      _guardedTool(
        createAcquireWaveformTool(
          acquire: acquireWaveform,
          agentName: 'AudioAgent',
        ),
      ),
      if (instrumentAgent != null)
        _guardedTool(
          createScpiAgentTool(instrumentAgent, agentName: 'AudioAgent'),
        ),
      _guardedTool(_submissionTool()),
    ];
    _agent = Agent(
      model,
      displayName: 'AudioAgent',
      maxToolCalls: maxToolCalls,
      tools: _tools,
    );
  }

  /// Runs one audio request and returns the structured submission.
  ///
  /// [autonomous] is true only after the Waveform Agent obtained the user's
  /// one-time permission for the audio task. It allows the agent to change
  /// scope/generator settings and run sweeps as needed.
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
        'error': 'The audio analysis was cancelled.',
      };
    }
    final trimmed = request.trim();
    if (trimmed.isEmpty) {
      return <String, dynamic>{'error': 'The audio request is empty.'};
    }

    final context = _contextProvider();
    if (context == null || context.availableChannels.isEmpty) {
      return <String, dynamic>{
        'error':
            'No usable audio acquisition is available. Acquire a waveform '
            'first.',
      };
    }

    final requestedChannel = channel?.trim();
    final prompt = StringBuffer()
      ..writeln('AUDIO REQUEST FROM THE WAVEFORM AGENT:')
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
      ..writeln(_contextSummary(context))
      ..writeln(
        'Run all measurements needed for this request. If autonomous '
        'permission is granted, you may change the oscilloscope or signal '
        'generator through scpi_instrument_agent and run a Bode sweep when '
        'the measurement requires it. Call acquire_waveform once after a '
        'change. Call submit_audio_analysis exactly once with the structured '
        'result. Write the summary in the language of the request.',
      );

    _lastSubmission = null;
    _partialResults.clear();
    _activeCancelToken = cancelToken;
    final logger = AppLogger(agentName: 'AudioAgent', toolName: 'analyze');
    logger.log(
      'Audio analysis started '
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
        done.completeError(const _AudioAnalysisCancelled());
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
            history: [ChatMessage.system(audioAgentSystemPrompt)],
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
    } on _AudioAnalysisCancelled {
      logger.log('Audio analysis cancelled');
      return <String, dynamic>{
        'cancelled': true,
        'error': 'The audio analysis was cancelled.',
      };
    } on Object catch (error) {
      logger.error('Audio analysis failed: $error');
      return <String, dynamic>{
        'error': 'The AudioAgent request failed ($error).',
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
        'AudioAgent did not submit a structured result '
        '(partial tool results=${_partialResults.length}).',
      );
      return <String, dynamic>{
        'ok': false,
        'error': 'The AudioAgent did not submit a structured result.',
        if (response.isNotEmpty) 'detail': response,
        if (partial.isNotEmpty) 'partialResults': partial,
        'needsInput': partial.isEmpty
            ? 'The audio analysis could not be completed. Should I split it '
                  'into focused blocks?'
            : 'Some measurements completed. Should I continue with the '
                  'remaining blocks?',
        'limitations': const [
          'The AudioAgent reached its measurement limit before submitting a '
              'structured result.',
        ],
      };
    }

    final measurementCount = submission['measurements'] is List
        ? (submission['measurements'] as List).length
        : 0;
    logger.log(
      'Audio analysis completed '
      '(measurements=$measurementCount, autonomous=$autonomous)',
    );
    return <String, dynamic>{
      'ok': submission['error'] == null,
      ...submission,
      if (response.isNotEmpty) 'response': response,
      'autonomous': autonomous,
      'availableChannels': context.availableChannels,
      if (requestedChannel != null && requestedChannel.isNotEmpty)
        'requestedChannel': requestedChannel,
    };
  }

  /// Clears the sweep cache for a new user request.
  ///
  /// The Waveform Agent calls this once per request so all audio sub-agent
  /// calls within that request can share one Bode sweep, while a later
  /// request never reuses stale data.
  void clearSweepCache() {
    _cachedSweep = null;
    _cachedSweepKey = null;
  }

  /// Returns the sweep provider with a one-analysis cache.
  ///
  /// Phase is always measured so the gain, phase, group-delay and bandwidth
  /// tools can share one sweep when they use the same range and point count.
  /// The cache is cleared at the start of every user request.
  Future<AudioSweepData?> _cachedSweepProvider(
    AudioSweepRequest request,
  ) async {
    final provider = _sweepProvider;
    if (provider == null) return null;
    final cancelToken = _activeCancelToken;
    if (cancelToken?.isCancelled == true) {
      throw const AudioSweepException(
        'The Bode sweep was cancelled.',
        code: 'SWEEP_CANCELLED',
      );
    }
    final points = request.pointCount.clamp(2, 50).toInt();
    final effective = AudioSweepRequest(
      startFrequencyHz: request.startFrequencyHz,
      stopFrequencyHz: request.stopFrequencyHz,
      pointCount: points,
      measurePhase: true,
      cancelToken: cancelToken,
    );
    final key =
        '${effective.startFrequencyHz}|${effective.stopFrequencyHz}|'
        '$points';
    final cached = _cachedSweep;
    if (cached != null && _cachedSweepKey == key) return cached;
    final data = await provider(effective);
    if (data != null) {
      _cachedSweep = data;
      _cachedSweepKey = key;
    }
    return data;
  }

  String _contextSummary(AudioAnalysisContext context) {
    final buffer = StringBuffer()
      ..writeln('Device: ${context.deviceName ?? 'unknown'}')
      ..writeln('ADC bits: ${context.adcBits}');
    for (final id in context.availableChannels) {
      final data = context.channels[id];
      if (data == null) continue;
      buffer.writeln(
        '$id: ${data.sampleCount} samples, '
        '${data.sampleRateHz.toStringAsFixed(1)} Sa/s, '
        '${data.durationSeconds.toStringAsFixed(6)} s, '
        'full scale ${data.fullScaleVolts.toStringAsFixed(6)} V',
      );
    }
    buffer
      ..writeln(
        'Sweep provider registered: $_sweepAvailable'
        '${_sweepAvailable ? ' (a sweep also needs a connected signal '
                  'generator and enabled CH1/CH2 traces)' : ''}',
      )
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
    'error': 'The audio analysis was cancelled.',
    'error_code': 'CANCELLED',
  };

  Tool<Map<String, dynamic>> _submissionTool() {
    return Tool<Map<String, dynamic>>(
      name: 'submit_audio_analysis',
      description:
          'Submits the final structured audio analysis to the Waveform '
          'Agent. Call it exactly once after all measurements are complete. '
          'Include one measurement entry per reported metric with its unit, '
          'channel and method. Do not dump raw tool output. If the request '
          'cannot be completed, set `error` or `needsInput` and explain the '
          'limitation. The summary must be in the language of the audio '
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
                'Metric name, for example thdPercent, snrDb, gainDb, '
                'frequencyHz, rmsVolts.',
          },
          'value': {'type': 'number', 'description': 'Measured numeric value.'},
          'unit': {
            'type': 'string',
            'description': 'Unit, for example %, dB, dBFS, V, Hz, s.',
          },
          'channel': {
            'type': 'string',
            'description': 'Channel the value belongs to (ch1-ch4), if any.',
          },
          'method': {
            'type': 'string',
            'description':
                'Measurement method or tool, for example fft_thd or '
                'bode_sweep_minus_3db.',
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
      'description': 'Known limits such as FFT resolution or 8-bit ADC.',
    },
    'toolsUsed': {
      'type': 'array',
      'items': {'type': 'string'},
      'description': 'Audio and instrument tools used for this result.',
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
            'sweep',
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

/// Thrown internally when the chat request cancels the audio analysis.
class _AudioAnalysisCancelled implements Exception {
  const _AudioAnalysisCancelled();
}
