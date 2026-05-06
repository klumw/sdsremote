import 'dart:async';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:langchain/langchain.dart'
    hide Agent, ChatMessage, ChatMessageRole, Tool;

import '../logger.dart';

/// A query agent that searches a knowledgebase (Markdown document) for
/// information about an oscilloscope device and returns a summarized answer.
///
/// The agent has a built-in tool called `knowledgebase_search` that splits
/// the knowledgebase into chunks using [MarkdownTextSplitter] and searches
/// for relevant chunks based on the query.
///
/// The agent limits the number of tool calls per user input to
/// [maxToolCalls] (default: 10). This prevents runaway tool loops.
///
/// Usage:
/// ```dart
/// final agent = QueryAgent();
/// final answer = await agent.send('How do I set the trigger level?');
/// print(answer);
/// ```
class QueryAgent {
  /// Path to the knowledgebase Markdown file.
  static const _defaultKnowledgebasePath = 'docs/knowledgebase.md';

  /// Default maximum number of tool calls per user input.
  static const int defaultMaxToolCalls = 3;

  /// The underlying dartantic_ai Agent instance.
  final Agent _agent;

  /// The chat history for multi-turn conversations.
  final List<ChatMessage> _history = [];

  /// Maximum number of tool calls allowed per user input.
  final int maxToolCalls;

  /// Creates a [QueryAgent] with a knowledgebase search tool.
  ///
  /// The [model] parameter specifies the model to use in `provider:model`
  /// format. Defaults to `deepseek:deepseek-v4-flash`.
  ///
  /// The [knowledgebasePath] parameter specifies the path to the Markdown
  /// knowledgebase file. Defaults to `docs/knowledgebase.md`.
  ///
  /// The [systemPrompt] parameter sets an optional system message.
  ///
  /// The [maxToolCalls] parameter limits the number of tool calls per
  /// user input. Defaults to [defaultMaxToolCalls] (10).
  QueryAgent({
    String model = 'deepseek:deepseek-v4-flash',
    String knowledgebasePath = _defaultKnowledgebasePath,
    String? systemPrompt,
    this.maxToolCalls = defaultMaxToolCalls,
  }) : _agent = Agent(
          model,
          displayName: 'QueryAgent',
          tools: [
            _createKnowledgebaseSearchTool(
              knowledgebasePath,
              agentName: 'QueryAgent',
            ),
          ],
        ) {
    if (systemPrompt != null) {
      _history.add(ChatMessage.system(systemPrompt));
    }
    final logger = AppLogger(
      agentName: 'QueryAgent',
      toolName: 'constructor',
    );
    logger.log(
      '[DEBUG QueryAgent.constructor] systemPrompt=$systemPrompt, '
      '_history.length=${_history.length}, '
      '_history[0]?.role=${_history.isNotEmpty ? _history[0].role : "N/A"}, '
      '_history[0]?.text="${_history.isNotEmpty ? _history[0].text : "N/A"}"',
    );
  }

  /// Loads and splits the knowledgebase Markdown file into chunks.
  static List<Document> _loadKnowledgebase(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Knowledgebase file not found', path);
    }

    final markdownText = file.readAsStringSync();

    final splitter = MarkdownTextSplitter(
      chunkSize: 100,
      chunkOverlap: 0,
    );

    return splitter.createDocuments([markdownText]);
  }

  /// Creates the knowledgebase search tool.
  ///
  /// The tool searches the pre-loaded chunks for content relevant to the
  /// user's query by checking which chunks contain words from the query.
  static Tool<Map<String, dynamic>> _createKnowledgebaseSearchTool(
    String knowledgebasePath, {
    String agentName = 'unknown',
  }) {
    // Load chunks at tool creation time.
    final chunks = _loadKnowledgebase(knowledgebasePath);

    return Tool<Map<String, dynamic>>(
      name: 'knowledgebase_search',
      description:
          'Search the oscilloscope knowledgebase for information about '
          'commands, settings, troubleshooting, or specifications. '
          'Use this tool when you need to find information about how to '
          'use the oscilloscope, what commands are available, or how to '
          'troubleshoot issues.',
      inputSchema: Schema.fromMap({
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description':
                'The search query describing what information you need, '
                'e.g. "How to set trigger level" or "C1:TRA command"',
          },
        },
        'required': ['query'],
      }),
      onCall: (args) async {
        final query = (args['query'] as String).toLowerCase();
        final logger = AppLogger(
          agentName: agentName,
          toolName: 'knowledgebase_search',
        );
        final queryWords =
            query.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();

        // Score each chunk by how many query words it contains.
        final scored = <_ScoredChunk>[];
        for (var i = 0; i < chunks.length; i++) {
          final content = chunks[i].pageContent.toLowerCase();
          var score = 0;
          for (final word in queryWords) {
            if (content.contains(word)) {
              score++;
            }
          }
          if (score > 0) {
            scored.add(_ScoredChunk(score: score, index: i));
          }
        }

        // Sort by score descending, take top matches.
        scored.sort((a, b) => b.score.compareTo(a.score));
        final topChunks = scored.take(5).toList();

        Map<String, dynamic> result;
        if (topChunks.isEmpty) {
          result = {
            'results':
                'No relevant information found in the knowledgebase.',
          };
        } else {
          final results = topChunks.map((sc) {
            final chunk = chunks[sc.index];
            return '--- Chunk (relevance: ${sc.score}) ---\n${chunk.pageContent}';
          }).join('\n\n');
          result = {'results': results};
        }

        logger.logToolCall(input: args, output: result);
        return result;
      },
    );
  }

  /// The display name of the agent (e.g., "DeepSeek").
  String get displayName => _agent.displayName;

  /// The current model name being used.
  String get model => _agent.model;

  /// Sends a [prompt] and returns the full response as a single string.
  ///
  /// The conversation history is automatically maintained for multi-turn
  /// conversations.
  Future<String> send(String prompt) async {
    final logger = AppLogger(
      agentName: 'QueryAgent',
      toolName: 'send',
    );
    logger.log(
      '[DEBUG QueryAgent.send] _history has ${_history.length} messages:',
    );
    for (var i = 0; i < _history.length; i++) {
      final msg = _history[i];
      logger.log(
        '[DEBUG QueryAgent.send]   [$i] role=${msg.role} '
        'text="${msg.text.substring(0, msg.text.length > 80 ? 80 : msg.text.length)}"'
        '${msg.hasToolCalls ? ' hasToolCalls' : ''}'
        '${msg.hasToolResults ? ' hasToolResults' : ''}',
      );
    }
    final result = await _agent.send(prompt, history: _history);
    _history.addAll(result.messages);
    return result.output.trim();
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
    final logger = AppLogger(
      agentName: 'QueryAgent',
      toolName: 'sendStream',
    );
    logger.log(
      '[DEBUG QueryAgent.sendStream] _history has ${_history.length} '
      'messages:',
    );
    for (var i = 0; i < _history.length; i++) {
      final msg = _history[i];
      logger.log(
        '[DEBUG QueryAgent.sendStream]   [$i] role=${msg.role} '
        'text="${msg.text.substring(0, msg.text.length > 80 ? 80 : msg.text.length)}"'
        '${msg.hasToolCalls ? ' hasToolCalls' : ''}'
        '${msg.hasToolResults ? ' hasToolResults' : ''}',
      );
    }
    final chunks = <String>[];
    var toolCallCount = 0;

    await for (final chunk in _agent.sendStream(prompt, history: _history)) {
      // Count tool calls by checking for model messages with tool calls.
      for (final msg in chunk.messages) {
        if (msg.role == ChatMessageRole.model && msg.hasToolCalls) {
          toolCallCount++;
        }
      }

      // If we've exceeded the max tool calls, stop yielding and break.
      if (toolCallCount > maxToolCalls) {
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

/// Internal helper to track scored chunks.
class _ScoredChunk {
  final int score;
  final int index;

  const _ScoredChunk({required this.score, required this.index});
}
