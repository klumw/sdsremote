import 'package:dartantic_ai/dartantic_ai.dart';

import '../tools/acquire_waveform_tool.dart';
import '../tools/calculator_tool.dart';
import '../tools/date_time_tool.dart';
import '../tools/logic_level_reference_tool.dart';
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
import '../tools/waveform_summary_tool.dart';
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
  static const int _maxHistoryMessages = 12;

  final Agent _agent;
  List<ChatMessage> _history;

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
    SpecificationUploadProvider? requestSpecUpload,
    String? vxi11Host,
    ScpiCommandCallback? onCommandSent,
    SignalGeneratorStatusProvider? readSignalGeneratorStatus,
    SignalGeneratorApplyProvider? applySignalGenerator,
    SignalGeneratorActionProvider? controlSignalGenerator,
    SignalGeneratorIntentCheck? isSignalGeneratorIntentEnabled,
    int instrumentToolCalls = defaultInstrumentToolCalls,
    int maxToolCalls = defaultMaxToolCalls,
  }) : _agent = Agent(
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
           createWaveformHistoryTool(
             readHistory: readWaveformHistory,
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
           createSpecificationAnalysisTool(
             analyze: SpecAnalystAgent(model: model).analyze,
             agentName: 'WaveformAgent',
           ),
           createLogicLevelReferenceTool(agentName: 'WaveformAgent'),
           createGenerateReferenceWaveformTool(
             generate: generateReferenceWaveform,
             agentName: 'WaveformAgent',
           ),
           if (vxi11Host != null)
             createScpiAgentTool(
               InstrumentAgent(
                 model: model,
                 vxi11Host: vxi11Host,
                 maxToolCalls: instrumentToolCalls,
                 onCommandSent: onCommandSent,
                 systemPrompt: instrumentAgentSystemPrompt,
               ),
               agentName: 'WaveformAgent',
             ),
           if (readSignalGeneratorStatus != null)
             createReadSignalGeneratorStatusTool(
               readStatus: readSignalGeneratorStatus,
               isEnabled: isSignalGeneratorIntentEnabled,
               agentName: 'WaveformAgent',
             ),
           if (applySignalGenerator != null)
             createSetSignalGeneratorTool(
               apply: applySignalGenerator,
               isEnabled: isSignalGeneratorIntentEnabled,
               agentName: 'WaveformAgent',
             ),
           if (controlSignalGenerator != null)
             createSignalGeneratorActionTool(
               control: controlSignalGenerator,
               isEnabled: isSignalGeneratorIntentEnabled,
               agentName: 'WaveformAgent',
             ),
           createMathTool(agentName: 'WaveformAgent'),
           createCalculatorTool(agentName: 'WaveformAgent'),
           createDateTimeTool(agentName: 'WaveformAgent'),
         ],
       ),
       _history = [ChatMessage.system(waveformAgentSystemPrompt)];

  String get displayName => _agent.displayName;

  String get model => _agent.model;

  /// Streams the final answer, suppressing intermediate "thinking aloud" text
  /// that precedes tool calls (same buffering policy as the calculator agent).
  Stream<String> sendStream(String prompt) async* {
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

    // The final answer is emitted once, after the tool-limit wording has been
    // removed. The model can see the orchestrator's rejected tool results in
    // its history and sometimes quotes the technical message; the user must
    // never receive it as the answer.
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
