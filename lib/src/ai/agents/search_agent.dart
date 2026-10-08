import 'dart:async';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../../logger.dart';
import '../tools/knowledgebase_search_tool.dart';
import 'max_tool_calls_handler.dart';

/// A search agent that searches a knowledgebase (Markdown document) for
/// information about an oscilloscope device and returns a summarized answer.
///
/// The agent has a built-in tool called `knowledgebase_search` that splits
/// the knowledgebase into chunks using a Markdown text splitter and searches
/// for relevant chunks based on the query.
///
/// The agent limits the number of tool calls per user input to
/// [maxToolCalls] (default: 10). This prevents runaway tool loops.
///
/// Usage:
/// ```dart
/// final agent = SearchAgent();
/// final answer = await agent.send('How do I set the trigger level?');
/// print(answer);
/// ```
class SearchAgent with MaxToolCallsHandler {
  /// Path to the knowledgebase Markdown file.
  static const _defaultKnowledgebasePath = 'docs/knowledgebase.md';

  /// Default maximum number of tool calls per user input.
  static const int defaultMaxToolCalls = 4;

  /// The underlying dartantic_ai Agent instance.
  final Agent _agent;

  /// The chat history for multi-turn conversations.
  final List<ChatMessage> _history = [];

  /// Maximum number of tool calls allowed per user input.
  @override
  final int maxToolCalls;

  /// Creates a [SearchAgent] with a knowledgebase search tool.
  ///
  /// The [model] parameter specifies the model to use in `provider:model`
  /// format.
  ///
  /// The [knowledgebasePath] parameter specifies the path to the Markdown
  /// knowledgebase file. Defaults to `docs/knowledgebase.md`.
  ///
  /// The [systemPrompt] parameter sets an optional system message.
  ///
  /// The [maxToolCalls] parameter limits the number of tool calls per
  /// user input. Defaults to [defaultMaxToolCalls] (10).
  SearchAgent({
    String model = 'deepseek:deepseek-v4-flash',
    String knowledgebasePath = _defaultKnowledgebasePath,
    String? systemPrompt,
    this.maxToolCalls = defaultMaxToolCalls,
  }) : _agent = Agent(
         model,
         displayName: 'SearchAgent',
         tools: [
           createKnowledgebaseSearchTool(
             knowledgebasePath,
             agentName: 'SearchAgent',
           ),
         ],
         maxToolCalls: maxToolCalls,
       ) {
    if (systemPrompt != null) {
      _history.add(ChatMessage.system(systemPrompt));
    }
    final logger = AppLogger(agentName: 'SearchAgent', toolName: 'constructor');
    logger.debug(
      '[DEBUG SearchAgent.constructor] systemPrompt=$systemPrompt, '
      '_history.length=${_history.length}, '
      '_history[0]?.role=${_history.isNotEmpty ? _history[0].role : "N/A"}, '
      '_history[0]?.text="${_history.isNotEmpty ? _history[0].text : "N/A"}"',
    );
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
    // Use sendStream which delegates to the inner Agent,
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
  /// Tool calls are limited to [maxToolCalls] per input by the underlying
  /// [Agent] (via [Agent.maxToolCalls]). When the limit is reached, the
  /// orchestrator returns error results for excess tool calls, telling the
  /// model to respond with what it has gathered so far.
  Stream<String> sendStream(String prompt) async* {
    final chunks = <String>[];

    await for (final chunk in _agent.sendStream(prompt, history: _history)) {
      // Yield text output. Tool calls and results are handled internally
      // by the inner Agent's orchestrator, including max tool calls
      // enforcement.
      if (chunk.output.isNotEmpty) {
        chunks.add(chunk.output);
        yield chunk.output;
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
      // The search agent must not retain history between calls. Keep only the
      // system prompt (if any) so each query starts fresh.
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
