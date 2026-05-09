import 'dart:async';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:langchain/langchain.dart'
    hide Agent, ChatMessage, ChatMessageRole, Tool;

import '../logger.dart';
import 'max_tool_calls_handler.dart';

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
class QueryAgent with MaxToolCallsHandler {
  /// Path to the knowledgebase Markdown file.
  static const _defaultKnowledgebasePath = 'docs/knowledgebase.md';

  /// Default maximum number of tool calls per user input.
  static const int defaultMaxToolCalls = 10;

  /// The underlying dartantic_ai Agent instance.
  final Agent _agent;

  /// The chat history for multi-turn conversations.
  final List<ChatMessage> _history = [];

  /// Maximum number of tool calls allowed per user input.
  @override
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
    logger.debug(
      '[DEBUG QueryAgent.constructor] systemPrompt=$systemPrompt, '
      '_history.length=${_history.length}, '
      '_history[0]?.role=${_history.isNotEmpty ? _history[0].role : "N/A"}, '
      '_history[0]?.text="${_history.isNotEmpty ? _history[0].text : "N/A"}"',
    );
  }

  /// Loads and splits the knowledgebase Markdown file into chunks.
  ///
  /// Tries [path] first; if not found, tries to resolve relative to the
  /// executable's directory (for installed .deb builds at
  /// `/usr/local/lib/sdsremote/`). Returns an empty list if no file is found
  /// anywhere, logging a warning rather than crashing.
  static List<Document> _loadKnowledgebase(String path) {
    String? resolvedPath;

    // 1. Try the provided path as-is (works during development).
    if (File(path).existsSync()) {
      resolvedPath = path;
    }

    // 2. Try relative to the executable's directory (installed .deb).
    if (resolvedPath == null) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final altPath = '$exeDir/docs/knowledgebase.md';
        if (File(altPath).existsSync()) {
          resolvedPath = altPath;
        }
      } catch (_) {
        // Ignore — Platform.resolvedExecutable may fail on some platforms.
      }
    }

    // 3. Try relative to the executable's parent directory.
    if (resolvedPath == null) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final altPath = '$exeDir/../docs/knowledgebase.md';
        if (File(altPath).existsSync()) {
          resolvedPath = altPath;
        }
      } catch (_) {
        // Ignore.
      }
    }

    // If no file was found anywhere, log a warning and return empty.
    if (resolvedPath == null) {
      AppLogger(agentName: 'QueryAgent', toolName: 'loadKnowledgebase').debug(
        'WARNING: Knowledgebase file not found at "$path" or any alternative '
        'location. The knowledgebase_search tool will be unavailable.',
      );
      return [];
    }

    AppLogger(agentName: 'QueryAgent', toolName: 'loadKnowledgebase').debug(
      'Loaded knowledgebase from: $resolvedPath',
    );

    final markdownText = File(resolvedPath).readAsStringSync();

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
  ///
  /// If the knowledgebase file could not be loaded ([chunks] is empty), the
  /// tool returns a "not available" message instead of crashing.
  static Tool<Map<String, dynamic>> _createKnowledgebaseSearchTool(
    String knowledgebasePath, {
    String agentName = 'unknown',
  }) {
    // Load chunks at tool creation time. Returns empty list if file missing.
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
        final logger = AppLogger(
          agentName: agentName,
          toolName: 'knowledgebase_search',
        );

        // If no chunks were loaded, the knowledgebase is unavailable.
        if (chunks.isEmpty) {
          final result = {
            'results':
                'Knowledgebase is not available. The knowledgebase file '
                'could not be found.',
          };
          logger.logToolCall(input: args, output: result);
          return result;
        }

        final query = (args['query'] as String).toLowerCase();
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
  ///
  /// Tool calls are counted and limited to [maxToolCalls] per input.
  /// When the limit is reached, the agent receives a tool result message
  /// telling it the limit was reached so it can respond gracefully.
  Future<String> send(String prompt) async {
    final logger = AppLogger(
      agentName: 'QueryAgent',
      toolName: 'send',
    );
    logger.debug(
      '[DEBUG QueryAgent.send] _history has ${_history.length} messages:',
    );
    for (var i = 0; i < _history.length; i++) {
      final msg = _history[i];
      logger.debug(
        '[DEBUG QueryAgent.send]   [$i] role=${msg.role} '
        'text="${msg.text.substring(0, msg.text.length > 80 ? 80 : msg.text.length)}"'
        '${msg.hasToolCalls ? ' hasToolCalls' : ''}'
        '${msg.hasToolResults ? ' hasToolResults' : ''}',
      );
    }

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
    final logger = AppLogger(
      agentName: 'QueryAgent',
      toolName: 'sendStream',
    );
    logger.debug(
      '[DEBUG QueryAgent.sendStream] _history has ${_history.length} '
      'messages:',
    );
    for (var i = 0; i < _history.length; i++) {
      final msg = _history[i];
      logger.debug(
        '[DEBUG QueryAgent.sendStream]   [$i] role=${msg.role} '
        'text="${msg.text.substring(0, msg.text.length > 80 ? 80 : msg.text.length)}"'
        '${msg.hasToolCalls ? ' hasToolCalls' : ''}'
        '${msg.hasToolResults ? ' hasToolResults' : ''}',
      );
    }
    final chunks = <String>[];
    var toolCallCount = 0;
    final allMessages = <ChatMessage>[];

    await for (final chunk in _agent.sendStream(prompt, history: _history)) {
      // Collect all messages for history preservation.
      allMessages.addAll(chunk.messages);

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

    // Reconstruct the full conversation history from all collected messages.
    // This preserves tool call and tool result messages across turns.
    if (allMessages.isNotEmpty) {
      _history.addAll(allMessages);
    } else {
      final fullOutput = chunks.join();
      if (fullOutput.isNotEmpty) {
        _history.addAll([
          ChatMessage.user(prompt),
          ChatMessage.model(fullOutput),
        ]);
      }
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
