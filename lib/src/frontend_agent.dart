import 'dart:async';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../logger.dart';
import 'agent.dart';
import 'query_agent.dart';
import 'systemprompts.dart';

/// Creates the tool that wraps the VXI-11 instrument agent.
///
/// The [vxiAgent] is captured in the closure so the tool can delegate
/// prompts to the instrument agent.
Tool<Map<String, dynamic>> _createScpiAgentTool(
  ChatAgent vxiAgent, {
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
      logger.logToolCall(
        input: args,
        output: {'response': response},
      );
      return {'response': response};
    },
  );
}

/// Creates the tool that wraps the knowledgebase query agent.
///
/// The [queryAgent] is captured in the closure so the tool can delegate
/// knowledgebase queries to the query agent.
Tool<Map<String, dynamic>> _createQueryAgentTool(
  QueryAgent queryAgent, {
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'query_agent',
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
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'query_agent',
      );
      final response = await queryAgent.send(query);
      logger.logToolCall(
        input: args,
        output: {'response': response},
      );
      return {'response': response};
    },
  );
}

/// A frontend AI agent that has the [ChatAgent] (with VXI-11 tool) and
/// [QueryAgent] (with knowledgebase search) as tools.
///
/// This creates a three-tier architecture:
/// - **FrontendAgent**: The user-facing agent that can answer general questions
///   or delegate to specialized sub-agents.
/// - **ChatAgent** (instrument agent): An internal agent equipped with the
///   VXI-11 tool for sending SCPI commands and queries to a remote instrument.
/// - **QueryAgent** (knowledgebase agent): An internal agent that searches a
///   Markdown knowledgebase for oscilloscope documentation.
///
/// The frontend agent has the following tools:
/// - `scpi_instrument_agent`: For sending SCPI commands to the instrument
/// - `query_agent`: For searching the oscilloscope knowledgebase
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

  /// Default maximum number of tool calls per user input for the frontend agent.
  static const int defaultMaxToolCalls = 3;

  /// Default maximum number of tool calls per user input for the instrument
  /// (VXI-11) sub-agent.
  static const int defaultInstrumentToolCalls = 5;

  /// Default maximum number of tool calls per user input for the knowledgebase
  /// query sub-agent.
  static const int defaultQueryToolCalls = 4;

  /// The underlying dartantic_ai Agent instance for the frontend.
  final Agent _frontendAgent;

  /// The chat history for multi-turn conversations.
  final List<ChatMessage> _history = [];

  /// Maximum number of tool calls allowed per user input for the frontend agent.
  final int maxToolCalls;

  /// Maximum number of tool calls allowed per user input for the instrument
  /// (VXI-11) sub-agent.
  final int instrumentToolCalls;

  /// Maximum number of tool calls allowed per user input for the knowledgebase
  /// query sub-agent.
  final int queryToolCalls;

  /// Creates a [FrontendAgent] with instrument and knowledgebase sub-agents.
  ///
  /// The [model] parameter specifies the model to use in `provider:model`
  /// format. Defaults to `deepseek:deepseek-v4-flash`.
  ///
  /// Supports:
  /// - `deepseek:<model>` - DeepSeek via OpenAI-compatible API
  /// - `edenai:<model>` - EdenAI via OpenAI-compatible API
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
  /// The [queryToolCalls] parameter limits the number of tool calls per
  /// user input for the knowledgebase query sub-agent.
  /// Defaults to [defaultQueryToolCalls] (3).
  FrontendAgent({
    String model = 'deepseek:deepseek-v4-flash',
    String? systemPrompt,
    String? vxi11Host,
    String knowledgebasePath = 'docs/knowledgebase.md',
    List<Tool>? tools,
    this.maxToolCalls = defaultMaxToolCalls,
    this.instrumentToolCalls = defaultInstrumentToolCalls,
    this.queryToolCalls = defaultQueryToolCalls,
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
            _createQueryAgentTool(
              _createQuerySubAgent(
                model: model,
                knowledgebasePath: knowledgebasePath,
                maxToolCalls: queryToolCalls,
              ),
              agentName: 'FrontendAgent',
            ),
            if (tools != null) ...tools,
          ],
        ) {
    _history.add(ChatMessage.system(systemPrompt ?? frontendAgentDefaultSystemPrompt));
  }

  /// The display name of the agent (e.g., "DeepSeek").
  String get displayName => _frontendAgent.displayName;

  /// The current model name being used.
  String get model => _frontendAgent.model;

  /// Sends a [prompt] and returns the full response as a single string.
  ///
  /// The conversation history is automatically maintained for multi-turn
  /// conversations.
  Future<String> send(String prompt) async {
    final logger = AppLogger(
      agentName: 'FrontendAgent',
      toolName: 'send',
    );
    logger.log(
      '[DEBUG FrontendAgent.send] _history has ${_history.length} messages:',
    );
    for (var i = 0; i < _history.length; i++) {
      final msg = _history[i];
      logger.log(
        '[DEBUG FrontendAgent.send]   [$i] role=${msg.role} '
        'text="${msg.text.substring(0, msg.text.length > 80 ? 80 : msg.text.length)}"'
        '${msg.hasToolCalls ? ' hasToolCalls' : ''}'
        '${msg.hasToolResults ? ' hasToolResults' : ''}',
      );
    }
    logger.logToolCall(
      input: {'prompt': prompt},
      output: {},
    );
    final result = await _frontendAgent.send(prompt, history: _history);
    _history.addAll(result.messages);
    final output = result.output.trim();
    logger.logToolCall(
      input: {'prompt': prompt},
      output: {'response': output},
    );
    return output;
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
      agentName: 'FrontendAgent',
      toolName: 'sendStream',
    );
    logger.log(
      '[DEBUG FrontendAgent.sendStream] _history has ${_history.length} '
      'messages:',
    );
    for (var i = 0; i < _history.length; i++) {
      final msg = _history[i];
      logger.log(
        '[DEBUG FrontendAgent.sendStream]   [$i] role=${msg.role} '
        'text="${msg.text.substring(0, msg.text.length > 80 ? 80 : msg.text.length)}"'
        '${msg.hasToolCalls ? ' hasToolCalls' : ''}'
        '${msg.hasToolResults ? ' hasToolResults' : ''}',
      );
    }
    logger.logToolCall(
      input: {'prompt': prompt},
      output: {},
    );
    final chunks = <String>[];
    var toolCallCount = 0;
    var chunkIndex = 0;

    await for (final chunk
        in _frontendAgent.sendStream(prompt, history: _history)) {
      chunkIndex++;
      logger.log(
        '[DIAG FrontendAgent.sendStream] Chunk #$chunkIndex: '
        'output="${chunk.output}" (len=${chunk.output.length}), '
        'messages=${chunk.messages.length}, '
        'finishReason=${chunk.finishReason}, '
        'usage=${chunk.usage}',
      );

      // Log the text of each message in the chunk
      for (var i = 0; i < chunk.messages.length; i++) {
        final msg = chunk.messages[i];
        final textPreview = msg.text.length > 120
            ? '${msg.text.substring(0, 120)}...'
            : msg.text;
        logger.log(
          '[DIAG FrontendAgent.sendStream]   Msg[$i]: '
          'role=${msg.role}, '
          'text="$textPreview", '
          'hasToolCalls=${msg.hasToolCalls}, '
          'hasToolResults=${msg.hasToolResults}, '
          'partsCount=${msg.parts.length}',
        );
        // Log individual parts
        for (var p = 0; p < msg.parts.length; p++) {
          final part = msg.parts[p];
          logger.log(
            '[DIAG FrontendAgent.sendStream]     Part[$p]: '
            'type=${part.runtimeType}',
          );
          if (part is ToolPart) {
            logger.log(
              '[DIAG FrontendAgent.sendStream]       toolName=${part.toolName}, '
              'kind=${part.kind}, '
              'callId=${part.callId}',
            );
          }
        }
      }

      // Log tool calls and tool results from chunk messages.
      for (final msg in chunk.messages) {
        if (msg.role == ChatMessageRole.model && msg.hasToolCalls) {
          toolCallCount++;
          for (final toolCall in msg.toolCalls) {
            logger.logToolCall(
              input: {
                'tool': toolCall.toolName,
                'callId': toolCall.callId,
                'arguments': toolCall.arguments,
              },
              output: {},
            );
          }
        }
        if (msg.hasToolResults) {
          for (final toolResult in msg.toolResults) {
            logger.logToolCall(
              input: {
                'tool': toolResult.toolName,
                'callId': toolResult.callId,
              },
              output: {
                'result': toolResult.result,
              },
            );
          }
        }
      }

      // If we've exceeded the max tool calls, stop yielding and break.
      if (toolCallCount > maxToolCalls) {
        logger.log(
          '[DIAG FrontendAgent.sendStream] BREAKING: '
          'toolCallCount=$toolCallCount > maxToolCalls=$maxToolCalls',
        );
        break;
      }

      chunks.add(chunk.output);
      yield chunk.output;
    }

    logger.log(
      '[DIAG FrontendAgent.sendStream] Stream ended. '
      'Total chunks=$chunkIndex, '
      'toolCallCount=$toolCallCount, '
      'chunks collected=${chunks.length}',
    );
    for (var i = 0; i < chunks.length; i++) {
      logger.log(
        '[DIAG FrontendAgent.sendStream]   chunks[$i]="'
        '${chunks[i].length > 80 ? chunks[i].substring(0, 80) : chunks[i]}" '
        '(len=${chunks[i].length})',
      );
    }

    // Reconstruct the full messages from the concatenated output.
    final fullOutput = chunks.join();
    if (fullOutput.isNotEmpty) {
      _history.addAll([
        ChatMessage.user(prompt),
        ChatMessage.model(fullOutput),
      ]);
    }
    logger.logToolCall(
      input: {'prompt': prompt},
      output: {'response': fullOutput},
    );
  }

  /// Clears the conversation history.
  void clearHistory() {
    _history.clear();
  }

  /// Creates the internal instrument agent.
  static ChatAgent _createVxiAgent({
    required String model,
    required String? vxi11Host,
    required int maxToolCalls,
  }) {
    return ChatAgent(
      model: model,
      vxi11Host: vxi11Host,
      maxToolCalls: maxToolCalls,
      systemPrompt: instrumentAgentSystemPrompt,
    );
  }

  /// Creates the internal query agent.
  static QueryAgent _createQuerySubAgent({
    required String model,
    required String knowledgebasePath,
    required int maxToolCalls,
  }) {
    return QueryAgent(
      model: model,
      knowledgebasePath: knowledgebasePath,
      maxToolCalls: maxToolCalls,
      systemPrompt: queryAgentSystemPrompt,
    );
  }
}
