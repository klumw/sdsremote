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
      logger.logToolCall(
        input: args,
        output: {'response': response},
      );
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
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'search_agent',
      );
      final response = await searchAgent.send(query);
      logger.logToolCall(
        input: args,
        output: {'response': response},
      );
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
  final List<ChatMessage> _history = [];

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
    _history.add(ChatMessage.system(systemPrompt ?? frontendAgentDefaultSystemPrompt));
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
    final logger = AppLogger(
      agentName: 'FrontendAgent',
      toolName: 'send',
    );
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
  /// Tool call limits are enforced by the sub-agents ([SearchAgent],
  /// [InstrumentAgent]). The frontend agent itself does not impose a limit.
  Stream<String> sendStream(String prompt) async* {
    final logger = AppLogger(
      agentName: 'FrontendAgent',
      toolName: 'sendStream',
    );
    final chunks = <String>[];

    await for (final chunk
        in _frontendAgent.sendStream(prompt, history: _history)) {
      chunks.add(chunk.output);
      yield chunk.output;
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
