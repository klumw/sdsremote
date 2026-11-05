import 'package:dartantic_ai/dartantic_ai.dart';

import '../../devices/device_agent_context.dart';
import '../cancellation.dart';
import '../tools/acquire_waveform_tool.dart';
import '../tools/audio/audio_tools.dart';
import '../tools/audio_agent_tool.dart';
import '../tools/calculator_tool.dart';
import '../tools/chat_choice_tool.dart';
import '../tools/date_time_tool.dart';
import '../tools/digital_agent_tool.dart';
import '../tools/digital_measurement_tools.dart';
import '../tools/math_tool.dart';
import '../tools/scpi_agent_tool.dart';
import '../tools/signal_generator_tool.dart';
import '../tools/spec_analyst_tool.dart';
import '../tools/specification_upload_tool.dart';
import '../tools/spectrum_summary_tool.dart';
import '../tools/vxi11_tool.dart';
import '../tools/waveform_analysis_tools.dart';
import '../tools/waveform_fault_profile_tool.dart';
import '../tools/waveform_fault_tool.dart';
import '../tools/waveform_history_tool.dart';
import '../tools/waveform_report_tool.dart';
import '../tools/waveform_summary_tool.dart';
import 'audio_agent.dart';
import 'digital_agent.dart';
import 'instrument_agent.dart';
import 'spec_analyst_agent.dart';
import 'systemprompts.dart';

/// Analysis assistant for the Acquire Waveform view.
///
/// The agent sees the current time-domain measurements and the FFT spectrum
/// through deterministic read tools, performs derived calculations with the
/// math and calculator tools, and can place results in time with the
/// date/time tool. When an instrument address is configured it can also read
/// live values and change scope settings through the instrument agent; the
/// system prompt requires explicit user confirmation before any change.
class WaveformAgent {
  static const int defaultMaxToolCalls = 16;
  static const int defaultInstrumentToolCalls = 8;
  static const int _maxHistoryMessages = 20;

  late final Agent _agent;
  List<ChatMessage> _history;
  InstrumentAgent? _instrumentAgent;
  late final AudioAgent _audioAgent;
  late final DigitalAgent _digitalAgent;
  CancellationToken? _activeCancelToken;

  /// The instrument sub-agent, exposed for diagnostics and tests.
  InstrumentAgent? get instrumentAgent => _instrumentAgent;

  /// The audio measurement sub-agent, exposed for diagnostics and tests.
  AudioAgent get audioAgent => _audioAgent;

  /// The digital measurement sub-agent, exposed for diagnostics and tests.
  DigitalAgent get digitalAgent => _digitalAgent;

  WaveformAgent({
    String model = 'deepseek:deepseek-v4-flash',
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
    SpecificationUploadProvider? requestSpecUpload,
    ChatChoiceProvider? requestUserChoice,
    String? vxi11Host,
    ScpiCommandCallback? onCommandSent,
    DeviceAgentContext? instrumentDeviceContext,
    SignalGeneratorStatusProvider? readSignalGeneratorStatus,
    SignalGeneratorApplyProvider? applySignalGenerator,
    SignalGeneratorActionProvider? controlSignalGenerator,
    SignalGeneratorIntentCheck? isSignalGeneratorIntentEnabled,
    AudioAnalysisContextProvider? audioAnalysisContext,
    AudioSweepProvider? audioSweep,
    DigitalMeasurementProvider? digitalMeasurement,
    void Function()? suspendResponseTimeout,
    void Function()? resumeResponseTimeout,
    int instrumentToolCalls = defaultInstrumentToolCalls,
    int maxToolCalls = defaultMaxToolCalls,
  }) : _history = [ChatMessage.system(waveformAgentSystemPrompt)] {
    final instrumentAgent = vxi11Host == null
        ? null
        : InstrumentAgent(
            model: model,
            vxi11Host: vxi11Host,
            maxToolCalls: instrumentToolCalls,
            onCommandSent: onCommandSent,
            deviceContext: instrumentDeviceContext,
            readSignalGeneratorStatus: readSignalGeneratorStatus,
            applySignalGenerator: applySignalGenerator,
            controlSignalGenerator: controlSignalGenerator,
            isSignalGeneratorIntentEnabled: isSignalGeneratorIntentEnabled,
          );
    _instrumentAgent = instrumentAgent;
    _audioAgent = AudioAgent(
      model: model,
      contextProvider: audioAnalysisContext ?? () => null,
      sweepProvider: audioSweep,
      acquireWaveform: acquireWaveform,
      instrumentAgent: instrumentAgent,
    );
    _digitalAgent = DigitalAgent(
      model: model,
      readWaveformSummary: readWaveformSummary,
      readSpectrumSummary: readSpectrumSummary,
      readWaveformFeatures: readWaveformFeatures,
      classifyWaveform: classifyWaveform,
      analyzeWaveformFaults: analyzeWaveformFaults,
      manageFaultProfile: manageFaultProfile,
      acquireWaveform: acquireWaveform,
      instrumentAgent: instrumentAgent,
      digitalMeasurement: digitalMeasurement,
    );
    _agent = Agent(
      model,
      displayName: 'WaveformAgent',
      maxToolCalls: maxToolCalls,
      tools: [
        createWaveformSummaryTool(
          readSummary: readWaveformSummary,
          agentName: 'WaveformAgent',
        ),
        createSpectrumSummaryTool(
          readSummary: readSpectrumSummary,
          agentName: 'WaveformAgent',
        ),
        createAcquireWaveformTool(
          acquire: acquireWaveform,
          agentName: 'WaveformAgent',
        ),
        if (readSignalGeneratorStatus != null)
          createReadSignalGeneratorStatusTool(
            readStatus: readSignalGeneratorStatus,
            agentName: 'WaveformAgent',
            description:
                'Return the status of the separate JDS6600/FY6900 signal '
                'generator: the configured device, whether it is detected and '
                'connected, the serial port, model, cached per-channel '
                'settings, the output states and the device limits. Call it '
                'before proposing an automatic frequency/Bode sweep. This '
                'read-only pre-check does not need a signal-generator '
                'keyword; generator changes still require the keyword and '
                'user confirmation.',
          ),
        createWaveformHistoryTool(
          readHistory: readWaveformHistory,
          agentName: 'WaveformAgent',
        ),
        createWaveformReportTool(
          createReport: createWaveformReport,
          agentName: 'WaveformAgent',
        ),
        createClassifyWaveformTool(
          classify: classifyWaveform,
          agentName: 'WaveformAgent',
        ),
        createCompareWaveformToReferencesTool(
          compare: compareWaveformToReferences,
          agentName: 'WaveformAgent',
        ),
        createCompareWaveformsTool(
          compare: compareWaveforms,
          agentName: 'WaveformAgent',
        ),
        createGetWaveformFeaturesTool(
          readFeatures: readWaveformFeatures,
          agentName: 'WaveformAgent',
        ),
        createWaveformFaultAnalysisTool(
          analyze: analyzeWaveformFaults,
          agentName: 'WaveformAgent',
        ),
        createWaveformFaultProfileTool(
          manage: manageFaultProfile,
          agentName: 'WaveformAgent',
        ),
        createSpecificationUploadTool(
          requestUpload: requestSpecUpload,
          agentName: 'WaveformAgent',
        ),
        createChatChoiceTool(
          requestChoice: requestUserChoice,
          agentName: 'WaveformAgent',
        ),
        createSpecificationAnalysisTool(
          analyze: SpecAnalystAgent(model: model).analyze,
          agentName: 'WaveformAgent',
        ),
        createGenerateReferenceWaveformTool(
          generate: generateReferenceWaveform,
          agentName: 'WaveformAgent',
        ),
        if (instrumentAgent != null)
          createScpiAgentTool(instrumentAgent, agentName: 'WaveformAgent'),
        createAudioAnalysisAgentTool(
          analyze:
              ({
                required String request,
                bool autonomous = false,
                String? channel,
                String? focus,
              }) => _audioAgent.analyze(
                request: request,
                autonomous: autonomous,
                channel: channel,
                focus: focus,
                cancelToken: _activeCancelToken,
              ),
          onLongRunningStart: suspendResponseTimeout,
          onLongRunningEnd: resumeResponseTimeout,
          agentName: 'WaveformAgent',
        ),
        createDigitalAnalysisAgentTool(
          analyze:
              ({
                required String request,
                bool autonomous = false,
                String? channel,
                String? focus,
              }) => _digitalAgent.analyze(
                request: request,
                autonomous: autonomous,
                channel: channel,
                focus: focus,
                cancelToken: _activeCancelToken,
              ),
          onLongRunningStart: suspendResponseTimeout,
          onLongRunningEnd: resumeResponseTimeout,
          agentName: 'WaveformAgent',
        ),
        createMathTool(agentName: 'WaveformAgent'),
        createCalculatorTool(agentName: 'WaveformAgent'),
        createDateTimeTool(agentName: 'WaveformAgent'),
      ],
    );
  }

  String get displayName => _agent.displayName;

  String get model => _agent.model;

  /// Streams the final answer, suppressing intermediate "thinking aloud" text
  /// that precedes tool calls (same buffering policy as the calculator agent).
  Stream<String> sendStream(
    String prompt, {
    CancellationToken? cancelToken,
  }) async* {
    _audioAgent.clearSweepCache();
    _activeCancelToken = cancelToken;
    // A cancelled or abandoned audio analysis must not leave generator access
    // open for the next request. The AudioAgent also resets the grant in its
    // own cleanup path.
    _instrumentAgent?.setAutonomousGeneratorAccess(false);
    try {
      final textBuffer = <String>[];
      final allChunks = <String>[];
      var hasSeenToolCall = false;
      var hasFlushedAfterTools = false;

      await for (final chunk in _agent.sendStream(prompt, history: _history)) {
        final hasToolCalls = chunk.messages.any(
          (message) => message.hasToolCalls,
        );
        if (hasToolCalls) {
          textBuffer.clear();
          hasSeenToolCall = true;
          hasFlushedAfterTools = false;
        }
        final hasToolResults = chunk.messages.any(
          (message) => message.hasToolResults,
        );
        if (hasToolResults) hasFlushedAfterTools = false;

        if (chunk.output.isNotEmpty) {
          if (!hasSeenToolCall || !hasFlushedAfterTools) {
            textBuffer.add(chunk.output);
          } else {
            allChunks.add(chunk.output);
          }
        }

        if (hasSeenToolCall &&
            !hasFlushedAfterTools &&
            chunk.output.isNotEmpty &&
            !hasToolCalls &&
            !hasToolResults) {
          hasFlushedAfterTools = true;
          for (final buffered in textBuffer) {
            allChunks.add(buffered);
          }
          textBuffer.clear();
        }
      }

      if (textBuffer.isNotEmpty) {
        allChunks.addAll(textBuffer);
        textBuffer.clear();
      }

      // The final answer is emitted once, after the tool-limit wording has
      // been removed. The model can see the orchestrator's rejected tool
      // results in its history and sometimes quotes the technical message; the
      // user must never receive it as the answer.
      final output = _sanitizeToolLimitText(allChunks.join());
      if (output.isNotEmpty) {
        yield output;
        _history.addAll([ChatMessage.user(prompt), ChatMessage.model(output)]);
        if (_history.length > _maxHistoryMessages + 1) {
          _history = [
            _history.first,
            ..._history.sublist(_history.length - _maxHistoryMessages),
          ];
        }
      }
    } finally {
      if (identical(_activeCancelToken, cancelToken)) {
        _activeCancelToken = null;
      }
    }
  }

  void clearHistory() {
    _history = [ChatMessage.system(waveformAgentSystemPrompt)];
  }
}

/// Removes technical tool-limit wording from the final assistant answer.
String _sanitizeToolLimitText(String text) {
  return text
      .replaceAll(
        RegExp(r'Maximum tool calls \(\d+\) reached\.?', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(
          r'Please try rephrasing your request to be more specific\.?',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'Please respond with what you have so far\.?',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'\b(?:the\s+)?(?:'
          r'per-request\s+(?:tool[-\s]?call\s+)?limit|'
          r'tool[-\s]?call\s+limit|'
          r'call\s+limit'
          r')\b',
          caseSensitive: false,
        ),
        'a request restriction',
      )
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
