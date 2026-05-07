import 'dart:async';

import 'package:dartantic_ai/dartantic_ai.dart';

import 'max_tool_calls_handler.dart';
import 'vxi11_tool.dart';

/// A reusable AI agent that uses DeepSeek or EdenAI via the OpenAI-compatible API.
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
/// final agent = ChatAgent();
/// await for (final chunk in agent.sendStream('Send C1:TRA OFF to the device')) {
///   print(chunk);
/// }
/// ```
class ChatAgent with MaxToolCallsHandler {
  /// Default maximum number of tool calls per user input.
  static const int defaultMaxToolCalls = 3;

  /// The underlying dartantic_ai Agent instance.
  final Agent _agent;

  /// The chat history for multi-turn conversations.
  final List<ChatMessage> _history = [];

  /// Maximum number of tool calls allowed per user input.
  @override
  final int maxToolCalls;

  /// Creates a [ChatAgent] configured for the specified model with optional tools.
  ///
  /// The [model] parameter specifies the model to use in `provider:model`
  /// format. Defaults to `deepseek:deepseek-v4-flash`.
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
  ChatAgent({
    String model = 'deepseek:deepseek-v4-flash',
    String? systemPrompt,
    String? vxi11Host,
    List<Tool>? tools,
    this.maxToolCalls = defaultMaxToolCalls,
    double? temperature,
  }) : _agent = Agent(
          model,
          displayName: 'ChatAgent',
          temperature: temperature,
          tools: [
            if (vxi11Host != null) createVxi11Tool(
              host: vxi11Host,
              agentName: 'ChatAgent',
            ),
            if (tools != null) ...tools,
          ],
        ) {
    if (systemPrompt != null) {
      _history.add(ChatMessage.system(systemPrompt));
    }
  }

  /// The display name of the agent (e.g., "DeepSeek").
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

      // If we've exceeded the max tool calls, inject a tool result message
      // telling the LLM the limit was reached so it can respond gracefully.
      if (isMaxToolCallsExceeded(toolCallCount)) {
        final result = buildMaxToolCallsMessage();
        _history.add(result.toolResultMessage);
        yield result.message;
        break;
      }

      chunks.add(chunk.output);
      yield chunk.output;
    }

    // Reconstruct the full messages from the concatenated output.
    final fullOutput = chunks.join();
    if (fullOutput.isNotEmpty) {
      _history.addAll([
        ChatMessage.user(prompt),
        ChatMessage.model(fullOutput),
      ]);
    }
  }

  /// Clears the conversation history.
  void clearHistory() {
    _history.clear();
  }
}
