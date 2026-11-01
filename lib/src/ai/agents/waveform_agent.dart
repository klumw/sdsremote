import 'package:dartantic_ai/dartantic_ai.dart';

import '../tools/calculator_tool.dart';
import '../tools/date_time_tool.dart';
import '../tools/math_tool.dart';
import '../tools/spectrum_summary_tool.dart';
import '../tools/waveform_summary_tool.dart';
import 'systemprompts.dart';

/// Analysis assistant for the Acquire Waveform view.
///
/// The agent sees the current time-domain measurements and the FFT spectrum
/// through deterministic read tools, performs derived calculations with the
/// math and calculator tools, and can place results in time with the
/// date/time tool. It never controls the instrument.
class WaveformAgent {
  static const int defaultMaxToolCalls = 8;
  static const int _maxHistoryMessages = 12;

  final Agent _agent;
  List<ChatMessage> _history;

  WaveformAgent({
    String model = 'deepseek:deepseek-v4-flash',
    WaveformSummaryProvider? readWaveformSummary,
    SpectrumSummaryProvider? readSpectrumSummary,
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
          yield chunk.output;
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
          yield buffered;
        }
        textBuffer.clear();
      }
    }

    if (textBuffer.isNotEmpty) {
      for (final buffered in textBuffer) {
        allChunks.add(buffered);
        yield buffered;
      }
    }

    final output = allChunks.join();
    if (output.isNotEmpty) {
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
