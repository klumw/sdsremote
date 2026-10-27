import 'dart:async';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../tools/macro_tools.dart';
import '../tools/math_tool.dart';
import 'systemprompts.dart';

/// A user-facing agent that edits the macro currently open in the Macro
/// Editor.
///
/// Unlike [FrontendAgent], this agent has no instrument or knowledgebase
/// sub-agents. Its tools work directly on the editor state:
/// - `read_macro` — returns the complete editor content.
/// - `write_macro` — replaces the complete editor content.
/// - `validate_macro` — lints the editor content or a candidate version.
/// - `read_siggen_status` — returns the configured signal generator type and
///   its live connection and channel status.
/// - `math_tool` — deterministic arithmetic, unit conversion and readable
///   value formatting.
///
/// The complete macro language reference is part of
/// [macroAgentSystemPrompt], so the model does not need a documentation tool.
///
/// Tool calls are limited per user input by [maxToolCalls] (default: 12),
/// enforced by the underlying [Agent].
class MacroAgent {
  /// Default maximum number of tool calls per user input.
  static const int defaultMaxToolCalls = 12;

  /// Maximum number of history messages kept after the system prompt.
  ///
  /// Ten messages correspond to five user/assistant turns. Tool calls and
  /// their results are not stored in the history (the dartantic_ai Agent
  /// manages them internally for the duration of one request), so keeping
  /// more turns would only grow the token budget without giving the model
  /// access to older tool results. The current macro is always available
  /// through `read_macro` instead.
  static const int _maxHistoryMessages = 10;

  /// The underlying dartantic_ai Agent instance.
  final Agent _agent;

  /// The chat history for multi-turn conversations.
  List<ChatMessage> _history = [];

  /// Maximum number of tool calls allowed per user input.
  final int maxToolCalls;

  /// Creates a [MacroAgent].
  ///
  /// [readMacro] must return the current editor content and [writeMacro] must
  /// replace it. Both callbacks are captured by the tools, so the agent always
  /// works on the live editor state rather than on a snapshot.
  ///
  /// [macroFileName] is optional and only used to report the loaded file name
  /// in the `read_macro` result.
  MacroAgent({
    String model = 'deepseek:deepseek-v4-flash',
    required MacroReader readMacro,
    required MacroWriter writeMacro,
    String? Function()? macroFileName,
    MacroSiggenStatusReader? readSiggenStatus,
    this.maxToolCalls = defaultMaxToolCalls,
  }) : _agent = Agent(
         model,
         displayName: 'MacroAgent',
         maxToolCalls: maxToolCalls,
         tools: [
           createReadMacroTool(
             readMacro: readMacro,
             macroFileName: macroFileName,
             agentName: 'MacroAgent',
           ),
           createWriteMacroTool(
             writeMacro: writeMacro,
             agentName: 'MacroAgent',
           ),
           createValidateMacroTool(
             readMacro: readMacro,
             agentName: 'MacroAgent',
           ),
           createReadSiggenStatusTool(
             readStatus: readSiggenStatus,
             agentName: 'MacroAgent',
           ),
           createMathTool(agentName: 'MacroAgent'),
         ],
       ) {
    _history.add(ChatMessage.system(macroAgentSystemPrompt));
  }

  /// The display name of the agent.
  String get displayName => _agent.displayName;

  /// The current model name being used.
  String get model => _agent.model;

  /// Sends a [prompt] and streams the response chunks.
  ///
  /// The conversation history is automatically maintained for multi-turn
  /// conversations.
  ///
  /// **Buffering behavior** mirrors [FrontendAgent]: text that the model
  /// streams before deciding to call a tool is discarded, so the user only
  /// sees the final answer after all tool calls have completed. Text that
  /// arrives without any preceding tool call is streamed normally.
  Stream<String> sendStream(String prompt) async* {
    // Buffer for text chunks that may be discarded if followed by tool calls.
    final textBuffer = <String>[];
    // Accumulator for the final output (used for history management).
    final allChunks = <String>[];
    // Whether we've seen a tool call in the current response cycle.
    var hasSeenToolCall = false;
    // Whether we've already flushed the buffer after tool calls complete.
    var hasFlushedAfterTools = false;

    await for (final chunk in _agent.sendStream(prompt, history: _history)) {
      final hasToolCalls = chunk.messages.any((msg) => msg.hasToolCalls);

      if (hasToolCalls) {
        // The model decided to call a tool. Discard buffered "thinking aloud"
        // text — it was intermediate reasoning before the tool call.
        textBuffer.clear();
        hasSeenToolCall = true;
        hasFlushedAfterTools = false;
      }

      final hasToolResults = chunk.messages.any((msg) => msg.hasToolResults);

      if (hasToolResults) {
        // Tool results are coming back. The next text chunks will be the
        // model's actual answer. Reset the flag so we flush the buffer.
        hasFlushedAfterTools = false;
      }

      if (chunk.output.isNotEmpty) {
        if (!hasSeenToolCall || !hasFlushedAfterTools) {
          textBuffer.add(chunk.output);
        } else {
          // Past the tool call cycle: stream the final answer directly.
          allChunks.add(chunk.output);
          yield chunk.output;
        }
      }

      // Detect the end of a tool-call cycle: after tool results have been
      // processed, the next chunk with text and no tool calls/results means
      // the model is producing its final answer. Flush the buffer.
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

    // If the stream ends with buffered text that was never flushed (e.g. no
    // tool calls occurred), yield it now.
    if (textBuffer.isNotEmpty) {
      for (final buffered in textBuffer) {
        allChunks.add(buffered);
        yield buffered;
      }
      textBuffer.clear();
    }

    // Only add the user prompt and final text response to the history.
    // The dartantic_ai Agent internally manages tool call/result message pairs
    // in its StreamingState. Adding them here would cause duplicates and
    // "tool result without matching tool call" API errors on subsequent calls.
    final fullOutput = allChunks.join();
    if (fullOutput.isNotEmpty) {
      _history.addAll([
        ChatMessage.user(prompt),
        ChatMessage.model(fullOutput),
      ]);
      if (_history.length > _maxHistoryMessages + 1) {
        _history = [
          _history[0],
          ..._history.sublist(_history.length - _maxHistoryMessages),
        ];
      }
    }
  }

  /// Clears the conversation history but keeps the system prompt.
  void clearHistory() {
    _history = [ChatMessage.system(macroAgentSystemPrompt)];
  }
}
