import 'dart:async';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../logger.dart';
import 'instrument_agent.dart';
import 'search_agent.dart';
import 'systemprompts.dart';

/// Creates the tool that wraps the VXI-11 instrument agent.
///
/// The [vxiAgent] is captured in the closure so the tool can delegate
/// prompts to the instrument agent.
Tool<Map<String, dynamic>> _createScpiAgentTool(
  InstrumentAgent vxiAgent, {
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'scpi_instrument_agent',
    description:
        'Send SCPI commands and queries to a VXI-11 instrument. '
        'Use this tool when you need to interact with the connected '
        'measurement instrument. Describe what you want to do with the '
        'instrument in natural language, and the instrument agent will '
        'handle the SCPI communication.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'prompt': {
          'type': 'string',
          'description':
              'Describe what you want to do with the instrument in natural '
              'language, e.g. "Send the command C1:TRA OFF" or '
              '"Query the device identification with *IDN?"',
        },
      },
      'required': ['prompt'],
    }),
    onCall: (args) async {
      final prompt = args['prompt'] as String;
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'scpi_instrument_agent',
      );
      final response = await vxiAgent.send(prompt);
      logger.logToolCall(input: args, output: {'response': response});
      return {'response': response};
    },
  );
}

/// Creates the tool that wraps the knowledgebase search agent.
///
/// The [searchAgent] is captured in the closure so the tool can delegate
/// knowledgebase queries to the search agent.
Tool<Map<String, dynamic>> _createSearchAgentTool(
  SearchAgent searchAgent, {
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'search_agent',
    description:
        'Search the oscilloscope knowledgebase for information about '
        'commands, settings, troubleshooting, or device specifications. '
        'Use this tool when you need to answer questions about how to use '
        'the oscilloscope, what SCPI commands are available, how to '
        'configure channels or triggers, or how to troubleshoot issues. '
        'The knowledgebase contains documentation about the oscilloscope '
        'device including channel setup, timebase, measurements, '
        'troubleshooting, and specifications.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description':
              'The question about the oscilloscope device, e.g. '
              '"How do I set the trigger level?" or '
              '"What is the C1:TRA command?" or '
              '"What are the specifications of the SDS1202X-E?"',
        },
      },
      'required': ['query'],
    }),
    onCall: (args) async {
      final query = args['query'] as String;
      final logger = AppLogger(agentName: agentName, toolName: 'search_agent');
      final response = await searchAgent.send(query);
      logger.logToolCall(input: args, output: {'response': response});
      return {'response': response};
    },
  );
}

/// A frontend AI agent that has the [InstrumentAgent] (with VXI-11 tool) and
/// [SearchAgent] (with knowledgebase search) as tools.
///
/// This creates a three-tier architecture:
/// - **FrontendAgent**: The user-facing agent that can answer general questions
///   or delegate to specialized sub-agents.
/// - **InstrumentAgent** (instrument agent): An internal agent equipped with the
///   VXI-11 tool for sending SCPI commands and queries to a remote instrument.
/// - **SearchAgent** (knowledgebase agent): An internal agent that searches a
///   Markdown knowledgebase for oscilloscope documentation.
///
/// The frontend agent has the following tools:
/// - `scpi_instrument_agent`: For sending SCPI commands to the instrument
/// - `search_agent`: For searching the oscilloscope knowledgebase
///
/// All agents limit the number of tool calls per user input to
/// [maxToolCalls] (default: 10). This prevents runaway tool loops.
///
/// Usage:
/// ```dart
/// final agent = FrontendAgent();
/// await for (final chunk in agent.sendStream('What is the device ID?')) {
///   print(chunk);
/// }
/// ```
class FrontendAgent {
  /// Default maximum number of tool calls per user input for the instrument
  /// (VXI-11) sub-agent.
  static const int defaultInstrumentToolCalls = 10;

  /// Default maximum number of tool calls per user input for the knowledgebase
  /// search sub-agent.
  static const int defaultSearchToolCalls = 8;

  /// The underlying dartantic_ai Agent instance for the frontend.
  final Agent _frontendAgent;

  /// The chat history for multi-turn conversations.
  List<ChatMessage> _history = [];

  /// Maximum number of tool calls allowed per user input for the instrument
  /// (VXI-11) sub-agent. Only applies to the sub-agent; the frontend agent
  /// itself does not enforce a tool call limit — the sub-agents' limits
  /// prevent runaway loops.
  final int instrumentToolCalls;

  /// Maximum number of tool calls allowed per user input for the knowledgebase
  /// search sub-agent.
  final int searchToolCalls;

  /// Creates a [FrontendAgent] with instrument and knowledgebase search sub-agents.
  ///
  /// The [model] parameter specifies the model to use in `provider:model`
  /// format.
  ///
  /// The [systemPrompt] parameter sets an optional system message for the
  /// frontend agent. If null, [frontendAgentDefaultSystemPrompt] is used.
  ///
  /// The [vxi11Host] parameter sets the default VXI-11 instrument IP.
  /// If null, no VXI-11 tool is added. Defaults to `192.168.178.95`.
  ///
  /// The [knowledgebasePath] parameter sets the path to the knowledgebase
  /// Markdown file. Defaults to `docs/knowledgebase.md`.
  ///
  /// The [tools] parameter allows adding additional custom tools to the
  /// frontend agent.
  ///
  /// The [maxToolCalls] parameter limits the number of tool calls per
  /// user input for the frontend agent. Defaults to [defaultMaxToolCalls] (3).
  ///
  /// The [instrumentToolCalls] parameter limits the number of tool calls per
  /// user input for the instrument (VXI-11) sub-agent.
  /// Defaults to [defaultInstrumentToolCalls] (5).
  ///
  /// The [searchToolCalls] parameter limits the number of tool calls per
  /// user input for the knowledgebase search sub-agent.
  /// Defaults to [defaultSearchToolCalls] (10).
  ///
  /// Note: [maxToolCalls] (frontend-level) has been removed — the sub-agents'
  /// limits are sufficient. The frontend agent streams all responses as-is.
  FrontendAgent({
    String model = 'deepseek:deepseek-v4-flash',
    String? systemPrompt,
    String? vxi11Host,
    String knowledgebasePath = 'docs/knowledgebase.md',
    List<Tool>? tools,
    this.instrumentToolCalls = defaultInstrumentToolCalls,
    this.searchToolCalls = defaultSearchToolCalls,
  }) : _frontendAgent = Agent(
         model,
         displayName: 'FrontendAgent',
         tools: [
           if (vxi11Host != null)
             _createScpiAgentTool(
               _createVxiAgent(
                 model: model,
                 vxi11Host: vxi11Host,
                 maxToolCalls: instrumentToolCalls,
               ),
               agentName: 'FrontendAgent',
             ),
           _createSearchAgentTool(
             _createSearchSubAgent(
               model: model,
               knowledgebasePath: knowledgebasePath,
               maxToolCalls: searchToolCalls,
             ),
             agentName: 'FrontendAgent',
           ),
           if (tools != null) ...tools,
         ],
       ) {
    _history.add(
      ChatMessage.system(systemPrompt ?? frontendAgentDefaultSystemPrompt),
    );
  }

  /// The display name of the agent.
  String get displayName => _frontendAgent.displayName;

  /// The current model name being used.
  String get model => _frontendAgent.model;

  /// Sends a [prompt] and returns the full response as a single string.
  ///
  /// The conversation history is automatically maintained for multi-turn
  /// conversations.
  Future<String> send(String prompt) async {
    final logger = AppLogger(agentName: 'FrontendAgent', toolName: 'send');
    logger.debug(
      '[DEBUG FrontendAgent.send] _history has ${_history.length} messages:',
    );
    for (var i = 0; i < _history.length; i++) {
      final msg = _history[i];
      logger.debug(
        '[DEBUG FrontendAgent.send]   [$i] role=${msg.role} '
        'text="${msg.text.substring(0, msg.text.length > 80 ? 80 : msg.text.length)}"'
        '${msg.hasToolCalls ? ' hasToolCalls' : ''}'
        '${msg.hasToolResults ? ' hasToolResults' : ''}',
      );
    }
    logger.logToolCall(input: {'prompt': prompt}, output: {});
    final result = await _frontendAgent.send(prompt, history: _history);
    _history.addAll(result.messages);
    final output = result.output.trim();
    logger.logToolCall(input: {'prompt': prompt}, output: {'response': output});
    return output;
  }

  /// Sends a [prompt] and streams the response chunks.
  ///
  /// The conversation history is automatically maintained for multi-turn
  /// conversations.
  ///
  /// Tool call limits are enforced by the sub-agents ([SearchAgent],
  /// [InstrumentAgent]). The frontend agent itself does not impose a limit.
  ///
  /// **Buffering behavior**: When the frontend agent's underlying LLM decides
  /// to call a tool (e.g. `search_agent` or `scpi_instrument_agent`), it often
  /// first streams intermediate "thinking aloud" text like "Let me search for
  /// that information..." before making the tool call. This text is buffered
  /// and discarded if a tool call follows, so the user only sees the final
  /// answer after all tool calls complete. Text that arrives without any
  /// preceding tool call in the same response is streamed immediately.
  Stream<String> sendStream(String prompt) async* {
    // Buffer for text chunks that may be discarded if followed by tool calls.
    final textBuffer = <String>[];
    // Accumulator for the final output (used for history management).
    final allChunks = <String>[];
    // Whether we've seen a tool call in the current response cycle.
    var hasSeenToolCall = false;
    // Whether we've already flushed the buffer (after tool calls complete).
    var hasFlushedAfterTools = false;

    await for (final chunk in _frontendAgent.sendStream(
      prompt,
      history: _history,
    )) {
      // Check if this chunk contains tool call messages.
      final hasToolCalls = chunk.messages.any((msg) => msg.hasToolCalls);

      if (hasToolCalls) {
        // The model decided to call a tool. Discard any buffered "thinking
        // aloud" text — it was just the model's intermediate reasoning before
        // deciding to use a tool.
        textBuffer.clear();
        hasSeenToolCall = true;
        hasFlushedAfterTools = false;
      }

      // Check if this chunk contains tool result messages (responses from
      // tool execution). After tool results, the model will produce its final
      // answer in subsequent chunks.
      final hasToolResults = chunk.messages.any((msg) => msg.hasToolResults);

      if (hasToolResults) {
        // Tool results are coming back. The next text chunks will be the
        // model's actual answer. Reset the flag so we flush the buffer.
        hasFlushedAfterTools = false;
      }

      // If this chunk has text output, decide whether to buffer or yield.
      if (chunk.output.isNotEmpty) {
        if (hasSeenToolCall && !hasFlushedAfterTools) {
          // We're in a post-tool-call phase. Buffer text until we see the
          // first non-empty text after tool results — that's the real answer.
          textBuffer.add(chunk.output);
        } else if (!hasSeenToolCall) {
          // No tool calls seen yet — this could be a direct answer or
          // pre-tool-call thinking. Buffer it in case a tool call follows.
          textBuffer.add(chunk.output);
        } else {
          // hasSeenToolCall && hasFlushedAfterTools: we're past the tool
          // call cycle, streaming the final answer directly.
          allChunks.add(chunk.output);
          yield chunk.output;
        }
      }

      // Detect the end of a tool-call cycle: after tool results have been
      // processed, the next chunk with text AND no tool calls/results means
      // the model is producing its final answer. Flush the buffer.
      if (hasSeenToolCall &&
          !hasFlushedAfterTools &&
          chunk.output.isNotEmpty &&
          !hasToolCalls &&
          !hasToolResults) {
        // This is the model's final answer after tools completed.
        // Flush the buffered text.
        hasFlushedAfterTools = true;
        for (final buffered in textBuffer) {
          allChunks.add(buffered);
          yield buffered;
        }
        textBuffer.clear();
      }
    }

    // After the stream ends, if there's still buffered text that was never
    // flushed (e.g. no tool calls occurred, or the stream ended before a
    // flush), yield it now.
    if (textBuffer.isNotEmpty) {
      for (final buffered in textBuffer) {
        allChunks.add(buffered);
        yield buffered;
      }
      textBuffer.clear();
    }

    // Only add the user prompt and final text response to _history.
    // The dartantic_ai Agent internally manages tool call/result message pairs
    // in its StreamingState. Adding them here would cause duplicates and
    // "tool result without matching tool call" API errors on subsequent calls.
    final fullOutput = allChunks.join();
    if (fullOutput.isNotEmpty) {
      _history.addAll([
        ChatMessage.user(prompt),
        ChatMessage.model(fullOutput),
      ]);
      // Keep history at max 4 entries: system prompt (index 0) + 3 most recent.
      // This prevents unbounded token growth while retaining recent context.
      if (_history.length > 4) {
        _history = [_history[0], ..._history.sublist(_history.length - 3)];
      }
    }
  }

  /// Clears the conversation history.
  void clearHistory() {
    _history.clear();
  }

  /// Creates the internal instrument agent.
  static InstrumentAgent _createVxiAgent({
    required String model,
    required String? vxi11Host,
    required int maxToolCalls,
  }) {
    return InstrumentAgent(
      model: model,
      vxi11Host: vxi11Host,
      maxToolCalls: maxToolCalls,
      systemPrompt: instrumentAgentSystemPrompt,
    );
  }

  /// Creates the internal search agent.
  static SearchAgent _createSearchSubAgent({
    required String model,
    required String knowledgebasePath,
    required int maxToolCalls,
  }) {
    return SearchAgent(
      model: model,
      knowledgebasePath: knowledgebasePath,
      maxToolCalls: maxToolCalls,
      systemPrompt: searchAgentSystemPrompt,
    );
  }
}
