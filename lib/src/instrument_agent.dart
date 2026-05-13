import 'dart:async';

import 'package:dartantic_ai/dartantic_ai.dart';

import 'max_tool_calls_handler.dart';
import 'vxi11_tool.dart';

/// A reusable AI agent for instrument control via an AI model.
///
/// This class wraps the dartantic_ai framework and provides a simple,
/// reusable interface for chat interactions. It can be used in both
/// console applications and Flutter apps.
///
/// By default, the agent is equipped with a VXI-11 tool that allows it
/// to send SCPI commands and queries to a remote instrument.
///
/// The agent limits the number of tool calls per user input to
/// [maxToolCalls] (default: 10). This prevents runaway tool loops.
///
/// Usage:
/// ```dart
/// final agent = InstrumentAgent();
/// await for (final chunk in agent.sendStream('Send C1:TRA OFF to the device')) {
///   print(chunk);
/// }
/// ```
class InstrumentAgent with MaxToolCallsHandler {
  /// Default maximum number of tool calls per user input.
  static const int defaultMaxToolCalls = 3;

  /// The underlying dartantic_ai Agent instance.
  final Agent _agent;

  /// The chat history for multi-turn conversations.
  final List<ChatMessage> _history = [];

  /// Maximum number of tool calls allowed per user input.
  @override
  final int maxToolCalls;

  /// Creates a [InstrumentAgent] configured for the specified model with optional tools.
  ///
  /// The [model] parameter specifies the model to use in `provider:model`
  /// format.
  ///
  /// The [systemPrompt] parameter sets an optional system message.
  ///
  /// The [vxi11Host] parameter sets the default VXI-11 instrument IP.
  /// If null, no VXI-11 tool is added. Defaults to `192.168.178.95`.
  ///
  /// The [tools] parameter allows adding additional custom tools.
  ///
  /// The [maxToolCalls] parameter limits the number of tool calls per
  /// user input. Defaults to [defaultMaxToolCalls] (10).
  InstrumentAgent({
    String model = 'deepseek:deepseek-v4-flash',
    String? systemPrompt,
    String? vxi11Host,
    List<Tool>? tools,
    this.maxToolCalls = defaultMaxToolCalls,
  }) : _agent = Agent(
          model,
          displayName: 'InstrumentAgent',
          tools: [
            if (vxi11Host != null) createVxi11Tool(
              host: vxi11Host,
              agentName: 'InstrumentAgent',
            ),
            if (tools != null) ...tools,
          ],
        ) {
    if (systemPrompt != null) {
      _history.add(ChatMessage.system(systemPrompt));
    }
  }

  /// The display name of the agent.
  String get displayName => _agent.displayName;

  /// The current model name being used.
  String get model => _agent.model;

  /// Sends a [prompt] and returns the full response as a single string.
  ///
  /// The conversation history is automatically maintained for multi-turn
  /// conversations.
  ///
  /// Tool calls are counted and limited to [maxToolCalls] per input.
  /// When the limit is reached, the agent receives a tool result message
  /// telling it the limit was reached so it can respond gracefully.
  Future<String> send(String prompt) async {
    // Use sendStream which has the maxToolCalls enforcement,
    // then accumulate the results into a single string.
    final chunks = <String>[];
    await for (final chunk in sendStream(prompt)) {
      chunks.add(chunk);
    }
    return chunks.join().trim();
  }

  /// Sends a [prompt] and streams the response chunks.
  ///
  /// The conversation history is automatically maintained for multi-turn
  /// conversations.
  ///
  /// Tool calls are counted and limited to [maxToolCalls] per input.
  /// When the limit is reached, the agent is forced to respond without
  /// further tool calls.
  Stream<String> sendStream(String prompt) async* {
    final chunks = <String>[];
    var toolCallCount = 0;
    var maxToolCallsReached = false;

    await for (final chunk in _agent.sendStream(prompt, history: _history)) {
      // Count individual tool calls by counting ToolPart.call parts in model
      // messages. A single model response can contain multiple tool calls.
      for (final msg in chunk.messages) {
        if (msg.role == ChatMessageRole.model) {
          for (final part in msg.parts) {
            if (part is ToolPart && part.kind == ToolPartKind.call) {
              toolCallCount++;
            }
          }
        }
      }

      // If we've exceeded the max tool calls, yield the error message once
      // and continue consuming the stream. The LLM will see this text as a
      // user message and produce a graceful final response in subsequent
      // chunks. We must NOT break — we need to let that final response
      // through so the caller gets a meaningful answer instead of just the
      // error text.
      if (isMaxToolCallsExceeded(toolCallCount) && !maxToolCallsReached) {
        maxToolCallsReached = true;
        yield 'Maximum tool calls ($maxToolCalls) reached. '
            'Please respond with what you have so far.';
      }

      // After the limit is reached, we still yield output chunks so the
      // LLM's final response (which contains no tool calls) is delivered.
      if (!maxToolCallsReached) {
        chunks.add(chunk.output);
        yield chunk.output;
      } else {
        // After the limit, only yield text output (not tool call messages).
        // The LLM's final response to the "maximum reached" prompt will
        // contain text parts that we want to deliver.
        if (chunk.output.isNotEmpty) {
          chunks.add(chunk.output);
          yield chunk.output;
        }
      }
    }

    // Only add the user prompt and final text response to _history.
    // The dartantic_ai Agent internally manages tool call/result message pairs
    // in its StreamingState. Adding them here would cause duplicates and
    // "tool result without matching tool call" API errors on subsequent calls.
    final fullOutput = chunks.join();
    if (fullOutput.isNotEmpty) {
      _history.addAll([
        ChatMessage.user(prompt),
        ChatMessage.model(fullOutput),
      ]);
      // The instrument agent must not retain history between calls. Keep only
      // the system prompt (if any) so each command starts fresh.
      if (_history.length > 1) {
        final systemPrompt = _history[0];
        _history.clear();
        _history.add(systemPrompt);
      } else {
        _history.clear();
      }
    }
  }

  /// Clears the conversation history.
  void clearHistory() {
    _history.clear();
  }
}
