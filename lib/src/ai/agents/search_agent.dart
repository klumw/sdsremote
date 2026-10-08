import 'dart:async';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:langchain/langchain.dart'
    hide Agent, ChatMessage, ChatMessageRole, Tool;

import '../logger.dart';
import 'max_tool_calls_handler.dart';

/// A search agent that searches a knowledgebase (Markdown document) for
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
           _createKnowledgebaseSearchTool(
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

  /// Loads and splits the knowledgebase Markdown file into chunks.
  ///
  /// Resolution order (stops at first hit):
  /// 1. [path] as-is (works during development on Linux/Mac).
  /// 2. Relative to the executable's directory (installed .deb at
  ///    `/usr/local/lib/sdsremote/`).
  /// 3. Relative to the executable's parent directory.
  /// 4. Walk up from the executable's directory, looking for
  ///    `docs/knowledgebase.md` at each ancestor level. This handles Flutter
  ///    Windows development builds where the exe lives deep in
  ///    `build\windows\x64\runner\Release\` and the project root is several
  ///    levels up.
  /// 5. Inside the Flutter assets bundle directory
  ///    (`data/flutter_assets/docs/knowledgebase.md` relative to the
  ///    executable). This handles Windows release installs where the asset
  ///    is bundled by Flutter at `C:\Program Files\SDS-Remote\data\flutter_assets\`.
  ///
  /// Returns an empty list if no file is found anywhere, logging a warning
  /// rather than crashing.
  static List<Document> _loadKnowledgebase(String path) {
    final logger = AppLogger(
      agentName: 'SearchAgent',
      toolName: 'loadKnowledgebase',
    );

    String? resolvedPath;

    // 1. Try the provided path as-is (works during development).
    if (File(path).existsSync()) {
      resolvedPath = path;
    }

    // 2. Try relative to the executable's directory (installed .deb).
    if (resolvedPath == null) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final altPath =
            '$exeDir${Platform.pathSeparator}docs'
            '${Platform.pathSeparator}knowledgebase.md';
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
        final altPath =
            '$exeDir${Platform.pathSeparator}..'
            '${Platform.pathSeparator}docs'
            '${Platform.pathSeparator}knowledgebase.md';
        if (File(altPath).existsSync()) {
          resolvedPath = altPath;
        }
      } catch (_) {
        // Ignore.
      }
    }

    // 4. Walk up from the executable directory looking for the file.
    //    On Windows Flutter development builds the exe is at:
    //      build/windows/x64/runner/Release/sdsremote.exe
    //    and the project root (with docs/) is several levels up.
    if (resolvedPath == null) {
      try {
        var dir = File(Platform.resolvedExecutable).parent;
        // Walk up at most 10 levels to avoid infinite loops.
        for (var i = 0; i < 10; i++) {
          final candidate =
              '${dir.path}${Platform.pathSeparator}docs'
              '${Platform.pathSeparator}knowledgebase.md';
          if (File(candidate).existsSync()) {
            resolvedPath = candidate;
            break;
          }
          final parent = dir.parent;
          if (parent.path == dir.path) break; // Reached filesystem root.
          dir = parent;
        }
      } catch (_) {
        // Ignore.
      }
    }

    // 5. Try inside the Flutter assets bundle directory.
    //    On Windows release installs, Flutter bundles declared assets at:
    //      <exe_dir>/data/flutter_assets/<asset_path>
    //    e.g. C:\Program Files\SDS-Remote\data\flutter_assets\docs\knowledgebase.md
    if (resolvedPath == null) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final flutterAssetsDir =
            '$exeDir${Platform.pathSeparator}data'
            '${Platform.pathSeparator}flutter_assets';
        final assetsPath = '$flutterAssetsDir${Platform.pathSeparator}$path';
        if (File(assetsPath).existsSync()) {
          resolvedPath = assetsPath;
        }
      } catch (_) {
        // Ignore.
      }
    }

    // If no file was found anywhere, log a warning and return empty.
    if (resolvedPath == null) {
      logger.log(
        'WARNING: Knowledgebase file not found at "$path" or any alternative '
        'location. The knowledgebase_search tool will be unavailable.',
      );
      return [];
    }

    logger.log('Loaded knowledgebase from: $resolvedPath');

    final markdownText = File(resolvedPath).readAsStringSync();

    final splitter = MarkdownTextSplitter(chunkSize: 100, chunkOverlap: 0);

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
        final queryWords = query
            .split(RegExp(r'\s+'))
            .where((w) => w.length > 2)
            .toList();

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
            'results': 'No relevant information found in the knowledgebase.',
          };
        } else {
          final results = topChunks
              .map((sc) {
                final chunk = chunks[sc.index];
                return '--- Chunk (relevance: ${sc.score}) ---\n${chunk.pageContent}';
              })
              .join('\n\n');
          result = {'results': results};
        }

        logger.logToolCall(input: args, output: result);
        return result;
      },
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

/// Internal helper to track scored chunks.
class _ScoredChunk {
  final int score;
  final int index;

  const _ScoredChunk({required this.score, required this.index});
}
